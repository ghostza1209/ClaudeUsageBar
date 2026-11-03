import Foundation
import Testing
import UsageCore

private let weekly = LimitWindow(percent: 27, resetsAt: Date(timeIntervalSince1970: 1_800_400_000))
private let reset = Date(timeIntervalSince1970: 1_800_000_000)
private func five(resetsAt: Date = reset) -> LimitWindow { LimitWindow(percent: 40, resetsAt: resetsAt) }
private func capture(fiveHour: LimitWindow?, at capturedAt: Date) -> PlanLimits {
    .ok(fiveHour: fiveHour, sevenDay: weekly, capturedAt: capturedAt)
}

@Test func aFiveHourWindowNeverSeenIsUncapped() {
    #expect(FiveHourHistory().isUncapped(capture(fiveHour: nil, at: reset)))
}

@Test func aCaptureThatHasTheFiveHourWindowIsNeverUncapped() {
    #expect(!FiveHourHistory().isUncapped(capture(fiveHour: five(), at: reset)))
}

@Test func aWindowMissingRightAfterItsRememberedResetIsNotUncapped() {
    var history = FiveHourHistory()
    history.observe(capture(fiveHour: five(), at: reset.addingTimeInterval(-3600)))
    #expect(!history.isUncapped(capture(fiveHour: nil, at: reset.addingTimeInterval(60))))
    #expect(!history.isUncapped(capture(fiveHour: nil, at: reset.addingTimeInterval(5 * 3600))))
}

@Test func aWindowMissingMoreThanFiveHoursAfterItsRememberedResetIsUncapped() {
    var history = FiveHourHistory()
    history.observe(capture(fiveHour: five(), at: reset.addingTimeInterval(-3600)))
    #expect(history.isUncapped(capture(fiveHour: nil, at: reset.addingTimeInterval(5 * 3600 + 1))))
}

@Test func seeingTheWindowAgainClearsTheUncappedVerdict() {
    var history = FiveHourHistory()
    history.observe(capture(fiveHour: five(), at: reset.addingTimeInterval(-3600)))
    let later = reset.addingTimeInterval(10 * 3600)
    history.observe(capture(fiveHour: five(resetsAt: later.addingTimeInterval(5 * 3600)), at: later))
    #expect(!history.isUncapped(capture(fiveHour: nil, at: later.addingTimeInterval(3600))))
}

@Test func aCaptureWithoutTheWindowDoesNotForgetTheRememberedReset() {
    var history = FiveHourHistory()
    history.observe(capture(fiveHour: five(), at: reset.addingTimeInterval(-3600)))
    history.observe(capture(fiveHour: nil, at: reset.addingTimeInterval(30)))
    #expect(!history.isUncapped(capture(fiveHour: nil, at: reset.addingTimeInterval(60))))
}

@Test func statesWithoutAGoodCaptureAreNeverUncapped() {
    #expect(!FiveHourHistory().isUncapped(.noData))
    #expect(!FiveHourHistory().isUncapped(.unreadable("x")))
    #expect(!FiveHourHistory().isUncapped(.notInstalled))
}
