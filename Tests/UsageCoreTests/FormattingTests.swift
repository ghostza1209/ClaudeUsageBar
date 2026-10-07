import Foundation
import Testing
import UsageCore

@Test(arguments: [
    (0.0, "$0.00"),
    (18.42, "$18.42"),
    (99.994, "$99.99"),
    (99.995, "$100"),
    (123.4, "$123"),
    (999.49, "$999"),
    (999.60, "$1.0k"),
    (1_000.0, "$1.0k"),
    (1_249.0, "$1.2k"),
    (1_234_567.0, "$1,234.6k"),
])
func compactCurrencyBands(amount: Double, expected: String) {
    #expect(compactCurrency(amount) == expected)
}

@Test func compactCurrencyIgnoresNonUSLocale() throws {
    UserDefaults.standard.setVolatileDomain(["AppleLocale": "de_DE"], forName: UserDefaults.argumentDomain)
    try #require(Locale.current.identifier == "de_DE")
    #expect(compactCurrency(18.42) == "$18.42")
    #expect(compactCurrency(1_234_567.0) == "$1,234.6k")
}
