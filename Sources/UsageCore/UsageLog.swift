import Foundation

public struct Tokens: Sendable, Equatable, Codable {
    public var input = 0, output = 0, cacheRead = 0, cacheWrite5m = 0, cacheWrite1h = 0
    public var total: Int { input + output + cacheRead + cacheWrite5m + cacheWrite1h }
    public var cacheWrite: Int { cacheWrite5m + cacheWrite1h }

    mutating func add(_ other: Tokens) {
        input += other.input; output += other.output; cacheRead += other.cacheRead
        cacheWrite5m += other.cacheWrite5m; cacheWrite1h += other.cacheWrite1h
    }

    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite5m: Int = 0, cacheWrite1h: Int = 0) {
        (self.input, self.output, self.cacheRead, self.cacheWrite5m, self.cacheWrite1h) = (input, output, cacheRead, cacheWrite5m, cacheWrite1h)
    }
}

public struct AdvisorIteration: Sendable, Equatable, Codable {
    public let model: String
    public let tokens: Tokens
}

/// One API response from an `assistant` log line.
public struct UsageRecord: Sendable, Equatable, Codable {
    public let messageId: String
    public let requestId: String?
    public let timestamp: Date
    public let model: String
    public let sessionId: String?
    public let cwd: String?
    public let tokens: Tokens
    public let webSearchRequests: Int
    public let speed: String?
    public let advisors: [AdvisorIteration]
}

/// Records deduped globally on `(message.id, requestId)`, keeping the copy with the largest token total,
/// because a response is split over several lines and streamed partials repeat it with smaller counts.
public struct RecordStore: Sendable {
    struct Key: Hashable { let messageId: String, requestId: String? }
    private var byKey: [Key: UsageRecord] = [:]

    public init() {}

    public var records: some Collection<UsageRecord> { byKey.values }

    public mutating func insert(_ record: UsageRecord) {
        let key = Key(messageId: record.messageId, requestId: record.requestId)
        if let kept = byKey[key], kept.tokens.total >= record.tokens.total { return }
        byKey[key] = record
    }
}

private let usageNeedle = Array(#""usage""#.utf8)
private let iso8601 = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

/// Parses newline-separated log lines into records. Non-assistant, `<synthetic>` and malformed lines are skipped.
public func parseUsageLines(_ data: Data) -> [UsageRecord] {
    // Only lines containing `"usage"` are JSON-decoded; memchr/memmem is ~4x faster than Data.split + firstRange.
    var lines: [Data] = []
    data.withUnsafeBytes { buffer in
        guard let base = buffer.baseAddress else { return }
        var start = 0
        while start < buffer.count {
            let end = memchr(base + start, 0x0A, buffer.count - start).map { UnsafeRawPointer($0) - base } ?? buffer.count
            if memmem(base + start, end - start, usageNeedle, usageNeedle.count) != nil {
                lines.append(Data(bytes: base + start, count: end - start))
            }
            start = end + 1
        }
    }
    let decoder = JSONDecoder()
    return lines.compactMap { line in
        guard let raw = try? decoder.decode(RawLine.self, from: line),
              raw.type == "assistant",
              let message = raw.message, let id = message.id, let model = message.model, model != "<synthetic>",
              let usage = message.usage,
              let timestamp = raw.timestamp.flatMap({ try? iso8601.parse($0) })
        else { return nil }
        return UsageRecord(
            messageId: id, requestId: raw.requestId, timestamp: timestamp, model: model,
            sessionId: raw.sessionId, cwd: raw.cwd, tokens: usage.tokens,
            webSearchRequests: usage.server_tool_use?.web_search_requests ?? 0, speed: usage.speed,
            advisors: (usage.iterations ?? []).compactMap { iteration in
                guard iteration.type == "advisor_message", let model = iteration.model else { return nil }
                return AdvisorIteration(model: model, tokens: iteration.tokens)
            })
    }
}

private struct RawLine: Decodable {
    let type: String?
    let timestamp: String?
    let requestId: String?
    let sessionId: String?
    let cwd: String?
    let message: Message?

    struct Message: Decodable {
        let id: String?
        let model: String?
        let usage: Usage?
    }

    struct Usage: Decodable {
        let input_tokens: Int?
        let output_tokens: Int?
        let cache_read_input_tokens: Int?
        let cache_creation_input_tokens: Int?
        let cache_creation: CacheCreation?
        let server_tool_use: ServerToolUse?
        let speed: String?
        let iterations: [Usage]?
        let type: String?
        let model: String?

        /// The 5m/1h split doesn't always add up to `cache_creation_input_tokens`; the remainder is billed as 5m.
        var tokens: Tokens {
            let write1h = cache_creation?.ephemeral_1h_input_tokens ?? 0
            let writeTotal = cache_creation_input_tokens ?? (cache_creation?.ephemeral_5m_input_tokens ?? 0) + write1h
            return Tokens(
                input: input_tokens ?? 0, output: output_tokens ?? 0, cacheRead: cache_read_input_tokens ?? 0,
                cacheWrite5m: max(writeTotal - write1h, 0), cacheWrite1h: write1h)
        }
    }

    struct CacheCreation: Decodable {
        let ephemeral_5m_input_tokens: Int?
        let ephemeral_1h_input_tokens: Int?
    }

    struct ServerToolUse: Decodable {
        let web_search_requests: Int?
    }
}
