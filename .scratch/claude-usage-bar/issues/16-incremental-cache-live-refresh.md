# 16: Incremental record cache and live refresh

**What to build:** Parsed records persist in one atomic `Codable` JSON cache in `~/Library/Application Support/ClaudeUsageBar/` with per-file state, so later launches read only appended bytes. History is bounded to 62 days. An always-on FSEvents stream (2 s latency) on `~/.claude/projects` and the app's Application Support dir triggers incremental parses of changed files, so the title updates while Claude Code streams. A one-shot midnight timer (re-armed on day change and wake) rolls Today.

**Blocked by:** 15

**Status:** resolved

Spec: [spec.md](../spec.md)

- [x] Per-file state `(path, device+inode, size, offset)`; reads stop at the last newline; half lines wait
- [x] Inode change or size < offset → drop the file's records and reparse; deleted file → records kept
- [x] Files with mtime older than today − 62 days are skipped unopened; older records pruned
- [x] Cache stores no prices; schema-version bump forces a full rescan; cache written atomically when a scan completes
- [x] A simulated relaunch over an unchanged tree reads no new bytes
- [x] FSEvents stream watches both directories (directory-level, not per file) and drives incremental parsing
- [x] Midnight one-shot timer re-armed on `NSCalendarDayChanged` and wake
- [x] Closed popover + Claude Code idle: no timers other than midnight (check by hand in Activity Monitor)

## Comments

- The cache is `~/Library/Application Support/ClaudeUsageBar/records.json` (`UsageCache`, schema version 1). Each file entry holds that file's own records, deduped within the file, so a reset drops exactly its records. The global `(message.id, requestId)` store merges every file's records. That merged store is kept between passes and rebuilt only when a reset or prune drops records.
- **Deviation: the cache is saved after the launch pass, then at most every 10 min, not after every incremental pass.** A save encodes every record: 0.34–0.41 s for about 64k records and a 26 MB JSON file. Saving every 2 s while Claude Code streams would cost about 20% CPU. A stale cache only means the next launch rereads up to 10 min of appended bytes. Offsets and records are always saved together, so totals stay correct.
- Measured on this machine (release build, warm page cache, 2.3 GB, 2.66k files, about 63–64k records):
  - Cold full pass: 5.1–6.5 s.
  - Save: 0.34–0.41 s.
  - Load: 0.30 s.
  - Warm full pass (stats every file, reads only appended bytes): 0.13–0.16 s.
  - One FSEvents pass, including title recompute: about 17 ms.
  - Warm launch of the bundled app: the title shows after 3.4 s and uses about 3 s CPU. It runs at `.background` QoS, likely on efficiency cores; the same work takes about 0.8 s in the test harness.
- Live check:
  - The title ticked up while this session wrote logs ($72.69 → $72.74 → … → $73.52). It matched a fresh cold scan to the cent ($72.77).
  - Streaming averaged 0.6–0.9% CPU with 0 idle wakeups (`top -stats cpu,idlew`).
  - Idle: 0.0% CPU, 0 idle wakeups.
- Peak memory: `FileHandle.readToEnd` data is autoreleased. Without a pool around each read, the cold pass held every file's bytes until it ended (2.4 GB peak footprint). With the pool the peak is 273 MB.
- `todayCost` now computes the day interval once instead of calling `Calendar.isDate` per record. The title went from 45 ms to 10 ms, which matters now that it runs on every pass.
- Full-pass and directory-pass keys must match. Paths are normalized with `appendingPathComponent`, which strips FSEvents' trailing slash, and `~/.claude/projects` is symlink-resolved. A test covers a symlinked home.
- Directory-level FSEvents: a batch's directories under `projects/` get a pass over the `.jsonl` files directly inside them. `MustScanSubDirs` or `RootChanged` triggers a full pass. Events in the Application Support dir only call `Usage.appSupportChanged`, the hook for ticket 20. That hook also fires on this app's own cache writes.
- Records in deleted files are kept until they age past the cutoff. Their entries are dropped on a full pass once empty.
- Checked the real tree: no `.jsonl` file ends without a newline, so the half-line wait never holds back a finished last line.
- Removed: `scanUsageLogs`, replaced by `UsageCache.update`.
