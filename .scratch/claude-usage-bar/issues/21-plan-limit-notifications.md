# 21: Plan-limit notifications

**What to build:** The app sends a macOS notification when fresh Plan-limits data crosses the warning or critical threshold for a window, at most once per threshold per window, re-armed when that window's `resets_at` changes. It works with the popover closed. Notification permission is requested on first launch.

**Blocked by:** 20

**Status:** ready-for-agent

Spec: [spec.md](../spec.md)

- [ ] Notification decision lives in `UsageCore`: input previous state + new capture + thresholds + enabled flag → which notifications to fire
- [ ] Fires only on fresh captures; never from stale or reset-zeroed values
- [ ] Once per threshold per window; re-arms on `resets_at` change
- [ ] Enabled flag and thresholds from `@AppStorage` (defaults on, 80/95)
- [ ] Tests cover crossing, no duplicate, re-arm, disabled
