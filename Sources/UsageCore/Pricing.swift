import Foundation

/// Per-token USD prices, as LiteLLM's `model_prices_and_context_window.json` spells them.
struct ModelPrice: Decodable, Sendable {
    let input_cost_per_token: Double
    let output_cost_per_token: Double
    let cache_read_input_token_cost: Double
    let cache_creation_input_token_cost: Double
    let cache_creation_input_token_cost_above_1hr: Double

    func cost(_ t: Tokens) -> Double {
        Double(t.input) * input_cost_per_token + Double(t.output) * output_cost_per_token
            + Double(t.cacheRead) * cache_read_input_token_cost
            + Double(t.cacheWrite5m) * cache_creation_input_token_cost
            + Double(t.cacheWrite1h) * cache_creation_input_token_cost_above_1hr
    }
}

public struct PriceTable: Sendable {
    let models: [String: ModelPrice]

    public init(json: Data) throws {
        models = try JSONDecoder().decode([String: ModelPrice].self, from: json)
    }

    /// Claude-only LiteLLM snapshot shipped with the app.
    public static let bundled = try! PriceTable(
        json: Data(contentsOf: Bundle.module.url(forResource: "prices", withExtension: "json")!))

    /// API list estimate of one record. An Unpriced model (no match, or `speed: fast`) adds nothing;
    /// advisor iterations are priced at their own model.
    public func cost(of record: UsageRecord) -> Double {
        parts(of: record).reduce(0) { $0 + ($1.cost ?? 0) }
    }

    /// The record's own model, then each advisor iteration at its own model. `cost` is nil for an Unpriced model.
    func parts(of record: UsageRecord) -> [(model: String, tokens: Tokens, cost: Double?)] {
        let own = record.speed == "fast" ? nil : price(record.model)
        var parts = [(record.model, record.tokens, own.map { $0.cost(record.tokens) + Double(record.webSearchRequests) * 0.01 })]
        for advisor in record.advisors {
            parts.append((advisor.model, advisor.tokens, price(advisor.model)?.cost(advisor.tokens)))
        }
        return parts
    }

    private func price(_ model: String) -> ModelPrice? {
        models[model] ?? models["anthropic/" + model]
    }
}

/// Today's (local calendar) API list estimate.
public func todayCost(_ store: RecordStore, prices: PriceTable, now: Date, calendar: Calendar) -> Double {
    let today = calendar.dateInterval(of: .day, for: now)!
    return store.records.filter { today.start <= $0.timestamp && $0.timestamp < today.end }.reduce(0) { $0 + prices.cost(of: $1) }
}

/// Menu bar title text: `—` with no records, else today's compact $.
public func menuBarTitle(_ store: RecordStore, prices: PriceTable, now: Date, calendar: Calendar) -> String {
    store.records.isEmpty ? "—" : compactCurrency(todayCost(store, prices: prices, now: now, calendar: calendar))
}
