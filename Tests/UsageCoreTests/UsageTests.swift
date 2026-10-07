import Foundation
import Testing
import UsageCore

// $/token: m = $1 in, $10 out, $0.10 cache read, $2 5m write, $4 1h write per MTok.
let prices = try! PriceTable(json: Data("""
{
 "m": {"input_cost_per_token": 1e-6, "output_cost_per_token": 1e-5, "cache_read_input_token_cost": 1e-7,
       "cache_creation_input_token_cost": 2e-6, "cache_creation_input_token_cost_above_1hr": 4e-6},
 "anthropic/p": {"input_cost_per_token": 1e-5, "output_cost_per_token": 0, "cache_read_input_token_cost": 0,
       "cache_creation_input_token_cost": 0, "cache_creation_input_token_cost_above_1hr": 0},
 "adv": {"input_cost_per_token": 1e-5, "output_cost_per_token": 1e-4, "cache_read_input_token_cost": 0,
       "cache_creation_input_token_cost": 0, "cache_creation_input_token_cost_above_1hr": 0}
}
""".utf8))

let bangkok: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Bangkok")!
    return calendar
}()
let now = Date(timeIntervalSince1970: 1_791_349_200)  // 2026-10-07T05:00:00Z = 12:00 in Bangkok

func line(
    id: String = "msg_1", req: String = "req_1", at: String = "2026-10-07T05:00:00.000Z", model: String = "m",
    usage: String = #""input_tokens":0,"output_tokens":0"#
) -> String {
    #"{"type":"assistant","timestamp":"\#(at)","requestId":"\#(req)","sessionId":"s1","cwd":"/w","#
        + #""message":{"id":"\#(id)","model":"\#(model)","content":[],"usage":{\#(usage)}}}"#
}

func tree(_ files: [String: [String]]) throws -> URL {
    let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    for (path, lines) in files {
        let url = home.appending(path: "projects/" + path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(lines.map { $0 + "\n" }.joined().utf8).write(to: url)
    }
    try FileManager.default.createDirectory(at: home.appending(path: "projects"), withIntermediateDirectories: true)
    return home
}

func scan(_ home: URL) -> RecordStore {
    var cache = UsageCache()
    cache.update(claudeHome: home, now: now, calendar: bangkok)
    return cache.store
}

private func cost(_ usage: String, model: String = "m") -> Double {
    prices.cost(of: parseUsageLines(Data(line(model: model, usage: usage).utf8))[0])
}

@Test func parserExtractsFields() throws {
    let usage = #"""
        "input_tokens":1,"output_tokens":2,"cache_read_input_tokens":3,"cache_creation_input_tokens":300,
        "cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":100},
        "server_tool_use":{"web_search_requests":2},"speed":"standard",
        "iterations":[{"type":"message","input_tokens":1,"output_tokens":2},
                      {"type":"advisor_message","model":"adv","input_tokens":40,"output_tokens":5}]
        """#.replacingOccurrences(of: "\n", with: "")
    let records = parseUsageLines(Data([
        line(usage: usage),
        line(id: "msg_2", model: "<synthetic>"),
        "{not json",
        #"{"type":"user","message":{"usage":{}}}"#,
        #"{"skill":"x","usage":3}"#,
    ].joined(separator: "\n").utf8))

    try #require(records.count == 1)
    let r = records[0]
    #expect(r.timestamp == now)
    #expect((r.messageId, r.requestId, r.model, r.sessionId, r.cwd, r.speed) == ("msg_1", "req_1", "m", "s1", "/w", "standard"))
    // 5m write is the total minus the 1h part, since the split field said 0.
    #expect(r.tokens == Tokens(input: 1, output: 2, cacheRead: 3, cacheWrite5m: 200, cacheWrite1h: 100))
    #expect(r.webSearchRequests == 2)
    #expect(r.advisors.map(\.model) == ["adv"])
    #expect(r.advisors.map(\.tokens) == [Tokens(input: 40, output: 5)])
}

@Test func splitAndPartialLinesCountOnceAcrossFilesKeepingLargest() throws {
    let home = try tree([
        "-w/s1.jsonl": [
            line(usage: #""input_tokens":100000,"output_tokens":7"#),    // streamed partial
            line(usage: #""input_tokens":100000,"output_tokens":3220"#), // final
            line(usage: #""input_tokens":100000,"output_tokens":7"#),    // another block of the same response
        ],
        "-w/s1/subagents/agent-a.jsonl": [
            line(usage: #""input_tokens":100000,"output_tokens":7"#),    // replayed partial copy
            line(req: "req_2", usage: #""input_tokens":0,"output_tokens":1000"#), // same message id, new request
        ],
    ])
    let store = scan(home)
    #expect(store.records.count == 2)
    // $0.10 input + $0.0322 output + $0.01 for req_2
    #expect(abs(todayCost(store, prices: prices, now: now, calendar: bangkok) - 0.1422) < 1e-9)
}

@Test func pricing() {
    // 1M of each token kind: $1 + $10 + $0.10 + $2 + $4
    #expect(abs(cost(#"""
        "input_tokens":1000000,"output_tokens":1000000,"cache_read_input_tokens":1000000,"cache_creation_input_tokens":2000000,\#
        "cache_creation":{"ephemeral_5m_input_tokens":1000000,"ephemeral_1h_input_tokens":1000000}
        """#) - 17.10) < 1e-9)
    #expect(abs(cost(#""input_tokens":100000"#, model: "p") - 1.0) < 1e-9)  // via anthropic/ prefix
    #expect(cost(#""input_tokens":100000"#, model: "unknown") == 0)
    #expect(cost(#""input_tokens":100000,"speed":"fast""#) == 0)
    #expect(abs(cost(#""input_tokens":0,"server_tool_use":{"web_search_requests":3}"#) - 0.03) < 1e-9)
    // main $0.001 at m, advisor $0.10 + $0.10 at its own model
    #expect(abs(cost(#"""
        "input_tokens":1000,"iterations":[{"type":"advisor_message","model":"adv","input_tokens":10000,"output_tokens":1000}]
        """#) - 0.201) < 1e-9)
}

@Test func bundledSnapshotPricesOpus55AtListPrice() {
    let record = parseUsageLines(Data(line(model: "claude-opus-5-5", usage: #""input_tokens":1000000,"output_tokens":1000000"#).utf8))[0]
    #expect(abs(PriceTable.bundled.cost(of: record) - 24.0) < 1e-9)  // $4 in + $20 out per MTok
}

@Test func todayFollowsLocalMidnight() throws {
    let home = try tree(["-w/s.jsonl": [
        line(id: "a", at: "2026-10-06T16:59:59.999Z", usage: #""input_tokens":1000000"#), // 23:59 Oct 6 local
        line(id: "b", at: "2026-10-06T17:00:00.000Z", usage: #""input_tokens":2000000"#), // 00:00 Oct 7 local
        line(id: "c", at: "2026-10-07T16:59:00.000Z", usage: #""input_tokens":4000000"#), // 23:59 Oct 7 local
        line(id: "d", at: "2026-10-07T17:00:00.000Z", usage: #""input_tokens":8000000"#), // 00:00 Oct 8 local
    ]])
    #expect(abs(todayCost(scan(home), prices: prices, now: now, calendar: bangkok) - 6.0) < 1e-9)
}

@Test func titleStates() throws {
    func title(_ files: [String: [String]]) throws -> String {
        menuBarTitle(scan(try tree(files)), prices: prices, now: now, calendar: bangkok)
    }
    #expect(try title([:]) == "—")
    #expect(try title(["-w/plugin/skill-injections.jsonl": [#"{"skill":"x"}"#]]) == "—")
    #expect(try title(["-w/s.jsonl": [line(at: "2026-10-06T05:00:00.000Z", usage: #""input_tokens":1000000"#)]]) == "$0.00")
    #expect(try title(["-w/s.jsonl": [line(usage: #""input_tokens":18420000"#)]]) == "$18.42")
}

@Test func titleShowsATrailingWarningWhileTheWrapperIsNotInstalled() {
    #expect(titleWithWarning("$18.42", warning: false) == "$18.42")
    #expect(titleWithWarning("$18.42", warning: true) == "$18.42 ⚠")
    #expect(titleWithWarning("—", warning: true) == "— ⚠")
    #expect(titleWithWarning(nil, warning: false) == nil)  // icon only while scanning
    #expect(titleWithWarning(nil, warning: true) == "⚠")
}
