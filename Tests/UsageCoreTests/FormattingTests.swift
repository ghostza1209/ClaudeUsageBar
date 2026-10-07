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

@Test(arguments: [
    (0.0, "$0.00"),
    (0.004, "<$0.01"),
    (0.0099, "<$0.01"),
    (0.01, "$0.01"),
    (18.4, "$18.40"),
    (3_124.5, "$3,124.50"),
    (1_234_567.891, "$1,234,567.89"),
])
func fullCurrencyFormats(amount: Double, expected: String) {
    #expect(fullCurrency(amount) == expected)
}

@Test func compactCurrencyIgnoresNonUSLocale() throws {
    UserDefaults.standard.setVolatileDomain(["AppleLocale": "de_DE"], forName: UserDefaults.argumentDomain)
    defer { UserDefaults.standard.removeVolatileDomain(forName: UserDefaults.argumentDomain) }
    try #require(Locale.current.identifier == "de_DE")
    #expect(compactCurrency(18.42) == "$18.42")
    #expect(compactCurrency(1_234_567.0) == "$1,234.6k")
    #expect(fullCurrency(3_124.5) == "$3,124.50")
}

@Test(arguments: [
    (-5.0, "0s"), (42.0, "42s"), (59.9, "59s"), (60.0, "1m"), (3599.0, "59m"),
    (3600.0, "1h 0m"), (11_579.0, "3h 12m"), (86_400.0, "1d 0h"), (187_800.0, "2d 4h"),
] as [(Double, String)])
func uptimeUsesTheTwoLargestUnits(seconds: Double, expected: String) {
    #expect(formatUptime(seconds) == expected)
}

@Test(arguments: [
    (0, "0 MB"), (413_000_000, "394 MB"), (1_072_693_248, "1023 MB"), (1_073_741_824, "1.0 GB"), (1_288_490_189, "1.2 GB"),
] as [(UInt64, String)])
func memoryIsMBBelowAGigabyte(bytes: UInt64, expected: String) {
    #expect(formatMemory(bytes) == expected)
}

@Test func cpuShowsADashUntilTheSecondSample() {
    #expect(formatCPU(nil) == "—")
    #expect(formatCPU(12.34) == "12.3%")
    #expect(formatCPU(0) == "0.0%")
}
