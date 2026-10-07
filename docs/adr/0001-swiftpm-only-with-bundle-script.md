# Swift Package only, with a script that assembles the .app

The app is a SwiftUI menu bar app, but it is built from a Swift Package with no Xcode project. A `UsageCore` library target holds the logic and has no UI; a `ClaudeUsageBar` executable target holds the SwiftUI layer. We chose this so the project is plain text, works cleanly with git (no `.pbxproj`), and is easy to test with `swift test`. SwiftPM cannot produce an `.app` bundle, and `UNUserNotificationCenter` crashes without one, so `scripts/bundle.sh` does it: it runs `swift build -c release`, writes `Contents/{MacOS,Info.plist}` (`LSUIElement`, `CFBundleIdentifier`), ad-hoc signs with `codesign -s -` and opens the app. That script is the only way to run the app, in development as well as for installs; `swift run` is not supported.

## Considered Options

- Plain Xcode project: produces the bundle natively, but its `.pbxproj` is opaque and diff-hostile.
- XcodeGen or Tuist: fixes the `.pbxproj` problem but adds a tool for a one-person project.
