# 18: Price table fetch and age

**What to build:** The full LiteLLM table is fetched at launch and every 24 h and cached atomically at `prices.json` in Application Support. Precedence: fetched cache, then the bundled snapshot. A failed fetch keeps the current table silently. A new table re-prices everything immediately. The popover shows "prices updated N days ago" only when the table is older than 7 days.

**Blocked by:** 15

**Status:** ready-for-agent

Spec: [spec.md](../spec.md)

- [ ] Fetcher is injected into `UsageCore`; tests cover success, failure keeping the current table, and fetched-over-bundled precedence
- [ ] `prices.json` written atomically; table age tracked
- [ ] Totals re-price immediately after a successful fetch
- [ ] Age line shown in the popover only when > 7 days
- [ ] `UsageCore` exposes a manual "update now" that reports success/failure (UI comes in ticket 24)
