# 22: Processes tab

**What to build:** The Processes tab lists running Claude Code Sessions: project name, cwd truncated in the middle, CPU %, RAM, uptime and a stop button that sends SIGTERM. Pids come from `~/.claude/sessions/*.json`, validated by `proc_pidpath` containing `/claude/versions/`. Sampling runs every 2 s only while the tab is visible.

**Blocked by:** 14

**Status:** ready-for-agent

Spec: [spec.md](../spec.md)

- [ ] Session files parsed defensively; pids not matching a Claude Code binary are dropped
- [ ] libproc: RSS and CPU time (Mach ticks via `mach_timebase_info`), start time, cwd
- [ ] CPU % from two samples; nil (shown `—`) on the first
- [ ] Stop sends `kill(pid, SIGTERM)`
- [ ] Empty state "no Claude Code sessions running"
- [ ] Timer runs only while the popover is open on this tab
- [ ] Tests use a real child process (validation predicate injectable so a test binary can stand in), list it, stop it, see it gone
