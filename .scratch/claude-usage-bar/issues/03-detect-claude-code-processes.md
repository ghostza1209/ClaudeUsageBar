# How can running Claude Code sessions be detected on macOS?

Type: research
Status: resolved

## Question

How can a macOS app list running Claude Code processes and, for each, get its cwd/project, CPU and RAM use, uptime, and map it to its Session (log file)? How can it kill one? Which APIs/commands work (ps, libproc, sysctl, lsof), and what do App Sandbox or other permission constraints rule out — i.e. does this force a non-sandboxed app?

## Answer

Claude Code writes `~/.claude/sessions/<pid>.json` for each live Session. Each file has `sessionId`, `cwd`, `startedAt`, `status` and `version`. The Session log is `~/.claude/projects/*/<sessionId>.jsonl`. This file is the pid-to-Session mapping; open files and argv don't contain it. The format is undocumented, so parse it defensively.

Per pid, libproc gives the stats: `PROC_PIDTASKINFO` for RSS and CPU time (CPU is in Mach ticks, so convert with `mach_timebase_info`), `PROC_PIDTBSDINFO` for start time, `PROC_PIDVNODEPATHINFO` for cwd. Validate each pid with `proc_pidpath` containing `/claude/versions/`; the kernel's process name is the version string, not `claude`. Stop a Session with `kill(pid, SIGTERM)`.

A sandboxed test build could not read `~/.claude`, got EPERM from `kill()`, and got 0 pids from `proc_listallpids`. So the app must be non-sandboxed and ship outside the Mac App Store (Developer ID plus notarization).

Details: [research/detect-claude-code-processes.md](../research/detect-claude-code-processes.md)
