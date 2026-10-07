# 19: Statusline wrapper install and uninstall

**What to build:** The user can install the statusline wrapper with a button in the Plan-limits header's "wrapper not installed" state. Install keeps the existing statusline working by chaining to it verbatim; the wrapper captures stdin to `statusline-input.json` only when it contains `rate_limits`. The app detects the installed state at launch and on every popover open, and shows a trailing ⚠ in the title when not installed. `UsageCore` exposes uninstall (Settings button arrives in ticket 24).

**Blocked by:** 14

**Status:** ready-for-agent

Spec: [spec.md](../spec.md)

- [ ] Files in Application Support: `statusline.sh`, `chain.sh` (previous command verbatim, empty if none), `previous-statusline.json` (whole previous object or a none-marker), `statusline-input.json`
- [ ] `statusLine.command` becomes the single-quoted absolute path to `statusline.sh`
- [ ] Wrapper (`/bin/sh`): captures via temp file + `mv` only when stdin contains `"rate_limits"`; always pipes stdin to `/bin/sh chain.sh`; capture failure never breaks chained output
- [ ] Installed iff `statusLine.command` exactly equals the wrapper command
- [ ] Uninstall restores the previous object (or removes the key) only while the command is still ours; always deletes the app's wrapper files
- [ ] settings.json edited via `JSONSerialization`, only `statusLine` touched, atomic write (`prettyPrinted`, `withoutEscapingSlashes`); unparseable file → error, never written
- [ ] Tests run the real wrapper with `/bin/sh` against stdin, incl. a claude-hud-style nested-quote command
