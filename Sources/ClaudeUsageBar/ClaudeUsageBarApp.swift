import AppKit
import SwiftUI
import UsageCore

@main
struct ClaudeUsageBarApp: App {
    @State private var usage = Usage()
    @AppStorage(Usage.gaugeColorKey) private var gaugeColor = GaugeColor.claude
    @AppStorage(Usage.gaugeWindowKey) private var gaugeWindow = GaugeWindow.weekly

    var body: some Scene {
        MenuBarExtra {
            Popover(usage: usage)
        } label: {
            let gauge = usage.menuBarGauge(gaugeWindow)
            Image(nsImage: gaugeImage(percent: gauge.percent, color: gaugeColor.nsColor))
            Text(gauge.text)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Which Plan-limits window the menu bar gauge shows.
enum GaugeWindow: String, CaseIterable {
    case fiveHour, weekly
    var title: String { self == .fiveHour ? "5-hour" : "Weekly" }
}

/// Menu bar gauge colours. `claude` is Claude Code's clay orange; `auto` follows the menu bar tint.
enum GaugeColor: String, CaseIterable {
    case claude, blue, green, purple, pink, auto

    var title: String { self == .auto ? "Match menu bar" : self == .claude ? "Claude Code orange" : rawValue.capitalized }
    var nsColor: NSColor? {
        switch self {
        case .claude: NSColor(srgbRed: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255, alpha: 1)
        case .blue: .systemBlue
        case .green: .systemGreen
        case .purple: .systemPurple
        case .pink: .systemPink
        case .auto: nil
        }
    }
    var swiftColor: Color { nsColor.map(Color.init(nsColor:)) ?? .primary }
}

/// A pill: dim track, fill for `percent` used. With a colour it is drawn as is (the track a mid grey that reads on
/// light and dark bars); without one it is a template, so it follows the menu bar tint.
private func gaugeImage(percent: Double, color: NSColor?) -> NSImage {
    let image = NSImage(size: NSSize(width: 28, height: 6), flipped: false) { rect in
        (color == nil ? NSColor.black.withAlphaComponent(0.3) : NSColor.gray.withAlphaComponent(0.45)).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
        (color ?? .black).setFill()
        let fill = NSRect(x: 0, y: 0, width: rect.width * min(max(percent, 0), 100) / 100, height: rect.height)
        NSBezierPath(roundedRect: fill, xRadius: 3, yRadius: 3).fill()
        return true
    }
    image.isTemplate = color == nil
    return image
}

/// Menu bar title: icon only while the launch pass runs, then refreshed by FSEvents and at midnight, with a trailing ⚠
/// while the statusline wrapper is not installed or the capture file is unreadable. The Usage tab's `summary` is
/// recomputed (off the main thread) only while the popover is open.
@MainActor @Observable final class Usage {
    /// Today's $ (or `—`); nil while the launch pass runs.
    private var baseTitle: String?
    var title: String? { titleWithWarning(baseTitle, warning: planLimits.warnsInTitle) }
    /// The menu bar label: the chosen window's percent used, or `—` / `⚠` (wrapper missing, capture unreadable) with an empty bar.
    func menuBarGauge(_ which: GaugeWindow) -> (percent: Double, text: String) {
        guard case .ok(let fiveHour, let weekly, _) = planLimits, let window = which == .weekly ? weekly : fiveHour else {
            return (0, planLimits.warnsInTitle ? "⚠" : "—")
        }
        let percent = window.displayPercent(now: .now)
        return (percent, "\(Int(percent.rounded()))%")
    }
    /// Settings shows it next to the Install / Uninstall buttons.
    private(set) var wrapperInstalled = true
    /// Re-read when the capture file changes (and on popover open); assigned only on a change, so an FSEvents batch
    /// that did not touch the capture file (this app's own cache write) re-renders nothing.
    var planLimits = PlanLimits.noData
    /// The clock the Plan-limits header renders against; ticks every minute while the popover is open.
    var now = Date.now
    /// Why the last Install click failed.
    var wrapperError: String?
    var summary: UsageSummary?
    let processes: ProcessMonitor
    let git: GitMonitor
    /// Files handled / total during the launch pass; nil once it is done.
    var scan: (done: Int, total: Int)? = (0, 0)
    var hasLogs = false
    /// When the live price table was fetched; nil while it is the bundled snapshot. Popover age line, Settings (ticket 24).
    var pricesFetchedAt: Date?
    /// A newer release's version, checked with the daily price fetch; the popover footer offers to install it.
    var updateAvailable: String?
    /// True while the install script runs; it quits this app on success, so only a failure ever resets it.
    var updating = false
    var updateFailed = false
    /// `@AppStorage` keys (percent, Int) for the ring colours; ticket 24 edits them; they also drive the notifications.
    static let warningThresholdKey = "warningThreshold"  // default 80
    static let criticalThresholdKey = "criticalThreshold"  // default 95
    /// `@AppStorage` key (Bool, default true) for Plan-limit notifications; ticket 24 edits it and requests permission on enable.
    static let notificationsEnabledKey = "notificationsEnabled"
    /// `@AppStorage` key (`GaugeWindow` raw value, default `weekly`) for the window the menu bar gauge shows.
    static let gaugeWindowKey = "gaugeWindow"
    /// `@AppStorage` key (`GaugeColor` raw value, default `claude`) for the menu bar gauge.
    static let gaugeColorKey = "gaugeColor"
    /// `@AppStorage` key (Bool, default false) set once the first-run tour is finished or skipped; Settings clears it.
    static let tourDoneKey = "tourDone"

    /// Key shared with the Settings UI (ticket 24).
    static let billingCycleStartDayKey = "billingCycleStartDay"
    @ObservationIgnored var billingCycleStartDay = 1 {
        didSet { if billingCycleStartDay != oldValue && popoverOpen { recompute() } }
    }
    @ObservationIgnored var popoverOpen = false {
        didSet {
            guard popoverOpen != oldValue else { return }
            minuteTimer?.invalidate()
            minuteTimer = nil
            guard popoverOpen else { return }
            recompute()
            refreshWrapper()
            now = .now
            let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.now = .now }
            }
            RunLoop.main.add(timer, forMode: .common)
            minuteTimer = timer
        }
    }
    @ObservationIgnored private var store = RecordStore()
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var prices = PriceTable.bundled

    private let logs: Logs
    private let projectsPrefix: String
    private let supportPrefix: String
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var midnight: Timer?
    @ObservationIgnored private var priceTimer: Timer?
    @ObservationIgnored private var minuteTimer: Timer?
    /// Settings requests authorization through it when the notifications toggle is switched on.
    @ObservationIgnored let notifier = NotificationPresenter()
    /// What was already announced; kept in a file in the support dir so a relaunch does not announce a window twice.
    @ObservationIgnored private var notificationState = NotificationState()
    private let notificationStateURL: URL
    private let priceStore: PriceStore
    private let wrapper: StatuslineWrapper
    private let supportDir: URL

    init() {
        var home = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude")
        var support = URL.applicationSupportDirectory.appending(path: "ClaudeUsageBar")
        // Manual testing: run against a throwaway tree instead of the real ~/.claude and Application Support.
        if let sandbox = ProcessInfo.processInfo.environment["CLAUDE_USAGE_BAR_SANDBOX"] {
            (home, support) = (URL(filePath: sandbox).appending(path: ".claude"), URL(filePath: sandbox).appending(path: "support"))
        }
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        processes = ProcessMonitor(claudeHome: home)
        git = GitMonitor(claudeHome: home)
        logs = Logs(claudeHome: home, cacheURL: support.appending(path: "records.json"))
        let projects = home.appending(path: "projects").resolvingSymlinksInPath().path
        projectsPrefix = projects + "/"
        priceStore = PriceStore(supportDir: support) {
            try await URLSession.shared.data(from: URL(string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json")!).0
        }
        supportPrefix = support.resolvingSymlinksInPath().path + "/"
        wrapper = StatuslineWrapper(claudeHome: home, supportDir: support)
        supportDir = support
        let installed = wrapper.isInstalled()
        wrapperInstalled = installed
        planLimits = readPlanLimits(supportDir: support, wrapperInstalled: installed)
        notificationStateURL = support.appending(path: "notification-state.json")
        notificationState = (try? JSONDecoder().decode(NotificationState.self, from: Data(contentsOf: notificationStateURL))) ?? .init()
        // A capture already on disk at launch is evaluated once permission is settled; the persisted state stops repeats.
        Task {
            await notifier.requestAuthorization()
            notifyOnCrossing()
        }

        Task(priority: .background) {
            (prices, pricesFetchedAt) = await (priceStore.table, priceStore.fetchedAt)
            let progress: @Sendable (Int, Int, RecordStore) -> Void = { done, total, partial in
                Task { @MainActor in self.scanProgress(done, total, partial) }
            }
            applied(await logs.update(dirs: nil, prices: prices, onProgress: progress))
        }
        git.records = { [unowned self] in self.store }
        priceTick()
        watcher = FileWatcher(paths: [projects, support.path]) { [weak self] events in
            Task { @MainActor in self?.filesChanged(events) }
        }
        armMidnight()
        NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dayMayHaveChanged() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dayMayHaveChanged() }
        }
    }

    private func filesChanged(_ events: [FileWatcher.Event]) {
        if events.contains(where: { $0.path.hasPrefix(supportPrefix) }) { refreshPlanLimits() }
        let logEvents = events.filter { $0.path.hasPrefix(projectsPrefix) }
        guard !logEvents.isEmpty else { return }
        let rescan = logEvents.contains { $0.flags & UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged) != 0 }
        Task(priority: .background) { applied(await logs.update(dirs: rescan ? nil : logEvents.map(\.path), prices: prices)) }
    }

    private func applied(_ result: (title: String, store: RecordStore)) {
        (baseTitle, store, scan) = (result.title, result.store, nil)
        hasLogs = !store.records.isEmpty
        if popoverOpen { recompute() }
    }

    private func scanProgress(_ done: Int, _ total: Int, _ partial: RecordStore) {
        guard scan != nil else { return }  // the pass already finished
        (scan, store) = ((done, total), partial)
        if popoverOpen { recompute() }
    }

    private func recompute() {
        generation += 1
        let (id, store, day, prices) = (generation, store, billingCycleStartDay, prices)
        Task.detached(priority: .userInitiated) {
            let summary = summarize(store, prices: prices, now: .now, calendar: .current, billingCycleStartDay: day)
            await MainActor.run { if id == self.generation { self.summary = summary } }
        }
    }

    private func armMidnight() {
        midnight?.invalidate()
        let next = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dayMayHaveChanged() }
        }
        RunLoop.main.add(timer, forMode: .common)
        midnight = timer
    }

    /// A one-shot 24 h timer, re-armed by every attempt, so a failed fetch retries next cycle.
    private func priceTick() {
        armPriceTimer()
        Task { _ = await updatePrices() }
        Task { await checkForUpdate() }
    }

    private func checkForUpdate() async {
        guard let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            let (data, _) = try? await URLSession.shared.data(
                from: URL(string: "https://api.github.com/repos/ghostza1209/ClaudeUsageBar/releases/latest")!)
        else { return }
        updateAvailable = newerRelease(data, than: current)
    }

    /// Runs the one-line installer, which replaces the app, quits this copy and opens the new one.
    func installUpdate() {
        let script = Process()
        script.executableURL = URL(filePath: "/bin/sh")
        script.arguments = ["-c", "curl -fsSL https://raw.githubusercontent.com/ghostza1209/ClaudeUsageBar/HEAD/install.sh | sh"]
        script.terminationHandler = { [weak self] _ in
            Task { @MainActor in if let self { (self.updating, self.updateFailed) = (false, true) } }
        }
        (updating, updateFailed) = (true, false)
        do { try script.run() } catch { (updating, updateFailed) = (false, true) }
    }

    private func armPriceTimer() {
        priceTimer?.invalidate()
        let timer = Timer(timeInterval: 24 * 3600, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.priceTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        priceTimer = timer
    }

    /// Fetches the price table now (ticket 24's "Update now" calls this); on success restarts the 24 h timer and
    /// re-prices the title and, if open, the summary. `pricesFetchedAt` is the age to display.
    func updatePrices() async -> Result<Void, PriceUpdateError> {
        let result = await priceStore.updateNow()
        guard case .success = result else { return result }
        armPriceTimer()
        (prices, pricesFetchedAt) = await (priceStore.table, priceStore.fetchedAt)
        if baseTitle != nil { baseTitle = await logs.title(prices: prices) }
        if popoverOpen { recompute() }
        return result
    }

    /// Detection runs at launch and on every popover open; the Plan-limits state depends on it.
    func refreshWrapper() {
        wrapperInstalled = wrapper.isInstalled()
        refreshPlanLimits()
    }

    private func refreshPlanLimits() {
        let latest = readPlanLimits(supportDir: supportDir, wrapperInstalled: wrapperInstalled)
        guard latest != planLimits else { return }
        planLimits = latest
        notifyOnCrossing()
    }

    /// Runs the pure decision on the current read and posts what it fires; thresholds and the flag are read from the
    /// same defaults the `@AppStorage` views edit.
    private func notifyOnCrossing() {
        let defaults = UserDefaults.standard
        let result = planLimitNotifications(
            state: notificationState, limits: planLimits, now: .now,
            warning: Double(defaults.object(forKey: Self.warningThresholdKey) as? Int ?? 80),
            critical: Double(defaults.object(forKey: Self.criticalThresholdKey) as? Int ?? 95),
            enabled: defaults.object(forKey: Self.notificationsEnabledKey) as? Bool ?? true)
        guard result.state != notificationState else { return }
        notificationState = result.state
        try? JSONEncoder().encode(result.state).write(to: notificationStateURL, options: .atomic)
        for notification in result.fire { notifier.post(notification, now: .now) }
    }

    /// The Install button: chains the current statusline and points Claude Code at the wrapper.
    func installWrapper() {
        do {
            try wrapper.install()
            wrapperError = nil
        } catch {
            wrapperError = error.localizedDescription
        }
        refreshWrapper()
    }

    /// The Uninstall button: restores the previous statusline only while ours, then deletes the wrapper files.
    func uninstallWrapper() {
        do {
            try wrapper.uninstall()
            wrapperError = nil
        } catch {
            wrapperError = error.localizedDescription
        }
        refreshWrapper()
    }

    /// Midnight, `NSCalendarDayChanged` or wake: re-arm the timer and roll Today in the title.
    private func dayMayHaveChanged() {
        armMidnight()
        Task {
            if baseTitle != nil { baseTitle = await logs.title(prices: prices) }
            if popoverOpen { recompute() }
        }
    }
}

/// Owns the record cache and serializes passes over it.
actor Logs {
    private let claudeHome: URL
    private let cacheURL: URL
    private var cache: UsageCache?
    private var lastSave: ContinuousClock.Instant?

    init(claudeHome: URL, cacheURL: URL) {
        (self.claudeHome, self.cacheURL) = (claudeHome, cacheURL)
    }

    /// Reads appended bytes of the logs in `dirs` (nil: the whole tree) and returns the title and the records. The first
    /// call loads the cache, so it is the launch pass; `onProgress` reports the files handled so far.
    func update(
        dirs: [String]?, prices: PriceTable, onProgress: (@Sendable (Int, Int, RecordStore) -> Void)? = nil
    ) -> (title: String, store: RecordStore) {
        var cache = self.cache ?? .load(from: cacheURL)
        cache.update(claudeHome: claudeHome, dirs: dirs, now: .now, calendar: .current, progress: onProgress)
        self.cache = cache
        // ponytail: a save encodes every record (~0.4 s for 64k), so after the launch pass it runs at most every
        // 10 min. A quit loses only offsets: the next launch rereads up to 10 min of appended bytes.
        if lastSave.map({ $0.duration(to: .now) > .seconds(600) }) ?? true {
            try? cache.save(to: cacheURL)
            lastSave = .now
        }
        return (menuBarTitle(cache.store, prices: prices, now: .now, calendar: .current), cache.store)
    }

    func title(prices: PriceTable) -> String {
        menuBarTitle(cache?.store ?? RecordStore(), prices: prices, now: .now, calendar: .current)
    }
}

/// A directory-level FSEvents stream with 2 s latency; `handler` gets each batch on a private queue.
final class FileWatcher {
    struct Event: Sendable { let path: String, flags: FSEventStreamEventFlags }

    private let handler: @Sendable ([Event]) -> Void
    private var stream: FSEventStreamRef?

    init(paths: [String], handler: @escaping @Sendable ([Event]) -> Void) {
        self.handler = handler
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        stream = FSEventStreamCreate(
            nil,
            { _, info, count, paths, flags, _ in
                let watcher = Unmanaged<FileWatcher>.fromOpaque(info!).takeUnretainedValue()
                let paths = unsafeBitCast(paths, to: NSArray.self) as! [String]
                watcher.handler((0..<count).map { Event(path: paths[$0], flags: flags[$0]) })
            },
            &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 2,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes))
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue(label: "FileWatcher"))
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}

struct Popover: View {
    let usage: Usage
    @State private var tab = 0
    @State private var open = false
    @State private var showSettings = false
    @State private var contentHeight = 0.0
    @AppStorage(Usage.billingCycleStartDayKey) private var billingCycleStartDay = 1
    @AppStorage(Usage.tourDoneKey) private var tourDone = false
    @State private var tourStep = 0
    @State private var window: NSWindow?

    var body: some View {
        VStack(spacing: 8) {
            if !showSettings {
                PlanLimitsHeader(usage: usage).tourTarget(.header)
                Picker("", selection: $tab) {
                    Label("Usage", systemImage: "chart.bar").tag(0)
                    Label("Processes", systemImage: "cpu").tag(1)
                    Label("Git", systemImage: "arrow.triangle.branch").tag(2)
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small)
            }
            ScrollView {
                Group {
                    if showSettings {
                        SettingsView(usage: usage)
                    } else if tab == 0 {
                        UsageTab(usage: usage)
                    } else if tab == 1 {
                        ProcessesTab(monitor: usage.processes)
                    } else {
                        GitTab(monitor: usage.git)
                    }
                }
                .transition(.opacity)
                .frame(maxWidth: .infinity, minHeight: showSettings ? 0 : 160, alignment: .top)
                .onGeometryChange(for: Double.self, of: { $0.size.height }) { contentHeight = $0 }
            }
            .scrollIndicators(.never)
            .frame(height: min(contentHeight, 620))
            .animation(.snappy(duration: 0.2), value: tab)
            .animation(.snappy(duration: 0.2), value: showSettings)
            .tourTarget(.content)
            if !tourDone {
                TourCard(step: $tourStep) { (tourDone, tourStep, tab) = (true, 0, 0) }.tourTarget(.card)
            }
            HStack {
                Button { showSettings.toggle() } label: {
                    Label(showSettings ? "Back" : "Settings", systemImage: showSettings ? "chevron.left" : "gearshape")
                }
                .keyboardShortcut(",", modifiers: .command)
                .tourTarget(.settings)
                Spacer()
                if let version = usage.updateAvailable {
                    Button { usage.installUpdate() } label: {
                        Label(
                            usage.updating ? "Updating…" : usage.updateFailed ? "Update failed, retry" : "Update to \(version)",
                            systemImage: "arrow.down.circle")
                    }
                    .disabled(usage.updating).foregroundStyle(usage.updateFailed ? .red : .accentColor)
                    Spacer()
                }
                Button { NSApp.terminate(nil) } label: { Label("Quit", systemImage: "power") }
                    .keyboardShortcut("q", modifiers: .command)
            }
            .buttonStyle(.borderless).foregroundStyle(.secondary).font(.callout)
        }
        .padding(10)
        .overlayPreferenceValue(TourTargets.self) { anchors in
            Spotlight(target: tourDone ? nil : TourStep.all[tourStep].target, anchors: anchors)
        }
        .frame(width: 360)
        .onChange(of: billingCycleStartDay, initial: true) { usage.billingCycleStartDay = billingCycleStartDay }
        .onChange(of: tourStep) { if let step = TourStep.all[tourStep].tab { tab = step } }
        .onChange(of: tourDone) { if !tourDone { showSettings = false } }
        .onChange(of: open && tab == 1 && !showSettings, initial: true) { usage.processes.sampling = open && tab == 1 && !showSettings }
        .onChange(of: open && tab == 2 && !showSettings, initial: true) { usage.git.scanning = open && tab == 2 && !showSettings }
        .onGeometryChange(for: Double.self, of: { $0.size.height }) { fitWindow(height: $0) }
        .background(KeyWindowObserver { window, isKey in
            (usage.popoverOpen, open, self.window) = (isKey, isKey, window)
            if !isKey { showSettings = false }
        })
    }

    /// The menu bar window grows with the content but does not shrink: it keeps its size and centres the content,
    /// which leaves a gap under the menu bar. Shrink it here, keeping the top edge where it is.
    private func fitWindow(height: Double) {
        guard let window, abs(window.frame.height - height) > 0.5 else { return }
        var frame = window.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        window.setFrame(frame, display: true)
    }
}

/// Reports the hosting window and whether it is key. The popover panel is key exactly while open, and unlike
/// `onAppear` this fires on every open.
struct KeyWindowObserver: NSViewRepresentable {
    let onChange: (NSWindow, Bool) -> Void

    func makeNSView(context: Context) -> NSView { Observer(onChange) }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class Observer: NSView {
        let onChange: (NSWindow, Bool) -> Void
        init(_ onChange: @escaping (NSWindow, Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            NotificationCenter.default.removeObserver(self)
            guard let window else { return }
            for (name, isKey) in [(NSWindow.didBecomeKeyNotification, true), (NSWindow.didResignKeyNotification, false)] {
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self, weak window] _ in
                    MainActor.assumeIsolated { if let window { self?.onChange(window, isKey) } }
                }
            }
            onChange(window, window.isKeyWindow)
        }
    }
}
