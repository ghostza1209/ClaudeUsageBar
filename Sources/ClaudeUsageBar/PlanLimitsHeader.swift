import SwiftUI
import UsageCore

/// The rings header. Each failure state replaces only this view with a one-line message.
struct PlanLimitsHeader: View {
    let usage: Usage
    @AppStorage(Usage.warningThresholdKey) private var warning = 80
    @AppStorage(Usage.criticalThresholdKey) private var critical = 95

    var body: some View {
        switch usage.planLimits {
        case .notInstalled:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Wrapper not installed").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Install…") { usage.installWrapper() }.controlSize(.small)
                }
                if let error = usage.wrapperError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        case .noData:
            message("No Plan limits yet. Run Claude Code on a Pro or Max plan.", .secondary)
        case .unreadable(let reason):
            message("Plan limits unreadable: \(reason)", .red)
        case .ok(let fiveHour, let sevenDay, let capturedAt):
            VStack(spacing: 6) {
                HStack(spacing: 16) {
                    ring("5h", fiveHour, weekly: false)
                    ring("Week", sevenDay, weekly: true)
                }
                .frame(maxWidth: .infinity)
                Text(ageText(capturedAt: capturedAt, now: usage.now)).font(.caption2)
                    .foregroundStyle(isStale(capturedAt: capturedAt, now: usage.now) ? .orange : .secondary)
            }
        }
    }

    private func message(_ text: String, _ style: Color) -> some View {
        Text(text).font(.caption).foregroundStyle(style).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ring(_ name: String, _ window: LimitWindow?, weekly: Bool) -> some View {
        let percent = window?.displayPercent(now: usage.now) ?? 0
        let color: Color =
            switch limitLevel(percent: percent, warning: Double(warning), critical: Double(critical)) {
            case .normal: .accentColor
            case .warning: .orange
            case .critical: .red
            }
        return HStack(spacing: 8) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 6)
                Circle().trim(from: 0, to: percent / 100).stroke(color, style: .init(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(window == nil ? "—" : "\(Int(percent.rounded()))%").font(.caption.bold().monospacedDigit())
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading) {
                Text(name).font(.callout.bold())
                Text(window.map { resetText($0.resetsAt, now: usage.now, weekly: weekly, calendar: .current) } ?? "no data")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
