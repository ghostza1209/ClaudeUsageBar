# 24: Settings screen

**What to build:** Settings is one grouped `Form` with four sections. General: Launch at login (`SMAppService.mainApp`, status read live, inline error) and Billing-cycle start day (1–31). Notifications: toggle plus warning/critical thresholds (50–100 step 5, warning < critical). Statusline: state plus Install/Uninstall. Prices: table age plus "Update now" with spinner and inline error.

**Blocked by:** 17, 18, 19, 21

**Status:** resolved

Spec: [spec.md](../spec.md)

- [x] All values wired to the same `@AppStorage` keys used by tickets 17, 20, 21
- [x] Launch-at-login state never stored; read from `.status`
- [x] Threshold pickers enforce warning < critical
- [x] Uninstall behaves as ticket 19 (restore only if still ours)
- [x] "Update now" disables with spinner; success shows "just now" and restarts the 24 h timer; failure shows a short red inline message
- [ ] ⌘, opens Settings while the popover is open

## Comments

- Code: `ClaudeUsageBar/SettingsView.swift` (new, wired into the `Settings` scene), `UsageCore/PriceStore.swift` `priceAgeText(fetchedAt:now:)` (tested). `Usage` changes: `wrapperInstalled` is now observable (`private(set)`), `refreshWrapper()` and `notifier` are internal, new `uninstallWrapper()` mirroring `installWrapper()` (shares `wrapperError`).
- **Thresholds**: no normalisation function. Each picker only offers values that keep warning < critical (warning 50...critical-5, critical warning+5...100), so an invalid pair cannot be chosen; hence no pure function to test. A pair already stored by hand outside the UI (e.g. 80/70, or a non-multiple of 5) would show an empty picker until changed.
- **Launch at login**: the toggle's `get` is `SMAppService.mainApp.status == .enabled`; the status is re-read into view state whenever the Settings window becomes key and after each toggle. `.requiresApproval` shows a note pointing to System Settings > Login Items. Not toggled for real during verification (only the status read; the throwaway bundle id showed "off").
- **Notifications**: switching the toggle on calls `usage.notifier.requestAuthorization()` (the system prompts only once). The threshold pickers stay enabled while notifications are off, because they also colour the rings.
- **Statusline**: Install is disabled while installed; Uninstall is always enabled (it also removes leftover wrapper files after another tool overwrote the command, as ticket 07 specifies). Both go through `Usage`, so the popover header and the title ⚠ update at once; verified live in a sandbox (Install -> header "No Plan limits yet", Uninstall -> "Wrapper not installed" + ⚠ and settings.json restored with `padding` intact).
- **Prices**: `priceAgeText` shows `bundled snapshot` / `just now` (< 60 s) / `N minutes|hours|days ago`, a little finer than the spec's three forms so a 10-hour-old table does not read "just now". The age is computed on render, so a Settings window left open for hours does not tick until something re-renders it. "Update now" disables with a spinner; failure shows `Update failed: <message>` in red; success re-arms the 24 h timer through `Usage.updatePrices()` (ticket 18). Verified success live (`just now`, `prices.json` rewritten). The failure path was not exercised live (needs offline).
- **⌘,**: `.keyboardShortcut(",", modifiers: .command)` is on the popover's `SettingsLink`, but a synthetic ⌘, (CGEvent) while the popover was open did nothing (popover stayed, no Settings window), so this box is left unticked. Not verified with a real keyboard; no AppKit hack added. The gear opens Settings (verified).
- **Verified**: the Settings window opened from the gear in a sandboxed ad-hoc bundle (`com.ysz.ClaudeUsageBar.sandbox24`, `CLAUDE_USAGE_BAR_SANDBOX`), all four sections rendered. `ImageRenderer` renders a grouped `Form` blank here, so screenshots of the real window were used instead. Not exercised: the threshold picker option lists, the billing-day change recomputing the summary, and ring colours changing live (same `@AppStorage` keys as tickets 17/20; no new wiring).
