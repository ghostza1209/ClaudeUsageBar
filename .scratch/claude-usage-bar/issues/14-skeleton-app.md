# 14: Skeleton menu bar app

**What to build:** The Swift Package exists with a `UsageCore` library (no UI) and a `ClaudeUsageBar` SwiftUI executable, per ADR 0001. `scripts/bundle.sh` builds release, assembles an ad-hoc signed `.app` (`LSUIElement`, `CFBundleIdentifier`) and opens it. The app shows a menu bar icon; clicking it opens a ~380 pt popover with a placeholder Plan-limits header, segmented Usage / Processes / Git tabs with placeholder content, and a footer gear that opens an empty `Settings` scene in front. `swift test` runs Swift Testing against `UsageCore`.

**Blocked by:** None (can start immediately)

**Status:** resolved

Spec: [spec.md](../spec.md)

- [x] Package has `UsageCore` and `ClaudeUsageBar` targets, macOS 27+, no third-party dependencies
- [x] `scripts/bundle.sh` produces and opens a signed `.app`; `swift run` is not the supported path
- [x] Menu bar icon opens the popover with header placeholder, three tabs and a gear footer
- [x] Gear opens the Settings window in front
- [x] `swift test` passes with at least one real `UsageCore` test (e.g. the first piece needed by ticket 15 is fine to defer; a smoke-level test that asserts real behaviour)

## Comments

- Platform is `.macOS(.v27)`, which needs `swift-tools-version: 6.4`.
- The real `UsageCore` test covers the compact currency formatter from the spec (`compactCurrency`), including the $99.995, $999.60 and $1,000 band edges and output under a `de_DE` process locale. The full formatter (`<$0.01`) is left for ticket 15.
- Gear uses `SettingsLink` plus `NSApp.activate()`. Checked by hand: the Settings window opens on top of other windows. macOS cooperative activation may not make the app frontmost when another app holds focus.
- The `.app` is built at `.build/ClaudeUsageBar.app`.
