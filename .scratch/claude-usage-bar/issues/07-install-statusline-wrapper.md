# How is the statusline wrapper installed and removed?

Type: grilling
Status: resolved

## Question

Who edits `statusLine` in `~/.claude/settings.json` to point at the wrapper (the app on first launch, a button in Settings, a manual step), where the previous statusline command is kept so the wrapper can chain to it and restore it, how the app detects that the wrapper is installed or was overwritten (e.g. by claude-hud's own setup), and where the wrapper script and its capture file live?

## Answer

The user installs the wrapper with a button, and the app never edits Claude Code's config without that click.

- **Who installs**: an "Install" button sits in the Plan-limits header's "wrapper not installed" state, and another in Settings. Nothing happens automatically on first launch.
- **Files**: all live in `~/Library/Application Support/ClaudeUsageBar/`:
  - `statusline.sh`: the wrapper.
  - `chain.sh`: the previous `statusLine.command` string, written verbatim as the script body. The wrapper pipes stdin into `/bin/sh chain.sh`, so the existing command (claude-hud's nested-quote `bash -c '…'`) never needs escaping. The file is empty if there was no previous statusline.
  - `previous-statusline.json`: the whole previous `statusLine` object (including `padding` etc.), or a marker that there was none. Used only for restore.
  - `statusline-input.json`: the capture file.
- **Settings entry**: `statusLine.command` becomes the single-quoted absolute path to `statusline.sh`, quoted because the path contains a space.
- **Capture**: the wrapper writes all of stdin (temp file + `mv`), but only when it contains `"rate_limits"` (`grep -q`). Sessions without it (before the first API response, API-key sessions) then never wipe good data under last-write-wins. Captured-at is the file's mtime, not an added field. This amends [How should the app authenticate to read Plan limits?](05-plan-limits-auth.md). A capture failure must never break the chained statusline output.
- **Detection**: on launch and every time the popover opens, the app reads `statusLine.command` from `~/.claude/settings.json`. If it exactly equals the wrapper command, the state is installed. Anything else counts as not installed and shows the Install button again; reinstalling captures whatever is current (e.g. a newer claude-hud command) as the new chain. Project-level `.claude/settings*.json` overrides are not checked; this is a known limitation.
- **Uninstall**: a button in Settings. It restores `previous-statusline.json` (or removes the `statusLine` key if there was none) only while `command` is still the wrapper's. If the user has changed it since, settings are left untouched. Either way the app deletes its own wrapper files. Deleting the app alone leaves the wrapper working.
- **Writing settings.json**: parse with `JSONSerialization`, change only `statusLine`, write back atomically (`prettyPrinted`, `withoutEscapingSlashes`). If parsing fails, abort with an error and never overwrite. Losing key order and formatting is acceptable, because Claude Code's own `/config` rewrites the file too.
