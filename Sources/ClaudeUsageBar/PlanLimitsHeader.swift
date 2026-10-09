import SwiftUI
import UsageCore

/// The rings header. Each failure state replaces only this view with one tidy card.
struct PlanLimitsHeader: View {
    let usage: Usage
    @AppStorage(Usage.warningThresholdKey) private var warning = 80
    @AppStorage(Usage.criticalThresholdKey) private var critical = 95

    var body: some View {
        switch usage.planLimits {
        case .notInstalled:
            problem("exclamationmark.triangle", .orange, "Wrapper not installed", detail: usage.wrapperError, install: true)
        case .noData:
            problem("hourglass", .secondary, "No Plan limits yet. Run Claude Code on a Pro or Max plan.")
        case .unreadable(let reason):
            problem("bolt.slash", .red, "Plan limits unreadable: \(reason)")
        case .ok(let fiveHour, let sevenDay, let capturedAt):
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    ring("5-hour", fiveHour, weekly: false)
                    ring("Weekly", sevenDay, weekly: true)
                }
                Text(ageText(capturedAt: capturedAt, now: usage.now)).font(.caption2)
                    .foregroundStyle(isStale(capturedAt: capturedAt, now: usage.now) ? .orange : .secondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func problem(_ icon: String, _ color: Color, _ message: String, detail: String? = nil, install: Bool = false) -> some View {
        Card {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.title2).foregroundStyle(color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(message).font(.callout)
                    if let detail { Text(detail).font(.caption).foregroundStyle(.red) }
                }
                Spacer(minLength: 0)
                if install {
                    Button("Install…") { usage.installWrapper() }.buttonStyle(.borderedProminent).controlSize(.small)
                }
            }
        }
    }

    private func ring(_ name: String, _ window: LimitWindow?, weekly: Bool) -> some View {
        let percent = window?.displayPercent(now: usage.now) ?? 0
        let color: Color =
            switch limitLevel(percent: percent, warning: Double(warning), critical: Double(critical)) {
            case .normal: .accentColor
            case .warning: .orange
            case .critical: .red
            }
        let reset = window.map { resetText($0.resetsAt, now: usage.now, weekly: weekly, calendar: .current) } ?? "no usage yet"
        return Card {
            HStack(spacing: 8) {
                ZStack {
                    Circle().stroke(.quaternary, lineWidth: 5)
                    Circle().trim(from: 0, to: percent / 100)
                        .stroke(
                            AngularGradient(colors: [color.opacity(0.5), color], center: .center, startAngle: .zero, endAngle: .degrees(max(1, 360 * percent / 100))),
                            style: .init(lineWidth: 5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .opacity(percent > 0 ? 1 : 0)
                    Text("\(Int(percent.rounded()))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                }
                .frame(width: 42, height: 42)
                .animation(.snappy, value: percent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.callout.weight(.semibold))
                    Text(reset).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) limit \(Int(percent.rounded())) percent, \(reset)")
    }
}
