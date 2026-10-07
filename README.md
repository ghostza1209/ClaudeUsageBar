# Claude Usage Bar

A macOS menu bar app for Claude Code: Plan limits (5-hour and Weekly) as a mini gauge in the menu bar, and a popover with Usage (API list estimate in $), running Processes and Git status of the repos Claude Code worked in.

Requires macOS 27 or later. Everything runs locally; the only network call is the price table fetch (every 24 h) from LiteLLM's public GitHub file.

## Install (from the zip)

1. Unzip and move `ClaudeUsageBar.app` to `/Applications`.
2. The app is ad-hoc signed, not notarized, so macOS blocks the first launch: right-click the app, choose **Open**, then **Open** again. (Or run `xattr -cr /Applications/ClaudeUsageBar.app` once.)
3. Click the menu bar icon, then **Settings**.

## Plan limits need one setup step

Claude Code only exposes your Plan limits to its statusline. In the popover, press **Install…** (or Settings › Statusline › Install). This points `statusLine.command` in `~/.claude/settings.json` at a small wrapper that saves the limits and then runs your previous statusline unchanged. **Uninstall** restores the previous setting. Without it the gauge shows `⚠`.

## Notes

- Dollar amounts are API list prices for your token usage, not what you pay on a Pro/Max plan.
- Reads `~/.claude/projects/**/*.jsonl` and `~/.claude/sessions/`. Nothing is sent anywhere.

## Build from source

```sh
sh scripts/bundle.sh     # build, sign, open
sh scripts/package.sh    # build and zip to dist/ClaudeUsageBar.zip
swift test
```
