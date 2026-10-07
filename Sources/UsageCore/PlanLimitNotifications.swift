import Foundation

public enum LimitWindowName: String, Codable, Sendable { case fiveHour, sevenDay }

/// A threshold crossing to announce. `level` is `.warning` or `.critical`.
public struct LimitNotification: Equatable, Sendable {
    public let window: LimitWindowName
    public let level: LimitLevel
    public let percent: Double
    public let resetsAt: Date

    public init(window: LimitWindowName, level: LimitLevel, percent: Double, resetsAt: Date) {
        (self.window, self.level, self.percent, self.resetsAt) = (window, level, percent, resetsAt)
    }
}

/// What was already announced, persisted by the app between launches so a relaunch never repeats a notification.
public struct NotificationState: Codable, Equatable, Sendable {
    /// The `capturedAt` last evaluated; a capture is only evaluated once.
    var lastCapturedAt: Date?
    /// Per window (keyed by `LimitWindowName.rawValue`): the highest level announced for that `resets_at`.
    var announced: [String: Announced] = [:]

    struct Announced: Codable, Equatable, Sendable {
        var resetsAt: Date
        var level: LimitLevel
    }

    public init() {}
}

/// Decides which notifications a new Plan-limits read fires. Only a fresh `.ok` capture (new `capturedAt`, not stale)
/// counts, and a window past its `resets_at` is skipped (its percent is the old, reset-zeroed value). Per window a level
/// fires once per `resets_at`; a jump past both thresholds fires only `.critical`, with `.warning` consumed. A changed
/// `resets_at` re-arms the window. `critical` is held above `warning`. When `enabled` is false nothing fires but the
/// capture is still consumed, so enabling later announces only crossings seen after that.
public func planLimitNotifications(
    state: NotificationState, limits: PlanLimits, now: Date, warning: Double, critical: Double, enabled: Bool
) -> (fire: [LimitNotification], state: NotificationState) {
    guard case .ok(let fiveHour, let sevenDay, let capturedAt) = limits, capturedAt != state.lastCapturedAt else {
        return ([], state)
    }
    var state = state
    state.lastCapturedAt = capturedAt
    guard !isStale(capturedAt: capturedAt, now: now) else { return ([], state) }

    let critical = max(critical, warning + 1)
    var fire: [LimitNotification] = []
    for (name, window) in [(LimitWindowName.fiveHour, fiveHour), (.sevenDay, sevenDay)] {
        guard let window, now < window.resetsAt else { continue }
        var announced = state.announced[name.rawValue]
        if announced?.resetsAt != window.resetsAt { announced = .init(resetsAt: window.resetsAt, level: .normal) }
        let level = limitLevel(percent: window.percent, warning: warning, critical: critical)
        if level > announced!.level {
            announced!.level = level
            fire.append(LimitNotification(window: name, level: level, percent: window.percent, resetsAt: window.resetsAt))
        }
        state.announced[name.rawValue] = announced
    }
    return (enabled ? fire : [], state)
}
