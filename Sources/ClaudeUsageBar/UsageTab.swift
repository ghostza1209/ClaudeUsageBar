import Charts
import SwiftUI
import UsageCore

private let enUS = Locale(identifier: "en_US")

private func tokenCount(_ n: Int) -> String { n.formatted(.number.notation(.compactName).locale(enUS)) }

/// TermTracker order: Billing cycle, token breakdown, Today, last hour, 14 days, per model.
struct UsageTab: View {
    let usage: Usage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let scan = usage.scan {
                Label(scan.total > 0 ? "Scanning \(scan.done)/\(scan.total) files" : "Scanning files", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if usage.scan == nil && !usage.hasLogs {
                VStack(spacing: 6) {
                    Image(systemName: "doc.text.magnifyingglass").font(.title2)
                    Text("no Claude Code logs yet").font(.caption)
                }
                .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if let s = usage.summary {
                content(s)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .top)
    }

    @ViewBuilder private func content(_ s: UsageSummary) -> some View {
        Text("Billing cycle · since " + s.cycleStart.formatted(.dateTime.month(.abbreviated).day().locale(enUS)))
            .font(.caption).foregroundStyle(.secondary)
        HStack(alignment: .firstTextBaseline) {
            Text(fullCurrency(s.cycleCost)).font(.title.bold().monospacedDigit())
            Text("API list estimate").font(.caption).foregroundStyle(.secondary)
        }
        if s.unpricedModels > 0 {
            Text("excludes \(s.unpricedModels) unpriced model\(s.unpricedModels == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(.orange)
        }
        if let note = priceAgeNote(fetchedAt: usage.pricesFetchedAt, now: .now) {
            Text(note).font(.caption).foregroundStyle(.secondary)
        }
        HStack {
            ForEach([("Input", s.cycleTokens.input), ("Output", s.cycleTokens.output),
                     ("Cache read", s.cycleTokens.cacheRead), ("Cache write", s.cycleTokens.cacheWrite)], id: \.0) { name, n in
                VStack(alignment: .leading) {
                    Text(tokenCount(n)).font(.callout.monospacedDigit())
                    Text(name).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        Divider()
        HStack {
            Text("Today").font(.caption.bold())
            Text(fullCurrency(s.todayCost)).font(.caption.monospacedDigit())
            Spacer()
            Text("\(tokenCount(s.todayTokens)) tokens · \(s.todayRequests.formatted(.number.locale(enUS))) requests")
                .font(.caption2).foregroundStyle(.secondary)
        }
        Text("Last hour · tokens/min").font(.caption2).foregroundStyle(.secondary)
        Chart(Array(s.lastHour.enumerated()), id: \.offset) {
            AreaMark(x: .value("min", $0.offset), y: .value("tokens/min", $0.element))
                .foregroundStyle(.linearGradient(colors: [.accentColor.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom))
        }
        .chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 40)
        Text("14 days").font(.caption2).foregroundStyle(.secondary)
        Chart(s.daily, id: \.day) {
            BarMark(x: .value("day", $0.day, unit: .day), y: .value("$", $0.cost))
                .foregroundStyle($0.day == s.daily.last?.day ? Color.accentColor : .secondary.opacity(0.5))
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                // Drop ".00" so ticks read `$0`, `$50`, `$1.2k`.
                AxisValueLabel(value.as(Double.self).map { compactCurrency($0).replacing(".00", with: "") } ?? "")
            }
        }
        .frame(height: 60)
        Grid(alignment: .leading, verticalSpacing: 4) {
            ForEach(s.models, id: \.model) { m in
                GridRow {
                    Text(m.unpriced ? m.model + " (unpriced)" : m.model).lineLimit(1).truncationMode(.middle)
                    Text(tokenCount(m.tokens)).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    Text(fullCurrency(m.cost)).monospacedDigit().gridColumnAlignment(.trailing)
                }
            }
        }
        .font(.caption)
    }
}
