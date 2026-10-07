import Darwin
import Foundation

/// A running Claude Code Session: a `~/.claude/sessions/<pid>.json` file whose pid is alive and runs a Claude Code binary.
public struct ClaudeSession: Sendable, Equatable {
    public let pid: Int32
    public let sessionId: String?
    /// The live cwd from libproc; the session file's cwd only if libproc cannot read it.
    public let cwd: String
    public let status: String?
    public let version: String?
    public let rssBytes: UInt64
    /// Total CPU time (user + system) in ns.
    public let cpuNanos: UInt64
    public let startTime: Date
    /// 100 = one core busy. Filled by `ProcessSampler`; nil until the second sample.
    public internal(set) var cpuPercent: Double?
}

/// The undocumented session file, read defensively: any wrong-typed field fails the decode and the file is skipped.
private struct SessionFile: Decodable {
    var sessionId: String?
    var cwd: String?
    var status: String?
    var version: String?
}

private let timebase: mach_timebase_info = {
    var info = mach_timebase_info()
    mach_timebase_info(&info)
    return info
}()

private func pidInfo<T: BitwiseCopyable>(_ pid: Int32, _ flavor: Int32, _ info: T) -> T? {
    var info = info
    return proc_pidinfo(pid, flavor, 0, &info, Int32(MemoryLayout<T>.size)) == MemoryLayout<T>.size ? info : nil
}

/// The Sessions in `<claudeHome>/sessions/<pid>.json`, newest first. A pid is dropped when it is dead or when
/// `isClaudeBinary` rejects its executable path (a stale file, a reused pid, `claude --chrome-native-host`).
public func listClaudeSessions(
    claudeHome: URL, isClaudeBinary: (String) -> Bool = { $0.contains("/claude/versions/") }
) -> [ClaudeSession] {
    let files = (try? FileManager.default.contentsOfDirectory(at: claudeHome.appending(path: "sessions"), includingPropertiesForKeys: nil)) ?? []
    let sessions = files.compactMap { url -> ClaudeSession? in
        guard url.pathExtension == "json", let pid = Int32(url.deletingPathExtension().lastPathComponent), pid > 0,
            let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(SessionFile.self, from: data)
        else { return nil }
        var path = [UInt8](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &path, UInt32(path.count))
        guard length > 0, isClaudeBinary(String(decoding: path.prefix(Int(length)), as: UTF8.self)),
            let task = pidInfo(pid, PROC_PIDTASKINFO, proc_taskinfo()),
            let bsd = pidInfo(pid, PROC_PIDTBSDINFO, proc_bsdinfo())
        else { return nil }
        let cwd = pidInfo(pid, PROC_PIDVNODEPATHINFO, proc_vnodepathinfo()).map {
            withUnsafeBytes(of: $0.pvi_cdir.vip_path) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        }
        return ClaudeSession(
            pid: pid, sessionId: file.sessionId, cwd: cwd ?? file.cwd ?? "", status: file.status, version: file.version,
            rssBytes: task.pti_resident_size,
            // Mach ticks, not ns, on Apple Silicon.
            cpuNanos: (task.pti_total_user + task.pti_total_system) * UInt64(timebase.numer) / UInt64(timebase.denom),
            startTime: Date(timeIntervalSince1970: TimeInterval(bsd.pbi_start_tvsec)))
    }
    return sessions.sorted { $0.startTime > $1.startTime }
}

/// Holds the previous sample per pid so the next one can report CPU %.
public struct ProcessSampler {
    private var previous: [Int32: (cpuNanos: UInt64, at: Date)] = [:]

    public init() {}

    public mutating func sample(_ sessions: [ClaudeSession], at now: Date = .now) -> [ClaudeSession] {
        let last = previous
        previous = Dictionary(uniqueKeysWithValues: sessions.map { ($0.pid, ($0.cpuNanos, now)) })
        return sessions.map { session in
            var session = session
            if let p = last[session.pid], session.cpuNanos >= p.cpuNanos, now > p.at {
                session.cpuPercent = Double(session.cpuNanos - p.cpuNanos) / (now.timeIntervalSince(p.at) * 1e9) * 100
            }
            return session
        }
    }
}

/// Sends SIGTERM; returns the errno on failure. ESRCH means it was already gone.
public func stopSession(pid: Int32) -> Int32? {
    guard pid > 0 else { return EINVAL }  // kill(0 or negative) would signal a whole process group
    return kill(pid, SIGTERM) == 0 ? nil : errno
}
