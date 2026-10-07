import Foundation
import Testing
import UsageCore

private struct Offline: Error {}

private func entry(input: String) -> String {
    #"{"input_cost_per_token": \#(input), "output_cost_per_token": 0, "cache_read_input_token_cost": 0, "#
        + #""cache_creation_input_token_cost": 0, "cache_creation_input_token_cost_above_1hr": 0, "mode": "chat"}"#
}

/// A LiteLLM-shaped download: `claude-opus-5-5` at $2/MTok in, a non-Claude model, and the `sample_spec` row.
private let litellm = Data("""
{"sample_spec": {"input_cost_per_token": 0.0, "mode": "one of chat, embedding"},
 "claude-opus-5-5": \(entry(input: "2e-6")),
 "gpt-x": \(entry(input: "9e-6")),
 "anthropic.claude-opus-5-5": \(entry(input: "9e-6")),
 "claude-no-prices": {"mode": "chat"}}
""".utf8)

private func supportDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// $ for 1M input tokens of `model`.
private func cost(_ table: PriceTable, _ model: String) -> Double {
    table.cost(of: parseUsageLines(Data(line(model: model, usage: #""input_tokens":1000000"#).utf8))[0])
}

@Test func bundledSnapshotUntilFetchedTableWinsAndPersists() async throws {
    let dir = try supportDir()
    let store = PriceStore(supportDir: dir, fetcher: { litellm })
    #expect(abs(cost(await store.table, "claude-opus-5-5") - 4.0) < 1e-9)  // bundled: $4/MTok
    #expect(await store.fetchedAt == nil)

    guard case .success = await store.updateNow() else { Issue.record("update failed"); return }
    #expect(abs(cost(await store.table, "claude-opus-5-5") - 2.0) < 1e-9)  // fetched over bundled

    let relaunched = PriceStore(supportDir: dir, fetcher: { throw Offline() })
    #expect(abs(cost(await relaunched.table, "claude-opus-5-5") - 2.0) < 1e-9)  // cache over bundled
}

@Test func fetchedTableKeepsOnlyClaudeEntriesWithAllPriceFields() async throws {
    let store = PriceStore(supportDir: try supportDir(), fetcher: { litellm })
    _ = await store.updateNow()
    let table = await store.table
    #expect(cost(table, "gpt-x") == 0)  // Unpriced: not a Claude key
    #expect(cost(table, "anthropic.claude-opus-5-5") == 0)  // a Bedrock copy
    #expect(cost(table, "claude-no-prices") == 0)
    #expect(cost(table, "claude-haiku-4-5") == 0)  // bundled entries are gone, not merged
}

@Test func failedFetchKeepsTableAndWritesNoCache() async throws {
    for download in [Data("<html>404</html>".utf8), Data(#"{"gpt-x": \#(entry(input: "9e-6"))}"#.utf8), Data("{}".utf8), nil] {
        let dir = try supportDir()
        let store = PriceStore(supportDir: dir, fetcher: { if let download { download } else { throw Offline() } })
        guard case .failure(let error) = await store.updateNow() else { Issue.record("expected failure"); return }
        #expect(!error.message.isEmpty)
        #expect(abs(cost(await store.table, "claude-opus-5-5") - 4.0) < 1e-9)
        #expect(await store.fetchedAt == nil)
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "prices.json").path))
    }
}

@Test func failedFetchKeepsPreviouslyFetchedTable() async throws {
    let dir = try supportDir()
    let ok = PriceStore(supportDir: dir, fetcher: { litellm })
    _ = await ok.updateNow()
    let flaky = PriceStore(supportDir: dir, fetcher: { throw Offline() })
    _ = await flaky.updateNow()
    #expect(abs(cost(await flaky.table, "claude-opus-5-5") - 2.0) < 1e-9)
}

@Test func tableAgeIsTheFetchTime() async throws {
    let dir = try supportDir()
    let store = PriceStore(supportDir: dir, fetcher: { litellm }, clock: { now })
    _ = await store.updateNow()
    #expect(await store.fetchedAt == now)

    let tenDaysAgo = now.addingTimeInterval(-10 * 86400)
    try FileManager.default.setAttributes([.modificationDate: tenDaysAgo], ofItemAtPath: dir.appending(path: "prices.json").path)
    let relaunched = PriceStore(supportDir: dir, fetcher: { throw Offline() }, clock: { now })
    #expect(await relaunched.fetchedAt == tenDaysAgo)
}

@Test func ageNoteAppearsOnlyAfterSevenDays() {
    func note(daysAgo: Double) -> String? { priceAgeNote(fetchedAt: now.addingTimeInterval(-daysAgo * 86400), now: now) }
    #expect(note(daysAgo: 0.5) == nil)
    #expect(note(daysAgo: 7) == nil)
    #expect(note(daysAgo: 12.3) == "prices updated 12 days ago")
    #expect(priceAgeNote(fetchedAt: nil, now: now) == nil)
}
