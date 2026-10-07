// PROTOTYPE, throw away.
// Plan: three structurally different popover layouts (sub-shape B: no app exists yet), switchable with
// `--variant A|B|C` or the ‹ › strip / ←→ keys, crossed with a data-state toggle (`--state <name>`, ↑↓ keys)
// that shows every empty and failure state. All data is hardcoded; nothing reads ~/.claude.
// Run: swift run --package-path .scratch/claude-usage-bar/prototypes/menubar-popover-PROTOTYPE -- --variant A
import AppKit
import Charts
import SwiftUI

// MARK: - Switch axes

enum Variant: String, CaseIterable {
    case A, B, C
    var name: String {
        switch self {
        case .A: "Tabs + Plan limits strip"
        case .B: "One scrolling dashboard"
        case .C: "Rings header + bottom tab bar"
        }
    }
}

enum DataState: String, CaseIterable {
    case normal, noLogs, wrapperMissing, limitsNoData, limitsUnreadable, limitsStale, sourcesFailed
    var label: String {
        switch self {
        case .normal: "normal"
        case .noLogs: "no logs yet"
        case .wrapperMissing: "wrapper not installed"
        case .limitsNoData: "Plan limits: no data yet"
        case .limitsUnreadable: "Plan limits: unreadable"
        case .limitsStale: "Plan limits: stale (5h reset passed)"
        case .sourcesFailed: "git/processes failed, none running"
        }
    }
}

@Observable final class Proto {
    var variant: Variant
    var state: DataState
    init() {
        let args = CommandLine.arguments
        func arg(_ k: String) -> String? { args.firstIndex(of: k).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
        variant = arg("--variant").flatMap(Variant.init) ?? .A
        state = arg("--state").flatMap(DataState.init) ?? .normal
    }
    func cycleVariant(_ d: Int) { variant = Variant.allCases[(Variant.allCases.firstIndex(of: variant)! + d + 3) % 3] }
    func cycleState(_ d: Int) {
        let all = DataState.allCases
        state = all[(all.firstIndex(of: state)! + d + all.count) % all.count]
    }
}

// MARK: - Fake data

struct Limit { let name: String; let pct: Double; let resets: String }
struct ModelRow { let model: String; let tokens: String; let cost: Double }
struct Proc { let project: String; let cwd: String; let cpu: Double; let ramMB: Int; let uptime: String }
struct Repo { let name: String; let branch: String; let dirty: Int; let ahead: Int; let behind: Int; let last: String; let ago: String }

enum Fake {
    static let todayCost = 18.42
    static let cycleCost = 412.77
    static let cycle = "Billing cycle · since Sep 15"
    static let cycleTokens: [(String, String)] = [("Input", "1.2M"), ("Output", "3.8M"), ("Cache read", "412M"), ("Cache write", "21M")]
    static let todayTokens = "14.6M tokens · 212 requests"
    static let lastHour: [Double] = (0..<60).map { i in max(0, 900 + 700 * sin(Double(i) / 6) + Double((i * 37) % 300)) }
    static let trend: [Double] = [22, 31, 12, 0, 8, 44, 38, 27, 19, 51, 33, 29, 40, 18.42]
    static let models = [ModelRow(model: "Opus 5.5", tokens: "302M", cost: 341.10),
                         ModelRow(model: "Sonnet 5.5", tokens: "121M", cost: 64.02),
                         ModelRow(model: "Haiku 4.5", tokens: "15M", cost: 7.65)]
    static let limits = [Limit(name: "5-hour window", pct: 0.63, resets: "resets in 1h 52m"),
                         Limit(name: "Weekly window", pct: 0.84, resets: "resets Thu 09:00")]
    static let procs = [Proc(project: "claude-usage-bar", cwd: "~/Desktop/projects/personal/claude-usage-bar", cpu: 4.1, ramMB: 412, uptime: "1h 07m"),
                        Proc(project: "fazwaz", cwd: "~/Desktop/projects/work/fazwaz", cpu: 22.8, ramMB: 655, uptime: "3h 41m"),
                        Proc(project: "popdeal-web", cwd: "~/Desktop/projects/work/popdeal-web", cpu: 0.3, ramMB: 298, uptime: "12m")]
    static let repos = [Repo(name: "claude-usage-bar", branch: "main", dirty: 3, ahead: 0, behind: 0, last: "Add map", ago: "8m"),
                        Repo(name: "fazwaz", branch: "OP-2374-fix-search", dirty: 0, ahead: 2, behind: 5, last: "Fix resolver N+1", ago: "41m"),
                        Repo(name: "popdeal-web", branch: "develop", dirty: 12, ahead: 0, behind: 0, last: "Bump deps", ago: "2d")]
}

// MARK: - Shared bits (small widgets only; layouts are per variant)

let money: FloatingPointFormatStyle<Double>.Currency = .currency(code: "USD").precision(.fractionLength(2))

struct LimitsMessage: View {
    let state: DataState
    var body: some View {
        switch state {
        case .wrapperMissing:
            HStack { Image(systemName: "puzzlepiece.extension"); Text("Plan limits need the statusline wrapper.").font(.caption); Spacer(); Button("Install…") {}.controlSize(.small) }
        case .limitsNoData:
            HStack { Image(systemName: "hourglass"); Text("No Plan limits yet. Run Claude Code (Pro/Max) to capture them.").font(.caption) }
        case .limitsUnreadable:
            HStack { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange); Text("Plan limits file unreadable: unexpected JSON at rate_limits.five_hour").font(.caption) }
        default: EmptyView()
        }
    }
}

func limitsAvailable(_ s: DataState) -> Bool { ![.wrapperMissing, .limitsNoData, .limitsUnreadable].contains(s) }

func limits(for s: DataState) -> [Limit] {
    s == .limitsStale ? [Limit(name: "5-hour window", pct: 0, resets: "reset passed, 0%"), Fake.limits[1]] : Fake.limits
}

func ageText(_ s: DataState) -> String { s == .limitsStale ? "updated 47 min ago" : "updated 1 min ago" }

func pctColor(_ pct: Double) -> Color { pct >= 0.95 ? .red : pct >= 0.8 ? .orange : .accentColor }

struct LimitBar: View {
    let l: Limit
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(l.name).font(.caption); Spacer(); Text(l.pct, format: .percent.precision(.fractionLength(0))).font(.caption.monospacedDigit().bold()) }
            ProgressView(value: l.pct).tint(pctColor(l.pct))
            Text(l.resets).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct Sparkline: View {
    var height: CGFloat = 40
    var body: some View {
        Chart(Array(Fake.lastHour.enumerated()), id: \.offset) { AreaMark(x: .value("min", $0.offset), y: .value("tok/min", $0.element)).foregroundStyle(.linearGradient(colors: [.accentColor.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)) }
            .chartXAxis(.hidden).chartYAxis(.hidden).frame(height: height)
    }
}

struct Trend: View {
    var height: CGFloat = 60
    var body: some View {
        Chart(Array(Fake.trend.enumerated()), id: \.offset) { BarMark(x: .value("day", $0.offset), y: .value("$", $0.element)).foregroundStyle($0.offset == 13 ? Color.accentColor : .secondary.opacity(0.5)) }
            .chartXAxis(.hidden).chartYAxis(.hidden).frame(height: height)
    }
}

struct ModelsTable: View {
    var body: some View {
        Grid(alignment: .leading, verticalSpacing: 4) {
            ForEach(Fake.models, id: \.model) { m in
                GridRow { Text(m.model); Text(m.tokens).foregroundStyle(.secondary).gridColumnAlignment(.trailing); Text(m.cost, format: money).monospacedDigit().gridColumnAlignment(.trailing) }
            }
        }.font(.caption)
    }
}

struct EmptyNote: View {
    let icon: String; let text: String
    var body: some View {
        VStack(spacing: 6) { Image(systemName: icon).font(.title2).foregroundStyle(.secondary); Text(text).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            .frame(maxWidth: .infinity).padding(.vertical, 20)
    }
}

struct ProcRow: View {
    let p: Proc
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) { Text(p.project).font(.callout); Text(p.cwd).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
            Spacer()
            Text("\(p.cpu, specifier: "%.1f")% · \(p.ramMB) MB · \(p.uptime)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Button { } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless).help("Stop (SIGTERM)")
        }
    }
}

struct RepoRow: View {
    let r: Repo
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(r.name).font(.callout); Spacer()
                if r.dirty > 0 { Label("\(r.dirty)", systemImage: "pencil").font(.caption) }
                if r.ahead > 0 { Text("↑\(r.ahead)").font(.caption) }
                if r.behind > 0 { Text("↓\(r.behind)").font(.caption) }
            }
            Text("\(r.branch) · \(r.last) · \(r.ago) ago").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

struct ProcessesList: View {
    let state: DataState
    var body: some View {
        if state == .sourcesFailed { EmptyNote(icon: "terminal", text: "No Claude Code sessions running.") }
        else { ForEach(Fake.procs, id: \.project) { ProcRow(p: $0) } }
    }
}

struct ReposList: View {
    let state: DataState
    var body: some View {
        if state == .sourcesFailed { EmptyNote(icon: "exclamationmark.triangle", text: "git not found at /usr/bin/git.\nInstall Command Line Tools.") }
        else if state == .noLogs { EmptyNote(icon: "folder", text: "No repos yet. Repos appear once Claude Code works in them.") }
        else { ForEach(Fake.repos, id: \.name) { RepoRow(r: $0) } }
    }
}

// MARK: - Variant A: TermTracker-faithful tabs, Plan limits as a permanent strip above them

struct VariantA: View {
    let state: DataState
    @State private var tab = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox {
                if limitsAvailable(state) {
                    HStack(spacing: 14) { ForEach(limits(for: state), id: \.name) { LimitBar(l: $0) } }
                    Text(ageText(state)).font(.caption2).foregroundStyle(state == .limitsStale ? .orange : .secondary).frame(maxWidth: .infinity, alignment: .trailing)
                } else { LimitsMessage(state: state) }
            } label: { Text("Plan limits").font(.caption.bold()) }
            Picker("", selection: $tab) { Text("Usage").tag(0); Text("Processes").tag(1); Text("Git").tag(2) }.pickerStyle(.segmented).labelsHidden()
            Group {
                switch tab {
                case 0: usage
                case 1: VStack(spacing: 8) { ProcessesList(state: state) }
                default: VStack(alignment: .leading, spacing: 8) { ReposList(state: state) }
                }
            }.frame(minHeight: 260, alignment: .top)
        }
    }
    @ViewBuilder var usage: some View {
        if state == .noLogs { EmptyNote(icon: "doc.text.magnifyingglass", text: "No Claude Code logs in ~/.claude/projects yet.") }
        else {
            VStack(alignment: .leading, spacing: 8) {
                Text(Fake.cycle).font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) { Text(Fake.cycleCost, format: money).font(.title.bold().monospacedDigit()); Text("API list estimate").font(.caption).foregroundStyle(.secondary) }
                HStack { ForEach(Fake.cycleTokens, id: \.0) { t in VStack(alignment: .leading) { Text(t.1).font(.callout.monospacedDigit()); Text(t.0).font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading) } }
                Divider()
                HStack { Text("Today").font(.caption.bold()); Text(Fake.todayCost, format: money).font(.caption.monospacedDigit()); Spacer(); Text(Fake.todayTokens).font(.caption2).foregroundStyle(.secondary) }
                Text("Last hour · tokens/min").font(.caption2).foregroundStyle(.secondary); Sparkline()
                Text("14 days").font(.caption2).foregroundStyle(.secondary); Trend()
                ModelsTable()
            }
        }
    }
}

// MARK: - Variant B: no tabs, one scrolling dashboard with collapsible sections

struct VariantB: View {
    let state: DataState
    @State private var openUsage = true
    @State private var openProcs = true
    @State private var openGit = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if limitsAvailable(state) {
                    ForEach(limits(for: state), id: \.name) { l in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) { Text(l.pct, format: .percent.precision(.fractionLength(0))).font(.title2.bold().monospacedDigit()).foregroundStyle(pctColor(l.pct)); Text(l.name).font(.callout); Spacer(); Text(l.resets).font(.caption).foregroundStyle(.secondary) }
                            ProgressView(value: l.pct).tint(pctColor(l.pct)).scaleEffect(y: 2)
                        }
                    }
                    Text(ageText(state)).font(.caption2).foregroundStyle(state == .limitsStale ? .orange : .secondary)
                } else { LimitsMessage(state: state).padding(8).background(.quaternary, in: .rect(cornerRadius: 6)) }
                Divider()
                DisclosureGroup(isExpanded: $openUsage) {
                    if state == .noLogs { EmptyNote(icon: "doc.text.magnifyingglass", text: "No Claude Code logs yet.") }
                    else {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { stat("Today", Fake.todayCost); stat("Billing cycle", Fake.cycleCost) }
                            Sparkline(height: 30); Trend(height: 40); ModelsTable()
                        }.padding(.top, 4)
                    }
                } label: { sectionLabel("Usage", state == .noLogs ? "—" : Fake.todayCost.formatted(money) + " today") }
                DisclosureGroup(isExpanded: $openProcs) { VStack(spacing: 6) { ProcessesList(state: state) }.padding(.top, 4) }
                    label: { sectionLabel("Processes", state == .sourcesFailed ? "0" : "\(Fake.procs.count) running") }
                DisclosureGroup(isExpanded: $openGit) { VStack(alignment: .leading, spacing: 6) { ReposList(state: state) }.padding(.top, 4) }
                    label: { sectionLabel("Git", state == .sourcesFailed ? "error" : "\(Fake.repos.filter { $0.dirty > 0 }.count) dirty") }
            }
        }.frame(height: 480)
    }
    func stat(_ t: String, _ v: Double) -> some View {
        VStack(alignment: .leading) { Text(v, format: money).font(.title3.bold().monospacedDigit()); Text("\(t) · API list estimate").font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading)
    }
    func sectionLabel(_ t: String, _ s: String) -> some View { HStack { Text(t).font(.headline); Spacer(); Text(s).font(.caption).foregroundStyle(.secondary) } }
}

// MARK: - Variant C: Plan limits as rings header, icon tab bar at bottom, Usage leads with the sparkline

struct VariantC: View {
    let state: DataState
    @State private var tab = 0
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                if limitsAvailable(state) {
                    ForEach(limits(for: state), id: \.name) { l in
                        HStack(spacing: 8) {
                            ZStack {
                                Circle().stroke(.quaternary, lineWidth: 6)
                                Circle().trim(from: 0, to: l.pct).stroke(pctColor(l.pct), style: .init(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                                Text(l.pct, format: .percent.precision(.fractionLength(0))).font(.caption.bold().monospacedDigit())
                            }.frame(width: 48, height: 48)
                            VStack(alignment: .leading) { Text(l.name == "5-hour window" ? "5h" : "Week").font(.callout.bold()); Text(l.resets).font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                } else { LimitsMessage(state: state) }
            }.frame(maxWidth: .infinity)
            if limitsAvailable(state) { Text(ageText(state)).font(.caption2).foregroundStyle(state == .limitsStale ? .orange : .secondary) }
            Divider()
            Group {
                switch tab {
                case 0: usage
                case 1: VStack(spacing: 8) { ProcessesList(state: state) }
                default: VStack(alignment: .leading, spacing: 8) { ReposList(state: state) }
                }
            }.frame(height: 270, alignment: .top)
            Divider()
            HStack {
                tabButton(0, "chart.bar.xaxis", "Usage"); tabButton(1, "cpu", "Processes"); tabButton(2, "arrow.triangle.branch", "Git")
            }
        }
    }
    @ViewBuilder var usage: some View {
        if state == .noLogs { EmptyNote(icon: "doc.text.magnifyingglass", text: "No Claude Code logs yet.") }
        else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) { Text("\(Int(Fake.lastHour.last!)) tok/min").font(.title2.bold().monospacedDigit()); Text("now").font(.caption).foregroundStyle(.secondary) }
                Sparkline(height: 70)
                HStack {
                    VStack(alignment: .leading) { Text(Fake.todayCost, format: money).font(.headline.monospacedDigit()); Text("Today").font(.caption2).foregroundStyle(.secondary) }
                    Spacer()
                    VStack(alignment: .trailing) { Text(Fake.cycleCost, format: money).font(.headline.monospacedDigit()); Text("Billing cycle (API list estimate)").font(.caption2).foregroundStyle(.secondary) }
                }
                Trend(height: 40); ModelsTable()
            }
        }
    }
    func tabButton(_ i: Int, _ icon: String, _ t: String) -> some View {
        Button { tab = i } label: { VStack(spacing: 2) { Image(systemName: icon); Text(t).font(.caption2) }.frame(maxWidth: .infinity).foregroundStyle(tab == i ? Color.accentColor : .secondary) }.buttonStyle(.plain)
    }
}

// MARK: - Popover with the prototype switcher strip

struct Popover: View {
    @Bindable var p: Proto
    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch p.variant {
                case .A: VariantA(state: p.state)
                case .B: VariantB(state: p.state)
                case .C: VariantC(state: p.state)
                }
            }.id("\(p.variant)\(p.state)").padding(12)
            // Prototype switcher: deliberately loud so it is not mistaken for the design.
            VStack(spacing: 4) {
                HStack {
                    Button("‹") { p.cycleVariant(-1) }; Spacer()
                    Text("\(p.variant.rawValue) (\(p.variant.name))").bold(); Spacer()
                    Button("›") { p.cycleVariant(1) }
                }
                HStack {
                    Button("▲") { p.cycleState(-1) }; Spacer()
                    Text("state: \(p.state.label)"); Spacer()
                    Button("▼") { p.cycleState(1) }
                }
            }
            .font(.caption).buttonStyle(.borderless).foregroundStyle(.black)
            .padding(8).background(.yellow)
        }
        .frame(width: 380)
        .focusable().focusEffectDisabled()
        .onKeyPress(.leftArrow) { p.cycleVariant(-1); return .handled }
        .onKeyPress(.rightArrow) { p.cycleVariant(1); return .handled }
        .onKeyPress(.upArrow) { p.cycleState(-1); return .handled }
        .onKeyPress(.downArrow) { p.cycleState(1); return .handled }
        .onAppear { print("variant=\(p.variant.rawValue) state=\(p.state.rawValue)") }
        .onChange(of: "\(p.variant)\(p.state)") { print("variant=\(p.variant.rawValue) state=\(p.state.rawValue)") }
    }
}

struct MenuTitle: View {
    let state: DataState
    var body: some View {
        // Settled: icon + today's API list estimate. Only its empty/warning states are in question.
        switch state {
        case .noLogs: HStack(spacing: 3) { Image(systemName: "sparkle"); Text("—") }
        case .wrapperMissing, .limitsUnreadable: HStack(spacing: 3) { Image(systemName: "sparkle"); Text(Fake.todayCost, format: money); Image(systemName: "exclamationmark.triangle.fill") }
        default: HStack(spacing: 3) { Image(systemName: "sparkle"); Text(Fake.todayCost, format: money) }
        }
    }
}

struct ProtoApp: App {
    @State private var p = Proto()
    init() { DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) } }
    var body: some Scene {
        MenuBarExtra { Popover(p: p) } label: { MenuTitle(state: p.state) }
            .menuBarExtraStyle(.window)
    }
}

ProtoApp.main()
