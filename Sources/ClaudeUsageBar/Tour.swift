import SwiftUI

/// One stop of the first-run tour. `tab` is the popover tab shown behind the card, nil to leave it as is;
/// `target` is the part of the popover the spotlight frames, nil for none.
struct TourStep {
    let icon: String, title: String, text: String, tab: Int?, target: TourTarget?

    static let all = [
        TourStep(icon: "gauge.with.dots.needle.67percent", title: "Welcome to Claude Usage Bar",
                 text: "The gauge in the menu bar shows how much of your Weekly limit you have used, and when it resets.", tab: nil, target: nil),
        TourStep(icon: "circle.dashed", title: "Plan limits",
                 text: "Your 5-hour and Weekly limits, straight from Claude Code. If you see ⚠, press Install… once.", tab: nil, target: .header),
        TourStep(icon: "chart.bar", title: "Usage",
                 text: "Cost for the billing cycle and today at API list prices (an estimate, not your plan bill), tokens and charts.", tab: 0, target: .content),
        TourStep(icon: "cpu", title: "Processes",
                 text: "Every running Claude Code session with its CPU, memory and uptime. Stop one from here.", tab: 1, target: .content),
        TourStep(icon: "arrow.triangle.branch", title: "Git",
                 text: "Status of the repos Claude Code has been working in.", tab: 2, target: .content),
        TourStep(icon: "gearshape", title: "Settings",
                 text: "Pick the menu bar window and colour, notification thresholds and your billing-cycle start day. ⌘, opens it.", tab: nil, target: .settings),
    ]
}

enum TourTarget { case header, content, settings, card }

/// Bounds of each view marked with `tourTarget(_:)`, read by `Spotlight`.
struct TourTargets: PreferenceKey {
    static let defaultValue: [TourTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourTarget: Anchor<CGRect>], nextValue: () -> [TourTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func tourTarget(_ target: TourTarget) -> some View {
        anchorPreference(key: TourTargets.self, value: .bounds) { [target: $0] }
    }
}

/// Dims the popover except the step's target and the tour card, and rings the target. Clicks pass through.
struct Spotlight: View {
    let target: TourTarget?
    let anchors: [TourTarget: Anchor<CGRect>]

    var body: some View {
        GeometryReader { proxy in
            let hole = target.flatMap { anchors[$0] }.map { proxy[$0].insetBy(dx: -4, dy: -4) }
            let card = anchors[.card].map { proxy[$0] }
            if let hole {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: proxy.size))
                    for rect in [hole, card].compactMap({ $0 }) { path.addRoundedRect(in: rect, cornerSize: CGSize(width: 10, height: 10)) }
                }
                .fill(.black.opacity(0.45), style: FillStyle(eoFill: true))
                RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: hole.width, height: hole.height)
                    .position(x: hole.midX, y: hole.midY)
            }
        }
        .allowsHitTesting(false)
        .animation(.snappy(duration: 0.25), value: target)
    }
}

/// Shown above the popover footer until finished or skipped.
struct TourCard: View {
    @Binding var step: Int
    let done: () -> Void

    var body: some View {
        let current = TourStep.all[step]
        let last = step == TourStep.all.count - 1
        Card {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: current.icon).font(.title2).foregroundStyle(Color.accentColor).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.title).font(.callout.weight(.semibold))
                    Text(current.text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .id(step)
            .transition(.opacity)
            HStack {
                Button("Skip", action: done).buttonStyle(.borderless).foregroundStyle(.secondary).opacity(last ? 0 : 1)
                Spacer()
                HStack(spacing: 4) {
                    ForEach(TourStep.all.indices, id: \.self) {
                        Circle().fill($0 == step ? Color.accentColor : Color.secondary.opacity(0.4)).frame(width: 5, height: 5)
                    }
                }
                .accessibilityLabel("Step \(step + 1) of \(TourStep.all.count)")
                Spacer()
                if step > 0 { Button("Back") { step -= 1 } }
                Button(last ? "Done" : "Next") { if last { done() } else { step += 1 } }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .animation(.snappy(duration: 0.2), value: step)
    }
}
