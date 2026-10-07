# 22: Processes tab

**What to build:** The Processes tab lists running Claude Code Sessions: project name, cwd truncated in the middle, CPU %, RAM, uptime and a stop button that sends SIGTERM. Pids come from `~/.claude/sessions/*.json`, validated by `proc_pidpath` containing `/claude/versions/`. Sampling runs every 2 s only while the tab is visible.

**Blocked by:** 14

**Status:** resolved

Spec: [spec.md](../spec.md)

- [x] Session files parsed defensively; pids not matching a Claude Code binary are dropped
- [x] libproc: RSS and CPU time (Mach ticks via `mach_timebase_info`), start time, cwd
- [x] CPU % from two samples; nil (shown `—`) on the first
- [x] Stop sends `kill(pid, SIGTERM)`
- [x] Empty state "no Claude Code sessions running"
- [x] Timer runs only while the popover is open on this tab
- [x] Tests use a real child process (validation predicate injectable so a test binary can stand in), list it, stop it, see it gone

## Comments

- `UsageCore/Processes.swift`: `listClaudeSessions(claudeHome:isClaudeBinary:)` (predicate defaults to `/claude/versions/`), `ProcessSampler`, `stopSession(pid:)` (returns errno; refuses pid <= 0 so `kill(0|-1)` can never signal a group). Pid comes from the file name (`<pid>.json`; the `.key` files are ignored). cwd is the live libproc cwd, falling back to the file's. Sorted newest first. A wrong-typed field in a session file fails the decode and the file is skipped.
- App: `ProcessMonitor` (`ProcessesTab.swift`) is driven by `Popover`: `open && tab == 1` toggles `sampling`; turning it off invalidates the 2 s timer and drops the rows and CPU baseline, so every open starts at `—` for 2 s. Sampling runs on the main actor (a few small files plus libproc calls; marked `ponytail:`).
- Stop: no confirmation. After SIGTERM the button stays disabled until the pid leaves the list or 5 s pass (so a Session that ignores SIGTERM can be retried). ESRCH counts as success; any other errno shows a red line under the rows.
- Not done: no pid-reuse check against the file's `procStart` (spec only asks for the path check); no scroll cap on the row list.
- Verified: listing against the real `~/.claude/sessions` matched `ps` exactly (RSS KB, CPU time, uptime). The popover cannot be reached by AX or screenshot, so `ProcessesTab` was rendered with `ImageRenderer` (temporary test, not committed) over a sandbox tree whose "claude" was an ad-hoc-signed copy of `/bin/sleep` at `<sandbox>/claude/versions/2.1.0` with the default predicate: first sample `—`, then `0.0%`, stop delivered SIGTERM, row gone, empty state, rows nil after close. The live timer start/stop on real popover open/close was not observed.
- Pre-existing flake seen once: `compactCurrencyIgnoresNonUSLocale` mutates global UserDefaults and can fail under parallel runs.
