import Foundation

public struct RepoCandidate: Sendable, Equatable {
    public let cwd: String
    public let lastActivity: Date
}

/// Distinct cwds Claude Code worked in during the last 14 days, newest first. A cwd's activity is its latest record;
/// a running session's cwd counts as `now`.
public func activeRepoCandidates(_ records: some Sequence<UsageRecord>, sessions: [ClaudeSession], now: Date) -> [RepoCandidate] {
    var latest: [String: Date] = [:]
    for record in records {
        guard let cwd = record.cwd, !cwd.isEmpty, record.timestamp > latest[cwd, default: .distantPast] else { continue }
        latest[cwd] = record.timestamp
    }
    for session in sessions where !session.cwd.isEmpty { latest[session.cwd] = now }
    let cutoff = now.addingTimeInterval(-14 * 86_400)
    return latest.filter { $0.value >= cutoff }.map { RepoCandidate(cwd: $0.key, lastActivity: $0.value) }
        .sorted { ($0.lastActivity, $1.cwd) > ($1.lastActivity, $0.cwd) }
}

public struct RepoStatus: Sendable, Equatable {
    public let name: String
    public let root: String
    /// A linked worktree: its own row, named by its directory.
    public let isWorktree: Bool
    public let lastActivity: Date
    /// `detached @1a2b3c4` for a detached HEAD; nil only for a timed-out row.
    public var branch: String?
    /// Changed, staged, conflicted and untracked entries.
    public var dirty = 0
    /// Both nil when the branch has no upstream.
    public var ahead: Int?
    public var behind: Int?
    /// nil in a repo without commits.
    public var subject: String?
    public var committedAt: Date?
    public var timedOut = false
}

public enum GitScanResult: Sendable, Equatable {
    /// No git binary, or the one found cannot run (the `/usr/bin/git` shim without the Command Line Tools).
    case gitNotFound
    /// Newest activity first, at most 15.
    case repos([RepoStatus])
}

/// The first executable `git` on `path`, then `/usr/bin/git`.
public func findGit(path: String = ProcessInfo.processInfo.environment["PATH"] ?? "") -> String? {
    (path.split(separator: ":").map(String.init) + ["/usr/bin"]).map { $0 + "/git" }
        .first { FileManager.default.isExecutableFile(atPath: $0) }
}

private enum GitOutcome: Sendable {
    case finished(status: Int32, stdout: Data)
    case timedOut
    case notRunnable
}

/// Runs git with `GIT_OPTIONAL_LOCKS=0` (a scan never contends for `index.lock` with Claude Code); SIGTERM after `timeout`.
private func runGit(_ path: String, _ args: [String], timeout: Duration) async -> GitOutcome {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(filePath: path)
            process.arguments = args
            process.environment = ProcessInfo.processInfo.environment.merging(["GIT_OPTIONAL_LOCKS": "0"]) { $1 }
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return continuation.resume(returning: .notRunnable) }
            let kill = DispatchWorkItem { process.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18, execute: kill)
            // ponytail: reads to EOF, so a grandchild that outlives a killed git would hold this thread; git status spawns none.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            kill.cancel()
            // terminate() is the only SIGTERM source.
            continuation.resume(returning: process.terminationReason == .uncaughtSignal ? .timedOut : .finished(status: process.terminationStatus, stdout: data))
        }
    }
}

private struct ResolvedRepo: Sendable {
    let root: String
    let isWorktree: Bool
}

private enum Resolution: Sendable {
    case repo(ResolvedRepo)
    case notGit
    /// Not cached: the next scan asks again.
    case timedOut
    case gitUnusable
}

private func mapLimited<T: Sendable, R: Sendable>(_ items: [T], limit: Int, _ transform: @escaping @Sendable (T) async -> R) async -> [R] {
    await withTaskGroup(of: (Int, R).self) { group in
        var results = [R?](repeating: nil, count: items.count)
        var next = 0
        func addNext() {
            let (index, item) = (next, items[next])
            group.addTask { (index, await transform(item)) }
            next += 1
        }
        while next < min(limit, items.count) { addNext() }
        for await (index, result) in group {
            results[index] = result
            if next < items.count { addNext() }
        }
        return results.map { $0! }
    }
}

/// Maps cwds to repos and scans them with `git status`/`git log`. Never fetches.
public actor GitScanner {
    private static let maxRepos = 15
    private static let concurrency = 4
    private let gitPath: String?
    private let timeout: Duration
    /// cwd → repo, for the app's lifetime; nil = not a repo (or deleted).
    private var resolved: [String: ResolvedRepo?] = [:]

    /// `gitPath` nil means no git was found. `timeout` is per repo.
    public init(gitPath: String? = findGit(), timeout: Duration = .seconds(3)) {
        (self.gitPath, self.timeout) = (gitPath, timeout)
    }

    /// `candidates` newest first. Subdirectories collapse into their repo; a worktree is its own repo; non-git, deleted and
    /// `/tmp` cwds are dropped. The cap applies to repos after that collapse.
    public func scan(_ candidates: [RepoCandidate]) async -> GitScanResult {
        guard let git = gitPath else { return .gitNotFound }
        let timeout = timeout
        let uncached = candidates.map(\.cwd).filter { resolved[$0] == nil && isScannable($0) }
        let fresh = await mapLimited(Array(Set(uncached)), limit: Self.concurrency) { cwd in (cwd, await Self.resolve(cwd, git: git, timeout: timeout)) }
        for (cwd, resolution) in fresh {
            switch resolution {
            case .repo(let repo): resolved[cwd] = repo
            case .notGit: resolved[cwd] = .some(nil)
            case .timedOut: break
            case .gitUnusable: return .gitNotFound
            }
        }

        var seen = Set<String>()
        var repos: [(ResolvedRepo, Date)] = []
        for candidate in candidates {
            guard let repo = resolved[candidate.cwd] ?? nil, seen.insert(repo.root).inserted else { continue }
            repos.append((repo, candidate.lastActivity))
            if repos.count == Self.maxRepos { break }
        }
        let scans = await mapLimited(repos, limit: Self.concurrency) { repo, activity in
            await Self.scanRepo(repo, lastActivity: activity, git: git, timeout: timeout)
        }
        return .repos(scans.compactMap { $0 })
    }

    /// Absolute (`git -C ""` or a relative path would look at the app's own cwd) and not under `/tmp`.
    private func isScannable(_ cwd: String) -> Bool {
        cwd.hasPrefix("/") && !["/tmp", "/private/tmp"].contains { cwd == $0 || cwd.hasPrefix($0 + "/") }
    }

    private static func resolve(_ cwd: String, git: String, timeout: Duration) async -> Resolution {
        let args = ["-C", cwd, "rev-parse", "--path-format=absolute", "--show-toplevel", "--git-dir", "--git-common-dir"]
        switch await runGit(git, args, timeout: timeout) {
        case .notRunnable: return .gitUnusable
        case .timedOut: return .timedOut
        case .finished(let status, let out):
            // 128 = not a repo or no such directory; any other failure means git itself cannot run.
            if status == 128 { return .notGit }
            let lines = String(decoding: out, as: UTF8.self).split(separator: "\n").map(String.init)
            guard status == 0, lines.count == 3 else { return .gitUnusable }
            return .repo(ResolvedRepo(root: lines[0], isWorktree: lines[1] != lines[2]))
        }
    }

    /// nil: the repo vanished since it was resolved.
    private static func scanRepo(_ repo: ResolvedRepo, lastActivity: Date, git: String, timeout: Duration) async -> RepoStatus? {
        var row = RepoStatus(
            name: (repo.root as NSString).lastPathComponent, root: repo.root, isWorktree: repo.isWorktree, lastActivity: lastActivity)
        let deadline = ContinuousClock.now + timeout
        switch await runGit(git, ["-C", repo.root, "status", "--porcelain=v2", "--branch"], timeout: timeout) {
        case .notRunnable: return nil
        case .timedOut: row.timedOut = true; return row
        case .finished(let status, let out):
            guard status == 0 else { return nil }
            parseStatus(String(decoding: out, as: UTF8.self), into: &row)
        }
        switch await runGit(git, ["-C", repo.root, "log", "-1", "--format=%s%x00%ct"], timeout: ContinuousClock.now.duration(to: deadline)) {
        case .notRunnable: return nil
        case .timedOut: row.timedOut = true; return row
        case .finished(let status, let out):
            // Exit 128 and no output: a repo without commits.
            let parts = String(decoding: out, as: UTF8.self).split(separator: "\0", maxSplits: 1).map(String.init)
            if status == 0, parts.count == 2, let seconds = TimeInterval(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) {
                (row.subject, row.committedAt) = (parts[0], Date(timeIntervalSince1970: seconds))
            }
        }
        return row
    }

    private static func parseStatus(_ output: String, into row: inout RepoStatus) {
        var head = "", oid = ""
        for line in output.split(separator: "\n") {
            if line.hasPrefix("# branch.head ") {
                head = String(line.dropFirst(14))
            } else if line.hasPrefix("# branch.oid ") {
                oid = String(line.dropFirst(13))
            } else if line.hasPrefix("# branch.ab ") {
                let counts = line.dropFirst(12).split(separator: " ")
                if counts.count == 2 { (row.ahead, row.behind) = (Int(counts[0].dropFirst()), Int(counts[1].dropFirst())) }
            } else if !line.hasPrefix("#") {
                row.dirty += 1
            }
        }
        row.branch = head == "(detached)" ? "detached @" + oid.prefix(7) : head
    }
}
