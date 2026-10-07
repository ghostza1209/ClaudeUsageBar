import Foundation

public struct DayCost: Sendable, Equatable {
    public let day: Date
    public var cost: Double
}

public struct ModelUsage: Sendable, Equatable {
    public let model: String
    public var tokens = 0
    public var cost = 0.0
    /// Some of its usage had no price (unknown model or `speed: fast`), so `cost` is partial.
    public var unpriced = false
}

/// Everything the Usage tab shows. Tokens include advisor iterations; the per-model table and the unpriced count
/// cover the Billing cycle.
public struct UsageSummary: Sendable, Equatable {
    public var cycleStart: Date
    public var cycleCost = 0.0
    public var cycleTokens = Tokens()
    public var todayCost = 0.0, todayTokens = 0, todayRequests = 0
    /// Tokens per minute over the 60 minutes up to `now`, oldest first; the last bucket ends at `now`.
    public var lastHour = [Int](repeating: 0, count: 60)
    /// The last 14 local days, oldest first, ending with today.
    public var daily: [DayCost]
    /// Most expensive first.
    public var models: [ModelUsage] = []
    public var unpricedModels: Int { models.filter(\.unpriced).count }
}

/// Midnight starting the Billing cycle that contains `now`. The start day is clamped to the month's last day;
/// before this month's start day the cycle began last month.
public func billingCycleStart(now: Date, calendar: Calendar, startDay: Int) -> Date {
    let today = calendar.startOfDay(for: now)
    func start(inMonthOf date: Date) -> Date {
        var components = calendar.dateComponents([.year, .month], from: date)
        components.day = min(max(startDay, 1), calendar.range(of: .day, in: .month, for: date)!.count)
        return calendar.date(from: components)!
    }
    let thisMonth = start(inMonthOf: today)
    return thisMonth <= today ? thisMonth : start(inMonthOf: calendar.date(byAdding: .month, value: -1, to: today)!)
}

public func summarize(
    _ store: RecordStore, prices: PriceTable, now: Date, calendar: Calendar, billingCycleStartDay: Int
) -> UsageSummary {
    let cycleStart = billingCycleStart(now: now, calendar: calendar, startDay: billingCycleStartDay)
    let today = calendar.dateInterval(of: .day, for: now)!
    var summary = UsageSummary(
        cycleStart: cycleStart,
        daily: (-13...0).map { DayCost(day: calendar.date(byAdding: .day, value: $0, to: today.start)!, cost: 0) })
    let earliest = min(cycleStart, summary.daily[0].day)
    var models: [String: ModelUsage] = [:]

    // One pass: a record is priced once however many of the windows it falls in.
    for record in store.records where earliest <= record.timestamp && record.timestamp < today.end {
        let parts = prices.parts(of: record)
        let cost = parts.reduce(0) { $0 + ($1.cost ?? 0) }
        let tokens = parts.reduce(0) { $0 + $1.tokens.total }
        if record.timestamp >= cycleStart {
            summary.cycleCost += cost
            for part in parts {
                summary.cycleTokens.add(part.tokens)
                var usage = models[part.model] ?? ModelUsage(model: part.model)
                usage.tokens += part.tokens.total
                usage.cost += part.cost ?? 0
                usage.unpriced = usage.unpriced || part.cost == nil
                models[part.model] = usage
            }
        }
        if let day = summary.daily.lastIndex(where: { $0.day <= record.timestamp }) {
            summary.daily[day].cost += cost
        }
        if record.timestamp >= today.start {
            summary.todayCost += cost
            summary.todayTokens += tokens
            summary.todayRequests += 1
        }
        let age = now.timeIntervalSince(record.timestamp)
        if age >= 0 && age < 3600 { summary.lastHour[59 - Int(age / 60)] += tokens }
    }
    summary.models = models.values.sorted { ($1.cost, $1.tokens, $0.model) < ($0.cost, $0.tokens, $1.model) }
    return summary
}
