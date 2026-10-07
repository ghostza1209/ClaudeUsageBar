import Foundation

private let enUS = Locale(identifier: "en_US")

/// Full dollar amount for the popover: `$3,124.50`; `<$0.01` for a non-zero amount that would round to nothing.
public func fullCurrency(_ amount: Double) -> String {
    if amount > 0 && amount < 0.01 { return "<$0.01" }
    return amount.formatted(.currency(code: "USD").precision(.fractionLength(2)).locale(enUS))
}

/// Compact dollar amount for the menu bar title and trend axis: `$18.42`, `$123`, `$1.2k`.
/// The band is chosen on the rounded value, so $999.60 shows `$1.0k`.
public func compactCurrency(_ amount: Double) -> String {
    let cents = (amount * 100).rounded()
    if cents < 10_000 {
        return (cents / 100).formatted(.currency(code: "USD").precision(.fractionLength(2)).locale(enUS))
    }
    let dollars = amount.rounded()
    if dollars < 1_000 {
        return "$\(Int(dollars))"
    }
    let thousands = (amount / 100).rounded() / 10
    return "$" + thousands.formatted(.number.precision(.fractionLength(1)).locale(enUS)) + "k"
}

/// `42s`, `7m`, `3h 12m`, `2d 4h`: the two largest units.
public func formatUptime(_ seconds: TimeInterval) -> String {
    let s = Int(max(seconds, 0))
    if s < 60 { return "\(s)s" }
    if s < 3600 { return "\(s / 60)m" }
    if s < 86_400 { return "\(s / 3600)h \(s % 3600 / 60)m" }
    return "\(s / 86_400)d \(s % 86_400 / 3600)h"
}

/// `394 MB`, `1.2 GB` (powers of 1024, as Activity Monitor).
public func formatMemory(_ bytes: UInt64) -> String {
    let mb = Double(bytes) / 1_048_576
    if mb < 1024 { return "\(Int(mb.rounded())) MB" }
    return (mb / 1024).formatted(.number.precision(.fractionLength(1)).locale(enUS)) + " GB"
}

/// `12.3%`, or `—` before the second sample.
public func formatCPU(_ percent: Double?) -> String {
    percent.map { $0.formatted(.number.precision(.fractionLength(1)).locale(enUS)) + "%" } ?? "—"
}
