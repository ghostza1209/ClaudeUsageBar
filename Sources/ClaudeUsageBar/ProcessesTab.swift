import SwiftUI
import UsageCore

/// Samples the running Sessions every 2 s while `sampling` is true (popover open on the Processes tab). Turning it off
/// stops the timer and forgets the rows and the CPU baseline, so the next open starts again at `—`.
@MainActor @Observable final class ProcessMonitor {
    /// nil until the first sample of an open.
    var rows: [ClaudeSession]?
    var stopError: String?
    /// Pids sent SIGTERM and not yet gone; their button is disabled for at most 5 s.
    private(set) var stopping: [Int32: Date] = [:]

    @ObservationIgnored var sampling = false {
        didSet {
            guard sampling != oldValue else { return }
            timer?.invalidate()
            timer = nil
            guard sampling else {
                (rows, sampler, stopError, stopping) = (nil, ProcessSampler(), nil, [:])
                return
            }
            sample()
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.sample() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var sampler = ProcessSampler()
    private let claudeHome: URL

    init(claudeHome: URL) { self.claudeHome = claudeHome }

    // ponytail: runs on the main actor; a few small files and a few libproc calls. Move off it if the list grows large.
    private func sample() {
        let sampled = sampler.sample(listClaudeSessions(claudeHome: claudeHome))
        let alive = Set(sampled.map(\.pid))
        stopping = stopping.filter { alive.contains($0.key) && $0.value.timeIntervalSinceNow > -5 }
        rows = sampled
    }

    func stop(_ pid: Int32) {
        if let code = stopSession(pid: pid), code != ESRCH {
            stopError = "Could not stop \(pid): " + String(cString: strerror(code))
            return
        }
        stopError = nil
        stopping[pid] = .now
    }
}

struct ProcessesTab: View {
    let monitor: ProcessMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let rows = monitor.rows {
                if rows.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "terminal").font(.title2)
                        Text("no Claude Code sessions running").font(.caption)
                    }
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 20)
                }
                ForEach(rows, id: \.pid) { row($0) }
            }
            if let error = monitor.stopError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .top)
    }

    private func row(_ s: ClaudeSession) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(s.cwd.split(separator: "/").last.map(String.init) ?? "/").font(.callout).lineLimit(1)
                Text(s.cwd).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text("\(formatCPU(s.cpuPercent)) · \(formatMemory(s.rssBytes)) · \(formatUptime(-s.startTime.timeIntervalSinceNow))")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Button { monitor.stop(s.pid) } label: { Image(systemName: "xmark.circle") }
                .buttonStyle(.borderless).help("Stop (SIGTERM)").disabled(monitor.stopping[s.pid] != nil)
        }
    }
}
