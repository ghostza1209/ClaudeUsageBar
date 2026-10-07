# 20: Plan-limits rings header

**What to build:** The popover header shows two rings, the 5-hour window and the Weekly window, with percent used, reset time and an "updated X min ago" age line (orange when stale), coloured accent / orange at warning / red at critical (thresholds from `@AppStorage`, default 80/95). Plan limits are read from the capture file, refreshed through the FSEvents stream. Each failure state replaces only the header with a distinct one-line message.

**Blocked by:** 16, 19

**Status:** ready-for-agent

Spec: [spec.md](../spec.md)

- [ ] Plan-limits state: not installed / no data yet / unreadable (short error) / ok (both windows with percent, reset, captured-at = file mtime)
- [ ] A window past its `resets_at` reads 0% for display
- [ ] Ring colour by threshold is computed in `UsageCore` from passed-in thresholds
- [ ] Title shows ⚠ when Plan limits are unreadable (in addition to not installed)
- [ ] While the popover is open, a 1-minute timer refreshes age labels and reset zeroing; it stops on close
- [ ] Tests cover each state including a malformed file, and the reset zeroing with an injected clock
