# 24: Settings screen

**What to build:** Settings is one grouped `Form` with four sections. General: Launch at login (`SMAppService.mainApp`, status read live, inline error) and Billing-cycle start day (1–31). Notifications: toggle plus warning/critical thresholds (50–100 step 5, warning < critical). Statusline: state plus Install/Uninstall. Prices: table age plus "Update now" with spinner and inline error.

**Blocked by:** 17, 18, 19, 21

**Status:** ready-for-agent

Spec: [spec.md](../spec.md)

- [ ] All values wired to the same `@AppStorage` keys used by tickets 17, 20, 21
- [ ] Launch-at-login state never stored; read from `.status`
- [ ] Threshold pickers enforce warning < critical
- [ ] Uninstall behaves as ticket 19 (restore only if still ours)
- [ ] "Update now" disables with spinner; success shows "just now" and restarts the 24 h timer; failure shows a short red inline message
- [ ] ⌘, opens Settings while the popover is open
