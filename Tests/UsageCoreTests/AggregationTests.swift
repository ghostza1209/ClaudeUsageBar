import Foundation
import Testing
import UsageCore

private func at(_ utc: String) -> Date { try! Date.ISO8601FormatStyle().parse(utc) }

private func records(_ lines: [String]) -> RecordStore {
    var store = RecordStore()
    for record in parseUsageLines(Data(lines.joined(separator: "\n").utf8)) { store.insert(record) }
    return store
}

// Bangkok is UTC+7, so local midnight is 17:00Z the day before.
@Test(arguments: [
    ("2026-10-07T05:00:00Z", 1, "2026-09-30T17:00:00Z"),   // Oct 7, day 1 -> Oct 1
    ("2026-10-07T05:00:00Z", 7, "2026-10-06T17:00:00Z"),   // start day is today -> Oct 7
    ("2026-10-07T05:00:00Z", 15, "2026-09-14T17:00:00Z"),  // before this month's day 15 -> Sep 15
    ("2027-01-10T05:00:00Z", 20, "2026-12-19T17:00:00Z"),  // across the year -> Dec 20
    ("2027-02-28T05:00:00Z", 31, "2027-02-27T17:00:00Z"),  // 31 clamps to Feb 28
    ("2027-03-15T05:00:00Z", 31, "2027-02-27T17:00:00Z"),  // Mar 31 not reached: last month's Feb 28
    ("2027-03-31T05:00:00Z", 31, "2027-03-30T17:00:00Z"),  // Mar 31
    ("2028-03-15T05:00:00Z", 31, "2028-02-28T17:00:00Z"),  // leap year: Feb 29
])
func billingCycleStartClampsToMonthEnd(now: String, day: Int, start: String) {
    #expect(billingCycleStart(now: at(now), calendar: bangkok, startDay: day) == at(start))
}

@Test func summaryAggregatesCycleTodayHourDaysAndModels() {
    // now = Oct 7 12:00 local; start day 5 -> cycle began Oct 5 00:00 local (Oct 4 17:00Z).
    let store = records([
        // 30 min ago, today, in cycle: $1 input + $1 output at m
        line(id: "a", at: "2026-10-07T04:30:00.000Z", usage: #""input_tokens":1000000,"output_tokens":100000"#),
        // 30 s ago: $0.50 at m, plus an advisor at adv: $0.10 input + $0.10 output
        line(id: "b", at: "2026-10-07T04:59:30.000Z", usage: #"""
            "input_tokens":500000,"iterations":[{"type":"advisor_message","model":"adv","input_tokens":10000,"output_tokens":1000}]
            """#.replacingOccurrences(of: "\n", with: "")),
        // 61 min ago, today, Unpriced model
        line(id: "c", at: "2026-10-07T03:59:00.000Z", model: "zz", usage: #""input_tokens":2000000"#),
        // yesterday, in cycle: $1 cache read + 2 web searches at $0.01
        line(id: "d", at: "2026-10-06T10:00:00.000Z", usage: #""cache_read_input_tokens":10000000,"server_tool_use":{"web_search_requests":2}"#),
        // Oct 4 local: in the 14-day series, before the cycle
        line(id: "e", at: "2026-10-04T10:00:00.000Z", usage: #""input_tokens":3000000"#),
        // Sep 20: in neither, so its Unpriced model is not counted
        line(id: "f", at: "2026-09-20T10:00:00.000Z", model: "old-unknown", usage: #""input_tokens":9000000"#),
    ])
    let s = summarize(store, prices: prices, now: now, calendar: bangkok, billingCycleStartDay: 5)

    #expect(s.cycleStart == at("2026-10-04T17:00:00Z"))
    #expect(abs(s.cycleCost - 3.72) < 1e-9)
    #expect(s.cycleTokens == Tokens(input: 3_510_000, output: 101_000, cacheRead: 10_000_000))
    #expect(abs(s.todayCost - 2.70) < 1e-9)
    #expect((s.todayTokens, s.todayRequests) == (3_611_000, 3))

    #expect(s.lastHour.count == 60)
    #expect(s.lastHour[29] == 1_100_000)
    #expect(s.lastHour[59] == 511_000)
    #expect(s.lastHour.reduce(0, +) == 1_611_000)

    #expect(s.daily.count == 14)
    #expect(s.daily[0].day == at("2026-09-23T17:00:00Z"))
    #expect(s.daily[13].day == at("2026-10-06T17:00:00Z"))
    #expect(s.daily.map(\.cost).enumerated().filter { $0.element != 0 }.map { "\($0.offset):\(String(format: "%.2f", $0.element))" }
        == ["10:3.00", "12:1.02", "13:2.70"])
    #expect(s.daily.enumerated().filter { $0.element.requests > 0 }.map { "\($0.offset):\($0.element.tokens)/\($0.element.requests)" }
        == ["10:3000000/1", "12:10000000/1", "13:3611000/3"])

    #expect(s.models.map(\.model) == ["m", "adv", "zz"])
    #expect(s.models.map(\.tokens) == [11_600_000, 11_000, 2_000_000])
    #expect(zip(s.models.map(\.cost), [3.52, 0.2, 0]).allSatisfy { abs($0 - $1) < 1e-9 })
    #expect(s.unpricedModels == 1)
}

@Test func lastHourBucketsAreMinutesBackFromNow() {
    let s = summarize(records([
        line(id: "edge", at: "2026-10-07T04:00:00.000Z", usage: #""input_tokens":1"#),   // exactly 60 min ago: out
        line(id: "oldest", at: "2026-10-07T04:00:01.000Z", usage: #""input_tokens":10"#), // 59:59 ago: first bucket
        line(id: "now", at: "2026-10-07T05:00:00.000Z", usage: #""input_tokens":100"#),   // now: last bucket
        line(id: "future", at: "2026-10-07T05:00:01.000Z", usage: #""input_tokens":1000"#),
    ]), prices: prices, now: now, calendar: bangkok, billingCycleStartDay: 1)
    #expect(s.lastHour[0] == 10)
    #expect(s.lastHour[59] == 100)
    #expect(s.lastHour.reduce(0, +) == 110)
}

@Test func emptyStoreSummarizesToZeros() {
    let s = summarize(RecordStore(), prices: prices, now: now, calendar: bangkok, billingCycleStartDay: 1)
    #expect((s.cycleCost, s.todayRequests, s.models.count, s.unpricedModels) == (0, 0, 0, 0))
    #expect(s.cycleStart == at("2026-09-30T17:00:00Z"))
}
