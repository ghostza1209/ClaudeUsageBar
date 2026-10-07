# 21: Plan-limit notifications

**What to build:** The app sends a macOS notification when fresh Plan-limits data crosses the warning or critical threshold for a window, at most once per threshold per window, re-armed when that window's `resets_at` changes. It works with the popover closed. Notification permission is requested on first launch.

**Blocked by:** 20

**Status:** resolved

Spec: [spec.md](../spec.md)

- [x] Notification decision lives in `UsageCore`: input previous state + new capture + thresholds + enabled flag → which notifications to fire
- [x] Fires only on fresh captures; never from stale or reset-zeroed values
- [x] Once per threshold per window; re-arms on `resets_at` change
- [x] Enabled flag and thresholds from `@AppStorage` (defaults on, 80/95)
- [x] Tests cover crossing, no duplicate, re-arm, disabled

## Comments

- Code: `UsageCore/PlanLimitNotifications.swift` (`planLimitNotifications(state:limits:now:warning:critical:enabled:)`, `NotificationState` (Codable), `LimitNotification`, `LimitWindowName`); `ClaudeUsageBar/Notifications.swift` (`NotificationPresenter`: authorization, `post`, delegate); hook in `Usage.refreshPlanLimits()` -> `notifyOnCrossing()`. `LimitLevel` became `Int`-raw, `Comparable`, `Codable`.
- **Rules.** Only an `.ok` capture whose `capturedAt` differs from `state.lastCapturedAt` is evaluated (it is then consumed even if stale, so it never becomes "fresh" later). Stale (`isStale`) fires nothing. A window with `now >= resets_at` is skipped (reset-zeroed value) and its state is left as is. Per window the highest announced level is stored with its `resets_at`; a different `resets_at` re-arms (resets to normal). Only a strictly higher level fires: a jump past both thresholds fires only critical and warning is consumed; dropping back and re-crossing does not repeat. Windows are independent.
- **Defensive thresholds**: `critical = max(critical, warning + 1)`. Ticket 24 still owns the UI validation (50-100, step 5, warning < critical).
- **Disabled**: nothing fires but the capture is still consumed, so turning notifications on later announces only crossings seen afterwards (enabling at 90% stays quiet until critical or the next reset).
- **Persistence**: `NotificationState` is stored as JSON in `<support dir>/notification-state.json` (not UserDefaults: it stays inside the sandbox dir during `CLAUDE_USAGE_BAR_SANDBOX` runs and `UsageCore` stays free of UserDefaults). Written only when the state changes. Persisted before posting, so a crash loses a notification rather than repeating it. The file lives in the FSEvents-watched dir; the echo re-reads an unchanged capture and does nothing.
- **@AppStorage keys for ticket 24**: `Usage.notificationsEnabledKey = "notificationsEnabled"` (Bool, default true), plus the existing `"warningThreshold"` (80) / `"criticalThreshold"` (95). `Usage` reads them from `UserDefaults.standard` at each evaluation (defaults when absent), so changes apply from the next capture. Ticket 24 should call `NotificationPresenter.requestAuthorization()` when the toggle turns on (the system prompts only once; the app also calls it on every launch).
- **Launch**: authorization is requested in `Usage.init`, and the capture already on disk is evaluated after it settles (the persisted state prevents repeats). A fresh-at-launch capture above a threshold that was never announced does notify.
- **Presentation**: a `UNUserNotificationCenterDelegate` returns `.banner, .sound` so a notification also shows while the popover is open (app active). Title `5-hour limit at 90%` / `Weekly limit at 97%`; body `Warning|Critical threshold reached; resets in 2h 14m` (Weekly: `resets Fri 08:00`). Identifier = window + level + `resets_at`.
- **Verification**: 70 tests pass (13 new). Sanity-broke once-per-window, re-arm, reset-zeroed guard, stale guard: each turned the matching tests red. Live: ad-hoc signed debug bundle with its own bundle id (`com.ysz.ClaudeUsageBar.sandboxtest`, so the real app's permission is untouched) run with `CLAUDE_USAGE_BAR_SANDBOX` and a fixture capture at 90%. Authorization could not be granted headlessly (`requestAuthorization` failed, no prompt reachable), so `add(request)` was reached (temporary logging, removed) with the expected title/body but returned `UNErrorDomain 1 "Notifications are not allowed"`; the state file recorded the fiveHour warning. A relaunch with the same capture did not call `add` again. A banner actually appearing was not observed; it needs the permission granted once in a normal session.
