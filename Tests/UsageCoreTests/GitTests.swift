import Foundation
import Testing

@testable import UsageCore

private let realGit = findGit()!

/// Runs real git in a throwaway repo, with a fixed identity and no user/system config.
@discardableResult
private func git(_ dir: URL, _ args: String...) throws -> String {
    let process = Process()
    process.executableURL = URL(filePath: realGit)
    process.arguments = ["-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false", "-c", "init.defaultBranch=main", "-c", "protocol.file.allow=always", "-C", dir.path] + args
    process.environment = ["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "PATH": "/usr/bin"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try process.run()
    let out = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0, "git \(args) failed")
    return String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func scratch() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    // realpath, because git reports real paths (/var is a symlink to /private/var).
    return URL(filePath: String(cString: realpath(dir.path, nil)))
}

/// A repo named `name` under `parent` with one commit "first".
@discardableResult
private func makeRepo(_ name: String, in parent: URL, commit: Bool = true) throws -> URL {
    let dir = parent.appending(path: name)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try git(dir, "init")
    if commit {
        try Data("a".utf8).write(to: dir.appending(path: "a.txt"))
        try git(dir, "add", "a.txt")
        try git(dir, "commit", "-m", "first")
    }
    return dir
}

private func candidates(_ cwds: URL..., ago: TimeInterval = 60) -> [RepoCandidate] {
    cwds.enumerated().map { RepoCandidate(cwd: $1.path, lastActivity: Date(timeIntervalSinceNow: -ago - Double($0))) }
}

private func scan(_ candidates: [RepoCandidate], scanner: GitScanner = GitScanner(gitPath: realGit)) async -> [RepoStatus] {
    guard case .repos(let rows) = await scanner.scan(candidates) else { return [] }
    return rows
}

/// A `git` that records `<GIT_OPTIONAL_LOCKS> <subcommand>` per call in `log`, then runs the real one.
private func recordingGit(in dir: URL) throws -> (path: String, log: URL) {
    let (script, log) = (dir.appending(path: "recording-git"), dir.appending(path: "calls.log"))
    // The subcommand is the first argument after `-C <dir>`.
    try Data("#!/bin/sh\necho \"$GIT_OPTIONAL_LOCKS $3\" >> '\(log.path)'\nexec '\(realGit)' \"$@\"\n".utf8).write(to: script)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    return (script.path, log)
}

// MARK: candidates

private func record(_ id: String, cwd: String?, at date: Date) -> UsageRecord {
    let cwdField = cwd.map { #""cwd":"\#($0)","# } ?? ""
    let time = date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    return parseUsageLines(Data(
        #"{"type":"assistant","timestamp":"\#(time)","requestId":"r\#(id)",\#(cwdField)"message":{"id":"m\#(id)","model":"m","usage":{"input_tokens":1}}}"#.utf8))[0]
}

private func session(_ cwd: String) -> ClaudeSession {
    ClaudeSession(pid: 1, sessionId: nil, cwd: cwd, status: nil, version: nil, rssBytes: 0, cpuNanos: 0, startTime: .now)
}

@Test func candidatesAreDistinctCwdsWithinFourteenDaysNewestFirst() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 86_400
    let records = [
        record("1", cwd: "/a", at: now - 5 * day),
        record("2", cwd: "/a", at: now - 3 * day),  // /a's latest wins
        record("3", cwd: "/a", at: now - 9 * day),
        record("4", cwd: "/b", at: now - 1 * day),
        record("5", cwd: "/old", at: now - 14 * day - 1),  // outside the window
        record("6", cwd: "/edge", at: now - 14 * day),  // exactly 14 days is inside
        record("7", cwd: nil, at: now),
    ]

    let result = activeRepoCandidates(records, sessions: [], now: now)

    #expect(result.map(\.cwd) == ["/b", "/a", "/edge"])
    #expect(result[1].lastActivity == now - 3 * day)
}

@Test func aRunningSessionsCwdCountsAsNow() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let records = [record("1", cwd: "/a", at: now - 3600), record("2", cwd: "/b", at: now - 60)]

    let result = activeRepoCandidates(records, sessions: [session("/a"), session("/c")], now: now)

    #expect(result.map(\.cwd) == ["/a", "/c", "/b"])  // /a and /c tie at now, ordered by path
    #expect(result[0].lastActivity == now)
}

// MARK: resolving

@Test func subdirectoriesCollapseIntoTheirRepo() async throws {
    let parent = try scratch()
    let repo = try makeRepo("proj", in: parent)
    try FileManager.default.createDirectory(at: repo.appending(path: "src/deep"), withIntermediateDirectories: true)

    let rows = await scan([
        RepoCandidate(cwd: repo.appending(path: "src/deep").path, lastActivity: Date(timeIntervalSince1970: 300)),
        RepoCandidate(cwd: repo.path, lastActivity: Date(timeIntervalSince1970: 200)),
        RepoCandidate(cwd: repo.appending(path: "src").path, lastActivity: Date(timeIntervalSince1970: 100)),
    ])

    #expect(rows.map(\.root) == [repo.path])
    #expect(rows[0].name == "proj")
    #expect(rows[0].branch == "main")
    #expect(rows[0].subject == "first")
    #expect(rows[0].lastActivity == Date(timeIntervalSince1970: 300))
    #expect(rows[0].isWorktree == false)
}

@Test func aWorktreeIsItsOwnRowWithItsOwnBranch() async throws {
    let parent = try scratch()
    let main = try makeRepo("main-repo", in: parent)
    let tree = parent.appending(path: "feature-tree")
    try git(main, "worktree", "add", "-b", "feature", tree.path)
    try Data("x".utf8).write(to: tree.appending(path: "new.txt"))

    let rows = await scan(candidates(main, tree))

    #expect(rows.map(\.name) == ["main-repo", "feature-tree"])
    #expect(rows.map(\.isWorktree) == [false, true])
    #expect(rows.map(\.branch) == ["main", "feature"])
    #expect(rows.map(\.dirty) == [0, 1])
}

@Test func nonGitDeletedAndTmpCwdsAreDroppedSilently() async throws {
    let parent = try scratch()
    let plain = parent.appending(path: "plain")
    try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
    let tmpRepo = URL(filePath: "/private/tmp/git-tab-test-\(UUID().uuidString)")
    try makeRepo(tmpRepo.lastPathComponent, in: URL(filePath: "/private/tmp"))
    defer { try? FileManager.default.removeItem(at: tmpRepo) }
    let kept = try makeRepo("kept", in: parent)

    let rows = await scan([
        RepoCandidate(cwd: plain.path, lastActivity: .now),
        RepoCandidate(cwd: parent.appending(path: "deleted").path, lastActivity: .now),
        RepoCandidate(cwd: tmpRepo.path, lastActivity: .now),
        RepoCandidate(cwd: "/tmp/" + tmpRepo.lastPathComponent, lastActivity: .now),
        RepoCandidate(cwd: "", lastActivity: .now),  // git -C "" would scan the test runner's own repo
        RepoCandidate(cwd: ".", lastActivity: .now),
        RepoCandidate(cwd: kept.path, lastActivity: .now),
    ])

    #expect(rows.map(\.name) == ["kept"])
}

@Test func theCapOfFifteenAppliesToReposNotCwdsAndKeepsTheNewest() async throws {
    let parent = try scratch()
    // 16 repos, r0 newest. r0 has three cwds, so there are 18 candidates for 16 repos.
    let repos = try (0..<16).map { try makeRepo("r\($0)", in: parent, commit: false) }
    for sub in ["a", "b"] { try FileManager.default.createDirectory(at: repos[0].appending(path: sub), withIntermediateDirectories: true) }
    var list = candidates(repos[0].appending(path: "a"), repos[0].appending(path: "b"), repos[0])
    list += (1..<16).map { RepoCandidate(cwd: repos[$0].path, lastActivity: Date(timeIntervalSinceNow: -1000 - Double($0))) }

    let rows = await scan(list)

    #expect(rows.map(\.name) == (0..<15).map { "r\($0)" })  // r15, the oldest repo, is cut; r0 appears once
}

// MARK: scanning

@Test func aheadAndBehindCompareAgainstTheLocalRemoteTrackingRef() async throws {
    let parent = try scratch()
    let remote = parent.appending(path: "remote.git")
    try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
    try git(remote, "init", "--bare")
    let mine = try makeRepo("mine", in: parent)
    try git(mine, "remote", "add", "origin", remote.path)
    try git(mine, "push", "-u", "origin", "main")
    // Another clone pushes one commit; this clone fetches it (the app itself never fetches).
    try git(parent, "clone", remote.path, "other")
    let other = parent.appending(path: "other")
    try Data("o".utf8).write(to: other.appending(path: "o.txt"))
    try git(other, "add", "o.txt")
    try git(other, "commit", "-m", "from other")
    try git(other, "push")
    try git(mine, "fetch")
    for n in 1...2 {
        try Data("\(n)".utf8).write(to: mine.appending(path: "m\(n).txt"))
        try git(mine, "add", "m\(n).txt")
        try git(mine, "commit", "-m", "mine \(n)")
    }

    let rows = await scan(candidates(mine))

    #expect(rows[0].ahead == 2)
    #expect(rows[0].behind == 1)
    #expect(rows[0].subject == "mine 2")
}

@Test func aBranchWithoutUpstreamHasNoAheadBehind() async throws {
    let repo = try makeRepo("solo", in: try scratch())

    let rows = await scan(candidates(repo))

    #expect(rows[0].ahead == nil)
    #expect(rows[0].behind == nil)
}

@Test func dirtyCountsModifiedStagedAndUntrackedEntries() async throws {
    let repo = try makeRepo("dirty", in: try scratch())
    try Data("changed".utf8).write(to: repo.appending(path: "a.txt"))
    try Data("s".utf8).write(to: repo.appending(path: "staged.txt"))
    try git(repo, "add", "staged.txt")
    try Data("u".utf8).write(to: repo.appending(path: "untracked.txt"))

    let rows = await scan(candidates(repo))

    #expect(rows[0].dirty == 3)
}

@Test func aRepoWithoutCommitsShowsItsBranchAndNoCommit() async throws {
    let repo = try makeRepo("empty", in: try scratch(), commit: false)
    try Data("u".utf8).write(to: repo.appending(path: "u.txt"))

    let rows = await scan(candidates(repo))

    #expect(rows.count == 1)
    #expect(rows[0].branch == "main")
    #expect(rows[0].subject == nil)
    #expect(rows[0].committedAt == nil)
    #expect(rows[0].dirty == 1)
}

@Test func aDetachedHeadShowsTheShortCommit() async throws {
    let repo = try makeRepo("detached", in: try scratch())
    let short = try git(repo, "rev-parse", "--short=7", "HEAD")
    try git(repo, "checkout", "--detach")

    let rows = await scan(candidates(repo))

    #expect(rows[0].branch == "detached @" + short)
    #expect(rows[0].ahead == nil)
}

@Test func commitTimeAndSubjectComeFromTheLastCommit() async throws {
    let repo = try makeRepo("dated", in: try scratch(), commit: false)
    try Data("a".utf8).write(to: repo.appending(path: "a.txt"))
    try git(repo, "add", "a.txt")
    let process = Process()
    process.executableURL = URL(filePath: realGit)
    process.arguments = ["-c", "user.name=t", "-c", "user.email=t@t", "-C", repo.path, "commit", "-m", "subject: with | odd chars"]
    process.standardOutput = FileHandle.nullDevice
    process.environment = ["GIT_COMMITTER_DATE": "@1700000000 +0000", "GIT_AUTHOR_DATE": "@1700000000 +0000", "GIT_CONFIG_GLOBAL": "/dev/null"]
    try process.run()
    process.waitUntilExit()

    let rows = await scan(candidates(repo))

    #expect(rows[0].subject == "subject: with | odd chars")
    #expect(rows[0].committedAt == Date(timeIntervalSince1970: 1_700_000_000))
}

// MARK: failure states

@Test func aSlowGitGivesATimedOutRowAndOthersStillScan() async throws {
    let parent = try scratch()
    let slow = try makeRepo("slow", in: parent)
    let script = parent.appending(path: "slow-git")
    // rev-parse answers; status hangs.
    try Data("#!/bin/sh\ncase \"$*\" in *rev-parse*) exec '\(realGit)' \"$@\";; *) exec /bin/sleep 20;; esac\n".utf8).write(to: script)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

    let started = ContinuousClock.now
    let rows = await scan(candidates(slow), scanner: GitScanner(gitPath: script.path, timeout: .milliseconds(500)))

    #expect(rows.count == 1)
    #expect(rows[0].timedOut)
    #expect(rows[0].branch == nil)
    #expect(started.duration(to: .now) < .seconds(5))
}

@Test func missingOrBrokenGitGivesTheGitNotFoundState() async throws {
    let repo = try makeRepo("any", in: try scratch())
    let broken = try scratch().appending(path: "git")
    // What the /usr/bin/git shim does without the Command Line Tools: exit 1.
    try Data("#!/bin/sh\nexit 1\n".utf8).write(to: broken)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: broken.path)

    for path in [nil, "/nonexistent/git", broken.path] {
        #expect(await GitScanner(gitPath: path).scan(candidates(repo)) == .gitNotFound)
    }
}

@Test func findGitUsesPathThenUsrBin() throws {
    let dir = try scratch()
    try Data("#!/bin/sh\n".utf8).write(to: dir.appending(path: "git"))
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.appending(path: "git").path)

    #expect(findGit(path: "/nonexistent:\(dir.path)") == dir.appending(path: "git").path)
    #expect(findGit(path: "/nonexistent") == "/usr/bin/git")
}

// MARK: scan hygiene

@Test func scansRunWithoutOptionalLocksNeverFetchAndResolveEachCwdOnce() async throws {
    let parent = try scratch()
    let repo = try makeRepo("watched", in: parent)
    let (path, log) = try recordingGit(in: parent)
    let scanner = GitScanner(gitPath: path)

    _ = await scan(candidates(repo), scanner: scanner)
    _ = await scan(candidates(repo), scanner: scanner)

    let calls = try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map(String.init)
    #expect(calls.sorted() == ["0 log", "0 log", "0 rev-parse", "0 status", "0 status"])
}
