import AppKit
import SwiftUI
import UsageCore

@main
struct ClaudeUsageBarApp: App {
    @State private var usage = Usage()

    var body: some Scene {
        MenuBarExtra {
            Popover()
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
@MainActor @Observable final class Usage {
    var title: String?
    /// Ticket 20 hook: something changed in the app's Application Support dir (the Plan-limits capture file,
    /// or this app's own cache write).
    var appSupportChanged: () -> Void = {}

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

        Task(priority: .background) { title = await logs.update(dirs: nil) }
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
        Task(priority: .background) { title = await logs.update(dirs: rescan ? nil : logEvents.map(\.path)) }
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
        Task { if title != nil { title = await logs.title() } }
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

    /// Reads appended bytes of the logs in `dirs` (nil: the whole tree) and returns the title. The first call loads
    /// the cache, so it is the launch pass.
    func update(dirs: [String]?) -> String {
        var cache = self.cache ?? .load(from: cacheURL)
        cache.update(claudeHome: claudeHome, dirs: dirs, now: .now, calendar: .current)
        self.cache = cache
        // ponytail: a save encodes every record (~0.4 s for 64k), so after the launch pass it runs at most every
        // 10 min. A quit loses only offsets: the next launch rereads up to 10 min of appended bytes.
        if lastSave.map({ $0.duration(to: .now) > .seconds(600) }) ?? true {
            try? cache.save(to: cacheURL)
            lastSave = .now
        }
        return title()
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
    @State private var tab = 0

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
            Text(["Usage", "Processes", "Git"][tab] + " coming soon.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 260, alignment: .top)
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
    }
}
