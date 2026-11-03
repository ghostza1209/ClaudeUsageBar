import Foundation

public struct FiveHourHistory: Codable, Equatable, Sendable {
    private static let windowLength: TimeInterval = 5 * 3600
    /// The `resets_at` of the last 5-hour window a capture carried.
    var lastResetsAt: Date?

    public init() {}

    public mutating func observe(_ limits: PlanLimits) {
        if case .ok(.some(let window), _, _) = limits { lastResetsAt = window.resetsAt }
    }
    public func isUncapped(_ limits: PlanLimits) -> Bool {
        guard case .ok(nil, _, let capturedAt) = limits else { return false }
        guard let lastResetsAt else { return true }
        return capturedAt.timeIntervalSince(lastResetsAt) > Self.windowLength
    }
}
