import Foundation
import Testing
import UsageCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let reset5h = t0.addingTimeInterval(3 * 3600)
private let resetWeek = t0.addingTimeInterval(4 * 86400)

private func ok(five: Double? = nil, week: Double? = nil, at: Date = t0, reset5h: Date = reset5h) -> PlanLimits {
    .ok(
        fiveHour: five.map { LimitWindow(percent: $0, resetsAt: reset5h) },
        sevenDay: week.map { LimitWindow(percent: $0, resetsAt: resetWeek) }, capturedAt: at)
}

/// Runs one evaluation 1 minute after the capture with the default 80/95 thresholds.
private func evaluate(
    _ state: NotificationState, _ limits: PlanLimits, now: Date = t0.addingTimeInterval(60),
    warning: Double = 80, critical: Double = 95, enabled: Bool = true
) -> (fire: [LimitNotification], state: NotificationState) {
    planLimitNotifications(state: state, limits: limits, now: now, warning: warning, critical: critical, enabled: enabled)
}

@Test func crossingWarningFiresOnceThenStaysQuiet() {
    let first = evaluate(NotificationState(), ok(five: 81))
    #expect(first.fire == [LimitNotification(window: .fiveHour, level: .warning, percent: 81, resetsAt: reset5h)])

    let second = evaluate(first.state, ok(five: 84, at: t0.addingTimeInterval(30)))
    #expect(second.fire.isEmpty)
}

@Test func belowWarningFiresNothing() {
    #expect(evaluate(NotificationState(), ok(five: 79.9, week: 10)).fire.isEmpty)
}

@Test func criticalFiresAfterWarningWithoutRepeatingWarning() {
    let warned = evaluate(NotificationState(), ok(five: 82)).state
    let crit = evaluate(warned, ok(five: 96, at: t0.addingTimeInterval(30)))
    #expect(crit.fire.map(\.level) == [.critical])
    #expect(evaluate(crit.state, ok(five: 99, at: t0.addingTimeInterval(45))).fire.isEmpty)
}

@Test func jumpingPastBothFiresOnlyCriticalAndConsumesWarning() {
    let jump = evaluate(NotificationState(), ok(five: 97))
    #expect(jump.fire.map(\.level) == [.critical])
    // Dropping back into the warning band later must not announce the already-consumed warning.
    #expect(evaluate(jump.state, ok(five: 85, at: t0.addingTimeInterval(30))).fire.isEmpty)
}

@Test func windowsAreIndependent() {
    let five = evaluate(NotificationState(), ok(five: 90, week: 20))
    #expect(five.fire.map(\.window) == [.fiveHour])
    let week = evaluate(five.state, ok(five: 90, week: 85, at: t0.addingTimeInterval(30)))
    #expect(week.fire == [LimitNotification(window: .sevenDay, level: .warning, percent: 85, resetsAt: resetWeek)])
}

@Test func changedResetsAtRearmsTheWindow() {
    let warned = evaluate(NotificationState(), ok(five: 90)).state
    let later = t0.addingTimeInterval(4 * 3600)
    let newReset = later.addingTimeInterval(5 * 3600)
    let again = evaluate(warned, ok(five: 88, at: later, reset5h: newReset), now: later.addingTimeInterval(60))
    #expect(again.fire == [LimitNotification(window: .fiveHour, level: .warning, percent: 88, resetsAt: newReset)])
}

@Test func windowPastItsResetNeverFires() {
    let afterReset = reset5h.addingTimeInterval(5)
    let result = evaluate(NotificationState(), ok(five: 99, at: reset5h.addingTimeInterval(1)), now: afterReset)
    #expect(result.fire.isEmpty)
}

@Test func staleCaptureNeverFires() {
    let result = evaluate(NotificationState(), ok(five: 99), now: t0.addingTimeInterval(601))
    #expect(result.fire.isEmpty)
}

@Test func theSameCaptureIsEvaluatedOnce() {
    // A 50% capture consumes t0; a different read of the same capturedAt (as after a relaunch) must not fire.
    let seen = evaluate(NotificationState(), ok(five: 50)).state
    #expect(evaluate(seen, ok(five: 90)).fire.isEmpty)
}

@Test func disabledFiresNothingAndConsumesTheCrossing() {
    let off = evaluate(NotificationState(), ok(five: 90), enabled: false)
    #expect(off.fire.isEmpty)
    #expect(evaluate(off.state, ok(five: 91, at: t0.addingTimeInterval(30))).fire.isEmpty)
}

@Test func nonOkStatesFireNothingAndKeepState() {
    let warned = evaluate(NotificationState(), ok(five: 90)).state
    for limits in [PlanLimits.notInstalled, .noData, .unreadable("x")] {
        let result = evaluate(warned, limits)
        #expect(result.fire.isEmpty)
        #expect(result.state == warned)
    }
}

@Test func criticalAtOrBelowWarningIsHeldAboveIt() {
    let swapped = { (percent: Double) in evaluate(NotificationState(), ok(five: percent), warning: 90, critical: 80).fire.map(\.level) }
    #expect(swapped(89) == [])
    #expect(swapped(90) == [.warning])
    #expect(swapped(91) == [.critical])
}

@Test func announcedStateSurvivesARelaunch() throws {
    let warned = evaluate(NotificationState(), ok(five: 90)).state
    let relaunched = try JSONDecoder().decode(NotificationState.self, from: JSONEncoder().encode(warned))
    #expect(evaluate(relaunched, ok(five: 92, at: t0.addingTimeInterval(30))).fire.isEmpty)
    #expect(evaluate(relaunched, ok(five: 97, at: t0.addingTimeInterval(30))).fire.map(\.level) == [.critical])
}
