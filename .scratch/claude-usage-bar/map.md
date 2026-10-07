# Map: Claude usage menu bar app

Label: wayfinder:map

## Destination

A build-ready spec for a personal macOS menu bar app (modelled on TermTracker) with three tabs — Usage, Processes, Git — plus Plan limits, with data sources, stack and UI decided, ready to hand to `/to-tickets`.

## Notes

- Domain: macOS menu bar app; data comes from Claude Code only (local logs, running processes, the repos it touches, Plan limits). Vocabulary in `GLOSSARY.md`.
- Reference UI: TermTracker Usage tab screenshot (cumulative totals per Billing cycle with token breakdown and API list estimate; Today; last-hour tokens/min sparkline; 14-day trend; per-model breakdown).
- Settled in charting: menu bar title = icon + today's API list estimate ($); Processes = running Claude Code sessions only (project/cwd, CPU/RAM, uptime, kill); Git = repos Claude Code recently worked in (branch, dirty count, ahead/behind, last commit); macOS notifications at configurable Plan-limit thresholds (default 80% / 95%); cumulative totals count from a configurable Billing-cycle start day.
- Personal use first: no notarization or distribution work.
- Grilling tickets: call `grilling` + `domain-modeling`.

## Decisions so far

- [How can running Claude Code sessions be detected on macOS?](issues/03-detect-claude-code-processes.md): `~/.claude/sessions/<pid>.json` maps pid to sessionId and cwd; libproc gives CPU, RSS, uptime and cwd; stop with `kill(SIGTERM)`; App Sandbox blocks `~/.claude` reads and `kill`, so the app must be non-sandboxed and ship outside the Mac App Store.
- [How can the app read Plan limits?](issues/01-plan-limits-data-source.md): primary source is Claude Code's official statusline stdin `rate_limits` (5h/7d `used_percentage` plus epoch `resets_at`), captured by a statusline wrapper that writes it to a file and chains to the existing statusline; the undocumented `api.anthropic.com/api/oauth/usage` using the Keychain `Claude Code-credentials` token is an optional opt-in fallback (read-only, never refresh, ToS grey area); cookie and PTY-scraping approaches are rejected.
- [What do Claude Code logs contain, and where do API prices come from?](issues/02-claude-code-log-format-and-pricing.md): per-response usage (input/output/cache read/5m+1h cache write, model, sessionId, cwd, timestamp) is in `assistant` lines of `~/.claude/projects/**/*.jsonl` incl. `subagents/`; dedupe globally on `(message.id, requestId)` keeping the largest total (lines are split and streamed partials), price advisor iterations separately; prices from LiteLLM's `model_prices_and_context_window.json` (matches Anthropic's pricing page), models.dev as fallback.
- [Which stack should the app be built with?](issues/04-choose-stack.md): native SwiftUI on macOS 27+, a Swift Package with no Xcode project (`UsageCore` library plus `ClaudeUsageBar` app) bundled by `scripts/bundle.sh` ([ADR 0001](../../docs/adr/0001-swiftpm-only-with-bundle-script.md)); no third-party dependencies, work runs in-process with Swift concurrency, git through the `git` command, a `/bin/sh` statusline wrapper, Swift Testing.

- [How should the app authenticate to read Plan limits?](issues/05-plan-limits-auth.md): it doesn't; statusline `rate_limits` only, written raw and atomically to one shared file (last write wins), parsed by the app; values show their age, a window past `resets_at` reads 0%, notifications fire once per window per threshold on fresh data only; distinct not-installed / no-data / unreadable states.

- [What should the menu bar title and popover look like?](issues/06-menu-bar-and-popover-layout.md): tabbed popover (Usage / Processes / Git) under a Plan-limits header of two rings (5-hour / Weekly, threshold-coloured, with age); TermTracker-order Usage tab; each empty or failed source replaces only its own area with a distinct message.
- [How is the statusline wrapper installed and removed?](issues/07-install-statusline-wrapper.md): Install/Uninstall buttons only (no silent edits); wrapper, verbatim `chain.sh` of the previous command, backup of the old `statusLine` and capture file live in `~/Library/Application Support/ClaudeUsageBar/`; capture only stdin containing `rate_limits` (mtime = captured-at); installed iff `statusLine.command` exactly matches; uninstall restores only if still ours.
- [How does the app parse GBs of logs without rescanning them?](issues/08-incremental-log-parsing.md): keep 62 days (skip files by mtime, prune older records); per-file inode/size/offset, append-only reads to the last newline, reparse on rewrite, keep records of deleted files; one atomic Codable JSON cache of per-response records keyed by `(message.id, requestId)` with no prices (priced at display, invalidated only by schema version); cold scan in background newest-first with partial totals and progress, title icon-only until done.
- [Which repos does the Git tab show, and how are they scanned cheaply?](issues/09-git-repo-scanning.md): cwds from the log cache plus running sessions, active in the last 14 days, max 15, newest first; `rev-parse --show-toplevel` cached per cwd, worktrees as own rows, non-git/deleted/`/tmp` cwds dropped; `git status --porcelain=v2 --branch` + `git log -1`, 4 concurrent, 3 s timeout, `GIT_OPTIONAL_LOCKS=0`; never fetch.
- [How does the API price table stay current?](issues/10-price-table-updates.md): bundled Claude-only LiteLLM snapshot plus fetch at launch and every 24 h cached in Application Support; exact id (then `anthropic/` prefix) lookup; unknown and fast-mode models are unpriced (tokens counted, $ excluded, popover marker); web search $0.01/request; table age shown only when >7 days old, always in Settings.
- [How is the dollar amount formatted?](issues/11-currency-formatting.md): always `$` in en_US format regardless of locale; popover 2 decimals with grouping, `<$0.01` for tiny non-zero; title compact (`$18.42` < $100, `$123` < $1,000, `$1.2k` above, banded on the rounded value); trend axis uses the same compact formatter.
- [When does each data source refresh?](issues/12-refresh-cadence.md): one always-on FSEvents stream (2 s latency) over `~/.claude/projects` and the app's Application Support dir drives log parsing and Plan-limit notifications; Processes (2 s) and Git (15 s) poll only while their tab is visible; a midnight one-shot (re-armed on day change and wake) plus a 1-minute timer while open; closed + idle = 0% CPU, streaming < 1%.
- [What does the Settings screen contain?](issues/13-settings-screen.md): popover gear opens the SwiftUI `Settings` scene (⌘, while open); one grouped Form with four sections: General (launch at login via `SMAppService` status, Billing-cycle start day 1–31 clamped to month end), Notifications (toggle plus warning/critical 80/95, 50–100 step 5, also drive ring colours), Statusline (Install/Uninstall), Prices (table age plus "Update now" with inline error); `@AppStorage` for user values, everything else stays constant.

## Not yet specified

- (nothing left: all fog graduated into tickets)

## Out of scope

- Codex, Gemini CLI or other agent sources (Claude Code only for now).
- Distribution, signing, notarization, auto-update.
- Non-Claude-Code processes in the Processes tab.
- OAuth usage endpoint fallback via the Keychain token ([How should the app authenticate to read Plan limits?](issues/05-plan-limits-auth.md)): Keychain prompts, 429 handling and ToS grey area outweigh fresher data while Claude Code is idle; revisit as a new effort if missed.
- Usage history beyond 62 days / past Billing cycles ([How does the app parse GBs of logs without rescanning them?](issues/08-incremental-log-parsing.md)): the UI only needs the current cycle and 14-day trend; keeping the cache bounded wins.
- models.dev as a second price source ([How does the API price table stay current?](issues/10-price-table-updates.md)): no 1h cache-write rate and LiteLLM covers every local model; the bundled snapshot is the fallback instead.
