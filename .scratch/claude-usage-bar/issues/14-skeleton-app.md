# 14: Skeleton menu bar app

**What to build:** The Swift Package exists with a `UsageCore` library (no UI) and a `ClaudeUsageBar` SwiftUI executable, per ADR 0001. `scripts/bundle.sh` builds release, assembles an ad-hoc signed `.app` (`LSUIElement`, `CFBundleIdentifier`) and opens it. The app shows a menu bar icon; clicking it opens a ~380 pt popover with a placeholder Plan-limits header, segmented Usage / Processes / Git tabs with placeholder content, and a footer gear that opens an empty `Settings` scene in front. `swift test` runs Swift Testing against `UsageCore`.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

Spec: [spec.md](../spec.md)

- [ ] Package has `UsageCore` and `ClaudeUsageBar` targets, macOS 27+, no third-party dependencies
- [ ] `scripts/bundle.sh` produces and opens a signed `.app`; `swift run` is not the supported path
- [ ] Menu bar icon opens the popover with header placeholder, three tabs and a gear footer
- [ ] Gear opens the Settings window in front
- [ ] `swift test` passes with at least one real `UsageCore` test (e.g. the first piece needed by ticket 15 is fine to defer; a smoke-level test that asserts real behaviour)
