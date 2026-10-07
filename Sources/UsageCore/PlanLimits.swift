import Foundation

/// One rate-limit window from the capture file's `rate_limits`.
public struct LimitWindow: Equatable, Sendable {
    /// Percent used, clamped to 0...100.
    public let percent: Double
    public let resetsAt: Date

    public init(percent: Double, resetsAt: Date) { (self.percent, self.resetsAt) = (percent, resetsAt) }

    /// 0 once the window has reset (`now >= resetsAt`), even if no newer capture has arrived.
    public func displayPercent(now: Date) -> Double { now >= resetsAt ? 0 : percent }
}

/// The Plan-limits state shown in the popover header.
public enum PlanLimits: Equatable, Sendable {
    case notInstalled
    /// No capture file, or it has no `rate_limits`.
    case noData
    /// The capture file exists but cannot be used; carries a short reason.
    case unreadable(String)
    /// A window Claude Code left out of `rate_limits` is nil. `capturedAt` is the capture file's mtime.
    case ok(fiveHour: LimitWindow?, sevenDay: LimitWindow?, capturedAt: Date)

    /// The menu bar title carries a trailing ⚠ for these states.
    public var warnsInTitle: Bool {
        switch self {
        case .notInstalled, .unreadable: true
        case .noData, .ok: false
        }
    }
}

/// Reads the capture file in `supportDir`. `wrapperInstalled` wins over any (possibly stale) capture file.
public func readPlanLimits(supportDir: URL, wrapperInstalled: Bool) -> PlanLimits {
    guard wrapperInstalled else { return .notInstalled }
    let url = supportDir.appending(path: StatuslineWrapper.captureFileName)
    guard FileManager.default.fileExists(atPath: url.path) else { return .noData }
    guard let data = try? Data(contentsOf: url),
        let capturedAt = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    else { return .unreadable("cannot read the capture file") }
    guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return .unreadable("the capture file is not a JSON object")
    }
    guard let limits = root["rate_limits"], !(limits is NSNull) else { return .noData }
    guard let limits = limits as? [String: Any] else { return .unreadable("rate_limits is not an object") }

    var windows: [LimitWindow?] = []
    for name in ["five_hour", "seven_day"] {
        guard let raw = limits[name], !(raw is NSNull) else {
            windows.append(nil)
            continue
        }
        guard let object = raw as? [String: Any], let percent = object["used_percentage"] as? Double,
            let resets = object["resets_at"] as? Double
        else { return .unreadable("\(name) needs used_percentage and resets_at") }
        windows.append(LimitWindow(percent: min(max(percent, 0), 100), resetsAt: Date(timeIntervalSince1970: resets)))
    }
    if windows.allSatisfy({ $0 == nil }) { return .noData }
    return .ok(fiveHour: windows[0], sevenDay: windows[1], capturedAt: capturedAt)
}

public enum LimitLevel: Equatable, Sendable { case normal, warning, critical }

/// Ring colour level: normal below `warning`, warning from `warning`, critical from `critical`.
public func limitLevel(percent: Double, warning: Double, critical: Double) -> LimitLevel {
    percent >= critical ? .critical : percent >= warning ? .warning : .normal
}

/// A capture older than this is stale: the age line turns orange, and ticket 21 never notifies from it.
public let planLimitsStaleAfter: TimeInterval = 600

public func isStale(capturedAt: Date, now: Date) -> Bool { now.timeIntervalSince(capturedAt) > planLimitsStaleAfter }

/// `updated 4 min ago`; a capture newer than `now` reads as just now.
public func ageText(capturedAt: Date, now: Date) -> String {
    let minutes = max(0, Int(now.timeIntervalSince(capturedAt) / 60))
    switch minutes {
    case 0: return "updated just now"
    case ..<60: return "updated \(minutes) min ago"
    case ..<1440: return "updated \(minutes / 60) h ago"
    default: return "updated \(minutes / 1440) d ago"
    }
}

/// `resets in 2h 14m` for the 5-hour window, `resets Thu 14:00` (in `calendar`'s zone) for the Weekly one.
public func resetText(_ resetsAt: Date, now: Date, weekly: Bool, calendar: Calendar) -> String {
    guard resetsAt > now else { return "reset passed" }
    if weekly {
        let formatter = DateFormatter()
        (formatter.locale, formatter.timeZone, formatter.dateFormat) = (Locale(identifier: "en_US_POSIX"), calendar.timeZone, "EEE HH:mm")
        return "resets " + formatter.string(from: resetsAt)
    }
    let minutes = Int(resetsAt.timeIntervalSince(now) / 60)
    if minutes < 1 { return "resets in <1m" }
    return "resets in " + (minutes >= 60 ? "\(minutes / 60)h " : "") + "\(minutes % 60)m"
}
