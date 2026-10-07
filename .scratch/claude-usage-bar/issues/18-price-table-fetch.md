# 18: Price table fetch and age

**What to build:** The full LiteLLM table is fetched at launch and every 24 h and cached atomically at `prices.json` in Application Support. Precedence: fetched cache, then the bundled snapshot. A failed fetch keeps the current table silently. A new table re-prices everything immediately. The popover shows "prices updated N days ago" only when the table is older than 7 days.

**Blocked by:** 15

**Status:** resolved

Spec: [spec.md](../spec.md)

- [x] Fetcher is injected into `UsageCore`; tests cover success, failure keeping the current table, and fetched-over-bundled precedence
- [x] `prices.json` written atomically; table age tracked
- [x] Totals re-price immediately after a successful fetch
- [x] Age line shown in the popover only when > 7 days
- [x] `UsageCore` exposes a manual "update now" that reports success/failure (UI comes in ticket 24)

## Comments

- `PriceStore` (UsageCore actor, `Sources/UsageCore/PriceStore.swift`) loads `prices.json` from the support dir, else the bundled snapshot. `updateNow() async -> Result<Void, PriceUpdateError>` is the single entry point (no separate `refresh()`): the scheduled fetch ignores the result, ticket 24's "Update now" shows `error.message`. In the app, ticket 24 should call `Usage.updatePrices()`, which on success also restarts the 24 h timer and re-prices the title and open summary; the age to display is `Usage.pricesFetchedAt` (nil for the bundled snapshot) and `priceAgeNote(fetchedAt:now:)` gives the popover wording (nil until > 7 days).
- Deviation: the cache holds the trimmed Claude-only table, not the full download. Same filter as the bundled snapshot: keys `claude-*` / `anthropic/claude-*` (not the ~190 Bedrock/Vertex copies) with all five price fields; a real fetch yields 22 keys.
- Table age = `prices.json` mtime on load, the injected clock after an update. The bundled snapshot has no known age, so `fetchedAt` is nil and nothing shows an age (a table that never updates never warns). Ticket 24's Settings should show "bundled snapshot" for nil.
- A failed manual update does not restart the timer; every scheduled attempt re-arms it, so failures retry in 24 h.
