<p align="center">
  <img src="docs/images/logo.svg" width="128" alt="Claude Usage Bar logo">
</p>

<h1 align="center">Claude Usage Bar</h1>

<p align="center">
  Your Claude Code limits and spend, one glance away in the macOS menu bar.
</p>

<p align="center">
  <img alt="version 1.0.0" src="https://img.shields.io/badge/version-1.0.0-D97757">
  <img alt="macOS 27+" src="https://img.shields.io/badge/macOS-27%2B-lightgrey">
  <img alt="Apple silicon and Intel" src="https://img.shields.io/badge/arch-arm64%20%7C%20x86__64-lightgrey">
  <img alt="Swift Package" src="https://img.shields.io/badge/built%20with-SwiftUI-F05138">
</p>

<p align="center">
  <img src="docs/images/screenshot.png" width="360" alt="Claude Usage Bar popover showing the 5-hour and Weekly limits, billing cycle cost and a 14-day chart">
</p>

## What you get

- **Plan limits in the menu bar.** A mini gauge for your 5-hour or Weekly window, in Claude Code orange (or any colour you pick), plus the time until it resets. Optional notifications as you approach a limit.
- **Usage.** Cost for the billing cycle and today, a token breakdown (input, output, cache read, cache write), a tokens-per-minute chart for the last hour and a 14-day cost chart.
- **Processes.** Every running Claude Code session with its CPU, memory and uptime, and a button to stop it.
- **Git.** Status of the repos Claude Code has been working in, at a glance.

Everything runs on your Mac. The only network call is the price table, fetched every 24 hours from LiteLLM's public file on GitHub.

## Install

Download `ClaudeUsageBar.zip` from the [Releases](https://github.com/ghostza1209/ClaudeUsageBar/releases) page. Requires macOS 27 or later; the build is universal (Apple silicon and Intel).

1. Unzip and move `ClaudeUsageBar.app` to `/Applications`.
2. The app is ad-hoc signed, not notarized, so macOS blocks the first launch. Either right-click the app, choose **Open**, then **Open** again; or, if that is not offered, open System Settings › Privacy & Security and press **Open Anyway**; or run `xattr -cr /Applications/ClaudeUsageBar.app` once.
3. Click the menu bar icon, then **Settings**.

## One setup step for Plan limits

Claude Code only exposes your 5-hour and Weekly limits to its statusline. In the popover, press **Install…** (or Settings › Statusline › Install). This points `statusLine.command` in `~/.claude/settings.json` at a small wrapper that saves the limits and then runs your previous statusline unchanged. **Uninstall** restores the previous setting. Without it the gauge shows `⚠`.

## About the numbers

| Number | Where it comes from | How far to trust it |
|---|---|---|
| 5-hour / Weekly % | Claude Code's own `rate_limits`, as reported by Anthropic | The official figure. It refreshes whenever Claude Code runs its statusline, and turns orange when it is over 10 minutes old. |
| Dollar amounts | Your token counts × API list prices | An **estimate**, not what you pay on a Pro/Max plan. Cross-checked against [ccusage](https://github.com/ryoppippi/ccusage) to within about 0.1%; both use the same LiteLLM prices. |
| Tokens | `~/.claude/projects/**/*.jsonl` on this Mac | Cache reads dominate the total, so it reads much larger than the tokens you "typed". Other machines and claude.ai are not counted. |

Models with no known price (and `fast` speed responses) count as $0, so the estimate can run low; the model table flags them.

## Privacy

It reads `~/.claude/projects/**/*.jsonl` and `~/.claude/sessions/`, and nothing is sent anywhere.

## Build from source

```sh
sh scripts/bundle.sh     # build, sign, open
sh scripts/package.sh    # universal build, zipped to dist/ClaudeUsageBar.zip
swift test
```

The app is a Swift Package with no Xcode project; see [the ADR](docs/adr/0001-swiftpm-only-with-bundle-script.md) for why. Domain terms (Plan limits, API list estimate, Billing cycle) are defined in [GLOSSARY.md](GLOSSARY.md).
