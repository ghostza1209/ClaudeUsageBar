import SwiftUI
import UsageCore

/// Scans the repos Claude Code worked in when `scanning` turns true (popover open on the Git tab), then every 15 s.
/// The last result stays on screen during a rescan and across a close, until the next open replaces it.
@MainActor @Observable final class GitMonitor {
    /// nil until the first scan finishes.
    var result: GitScanResult?
    /// Set by `Usage` once it exists: the current record cache (a copy-on-write handle, not a copy).
    @ObservationIgnored var records: () -> RecordStore = { RecordStore() }

    @ObservationIgnored var scanning = false {
        didSet {
            guard scanning != oldValue else { return }
            timer?.invalidate()
            timer = nil
            guard scanning else { return }
            scan()
            let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.scan() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var inFlight = false
    @ObservationIgnored private let scanner = GitScanner()
    private let claudeHome: URL

    init(claudeHome: URL) { self.claudeHome = claudeHome }

    /// Everything but the result assignment runs off the main actor; a scan still running at the next tick makes it skip.
    private func scan() {
        guard !inFlight else { return }
        inFlight = true
        let (store, home, scanner) = (records(), claudeHome, scanner)
        Task.detached(priority: .utility) {
            let candidates = activeRepoCandidates(store.records, sessions: listClaudeSessions(claudeHome: home), now: .now)
            let result = await scanner.scan(candidates)
            await MainActor.run {
                self.result = result
                self.inFlight = false
            }
        }
    }
}

struct GitTab: View {
    let monitor: GitMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch monitor.result {
            case nil:
                EmptyView()
            case .gitNotFound:
                note("exclamationmark.triangle", "git not found", hint: "Install the Command Line Tools: xcode-select --install")
            case .repos(let repos) where repos.isEmpty:
                note("folder", "no repos yet", hint: nil)
            case .repos(let repos):
                ForEach(repos, id: \.root) { row($0) }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .top)
    }

    private func note(_ icon: String, _ text: String, hint: String?) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title2)
            Text(text).font(.caption)
            if let hint { Text(hint).font(.caption2) }
        }
        .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 20)
    }

    private func row(_ r: RepoStatus) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(r.name).font(.callout).lineLimit(1)
                if r.isWorktree {
                    Text("worktree").font(.caption2).foregroundStyle(.secondary)
                        .padding(.horizontal, 4).background(.quaternary, in: Capsule())
                }
                Spacer()
                if r.dirty > 0 { Label("\(r.dirty)", systemImage: "pencil").font(.caption) }
                if let ahead = r.ahead, ahead > 0 { Text("↑\(ahead)").font(.caption) }
                if let behind = r.behind, behind > 0 { Text("↓\(behind)").font(.caption) }
            }
            if r.timedOut {
                Text("timed out").font(.caption2).foregroundStyle(.orange)
            } else {
                HStack(spacing: 4) {
                    Text(r.branch ?? "").layoutPriority(1)
                    Text("· " + (r.subject ?? "no commits yet")).lineLimit(1)
                    if let committed = r.committedAt { Text("· " + formatUptime(-committed.timeIntervalSinceNow) + " ago").fixedSize() }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
