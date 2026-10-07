# 16: Incremental record cache and live refresh

**What to build:** Parsed records persist in one atomic `Codable` JSON cache in `~/Library/Application Support/ClaudeUsageBar/` with per-file state, so later launches read only appended bytes. History is bounded to 62 days. An always-on FSEvents stream (2 s latency) on `~/.claude/projects` and the app's Application Support dir triggers incremental parses of changed files, so the title updates while Claude Code streams. A one-shot midnight timer (re-armed on day change and wake) rolls Today.

**Blocked by:** 15

**Status:** ready-for-agent

Spec: [spec.md](../spec.md)

- [ ] Per-file state `(path, device+inode, size, offset)`; reads stop at the last newline; half lines wait
- [ ] Inode change or size < offset → drop the file's records and reparse; deleted file → records kept
- [ ] Files with mtime older than today − 62 days are skipped unopened; older records pruned
- [ ] Cache stores no prices; schema-version bump forces a full rescan; cache written atomically when a scan completes
- [ ] A simulated relaunch over an unchanged tree reads no new bytes
- [ ] FSEvents stream watches both directories (directory-level, not per file) and drives incremental parsing
- [ ] Midnight one-shot timer re-armed on `NSCalendarDayChanged` and wake
- [ ] Closed popover + Claude Code idle: no timers other than midnight (check by hand in Activity Monitor)
