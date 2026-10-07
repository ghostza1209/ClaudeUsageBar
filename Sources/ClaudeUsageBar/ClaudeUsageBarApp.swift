import AppKit
import SwiftUI
import UsageCore

@main
struct ClaudeUsageBarApp: App {
    @State private var usage = Usage()

    var body: some Scene {
        MenuBarExtra {
            Popover(usage: usage)
        } label: {
            Image(systemName: "sparkle")
            if let title = usage.title { Text(title) }
        }
        .menuBarExtraStyle(.window)
        Settings {
            Text("Settings").frame(width: 360, height: 200)
        }
    }
}

/// Menu bar title: nil (icon only) while the launch pass runs, then refreshed by FSEvents and at midnight.
/// The Usage tab's `summary` is recomputed (off the main thread) only while the popover is open.
@MainActor @Observable final class Usage {
    var title: String?
    var summary: UsageSummary?
    /// Files handled / total during the launch pass; nil once it is done.
    var scan: (done: Int, total: Int)? = (0, 0)
    var hasLogs = false
    /// Ticket 20 hook: something changed in the app's Application Support dir (the Plan-limits capture file,
    /// or this app's own cache write).
    var appSupportChanged: () -> Void = {}

    /// Key shared with the Settings UI (ticket 24).
    static let billingCycleStartDayKey = "billingCycleStartDay"
    @ObservationIgnored var billingCycleStartDay = 1 {
        didSet { if billingCycleStartDay != oldValue && popoverOpen { recompute() } }
    }
    @ObservationIgnored var popoverOpen = false {
        didSet { if popoverOpen && !oldValue { recompute() } }
    }
    @ObservationIgnored private var store = RecordStore()
    @ObservationIgnored private var generation = 0

    private let logs: Logs
    private let projectsPrefix: String
    private let supportPrefix: String
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var midnight: Timer?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude")
        let support = URL.applicationSupportDirectory.appending(path: "ClaudeUsageBar")
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        logs = Logs(claudeHome: home, cacheURL: support.appending(path: "records.json"))
        let projects = home.appending(path: "projects").resolvingSymlinksInPath().path
        projectsPrefix = projects + "/"
        supportPrefix = support.resolvingSymlinksInPath().path + "/"

        Task(priority: .background) {
            let progress: @Sendable (Int, Int, RecordStore) -> Void = { done, total, partial in
                Task { @MainActor in self.scanProgress(done, total, partial) }
            }
            applied(await logs.update(dirs: nil, onProgress: progress))
        }
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
        if events.contains(where: { $0.path.hasPrefix(supportPrefix) }) { appSupportChanged() }
        let logEvents = events.filter { $0.path.hasPrefix(projectsPrefix) }
        guard !logEvents.isEmpty else { return }
        let rescan = logEvents.contains { $0.flags & UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged) != 0 }
        Task(priority: .background) { applied(await logs.update(dirs: rescan ? nil : logEvents.map(\.path))) }
    }

    private func applied(_ result: (title: String, store: RecordStore)) {
        (title, store, scan) = (result.title, result.store, nil)
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
        let (id, store, day) = (generation, store, billingCycleStartDay)
        Task.detached(priority: .userInitiated) {
            let summary = summarize(store, prices: .bundled, now: .now, calendar: .current, billingCycleStartDay: day)
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

    /// Midnight, `NSCalendarDayChanged` or wake: re-arm the timer and roll Today in the title.
    private func dayMayHaveChanged() {
        armMidnight()
        Task {
            if title != nil { title = await logs.title() }
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
        dirs: [String]?, onProgress: (@Sendable (Int, Int, RecordStore) -> Void)? = nil
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
        return (title(), cache.store)
    }

    func title() -> String {
        menuBarTitle(cache?.store ?? RecordStore(), prices: .bundled, now: .now, calendar: .current)
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
    @AppStorage(Usage.billingCycleStartDayKey) private var billingCycleStartDay = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox {
                Text("No Plan limits yet.").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text("Plan limits").font(.caption.bold())
            }
            Picker("", selection: $tab) {
                Text("Usage").tag(0)
                Text("Processes").tag(1)
                Text("Git").tag(2)
            }
            .pickerStyle(.segmented).labelsHidden()
            if tab == 0 {
                UsageTab(usage: usage)
            } else {
                Text(["Usage", "Processes", "Git"][tab] + " coming soon.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 260, alignment: .top)
            }
            Divider()
            HStack {
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless)
                    .simultaneousGesture(TapGesture().onEnded { NSApp.activate() })
            }
        }
        .padding(12)
        .frame(width: 380)
        .onChange(of: billingCycleStartDay, initial: true) { usage.billingCycleStartDay = billingCycleStartDay }
        .background(KeyWindowObserver { usage.popoverOpen = $0 })
    }
}

/// Reports whether the hosting window is key. The popover panel is key exactly while open, and unlike
/// `onAppear` this fires on every open.
struct KeyWindowObserver: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSView { Observer(onChange) }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class Observer: NSView {
        let onChange: (Bool) -> Void
        init(_ onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            NotificationCenter.default.removeObserver(self)
            guard let window else { return }
            for (name, isKey) in [(NSWindow.didBecomeKeyNotification, true), (NSWindow.didResignKeyNotification, false)] {
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.onChange(isKey) }
                }
            }
            onChange(window.isKeyWindow)
        }
    }
}
