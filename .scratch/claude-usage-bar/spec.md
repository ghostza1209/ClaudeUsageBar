# Spec: Claude usage menu bar app

Status: ready-for-agent

Source: [map.md](map.md) and its resolved tickets in [issues/](issues/). Vocabulary: [GLOSSARY.md](../../GLOSSARY.md). Architecture: [ADR 0001](../../docs/adr/0001-swiftpm-only-with-bundle-script.md).

## Problem Statement

I use Claude Code heavily on a Pro/Max subscription, but I can't see at a glance how much I'm using it. To know how close I am to my Plan limits I have to run `/usage` inside a Session. To know what my usage would cost at API prices, I have to run a CLI tool over gigabytes of logs. I lose track of which Claude Code Sessions are still running and eating CPU and RAM, and which repos Claude Code has left dirty or ahead of their remote. Nothing tells me before I hit the 5-hour or Weekly limit, so I find out when Claude Code stops.

## Solution

A personal, native macOS menu bar app that reads only what Claude Code already leaves on disk. The menu bar shows an icon and today's API list estimate. Clicking it opens a popover with:

- A **Plan-limits header**: two rings, the 5-hour window and the Weekly window, each with percent used, reset time and data age, coloured by threshold.
- Three tabs:
  - **Usage**: Billing-cycle totals, Today, a last-hour sparkline, a 14-day trend and a per-model table, all as an API list estimate. Layout follows TermTracker.
  - **Processes**: running Claude Code Sessions with CPU, RAM, uptime and a stop button.
  - **Git**: repos Claude Code recently worked in, with branch, dirty count, ahead/behind and last commit.

Plan limits come from Claude Code's official statusline `rate_limits`. A small wrapper script, installed with one click, captures them. The app sends macOS notifications when a window crosses the warning or critical threshold. It stays near 0% CPU while idle.

## User Stories

### Menu bar title

1. As a Claude Code user, I want today's API list estimate in the menu bar, so that I see my day's usage without clicking.
2. As a user, I want the title kept to about 6 characters (`$18.42`, `$123`, `$1.2k`), so that it doesn't crowd my menu bar.
3. As a user, I want the title to show `—` when there are no Claude Code logs yet, so that I can tell "nothing yet" apart from "$0.00".
4. As a user, I want the title to show only the icon while the first log scan is running, so that I'm never shown a misleadingly low partial total.
5. As a user, I want a trailing ⚠ in the title when the statusline wrapper is not installed or Plan limits are unreadable, so that I notice the Plan-limits feed is broken.
6. As a user, I want the title's $ to roll over at local midnight even if I don't open the popover, so that "today" is always today.

### Plan limits

7. As a Pro/Max subscriber, I want to see percent used for the 5-hour window and the Weekly window, so that I can pace my work.
8. As a subscriber, I want each window's reset time, so that I know when capacity comes back.
9. As a subscriber, I want each value to show its age ("updated 4 min ago"), so that I know how fresh it is, since it only updates while Claude Code is running.
10. As a subscriber, I want the age shown in orange when it is stale, so that I don't trust old numbers.
11. As a subscriber, I want a window past its reset time to read 0% without waiting for new data, so that the header doesn't show a limit that has already reset.
12. As a subscriber, I want the rings coloured accent, then orange at the warning threshold, then red at the critical threshold, so that I can read the state at a glance.
13. As a user who hasn't installed the wrapper, I want a "wrapper not installed" message with an Install button in the header, so that I can fix it in one click.
14. As a user on an API key or a fresh Session, I want a "no data yet" message prompting me to run Claude Code on Pro/Max, so that I understand why there is nothing to show.
15. As a user, I want a short error when the capture file is unreadable, so that a format change never crashes the app.
16. As a user running several Sessions at once, I want Plan limits to reflect the latest capture from any of them, so that I always see the newest value for my account.

### Notifications

17. As a subscriber, I want a macOS notification when a window crosses the warning threshold (default 80%), so that I can slow down before I'm cut off.
18. As a subscriber, I want a second notification at the critical threshold (default 95%), so that I know I'm about to hit the limit.
19. As a subscriber, I want each threshold to notify at most once per window, re-armed only when that window resets, so that I'm not spammed.
20. As a subscriber, I want notifications only on fresh data, so that I'm never alerted from a stale or reset value.
21. As a user, I want notifications to work while the popover is closed, so that I'm warned while I work in the terminal.
22. As a user, I want to turn notifications off, so that I can silence them.
23. As a user, I want notification permission requested on first launch or first enable, so that alerts work without digging through System Settings.

### Statusline wrapper

24. As a user, I want the app never to edit Claude Code's settings without my click, so that I stay in control of my config.
25. As a user, I want Install to keep my existing statusline (e.g. claude-hud) working exactly as before, so that I don't lose my current status display.
26. As a user, I want my existing statusline command kept verbatim, however complex its quoting, so that installing never breaks it.
27. As a user, I want the app to notice when another tool overwrote the statusline, and offer Install again, so that capture silently breaking is visible.
28. As a user, I want reinstalling to chain to whatever statusline is current, so that an updated claude-hud command is picked up.
29. As a user, I want Uninstall to restore my previous statusline exactly, including `padding` and other keys, so that removing the app leaves no trace.
30. As a user, I want Uninstall to leave settings untouched if I've since changed the statusline myself, so that it never clobbers my newer config.
31. As a user, I want the app to refuse to write a `settings.json` it can't parse, so that a malformed file is never overwritten.
32. As a user, I want a Session with no `rate_limits` (before the first response, or an API-key Session) never to wipe good captured data, so that the header keeps its last real value.
33. As a user, I want a capture failure never to break my statusline output, so that the wrapper is invisible when things go wrong.
34. As a user, I want deleting the app alone to leave the wrapper working, so that my statusline doesn't break if I remove the app without uninstalling.

### Usage tab

35. As a user, I want the API list estimate for the current Billing cycle with its start date, so that I see the month's value of my subscription.
36. As a user, I want the Billing cycle's token breakdown (input, output, cache read, cache write), so that I understand where the volume goes.
37. As a user, I want Today's cost, tokens and request count, so that I can track my daily pace.
38. As a user, I want a last-hour tokens/min sparkline, so that I can see current activity.
39. As a user, I want a 14-day trend chart with compact $ axis labels, so that I can spot heavy days.
40. As a user, I want a per-model table with tokens and $, so that I see which models drive cost.
41. As a user, I want sub-agent usage counted, so that the totals include everything Claude Code spent.
42. As a user, I want each response counted once even though the logs split and repeat it, so that totals aren't doubled.
43. As a user, I want advisor iterations priced at their own model, so that the estimate is accurate.
44. As a user, I want tokens from Unpriced models counted but left out of the $, with an "excludes N unpriced model(s)" note beside the amount, so that I know the estimate is partial.
45. As a user, I want web search requests priced at $0.01 each, so that tool costs are included.
46. As a user, I want amounts always shown as `$` in en_US format (`$3,124.50`) whatever my system locale, so that I never see `US$`.
47. As a user, I want tiny non-zero amounts shown as `<$0.01` and zero as `$0.00`, so that small values aren't hidden or misleading.
48. As a user, I want "Scanning n/m files" with partial totals during the first scan, so that I know the app is working on my 2+ GB of logs.
49. As a user, I want the newest files scanned first, so that Today and the last hour settle quickly.
50. As a user, I want later launches to be instant, reading only bytes appended since last time, so that the app doesn't reparse gigabytes.
51. As a user, I want totals not to drop when Claude Code deletes old transcripts, so that usage that happened stays counted.
52. As a user, I want a rewritten or truncated log reparsed from the start, so that totals stay correct.
53. As a user, I want a half-written log line to wait for the next pass, so that streaming writes never corrupt the parse.
54. As a user, I want "no Claude Code logs yet" when there are no logs, so that an empty tab is explained.
55. As a user, I want the Usage tab to update within a few seconds while Claude Code is streaming, so that I see live usage.

### Prices

56. As a user, I want API prices to come from a maintained public table that is refreshed automatically, so that estimates track Anthropic's price changes without an app update.
57. As a user, I want a bundled price snapshot used when offline or when the fetch fails, so that the estimate works from the first launch.
58. As a user, I want a price-table update to re-price all past usage immediately, so that every number uses current prices.
59. As a user, I want the popover to tell me when the price table is more than 7 days old, so that I know the estimate may be off.
60. As a user, I want to update prices manually from Settings, with an inline error on failure, so that I can force a refresh.

### Processes tab

61. As a user, I want a row for each running Claude Code Session, with project name and cwd (truncated in the middle), so that I know what is running where.
62. As a user, I want CPU %, RAM and uptime for each Session, so that I can spot a runaway Session.
63. As a user, I want CPU to show `—` until the second sample, so that I'm never shown a bogus first reading.
64. As a user, I want a stop button that sends SIGTERM to a Session, so that I can end a forgotten one cleanly.
65. As a user, I want only real Claude Code processes listed, validated by their executable path, so that stale session files or reused pids don't appear.
66. As a user, I want "no Claude Code sessions running" when there are none, so that the empty tab is explained.

### Git tab

67. As a user, I want a row for each repo Claude Code worked in during the last 14 days, newest first, at most 15, so that I see the repos that matter.
68. As a user, I want each row to show repo name, dirty count and ahead/behind, then branch, last commit subject and its age, so that I can see what Claude Code left behind.
69. As a user, I want repos with a running Session to count as active now, so that a brand-new Session's repo shows up.
70. As a user, I want subdirectory cwds collapsed into their repo, so that one repo isn't listed many times.
71. As a user, I want each worktree shown as its own row, labelled with the worktree name, so that parallel work in worktrees is visible.
72. As a user, I want non-git, deleted and `/tmp` cwds silently dropped, so that the list stays clean.
73. As a user, I want the app never to fetch, so that it never touches the network or my remotes.
74. As a user, I want a branch without an upstream to show no ahead/behind, so that I'm not shown a meaningless 0/0.
75. As a user, I want git scans never to take `index.lock`, so that the app never interferes with Claude Code's own git commands.
76. As a user, I want a slow repo to read "timed out" after 3 s without blocking the others, so that one huge repo doesn't stall the tab.
77. As a user, I want the previous rows kept on screen during a rescan, so that the tab doesn't flicker.
78. As a user, I want "git not found" with a fix hint, or "no repos yet" when there are no logs, so that an empty tab is explained.

### Settings

79. As a user, I want a gear in the popover that opens Settings in front (and ⌘, while the popover is open), so that I can reach it quickly.
80. As a user, I want a Launch at login toggle that reflects the real system state, so that it never lies.
81. As a user, I want to set the Billing-cycle start day (1–31, default 1, clamped to the last day of shorter months), so that totals match my subscription's renewal date.
82. As a user, I want to set warning and critical thresholds (50–100 in steps of 5, warning below critical), so that alerts and ring colours fit my pace.
83. As a user, I want the statusline install state with Install/Uninstall buttons in Settings, so that I can manage the wrapper in one place.
84. As a user, I want the price-table age always shown in Settings, so that I can check freshness.

### Footprint

85. As a user on battery, I want the app at 0% CPU with about zero wake-ups while the popover is closed and Claude Code is idle, so that it costs me nothing.
86. As a user, I want the app under 1% CPU on average while Claude Code is streaming, so that monitoring doesn't slow my work.
87. As a user, I want every popover-only timer to stop when I close the popover, so that nothing keeps polling in the background.

## Implementation Decisions

### Architecture and build (ADR 0001)

- Native SwiftUI, macOS 27+, non-sandboxed. Sandboxing blocks reading `~/.claude`, `kill()` and `proc_listallpids`. The app is not distributed through the Mac App Store.
- A Swift Package with no Xcode project and two targets:
  - `UsageCore`: a library with no UI. It holds log parsing, the record cache, pricing, Plan-limit capture parsing and notification state, process inspection, git scanning, statusline wrapper install/uninstall, and formatting.
  - `ClaudeUsageBar`: a SwiftUI executable using `MenuBarExtra(.window)`, Swift Charts, `Settings` and `UNUserNotificationCenter`.
- A bundle script builds release, writes `Info.plist` (`LSUIElement`, `CFBundleIdentifier`), ad-hoc signs the result and opens it. It is the only way to run the app; `swift run` is unsupported because notifications need a bundle.
- No third-party dependencies. Background work runs in-process with Swift concurrency. No daemon or LaunchAgent.
- `UsageCore` never reads UserDefaults. It takes its paths (Claude home, Application Support dir), a clock/calendar, user settings (Billing-cycle start day, thresholds) and a price-table fetcher as parameters. This is also the test seam.

### Data locations

- Claude Code logs: `assistant` lines in `~/.claude/projects/**/*.jsonl`, including `<sessionId>/subagents/**/agent-*.jsonl`.
- Running Sessions: `~/.claude/sessions/<pid>.json` (`sessionId`, `cwd`, `startedAt`, `status`, `version`). The format is undocumented, so parse it defensively.
- Claude Code settings: `~/.claude/settings.json`; only `statusLine` is touched.
- App files live in `~/Library/Application Support/ClaudeUsageBar/`:
  - `statusline.sh`
  - `chain.sh`
  - `previous-statusline.json`
  - `statusline-input.json`, the capture file
  - the log record cache
  - `prices.json`

### Log parsing and record cache

- A usage record is one API response, keyed globally by `(message.id, requestId)`. When several lines share a key, keep the one with the largest total, because responses are split and streamed partials repeat.
- Fields kept per record:
  - timestamp, model, sessionId, cwd
  - input, output, cache read, 5-minute cache write and 1-hour cache write tokens
  - web search request count
  - speed
  - advisor iterations, each with its own model and tokens
- Skip `<synthetic>` models and non-transcript `.jsonl` files.
- History cutoff is today − 62 days. Files whose mtime is older are skipped unopened, and records older than the cutoff are pruned.
- Per-file state is `(path, device+inode, size, read offset)`:
  - Read only appended bytes, up to the last newline.
  - If the inode changes or the size drops below the offset, drop that file's records and reparse it from 0.
  - If the file is deleted, keep its records.
- Persistence is one `Codable` JSON cache, written atomically, holding the per-file state and the records. It stores no prices. Only a schema-version bump invalidates it, which forces a full rescan.
- Cold start runs as a low-priority background task, newest-mtime files first. While it runs, it publishes partial totals and `n/m` progress, and the title stays icon-only until it finishes. The cache is written when the scan completes, so an interrupted scan restarts on the next launch.
- After the cold start, incremental passes run on the changed files only.

### Pricing

- Prices come only from LiteLLM's `model_prices_and_context_window.json`.
- A snapshot trimmed to Claude keys is bundled. The full table is fetched at launch and every 24 h, and cached atomically as `prices.json`. Precedence: fetched cache, then the bundled snapshot. A failed scheduled fetch keeps the current table silently.
- Lookup is by exact model id, then `anthropic/<id>`. There is no fuzzy or family matching.
- No match, or `speed: "fast"`, makes it an Unpriced model: its tokens are counted but left out of the $. The popover reports the count of excluded models. The title shows the partial sum with no marker.
- Web search costs $0.01 per request. The `inference_geo` multiplier is ignored. Advisor iterations are priced at their own model.
- Records are priced at display time, so a new table re-prices everything.

### Aggregation

- The core computes, for a given "now", calendar and Billing-cycle start day:
  - Billing-cycle $ and token breakdown, with the cycle start date. The start day is clamped to the month's last day.
  - Today's $, tokens and request count.
  - Last-hour tokens per minute.
  - A 14-day daily $ series.
  - Per-model tokens and $.
  - The unpriced-model count.
- "Today" and days use the local calendar.

### Formatting

- Two formatters, both `$` with `en_US` separators regardless of locale:
  - **Full** (popover, tooltips): 2 decimals with grouping. A non-zero amount below $0.01 shows `<$0.01`; zero shows `$0.00`.
  - **Compact** (title, trend axis): below $100 `$18.42`; $100–$999 whole dollars (`$123`); $1,000 and up one-decimal thousands (`$1.2k`). The band is chosen on the rounded value, so $999.60 shows `$1.0k`.

### Plan limits

- No authentication. The app never reads the Keychain or calls an Anthropic endpoint.
- The wrapper writes all of stdin to the capture file atomically (temp file + `mv`), but only when stdin contains `"rate_limits"`. Last write wins across Sessions. The file's mtime is the captured-at time.
- The app parses `rate_limits.five_hour` and `rate_limits.seven_day`, each with `used_percentage` (0–100) and `resets_at` (epoch seconds).
- The Plan-limits state is one of four:
  - **not installed**
  - **no data yet**: no capture file, or no `rate_limits`
  - **unreadable**: carries a short error
  - **ok**: both windows with percent, reset and captured-at
- A window past its `resets_at` is reported as 0% for display.
- Notification state per window: a threshold fires once, when fresh data crosses it, and re-arms when that window's `resets_at` changes. A window that has passed `resets_at` without new data never fires anything. Thresholds and the enabled flag are passed in.
- Ring colours: accent below the warning threshold, orange from warning, red from critical. They use the same thresholds as notifications.

### Statusline wrapper install and removal

- Install happens only on a user click (header button or Settings). Install does this:
  1. Read `statusLine` from `settings.json`.
  2. Save the whole previous `statusLine` object to `previous-statusline.json`, or a marker if there was none.
  3. Write the previous `command` verbatim as the body of `chain.sh` (empty if none).
  4. Write `statusline.sh`, which captures stdin and pipes it to `/bin/sh chain.sh`; a capture failure must never break the chained output.
  5. Set `statusLine.command` to the single-quoted absolute path of `statusline.sh`.
- Detection: the wrapper is installed if and only if `statusLine.command` exactly equals the wrapper command. Anything else counts as not installed. Project-level settings overrides are not checked; this is a known limitation.
- Uninstall restores `previous-statusline.json`, or removes the `statusLine` key if there was none. It does so only while the command is still the wrapper's. Either way, it deletes the app's wrapper files.
- Writing `settings.json`:
  - Parse it with `JSONSerialization` and change only `statusLine`.
  - Write it back atomically (`prettyPrinted`, `withoutEscapingSlashes`).
  - If parsing fails, abort with an error and never write.
  - Losing key order and formatting is acceptable.

### Processes

- List the pids from `~/.claude/sessions/*.json`. Validate each pid with `proc_pidpath` containing `/claude/versions/`, and drop the rest.
- Per pid, libproc supplies:
  - `PROC_PIDTASKINFO`: RSS and CPU time, converted from Mach ticks with `mach_timebase_info`
  - `PROC_PIDTBSDINFO`: start time, used for uptime
  - `PROC_PIDVNODEPATHINFO`: cwd
- CPU % is the delta between two samples. It is nil until the second sample.
- Stop sends `kill(pid, SIGTERM)`.

### Git

- The repo list is the distinct cwds from the record cache (the latest record is the last activity), plus the cwds of running Sessions (counted as active now). Keep the last 14 days, newest first, at most 15.
- Map each cwd to its repo with `git -C <cwd> rev-parse --show-toplevel`, cached per cwd for the app's lifetime:
  - Subdirectories collapse into their repo.
  - A worktree is its own row, labelled with its name.
  - Non-git, deleted, `/tmp` and `/private/tmp` cwds are dropped.
- The scan runs, per repo:
  - `git status --porcelain=v2 --branch`, for branch, ahead/behind and dirty count
  - `git log -1 --format=%s%x00%ct`, for subject and age
- Scan limits: at most 4 repos at once and a 3 s timeout per repo; a timed-out row reads "timed out". `GIT_OPTIONAL_LOCKS=0` is always set. The app never fetches, and a branch with no upstream has no ahead/behind.
- If the `git` binary is missing, the tab shows a distinct "git not found" state.

### Refresh cadence

- One always-on FSEvents stream with 2 s latency watches `~/.claude/projects` and the app's Application Support directory. A changed log runs an incremental parse. A capture-file change re-reads Plan limits and evaluates notifications. The stream watches the directory, not the file, because the wrapper replaces the file with `mv`.
- Processes: sampled every 2 s, only while the popover is open on that tab.
- Git: scanned when the tab is shown, then every 15 s while it stays visible.
- Wrapper detection: at launch and on every popover open.
- Prices: fetched at launch and every 24 h. "Update now" restarts the 24 h timer.
- Midnight: a one-shot timer at the next local midnight, re-armed on `NSCalendarDayChanged` and on wake from sleep.
- While the popover is open, a 1-minute timer refreshes age labels and the zeroing of reset windows. Closing the popover stops every popover timer.

### UI

- The popover is about 380 pt wide. Top to bottom:
  1. The Plan-limits rings header, with an age line underneath.
  2. Segmented tabs: Usage, Processes, Git.
  3. A footer with the gear.
- Each empty or failed state replaces only its own area.
- Settings is one grouped `Form` with four sections:
  - **General**: Launch at login via `SMAppService.mainApp`, its status read live and never stored, with registration errors shown inline. Billing-cycle start day.
  - **Notifications**: enable toggle (default on), warning/critical 80/95.
  - **Statusline**: state plus Install/Uninstall.
  - **Prices**: table age plus "Update now", with a spinner and an inline error.
- `@AppStorage` holds the Billing-cycle start day, the thresholds and the notification toggle.
- These values are constants in code: 14 days and 15 repos for Git, 62 days of history, the poll intervals, 24 h for prices, and the title banding.

## Testing Decisions

- **One seam: the public API of `UsageCore`**, confirmed with the user. Tests inject only the real boundaries:
  - **Root directories**: temp dirs filled with real fixture files (`.jsonl` logs, `sessions/*.json`, `settings.json`, capture files, price JSON).
  - **The clock and calendar**: for Today, midnight, Billing-cycle and `resets_at` behaviour.
  - **The price-table fetcher**: returns data, or fails.
- No mocks of `UsageCore`'s own collaborators. Git is tested with the real `git` binary in temp repos, including a worktree, an upstream for ahead/behind, and a dirty file. Processes are tested with a real child process: a session file points at its pid, the process is listed, stopped, and seen gone.
- A good test asserts observable output: totals, records, formatted strings, the Plan-limits state, whether a notification fires, the contents of `settings.json` and the wrapper files. Expected values are hardcoded literals worked out by hand from the fixtures, never recomputed with production formulas.
- Tests use Swift Testing (`import Testing`) and run with `swift test`.
- Modules and behaviours to cover:
  - **Log parsing and cache**:
    - split and partial lines dedupe to the largest total
    - sub-agent files are included
    - advisor iterations are priced at their own model
    - `<synthetic>` lines are skipped
    - an append reads only the new bytes
    - a half line waits for the next pass
    - a truncated or replaced (new inode) file is reparsed
    - a deleted file keeps its records
    - the 62-day cutoff skips files and prunes records
    - a schema bump forces a rescan
    - a cache round-trip across a simulated relaunch reads nothing new
  - **Pricing**:
    - exact and `anthropic/`-prefixed lookup
    - unknown and fast models are unpriced and counted
    - web search costs $0.01
    - a fetched table takes precedence over the bundled one
    - a failed fetch keeps the current table
  - **Aggregation**:
    - Billing-cycle start, including the clamp on the 31st in February
    - Today across local midnight
    - the last-hour per-minute buckets
    - the 14-day series
    - the per-model table
  - **Formatting**: `<$0.01`, `$0.00`, grouping under a non-US locale, and compact banding edges ($99.995, $999.60, $1,000, large values).
  - **Plan limits**:
    - each of the four states, including a malformed file
    - 0% past `resets_at`
    - notification fires once per threshold per window
    - re-arming when `resets_at` changes
    - no firing on stale or reset data
    - ring colour by threshold
  - **Statusline install and uninstall**:
    - install with no previous statusline, and with a claude-hud-style nested-quote command
    - the wrapper's capture filter, run against real stdin with `/bin/sh`
    - chaining keeps the previous command's output intact
    - capture failure still chains
    - detection when another tool overwrote the command
    - uninstall restores the full previous object
    - uninstall leaves a user-changed command alone
    - an unparseable `settings.json` is never written
  - **Processes**:
    - a session file whose pid is not a Claude Code binary is dropped
    - CPU is nil on the first sample
    - stop terminates the process
  - **Git**:
    - subdirectory collapse
    - a worktree as its own row
    - non-git, deleted and `/tmp` cwds dropped
    - the 14-day and 15-repo caps with ordering
    - ahead/behind, and none without an upstream
    - the "timed out" row
    - the "git not found" state
- The SwiftUI layer has no automated tests. It is checked by hand by running the bundled app, using the prototype's states as the checklist. The CPU and wake-up budgets are checked by hand in Activity Monitor.
- Prior art: none in the repo yet (greenfield). The throwaway prototype in `prototypes/menubar-popover-PROTOTYPE/` is the UI reference, not test prior art.

## Out of Scope

- Codex, Gemini CLI or any agent other than Claude Code.
- Distribution, Developer ID signing, notarization and auto-update. The app is ad-hoc signed for personal use.
- Processes that are not Claude Code in the Processes tab.
- The OAuth usage endpoint and any Keychain access for Plan limits.
- Usage history beyond 62 days, and viewing past Billing cycles.
- models.dev or any second price source.
- Checking project-level `.claude/settings*.json` statusline overrides.
- `git fetch`, a git refresh button and per-repo file watching.
- Configurable repo caps, history length, poll intervals or title banding.
- A polling fallback for FSEvents, unless events are measured to go missing.

## Further Notes

- The log and session-file formats are undocumented. Parse them defensively: skip unknown or malformed lines, and never crash.
- Measured scale on this machine: 2.3 GB across about 2,645 files, about 126k usage lines, about 60k responses after dedupe. A raw grep takes about 15 s, a useful yardstick for the cold scan.
- Research behind these decisions: `research/plan-limits-data-source.md`, `research/claude-code-log-format-and-pricing.md`, `research/detect-claude-code-processes.md`.
- Next step: `/to-tickets` on this spec.
