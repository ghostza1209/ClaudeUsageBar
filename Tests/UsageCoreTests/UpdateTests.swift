import Foundation
import Testing
import UsageCore

@Test(arguments: [
    ("v1.0.2", "1.0.1", "1.0.2"),
    ("v1.0.10", "1.0.9", "1.0.10"),
    ("1.1", "1.0.1", "1.1"),
    ("v1.0.1", "1.0.1", nil),
    ("v1.0.0", "1.0.1", nil),
])
func newerReleaseComparesNumerically(tag: String, current: String, expected: String?) {
    #expect(newerRelease(Data(#"{"tag_name":"\#(tag)","name":"x"}"#.utf8), than: current) == expected)
}

@Test func newerReleaseIgnoresAnErrorBody() {
    #expect(newerRelease(Data(#"{"message":"API rate limit exceeded"}"#.utf8), than: "1.0.1") == nil)
}
