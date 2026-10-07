# When does each data source refresh?

Type: grilling
Status: resolved
Blocked by: 08, 09

## Question

For each source (logs, Plan-limits capture file, running processes, git repos, `settings.json` wrapper detection, price table), what triggers a refresh: file-system events (FSEvents / `DispatchSource`), a timer (what interval), popover open, or a combination? Does cadence differ when the popover is closed (only the menu bar title and notifications need data) vs open? What is the CPU/battery budget at idle?

## Answer

Event-driven where data is needed while the popover is closed (menu bar title, notifications); timers only while something visible needs them.

- **Logs**: one FSEvents stream on `~/.claude/projects`, 2 s latency, always on; each batch triggers the incremental parse (ticket 08) of the changed files only. No polling fallback; add one only if events are measured to go missing.
- **Plan-limits capture file**: the same FSEvents stream also watches `~/Library/Application Support/ClaudeUsageBar/` (directory, not file: the wrapper replaces the file via `mv`, so a per-file `DispatchSource` would detach). Notifications are evaluated on each new capture.
- **Processes**: sampled every 2 s only while the popover is open on the Processes tab; CPU% reads `—` until the second sample. Nothing runs when closed.
- **Git**: scanned when the Git tab is shown, then every 15 s while it stays visible; previous rows stay on screen during a scan. No per-repo FSEvents, no refresh button, no scans while closed. Running-session cwds are read at scan time.
- **`settings.json` wrapper detection**: at launch and on every popover open (already settled in ticket 07).
- **Price table**: at launch and every 24 h (already settled in ticket 10).
- **Time-driven**: a one-shot timer at the next local midnight (rolls Today, the title $ and a Billing-cycle start), re-armed on `NSCalendarDayChanged` and wake from sleep. While the popover is open, a 1-minute timer refreshes age labels and shows a window past `resets_at` as 0%. Closed, `resets_at` is ignored (notifications fire on fresh data only).
- **Popover open**: starts the Processes/Git timers for the visible tab and the 1-minute timer; closing the popover stops all of them.
- **Budget (acceptance criteria, measured in Activity Monitor)**: popover closed and Claude Code idle → 0% CPU and ~0 idle wake-ups (only the midnight timer exists); while Claude Code streams → app CPU averages < 1%; popover open → no budget, but everything stops on close.
