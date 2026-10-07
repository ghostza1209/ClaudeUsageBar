import Foundation
import Testing

@testable import UsageCore

/// A Claude home whose `sessions/` holds one `<pid>.json` per pid, each claiming `cwd: /from/file`.
private func claudeHome(pids: [Int32]) throws -> URL {
    let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: home.appending(path: "sessions"), withIntermediateDirectories: true)
    for pid in pids {
        let json = #"{"pid":\#(pid),"sessionId":"abc-\#(pid)","cwd":"/from/file","startedAt":1,"status":"idle","version":"2.1.0"}"#
        try Data(json.utf8).write(to: home.appending(path: "sessions/\(pid).json"))
    }
    return home
}

private func spawn(_ path: String, _ args: [String] = [], in dir: URL? = nil) throws -> Process {
    let process = Process()
    process.executableURL = URL(filePath: path)
    process.arguments = args
    process.currentDirectoryURL = dir
    process.standardOutput = FileHandle.nullDevice
    try process.run()
    // Until exec lands, libproc still reports the parent's path; wait so every test lists the real binary.
    let name = URL(filePath: path).lastPathComponent
    var buffer = [CChar](repeating: 0, count: 4096)
    for _ in 0..<200 {
        if proc_pidpath(process.processIdentifier, &buffer, UInt32(buffer.count)) > 0, String(cString: buffer).hasSuffix("/" + name) { break }
        Thread.sleep(forTimeInterval: 0.01)
    }
    return process
}

private func isSleep(_ path: String) -> Bool { path.hasSuffix("/sleep") }

@Test func listsALiveSessionWithLibprocStats() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let child = try spawn("/bin/sleep", ["30"], in: dir)
    defer { child.terminate() }

    let sessions = listClaudeSessions(claudeHome: try claudeHome(pids: [child.processIdentifier]), isClaudeBinary: isSleep)

    #expect(sessions.map(\.pid) == [child.processIdentifier])
    #expect(sessions[0].sessionId == "abc-\(child.processIdentifier)")
    #expect(sessions[0].status == "idle")
    #expect(sessions[0].version == "2.1.0")
    #expect(sessions[0].cwd == "/private" + dir.path)  // libproc, not the file's "/from/file"
    #expect(sessions[0].rssBytes > 0 && sessions[0].rssBytes < 100_000_000)
    #expect(abs(sessions[0].startTime.timeIntervalSinceNow) < 30)
    #expect(sessions[0].cpuPercent == nil)
}

@Test func dropsAPidWhoseBinaryTheValidationRejects() throws {
    let child = try spawn("/bin/sleep", ["30"])
    defer { child.terminate() }
    let home = try claudeHome(pids: [child.processIdentifier])

    #expect(listClaudeSessions(claudeHome: home, isClaudeBinary: { $0.hasSuffix("/yes") }).isEmpty)
    #expect(listClaudeSessions(claudeHome: home).isEmpty)  // the default requires /claude/versions/
}

@Test func dropsAStaleFileForADeadPid() throws {
    let dead = try spawn("/usr/bin/true")
    dead.waitUntilExit()
    let live = try spawn("/bin/sleep", ["30"])
    defer { live.terminate() }

    let sessions = listClaudeSessions(claudeHome: try claudeHome(pids: [dead.processIdentifier, live.processIdentifier]), isClaudeBinary: { _ in true })

    #expect(sessions.map(\.pid) == [live.processIdentifier])
}

@Test func ignoresMalformedAndForeignFilesInTheSessionsDir() throws {
    let child = try spawn("/bin/sleep", ["30"])
    defer { child.terminate() }
    let home = try claudeHome(pids: [child.processIdentifier])
    let other = child.processIdentifier  // a live pid, so only the file content can exclude these
    for (name, content) in [
        ("\(other)x.json", "{}"), ("not-a-pid.json", "{}"), ("\(other).key", "{}"),
        ("1.json", "not json"), ("2.json", #"{"cwd": 5}"#), ("3.json", ""),
    ] {
        try Data(content.utf8).write(to: home.appending(path: "sessions/\(name)"))
    }

    #expect(listClaudeSessions(claudeHome: home, isClaudeBinary: { _ in true }).map(\.pid) == [child.processIdentifier])
    #expect(listClaudeSessions(claudeHome: home.appending(path: "missing"), isClaudeBinary: { _ in true }).isEmpty)
}

@Test func malformedFileForALivePidIsSkipped() throws {
    let child = try spawn("/bin/sleep", ["30"])
    defer { child.terminate() }
    let home = try claudeHome(pids: [])
    try Data(#"{"cwd": 5}"#.utf8).write(to: home.appending(path: "sessions/\(child.processIdentifier).json"))

    #expect(listClaudeSessions(claudeHome: home, isClaudeBinary: { _ in true }).isEmpty)
}

@Test func stopTerminatesTheChildAndTheNextListDropsIt() throws {
    let child = try spawn("/bin/sleep", ["30"])
    let home = try claudeHome(pids: [child.processIdentifier])
    #expect(listClaudeSessions(claudeHome: home, isClaudeBinary: isSleep).count == 1)

    #expect(stopSession(pid: child.processIdentifier) == nil)
    child.waitUntilExit()

    #expect(child.terminationReason == .uncaughtSignal)
    #expect(child.terminationStatus == SIGTERM)
    #expect(listClaudeSessions(claudeHome: home, isClaudeBinary: isSleep).isEmpty)
    #expect(stopSession(pid: child.processIdentifier) == ESRCH)
}

@Test func stopRefusesPidsThatWouldSignalAGroup() {
    #expect(stopSession(pid: 0) == EINVAL)
    #expect(stopSession(pid: -1) == EINVAL)
}

@Test func cpuIsNilOnTheFirstSampleThenMeasuresARealBusyChild() throws {
    let child = try spawn("/usr/bin/yes")
    defer { child.terminate() }
    let home = try claudeHome(pids: [child.processIdentifier])
    func isYes(_ path: String) -> Bool { path.hasSuffix("/yes") }
    var sampler = ProcessSampler()

    let first = sampler.sample(listClaudeSessions(claudeHome: home, isClaudeBinary: isYes))
    #expect(first.count == 1 && first[0].cpuPercent == nil)

    Thread.sleep(forTimeInterval: 0.5)
    let second = sampler.sample(listClaudeSessions(claudeHome: home, isClaudeBinary: isYes))
    // `yes` is a single busy thread: about 100 (one core), never above a core.
    let cpu = try #require(second[0].cpuPercent)
    #expect(cpu > 5 && cpu < 120)
}

@Test func cpuPercentIsTheCpuTimeDeltaOverWallTime() {
    func session(_ pid: Int32, cpuSeconds: Double) -> ClaudeSession {
        ClaudeSession(pid: pid, sessionId: nil, cwd: "/p", status: nil, version: nil, rssBytes: 0,
                      cpuNanos: UInt64(cpuSeconds * 1e9), startTime: .distantPast)
    }
    let t0 = Date(timeIntervalSince1970: 1000)
    var sampler = ProcessSampler()
    _ = sampler.sample([session(1, cpuSeconds: 1), session(2, cpuSeconds: 5)], at: t0)

    // pid 1: 2 s of CPU over 4 s wall = 50 %. pid 2 is new. pid 3 has fewer ticks than before (a reused pid).
    let second = sampler.sample([session(1, cpuSeconds: 3), session(3, cpuSeconds: 1)], at: t0 + 4)
    #expect(second.map(\.cpuPercent) == [50, nil])

    // pid 1 vanished then returned: no stale baseline.
    _ = sampler.sample([], at: t0 + 6)
    #expect(sampler.sample([session(1, cpuSeconds: 4)], at: t0 + 8)[0].cpuPercent == nil)
}
