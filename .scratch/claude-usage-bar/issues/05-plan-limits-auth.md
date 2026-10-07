# How should the app authenticate to read Plan limits?

Type: grilling
Status: resolved
Blocked by: 01

## Question

Given the options found for reading Plan limits, which credential approach does the app use (reuse Claude Code's existing credential, a pasted session cookie, a separate login, …), how is it stored, and what happens when it expires or the source breaks?

## Answer

No authentication. Plan limits come only from Claude Code's statusline stdin `rate_limits`; the app never reads the Keychain or calls an Anthropic endpoint. The OAuth usage fallback is out of scope (Keychain ACL prompts, 429 handling, two response shapes and ToS grey area, all to cover only usage from claude.ai web/desktop while Claude Code is idle).

- **Capture**: the statusline wrapper writes the raw `rate_limits` object plus a captured-at timestamp to one shared file, atomically (temp file + `mv`). Concurrent sessions all write the same file; last write wins (same account, so no per-session split). The app does all parsing, so a format change never needs a wrapper change.
- **Staleness**: every Plan-limits value shows its age ("updated X min ago"). A window past its `resets_at` is shown as 0% used without waiting for fresh data.
- **Notifications**: fire only on fresh data that crosses a threshold; once per window per threshold, re-armed when that window's `resets_at` changes.
- **Empty and broken states**, distinct in the UI: wrapper not installed; no data yet (no `rate_limits`: not Pro/Max, or no API response in the session yet; prompt to run Claude Code); unreadable data (short error, never crash).


## Comments

- Amended by [How is the statusline wrapper installed and removed?](07-install-statusline-wrapper.md): the capture file holds all of stdin (not just `rate_limits`), is written only when stdin contains `rate_limits`, and its mtime is the captured-at time.
