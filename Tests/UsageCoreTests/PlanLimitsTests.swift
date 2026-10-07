import Foundation
import Testing
import UsageCore

private let captured = Date(timeIntervalSince1970: 1_799_990_000)
private let reset5h = Date(timeIntervalSince1970: 1_800_000_000)  // Fri 2027-01-15 08:00 UTC
private let resetWeek = Date(timeIntervalSince1970: 1_800_400_000)
private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
}

/// A support dir holding `statusline-input.json` with the given text and mtime.
private func supportDir(capture: String?, mtime: Date = captured) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    if let capture {
        let file = dir.appending(path: StatuslineWrapper.captureFileName)
        try Data(capture.utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: file.path)
    }
    return dir
}

private func read(_ capture: String?, installed: Bool = true) throws -> PlanLimits {
    readPlanLimits(supportDir: try supportDir(capture: capture), wrapperInstalled: installed)
}

private let both = """
    {"model":{"id":"x"},"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1800000000},
    "seven_day":{"used_percentage":41,"resets_at":1800400000}},"cwd":"/tmp"}
    """

@Test func readsBothWindowsAndCapturedAtIsTheFileMtime() throws {
    #expect(try read(both) == .ok(
        fiveHour: LimitWindow(percent: 23.5, resetsAt: reset5h), sevenDay: LimitWindow(percent: 41, resetsAt: resetWeek),
        capturedAt: captured))
}

@Test func notInstalledWinsOverAFreshCaptureFile() throws {
    #expect(try read(both, installed: false) == .notInstalled)
}

@Test(arguments: [
    nil, "{}", #"{"rate_limits":null}"#, #"{"rate_limits":{}}"#, #"{"rate_limits":{"five_hour":null,"seven_day":null}}"#,
] as [String?])
func noDataWithoutRateLimits(capture: String?) throws {
    #expect(try read(capture) == .noData)
}

@Test(arguments: [
    "{not json", "[]", "", #"{"rate_limits":"x"}"#, #"{"rate_limits":{"five_hour":5}}"#,
    #"{"rate_limits":{"five_hour":{"resets_at":1}}}"#, #"{"rate_limits":{"five_hour":{"used_percentage":"9","resets_at":1}}}"#,
    #"{"rate_limits":{"seven_day":{"used_percentage":9}}}"#,
])
func unreadableOnMalformedCapture(capture: String) throws {
    guard case .unreadable(let reason) = try read(capture) else { Issue.record("not unreadable"); return }
    #expect(!reason.isEmpty)
}

@Test func aCaptureThatIsNotAFileIsUnreadable() throws {
    let dir = try supportDir(capture: nil)
    try FileManager.default.createDirectory(at: dir.appending(path: StatuslineWrapper.captureFileName), withIntermediateDirectories: false)
    #expect(readPlanLimits(supportDir: dir, wrapperInstalled: true) == .unreadable("cannot read the capture file"))
}

@Test func aWindowClaudeCodeLeftOutIsNilWhileTheOtherShows() throws {
    let capture = #"{"rate_limits":{"seven_day":{"used_percentage":7,"resets_at":1800400000}}}"#
    #expect(try read(capture) == .ok(fiveHour: nil, sevenDay: LimitWindow(percent: 7, resetsAt: resetWeek), capturedAt: captured))
}

@Test func percentIsClampedTo0Through100() throws {
    let capture = #"{"rate_limits":{"five_hour":{"used_percentage":130,"resets_at":1800000000},"seven_day":{"used_percentage":-4,"resets_at":1800400000}}}"#
    #expect(try read(capture) == .ok(
        fiveHour: LimitWindow(percent: 100, resetsAt: reset5h), sevenDay: LimitWindow(percent: 0, resetsAt: resetWeek),
        capturedAt: captured))
}

@Test func windowReadsZeroFromItsResetInstant() {
    let window = LimitWindow(percent: 62, resetsAt: reset5h)
    #expect(window.displayPercent(now: reset5h.addingTimeInterval(-1)) == 62)
    #expect(window.displayPercent(now: reset5h) == 0)
    #expect(window.displayPercent(now: reset5h.addingTimeInterval(3600)) == 0)
}

@Test func titleWarnsOnlyForNotInstalledAndUnreadable() {
    let ok = PlanLimits.ok(fiveHour: nil, sevenDay: nil, capturedAt: captured)
    #expect(PlanLimits.notInstalled.warnsInTitle)
    #expect(PlanLimits.unreadable("x").warnsInTitle)
    #expect(!PlanLimits.noData.warnsInTitle)
    #expect(!ok.warnsInTitle)
}

@Test func ringLevelChangesExactlyAtTheThresholds() {
    func level(_ percent: Double) -> LimitLevel { limitLevel(percent: percent, warning: 80, critical: 95) }
    #expect(level(79.9) == .normal)
    #expect(level(80) == .warning)
    #expect(level(94.9) == .warning)
    #expect(level(95) == .critical)
    #expect(limitLevel(percent: 55, warning: 50, critical: 60) == .warning)
}

@Test func staleAfterTenMinutes() {
    #expect(!isStale(capturedAt: captured, now: captured.addingTimeInterval(600)))
    #expect(isStale(capturedAt: captured, now: captured.addingTimeInterval(601)))
}

@Test func ageTextByMagnitude() {
    func age(_ seconds: TimeInterval) -> String { ageText(capturedAt: captured, now: captured.addingTimeInterval(seconds)) }
    #expect(age(-30) == "updated just now")
    #expect(age(59) == "updated just now")
    #expect(age(4 * 60 + 20) == "updated 4 min ago")
    #expect(age(3 * 3600 + 120) == "updated 3 h ago")
    #expect(age(50 * 3600) == "updated 2 d ago")
}

@Test func resetTextIsRelativeFor5HourAndWeekdayTimeForWeekly() {
    func five(_ before: TimeInterval) -> String {
        resetText(reset5h, now: reset5h.addingTimeInterval(-before), weekly: false, calendar: utc)
    }
    #expect(five(2 * 3600 + 14 * 60 + 30) == "resets in 2h 14m")
    #expect(five(14 * 60) == "resets in 14m")
    #expect(five(30) == "resets in <1m")
    #expect(five(-1) == "reset passed")
    #expect(resetText(reset5h, now: captured, weekly: true, calendar: utc) == "resets Fri 08:00")
    #expect(resetText(reset5h, now: reset5h, weekly: true, calendar: utc) == "reset passed")
}
