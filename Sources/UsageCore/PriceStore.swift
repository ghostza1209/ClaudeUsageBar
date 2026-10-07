import Foundation

public struct PriceUpdateError: Error, Sendable {
    public let message: String
}

/// The live price table: the fetched cache (`prices.json` in `supportDir`) if there is one, else the bundled snapshot.
public actor PriceStore {
    public private(set) var table: PriceTable
    /// When `table` was fetched (cache file mtime on load, the clock after an update). nil for the bundled snapshot,
    /// whose age is unknown, so nothing shows an age for it.
    public private(set) var fetchedAt: Date?
    private let cacheURL: URL
    private let fetcher: @Sendable () async throws -> Data
    private let clock: @Sendable () -> Date

    public init(supportDir: URL, fetcher: @escaping @Sendable () async throws -> Data, clock: @escaping @Sendable () -> Date = { .now }) {
        cacheURL = supportDir.appending(path: "prices.json")
        (self.fetcher, self.clock) = (fetcher, clock)
        if let data = try? Data(contentsOf: cacheURL), let cached = try? PriceTable(litellm: data) {
            table = cached
            fetchedAt = try? cacheURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        } else {
            table = .bundled
        }
    }

    /// Fetches and adopts a new table. On any failure the current table and cache stay as they are. The UI's
    /// "Update now" shows `message`; the scheduled fetch ignores the result.
    public func updateNow() async -> Result<Void, PriceUpdateError> {
        let data: Data
        do { data = try await fetcher() } catch { return .failure(PriceUpdateError(message: error.localizedDescription)) }
        let fetched: PriceTable
        do { fetched = try PriceTable(litellm: data) } catch {
            return .failure(error as? PriceUpdateError ?? PriceUpdateError(message: "The downloaded table is not valid JSON"))
        }
        // The cache holds the trimmed (Claude-only) table, so a launch parses a few KB, not the whole file.
        if let trimmed = try? JSONEncoder().encode(fetched.models) { try? trimmed.write(to: cacheURL, options: .atomic) }
        (table, fetchedAt) = (fetched, clock())
        return .success(())
    }
}

/// Popover note, only once the table is older than 7 days.
public func priceAgeNote(fetchedAt: Date?, now: Date) -> String? {
    guard let fetchedAt, now.timeIntervalSince(fetchedAt) > 7 * 86400 else { return nil }
    return "prices updated \(Int(now.timeIntervalSince(fetchedAt) / 86400)) days ago"
}
