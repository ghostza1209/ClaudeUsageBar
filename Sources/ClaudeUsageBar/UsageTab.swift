import Charts
import SwiftUI
import UsageCore

private let enUS = Locale(identifier: "en_US")

private func tokenCount(_ n: Int) -> String { n.formatted(.number.notation(.compactName).locale(enUS)) }

/// TermTracker order: Billing cycle with token breakdown, Today with last hour, 14 days, per model.
struct UsageTab: View {
    let usage: Usage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let scan = usage.scan {
                Label(scan.total > 0 ? "Scanning \(scan.done)/\(scan.total) files" : "Scanning files", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if usage.scan == nil && !usage.hasLogs {
                EmptyNote("doc.text.magnifyingglass", "no Claude Code logs yet")
            } else if let s = usage.summary {
                cycle(s)
                today(s)
                days(s)
                models(s)
            }
        }
    }

    private func cycle(_ s: UsageSummary) -> some View {
        let t = s.cycleTokens
        let parts = [("Input", t.input, Color.blue), ("Output", t.output, .green), ("Cache read", t.cacheRead, .purple), ("Cache write", t.cacheWrite, .orange)]
        return Card("Billing cycle · since " + s.cycleStart.formatted(.dateTime.month(.abbreviated).day().locale(enUS))) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(fullCurrency(s.cycleCost)).font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text("API list estimate").font(.caption).foregroundStyle(.secondary)
            }
            let note = priceAgeNote(fetchedAt: usage.pricesFetchedAt, now: .now)
            if s.unpricedModels > 0 || note != nil {
                HStack(spacing: 6) {
                    if s.unpricedModels > 0 { Chip("excludes \(s.unpricedModels) unpriced model\(s.unpricedModels == 1 ? "" : "s")", .orange) }
                    if let note { Chip(note, .secondary) }
                }
            }
            GeometryReader { g in
                let shown = parts.filter { $0.1 > 0 }
                let room = g.size.width - 2 * Double(max(shown.count - 1, 0))
                HStack(spacing: 2) {
                    ForEach(shown, id: \.0) { $0.2.frame(width: room * Double($0.1) / Double(t.total)) }
                }
            }
            .frame(height: 8).clipShape(Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(parts.map { "\($0.0) \(tokenCount($0.1))" }.joined(separator: ", "))
            HStack {
                ForEach(parts, id: \.0) { name, n, color in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Circle().fill(color).frame(width: 7, height: 7)
                            Text(name).font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(tokenCount(n)).font(.callout.weight(.medium).monospacedDigit())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func today(_ s: UsageSummary) -> some View {
        Card("Today") {
            HStack(alignment: .firstTextBaseline) {
                Text(fullCurrency(s.todayCost)).font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
                    .contentTransition(.numericText())
                Spacer()
                Text("\(tokenCount(s.todayTokens)) tokens · \(s.todayRequests.formatted(.number.locale(enUS))) requests")
                    .font(.caption).foregroundStyle(.secondary)
            }
            SectionTitle("Last hour · tokens/min")
            Chart(Array(s.lastHour.enumerated()), id: \.offset) {
                AreaMark(x: .value("min", $0.offset), y: .value("tokens/min", $0.element))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.linearGradient(colors: [.accentColor.opacity(0.5), .accentColor.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("min", $0.offset), y: .value("tokens/min", $0.element))
                    .interpolationMethod(.catmullRom).foregroundStyle(Color.accentColor)
            }
            .chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 30)
        }
    }

    private func days(_ s: UsageSummary) -> some View {
        let today = s.daily.last?.day
        return Card("14 days") {
            Chart(s.daily, id: \.day) {
                BarMark(x: .value("day", $0.day, unit: .day), y: .value("$", $0.cost))
                    .cornerRadius(3)
                    .foregroundStyle($0.day == today ? Color.accentColor : Color.accentColor.opacity(0.35))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow).locale(enUS), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    // Drop ".00" so ticks read `$0`, `$50`, `$1.2k`.
                    AxisValueLabel(value.as(Double.self).map { compactCurrency($0).replacing(".00", with: "") } ?? "")
                }
            }
            .frame(height: 60)
        }
    }

    private func models(_ s: UsageSummary) -> some View {
        Card("Models") {
            ForEach(s.models, id: \.model) { m in
                let share = s.cycleCost > 0 ? min(m.cost / s.cycleCost, 1) : 0
                VStack(spacing: 3) {
                    HStack(spacing: 6) {
                        let name = m.model.hasPrefix("claude-") ? String(m.model.dropFirst(7)) : m.model
                        Text(m.unpriced ? name + " (unpriced)" : name).font(.callout).lineLimit(1).truncationMode(.middle)
                        Text(tokenCount(m.tokens)).font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(fullCurrency(m.cost)).font(.callout.monospacedDigit())
                    }
                    Capsule().fill(.quaternary).frame(height: 3)
                        .overlay(alignment: .leading) {
                            GeometryReader { Capsule().fill(Color.accentColor).frame(width: $0.size.width * share) }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(Int((share * 100).rounded())) percent of the billing-cycle cost")
                }
            }
        }
    }
}
