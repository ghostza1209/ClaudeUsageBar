import Foundation
import Testing
import UsageCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let reset5h = Date(timeIntervalSince1970: 1_800_003_600)  // 2027-01-15T09:00:00Z
private let resetWeek = Date(timeIntervalSince1970: 1_800_400_000)  // 2027-01-19T23:06:40Z

private let body = """
    {"five_hour":{"utilization":23.5,"resets_at":"2027-01-15T09:00:00.000000+00:00"},
    "seven_day":{"utilization":41,"resets_at":"2027-01-19T23:06:40Z"},"seven_day_opus":null,"limits":[]}
    """

@Test func parsesBothWindowsWithEitherIsoForm() {
    #expect(parseUsageResponse(Data(body.utf8), fetchedAt: t0) == .ok(
        fiveHour: LimitWindow(percent: 23.5, resetsAt: reset5h), sevenDay: LimitWindow(percent: 41, resetsAt: resetWeek),
        capturedAt: t0))
}

@Test func nullFiveHourIsLeftOutLikeAnUncappedCapture() {
    let ultra = #"{"five_hour":null,"seven_day":{"utilization":7,"resets_at":"2027-01-19T23:06:40Z"}}"#
    #expect(parseUsageResponse(Data(ultra.utf8), fetchedAt: t0) == .ok(
        fiveHour: nil, sevenDay: LimitWindow(percent: 7, resetsAt: resetWeek), capturedAt: t0))
}

@Test(arguments: ["{}", #"{"five_hour":{"utilization":null,"resets_at":null},"seven_day":null}"#])
func noWindowsIsNoData(json: String) {
    #expect(parseUsageResponse(Data(json.utf8), fetchedAt: t0) == .noData)
}

@Test func notJsonIsUnreadable() {
    #expect(parseUsageResponse(Data("<html>".utf8), fetchedAt: t0) == .unreadable("the usage response is not a JSON object"))
}

private func ok(_ at: TimeInterval) -> PlanLimits {
    .ok(fiveHour: nil, sevenDay: LimitWindow(percent: at, resetsAt: resetWeek), capturedAt: Date(timeIntervalSince1970: at))
}

@Test func mergeTakesTheNewerOkEitherWay() {
    #expect(mergePlanLimits(capture: ok(10), endpoint: ok(20)) == ok(20))
    #expect(mergePlanLimits(capture: ok(30), endpoint: ok(20)) == ok(30))
}

@Test func mergeWarnsOnlyWhenNeitherSourceWorks() {
    #expect(mergePlanLimits(capture: .notInstalled, endpoint: ok(20)) == ok(20))
    #expect(mergePlanLimits(capture: .notInstalled, endpoint: .noData) == .noData)
    #expect(mergePlanLimits(capture: .notInstalled, endpoint: nil) == .notInstalled)
    #expect(mergePlanLimits(capture: ok(10), endpoint: .noData) == ok(10))
}

/// Keychain and network stand-ins: the boundary the endpoint is injected with.
private final class Fake: @unchecked Sendable {
    var keychain: Data?
    var writable = true
    var responses: [(Int, String)]
    var requests: [URLRequest] = []

    init(oauth: [String: Any]?, responses: [(Int, String)]) {
        keychain = oauth.map { try! JSONSerialization.data(withJSONObject: ["claudeAiOauth": $0, "mcpOAuth": ["x": 1]]) }
        self.responses = responses
    }

    var endpoint: UsageEndpoint {
        UsageEndpoint(readKeychain: { self.keychain }, writeKeychain: { if self.writable { self.keychain = $0 }; return self.writable }) { request in
            self.requests.append(request)
            let (status, text) = self.responses.removeFirst()
            return (Data(text.utf8), status)
        }
    }

    var stored: [String: Any] { try! JSONSerialization.jsonObject(with: keychain!) as! [String: Any] }
    var paths: [String] { requests.map { $0.url!.path } }
}

private var fresh: [String: Any] { ["accessToken": "A1", "refreshToken": "R1", "expiresAt": 1_800_003_600_000, "scopes": ["user:inference", "user:profile"]] }
private var expired: [String: Any] { fresh.merging(["expiresAt": 1_799_999_000_000]) { $1 } }
private let tokenReply = #"{"access_token":"A2","refresh_token":"R2","expires_in":28800}"#

@Test func freshTokenGoesStraightToTheEndpoint() async throws {
    let fake = Fake(oauth: fresh, responses: [(200, body)])
    #expect(try await fake.endpoint.fetch(now: t0).get() == .ok(
        fiveHour: LimitWindow(percent: 23.5, resetsAt: reset5h), sevenDay: LimitWindow(percent: 41, resetsAt: resetWeek),
        capturedAt: t0))
    #expect(fake.paths == ["/api/oauth/usage"])
    #expect(fake.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer A1")
    #expect(fake.requests[0].value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
}

@Test func expiredTokenIsRefreshedAndThePairWrittenBackKeepingOtherKeys() async throws {
    let fake = Fake(oauth: expired, responses: [(200, tokenReply), (200, body)])
    _ = try await fake.endpoint.fetch(now: t0).get()
    #expect(fake.paths == ["/v1/oauth/token", "/api/oauth/usage"])
    let sent = try #require(JSONSerialization.jsonObject(with: fake.requests[0].httpBody!) as? [String: String])
    #expect(sent == ["grant_type": "refresh_token", "refresh_token": "R1", "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
                     "scope": "user:inference user:profile"])
    #expect(fake.requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer A2")
    let oauth = try #require(fake.stored["claudeAiOauth"] as? [String: Any])
    #expect(oauth["accessToken"] as? String == "A2")
    #expect(oauth["refreshToken"] as? String == "R2")
    #expect((oauth["expiresAt"] as? NSNumber)?.int64Value == 1_800_028_800_000)
    #expect(oauth["scopes"] as? [String] == ["user:inference", "user:profile"])
    #expect(fake.stored["mcpOAuth"] != nil)
}

@Test func unauthorizedTokenIsRefreshedOnceThenRetried() async throws {
    let fake = Fake(oauth: fresh, responses: [(401, ""), (200, tokenReply), (200, body)])
    _ = try await fake.endpoint.fetch(now: t0).get()
    #expect(fake.paths == ["/api/oauth/usage", "/v1/oauth/token", "/api/oauth/usage"])
}

@Test func secondUnauthorizedNeedsLogin() async {
    let fake = Fake(oauth: fresh, responses: [(401, ""), (200, tokenReply), (401, "")])
    #expect(await fake.endpoint.fetch(now: t0) == .failure(.needsLogin))
}

@Test func rejectedRefreshTokenNeedsLoginAndLeavesTheItemAlone() async {
    let fake = Fake(oauth: expired, responses: [(400, #"{"error":"invalid_grant"}"#)])
    let before = fake.keychain
    #expect(await fake.endpoint.fetch(now: t0) == .failure(.needsLogin))
    #expect(fake.keychain == before)
}

@Test func missingCredentialsNeedLoginWithoutAnyRequest() async {
    let fake = Fake(oauth: nil, responses: [])
    #expect(await fake.endpoint.fetch(now: t0) == .failure(.needsLogin))
    #expect(fake.requests.isEmpty)
}

@Test func tooManyRequestsIsRateLimited() async {
    let fake = Fake(oauth: fresh, responses: [(429, "")])
    #expect(await fake.endpoint.fetch(now: t0) == .failure(.rateLimited))
}

@Test func refreshedPairSurvivesAFailedWriteAndIsWrittenNextTime() async throws {
    let fake = Fake(oauth: expired, responses: [(200, tokenReply), (200, body), (200, body)])
    fake.writable = false
    let endpoint = fake.endpoint
    _ = try await endpoint.fetch(now: t0).get()
    fake.writable = true
    _ = try await endpoint.fetch(now: t0).get()
    #expect(fake.paths == ["/v1/oauth/token", "/api/oauth/usage", "/api/oauth/usage"])
    #expect(fake.requests[2].value(forHTTPHeaderField: "Authorization") == "Bearer A2")
    #expect((fake.stored["claudeAiOauth"] as? [String: Any])?["refreshToken"] as? String == "R2")
}
