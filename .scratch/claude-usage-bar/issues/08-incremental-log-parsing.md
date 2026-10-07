# How does the app parse GBs of logs without rescanning them?

Type: grilling
Status: resolved

## Question

On this machine `~/.claude/projects` holds 2.3 GB across 2,645 `.jsonl` files in 42 project directories, 16 of them over 10 MB. How does the app avoid re-reading all of it each time it computes totals? The decisions are:

- What it remembers per file (byte offset, size, mtime, inode) so it reads only appended bytes, and how it handles a file that shrank, was rewritten or was deleted.
- Whether and where parsed results persist across launches (e.g. a cache file in Application Support), at what granularity (per-response records needed for the `(message.id, requestId)` dedupe, or pre-aggregated per day/model), and how a cache is invalidated (schema or price change).
- How a cold first launch behaves (scan time budget, progress or partial totals in the UI).
- How far back history must reach: everything, or only the current Billing cycle plus the 14-day trend.

## Answer

Measured here: 2.3 GB / 2,645 files, 2.1 GB modified in the last 45 days; a raw grep of every file takes about 15 s and finds about 126k `usage` lines (about 60k responses after dedupe).

- **History reach**: keep only what the UI uses. Cutoff = today − 62 days (covers any Billing cycle start plus the 14-day trend). Files whose mtime is older than the cutoff are skipped unopened (mtime ≥ last line's timestamp); records older than the cutoff are pruned. Viewing past Billing cycles is out of scope.
- **Per-file state**: `(path, device+inode, size, read offset)`. Read only appended bytes, stopping at the last `\n` (a half-written line waits for the next pass). Inode changed or size < offset → drop that file's records and reparse from 0. File deleted → **keep** its records (usage happened; totals must not drop when Claude Code cleans transcripts).
- **Persistence**: one `Codable` JSON cache in `~/Library/Application Support/ClaudeUsageBar/`, written atomically, holding the per-file state plus per-response records keyed globally by `(message.id, requestId)` (largest total wins): timestamp, model, sessionId, cwd, token counts by type. **No prices stored**; cost is computed at display time, so a price-table change never invalidates the cache. Only a schema-version bump invalidates it (full rescan).
- **Cold start**: background, low-priority task; files ordered newest mtime first so Today and the last hour settle first; the Usage tab shows partial totals with a "Scanning n/m files" indicator; no time budget; cache written once when the scan finishes (an interrupted scan restarts next launch).
- **Menu bar title during the cold scan**: icon only, no $ until the scan finishes (no misleading partial total). Plan-limit notifications are unaffected (they come from the statusline capture, not logs).
