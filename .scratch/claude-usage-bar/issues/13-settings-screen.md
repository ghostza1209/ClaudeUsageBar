# What does the Settings screen contain?

Type: grilling
Status: resolved
Blocked by: 09, 10, 11, 12

## Question

Which settings exist, their defaults and validation, and how Settings is opened (gear in the popover, `Settings` scene, ⌘,)? Known candidates: Billing-cycle start day, notification thresholds (default 80% / 95%), launch at login via `SMAppService`, statusline wrapper Install/Uninstall buttons, plus whatever the repo-scanning, price-table, currency and refresh-cadence decisions surface. Where are settings stored (`UserDefaults` / `@AppStorage`)?

## Answer

- **Opening**: a gear button in the popover footer opens the SwiftUI `Settings` scene via `SettingsLink`; ⌘, works while the popover is open. The app calls `NSApp.activate` so the window comes to the front.
- **Layout**: one `Form` with `.grouped` style, four sections, no toolbar tabs.
  1. **General**: Launch at login, a toggle bound to `SMAppService.mainApp` (default off, state read from `.status` every time, never stored; a registration error shows inline). Billing-cycle start day, a Picker 1–31 (default 1), clamped to the last day of shorter months.
  2. **Notifications**: an on/off toggle (default on; permission requested on first enable or first launch). Warning / critical thresholds (default 80 / 95), range 50–100 in steps of 5, warning < critical enforced. The same pair drives the Plan-limits ring colours (ticket 06).
  3. **Statusline**: installed / not-installed state with Install / Uninstall buttons, behaving as ticket 07 settled.
  4. **Prices**: the price-table age is always shown (ticket 10). An "Update now" button is disabled with a spinner while fetching. On success the age reads "just now" and the 24 h timer restarts from then. On failure a short red inline message shows (e.g. "Update failed: offline") and the current table stays; no notification is sent.
- **Storage**: Billing-cycle start day, both thresholds and the notifications toggle go in `@AppStorage` (UserDefaults). Launch at login and wrapper state are always read from their real source. `UsageCore` never reads UserDefaults; the app passes values in as parameters.
- **Not configurable** (constants in code): the Git repo recency window and max count (14 days / 15), the 62-day history, the poll intervals, the 24 h price fetch and the title $ banding.
