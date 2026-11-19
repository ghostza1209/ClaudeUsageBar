import Foundation

/// Why a usage-endpoint read produced no Plan limits.
public enum UsageEndpointError: Error, Equatable, Sendable {
    /// No Claude Code credentials in the Keychain, or the refresh token was rejected: `claude /login` fixes it.
    case needsLogin
    /// HTTP 429; the caller backs off.
    case rateLimited
    case failed(String)
}

/// Parses the `/api/oauth/usage` body. Each window is `{utilization: 0-100 | null, resets_at: ISO 8601 | null}` or null;
/// a window without both values is left out, like a capture that omits it.
public func parseUsageResponse(_ data: Data, fetchedAt: Date) -> PlanLimits {
    guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return .unreadable("the usage response is not a JSON object")
    }
    let iso = ISO8601DateFormatter()
    let isoFraction = ISO8601DateFormatter()
    isoFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let windows: [LimitWindow?] = ["five_hour", "seven_day"].map { name in
        guard let object = root[name] as? [String: Any], let percent = (object["utilization"] as? NSNumber)?.doubleValue,
            let text = object["resets_at"] as? String, let resetsAt = isoFraction.date(from: text) ?? iso.date(from: text)
        else { return nil }
        return LimitWindow(percent: min(max(percent, 0), 100), resetsAt: resetsAt)
    }
    if windows.allSatisfy({ $0 == nil }) { return .noData }
    return .ok(fiveHour: windows[0], sevenDay: windows[1], capturedAt: fetchedAt)
}

/// The statusline capture and the endpoint read combined: the newer `.ok` wins; otherwise any `.ok`; otherwise an
/// endpoint `.noData` beats a missing wrapper, so ⚠ shows only when neither source works.
public func mergePlanLimits(capture: PlanLimits, endpoint: PlanLimits?) -> PlanLimits {
    switch (capture, endpoint) {
    case (.ok(_, _, let a), .some(.ok(_, _, let b))): return b > a ? endpoint! : capture
    case (.ok, _): return capture
    case (_, .some(.ok)), (_, .some(.noData)): return endpoint!
    default: return capture
    }
}

/// Reads Plan limits from `/api/oauth/usage` with the OAuth token Claude Code keeps in the Keychain, refreshing it
/// when expired and writing the new pair back (see docs/adr/0002). Keychain and HTTP are injected for tests.
public actor UsageEndpoint {
    public typealias HTTP = @Sendable (URLRequest) async throws -> (Data, Int)
    private let readKeychain: @Sendable () -> Data?
    private let writeKeychain: @Sendable (Data) -> Bool
    private let http: HTTP
    /// A refreshed item whose Keychain write failed. Its refresh token is the only valid one now, so it is used in
    /// place of the Keychain and the write is retried on every read until it lands.
    private var unsaved: Data?

    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    public init(readKeychain: @escaping @Sendable () -> Data?, writeKeychain: @escaping @Sendable (Data) -> Bool, http: @escaping HTTP) {
        (self.readKeychain, self.writeKeychain, self.http) = (readKeychain, writeKeychain, http)
    }

    public func fetch(now: Date) async -> Result<PlanLimits, UsageEndpointError> {
        var rejected: String?
        // A 401 on an unexpired token means it was revoked or rotated: refresh once, then give up.
        for _ in 0..<2 {
            let token: String
            switch await validToken(now: now, rejected: rejected) {
            case .success(let valid): token = valid
            case .failure(let error): return .failure(error)
            }
            let data: Data, status: Int
            do { (data, status) = try await get(token) } catch { return .failure(.failed(error.localizedDescription)) }
            switch status {
            case 200: return .success(parseUsageResponse(data, fetchedAt: now))
            case 401: rejected = token
            case 429: return .failure(.rateLimited)
            default: return .failure(.failed("usage endpoint HTTP \(status)"))
            }
        }
        return .failure(.needsLogin)
    }

    private func get(_ token: String) async throws -> (Data, Int) {
        var request = URLRequest(url: Self.usageURL, timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        return try await http(request)
    }

    /// The stored access token while it has more than a minute left and is not `rejected`; otherwise exchanges the
    /// refresh token and writes the new pair back, keeping every other key. The item is read fresh on every call, so a
    /// pair the CLI rotated meanwhile is used rather than refreshed again.
    private func validToken(now: Date, rejected: String?) async -> Result<String, UsageEndpointError> {
        guard let stored = stored(), var root = (try? JSONSerialization.jsonObject(with: stored)) as? [String: Any],
            var oauth = root["claudeAiOauth"] as? [String: Any]
        else { return .failure(.needsLogin) }
        if let token = oauth["accessToken"] as? String, !token.isEmpty, token != rejected,
            let expiresAt = (oauth["expiresAt"] as? NSNumber)?.doubleValue, expiresAt / 1000 > now.timeIntervalSince1970 + 60
        {
            return .success(token)
        }
        guard let refreshToken = oauth["refreshToken"] as? String, !refreshToken.isEmpty else { return .failure(.needsLogin) }
        var request = URLRequest(url: Self.tokenURL, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": Self.clientID]
        if let scopes = oauth["scopes"] as? [String] { body["scope"] = scopes.joined(separator: " ") }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let data: Data, status: Int
        do { (data, status) = try await http(request) } catch { return .failure(.failed(error.localizedDescription)) }
        if status == 400 || status == 401 { return .failure(.needsLogin) }
        if status == 429 { return .failure(.rateLimited) }
        guard status == 200, let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let access = reply["access_token"] as? String, let expiresIn = (reply["expires_in"] as? NSNumber)?.doubleValue
        else { return .failure(.failed("token refresh HTTP \(status)")) }
        oauth["accessToken"] = access
        oauth["refreshToken"] = reply["refresh_token"] as? String ?? refreshToken
        oauth["expiresAt"] = Int64((now.timeIntervalSince1970 + expiresIn) * 1000)
        root["claudeAiOauth"] = oauth
        if let json = try? JSONSerialization.data(withJSONObject: root) { unsaved = writeKeychain(json) ? nil : json }
        return .success(access)
    }

    private func stored() -> Data? {
        guard let pending = unsaved else { return readKeychain() }
        if writeKeychain(pending) { unsaved = nil }
        return pending
    }
}

/// The `security` CLI reads and writes Claude Code's item, the way Claude Code itself reads it. The account is the
/// login name; the CLI's `claude-code-user` fallback for unusual names is not handled.
public enum ClaudeCodeKeychain {
    public static let service = "Claude Code-credentials"

    public static func read(service: String = service) -> Data? {
        let (status, out) = run(["find-generic-password", "-a", NSUserName(), "-s", service, "-w"], stdin: nil)
        guard status == 0 else { return nil }
        return Data(String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).utf8)
    }

    /// Updates the item in place (`-U`), hex-encoded through `security -i`'s stdin so the secret stays out of argv.
    /// That stdin takes lines under ~4 KB, so a bigger item goes through argv, as Claude Code itself does.
    /// `security -i` can exit 0 after a failed command, so success means the item reads back unchanged.
    public static func write(_ data: Data, service: String = service) -> Bool {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        let line = "add-generic-password -U -a \"\(NSUserName())\" -s \"\(service)\" -X \(hex)\n"
        if line.utf8.count < 4000 {
            _ = run(["-i"], stdin: Data(line.utf8))
        } else {
            _ = run(["add-generic-password", "-U", "-a", NSUserName(), "-s", service, "-X", hex], stdin: nil)
        }
        return read(service: service) == data
    }

    private static func run(_ arguments: [String], stdin: Data?) -> (status: Int32, out: Data) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/security")
        process.arguments = arguments
        let out = Pipe(), input = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = input
        do { try process.run() } catch { return (-1, Data()) }
        if let stdin { input.fileHandleForWriting.write(stdin) }
        try? input.fileHandleForWriting.close()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, data)
    }
}
