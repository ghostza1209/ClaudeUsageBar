# 20: Plan-limits rings header

**What to build:** The popover header shows two rings, the 5-hour window and the Weekly window, with percent used, reset time and an "updated X min ago" age line (orange when stale), coloured accent / orange at warning / red at critical (thresholds from `@AppStorage`, default 80/95). Plan limits are read from the capture file, refreshed through the FSEvents stream. Each failure state replaces only the header with a distinct one-line message.

**Blocked by:** 16, 19

**Status:** resolved

Spec: [spec.md](../spec.md)

- [x] Plan-limits state: not installed / no data yet / unreadable (short error) / ok (both windows with percent, reset, captured-at = file mtime)
- [x] A window past its `resets_at` reads 0% for display
- [x] Ring colour by threshold is computed in `UsageCore` from passed-in thresholds
- [x] Title shows ⚠ when Plan limits are unreadable (in addition to not installed)
- [x] While the popover is open, a 1-minute timer refreshes age labels and reset zeroing; it stops on close
- [x] Tests cover each state including a malformed file, and the reset zeroing with an injected clock

## Comments

- Code: `UsageCore/PlanLimits.swift` (`readPlanLimits(supportDir:wrapperInstalled:)`, `PlanLimits`, `LimitWindow.displayPercent(now:)`, `limitLevel`, `isStale`, `ageText`, `resetText`, `PlanLimits.warnsInTitle`); `ClaudeUsageBar/PlanLimitsHeader.swift` (header view); `Usage.planLimits` / `Usage.now` in the app.
- **Decisions.** A window missing from `rate_limits` (or null) is nil inside `.ok` and its ring shows `—` / "no data"; both missing, `rate_limits` absent/null/`{}`, or no capture file is `noData`. A present window without numeric `used_percentage` and `resets_at`, invalid JSON, a non-object root or `rate_limits`, or an unreadable file is `unreadable(reason)`. Percent is clamped to 0...100. `readPlanLimits` takes no clock: zeroing is `displayPercent(now:)`, applied by the view.
- **Stale = capture older than 10 min** (`planLimitsStaleAfter`); the age line turns orange. Ring level compares the raw (unrounded) percent, so 79.6 shows "80%" in the normal colour.
- **Reset text**: 5-hour `resets in 2h 14m` / `resets in <1m`; Weekly `resets Fri 08:00` (24 h, local zone, en_US); `reset passed` once `resets_at` is behind `now`.
- **`@AppStorage` keys** (Int percent, defaults 80/95): `Usage.warningThresholdKey = "warningThreshold"`, `Usage.criticalThresholdKey = "criticalThreshold"`. Ticket 24 edits them; ticket 21 reads them.
- **For ticket 21 (capture-fresh notion)**: a capture is fresh when `.ok`'s `capturedAt` differs from the last evaluated one and `!isStale(capturedAt:now:)`. `Usage.refreshPlanLimits()` is the single place the file is re-read (FSEvents batch touching the support dir, popover open, install click); hook notifications there when `latest != planLimits`. Use `displayPercent(now:)` / `resetsAt` changes for re-arming.
- **Re-render avoidance**: `Usage.appSupportChanged` (ticket 16's hook) was removed; the support-dir event now calls `refreshPlanLimits()` directly, which re-reads the small file and assigns `planLimits` only when it differs, so this app's own cache writes re-render nothing. The read is on the main thread (a ~1 KB file).
- Title ⚠ now follows `PlanLimits.warnsInTitle` (not installed or unreadable) instead of `!wrapperInstalled`; `wrapperInstalled` is private to `Usage`.
- 1-minute timer: created in the `popoverOpen` didSet only while open, invalidated on close; each tick sets `Usage.now`, which the header renders against. `now` is also set on open.
- Verification: unit tests (57 total pass). Sanity-broke `>=` to `>` and removal of zeroing in `displayPercent`, and both threshold comparisons: tests went red. The popover cannot be reached by AX or screenshot here (as in ticket 19), so the header was rendered with `ImageRenderer` (temporary test, not committed) over fixture capture files in a sandbox dir through the real `Usage` read path: ok, critical (96%), stale (orange age), past reset (0%), one window missing, no data, unreadable, not installed. The title read ⚠ for unreadable and not installed only. Timer start/stop and live FSEvents refresh were not observed in a running popover.
