import Foundation

private let enUS = Locale(identifier: "en_US")

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
