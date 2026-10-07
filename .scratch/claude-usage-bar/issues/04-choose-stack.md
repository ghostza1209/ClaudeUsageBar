# Which stack should the app be built with?

Type: grilling
Status: resolved
Blocked by: 01, 02, 03

## Question

Native SwiftUI (`MenuBarExtra`, Swift Charts) or Tauri (or another option), given the needs surfaced by the three research tickets: reading logs fast, process inspection and kill, git status across repos, Keychain/credential access for Plan limits, notifications, charts, and a light resident footprint?

## Answer

The app is native SwiftUI, targets macOS 27+, and is non-sandboxed.

- **Project:** a Swift Package only, with no Xcode project and two targets: `UsageCore` (library with no UI: log parsing, pricing, processes, git, Plan limits) and `ClaudeUsageBar` (SwiftUI executable using `MenuBarExtra(.window)` and Swift Charts).
- **Build and run:** `scripts/bundle.sh` builds release, assembles the `.app` (`Info.plist` with `LSUIElement` and `CFBundleIdentifier`), ad-hoc signs it and opens it. Use it for development and installs alike, because `UNUserNotificationCenter` needs a bundle. See [ADR 0001](../../../docs/adr/0001-swiftpm-only-with-bundle-script.md).
- **Dependencies:** no third-party packages. Apple frameworks only: Swift Charts, Security (Keychain), UserNotifications, libproc via `Darwin`, `Process`, `JSONDecoder`.
- **Background work:** runs in-process with Swift concurrency (actors or background Tasks). No daemon or LaunchAgent.
- **Git:** shells out to the system `git` (`git status --porcelain=v2 --branch` and `git log -1`). No libgit2.
- **Statusline wrapper:** a `/bin/sh` script. It writes stdin to a temp file, `mv`s it into place so the write is atomic, then pipes stdin on to the existing statusline. The app parses `rate_limits` from that file.
- **Tests:** Swift Testing (`import Testing`) against `UsageCore`.
