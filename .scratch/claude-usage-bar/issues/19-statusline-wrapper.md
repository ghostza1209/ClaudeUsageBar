# 19: Statusline wrapper install and uninstall

**What to build:** The user can install the statusline wrapper with a button in the Plan-limits header's "wrapper not installed" state. Install keeps the existing statusline working by chaining to it verbatim; the wrapper captures stdin to `statusline-input.json` only when it contains `rate_limits`. The app detects the installed state at launch and on every popover open, and shows a trailing ⚠ in the title when not installed. `UsageCore` exposes uninstall (Settings button arrives in ticket 24).

**Blocked by:** 14

**Status:** resolved

Spec: [spec.md](../spec.md)

- [x] Files in Application Support: `statusline.sh`, `chain.sh` (previous command verbatim, empty if none), `previous-statusline.json` (whole previous object or a none-marker), `statusline-input.json`
- [x] `statusLine.command` becomes the single-quoted absolute path to `statusline.sh`
- [x] Wrapper (`/bin/sh`): captures via temp file + `mv` only when stdin contains `"rate_limits"`; always pipes stdin to `/bin/sh chain.sh`; capture failure never breaks chained output
- [x] Installed iff `statusLine.command` exactly equals the wrapper command
- [x] Uninstall restores the previous object (or removes the key) only while the command is still ours; always deletes the app's wrapper files
- [x] settings.json edited via `JSONSerialization`, only `statusLine` touched, atomic write (`prettyPrinted`, `withoutEscapingSlashes`); unparseable file → error, never written
- [x] Tests run the real wrapper with `/bin/sh` against stdin, incl. a claude-hud-style nested-quote command

## Comments

- Wrapper: `UsageCore/StatuslineWrapper.swift` (`install()`, `uninstall()`, `isInstalled()`, `command`, `captureURL`, `captureFileName` for ticket 20). The capture filter is a POSIX `case` on the stdin held in a shell variable, not `grep -q`: same behaviour, no fork, and stdin is always fully consumed even when the support dir is unwritable (a temp-file-first design would leave chain.sh without input). Stdin is re-emitted with a single trailing newline.
- `install()` while already installed is a no-op (chaining to itself would loop). It parses settings.json first, so an unparseable file throws before any wrapper file is written. A missing settings.json is created containing only `statusLine`. The new `statusLine` is the previous object with `command` replaced (so `padding` etc. stay) and `type: "command"` set. `previous-statusline.json` holds the previous value, or the literal `null` for none.
- `uninstall()` with an unparseable settings.json throws and deletes nothing (deleting the files while settings still point at them would break the statusline). A symlinked settings.json is written through the link.
- Title: `titleWithWarning(_:warning:)` in `Pricing.swift`; the ⚠ shows during the launch scan too (alone beside the icon) and trails the title as `$18.42 ⚠`. Ticket 20 adds unreadable Plan limits to the same `warning` input.
- Popover header: "Wrapper not installed" + `Install…` button with an inline red error; detection runs at launch and on each popover open. The installed state shows the existing "No Plan limits yet." placeholder until ticket 20.
- For manual runs the app honours `CLAUDE_USAGE_BAR_SANDBOX=<dir>` (home = `<dir>/.claude`, support = `<dir>/support`) so nothing touches the real settings. Not documented elsewhere.
- Deferred: the Settings buttons (ticket 24), capture parsing and rings (ticket 20). The popover's not-installed rendering was not visually inspected (screenshots/AX could not reach the popover in this environment); the title ⚠ was read from the menu bar item.
