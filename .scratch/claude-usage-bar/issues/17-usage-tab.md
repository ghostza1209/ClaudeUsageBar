# 17: Usage tab

**What to build:** The Usage tab shows, in TermTracker order: the Billing-cycle API list estimate with its start date, the cycle's token breakdown (input / output / cache read / cache write), Today (cost, tokens, requests), a last-hour tokens/min sparkline, a 14-day trend (Swift Charts, compact $ axis) and a per-model table. Amounts use the full formatter. During the cold scan it shows partial totals with "Scanning n/m files"; with no logs it shows "no Claude Code logs yet".

**Blocked by:** 15

**Status:** resolved

Spec: [spec.md](../spec.md)

- [x] `UsageCore` aggregation for a given now/calendar/Billing-cycle start day: cycle $ + breakdown + start date, Today, last-hour per-minute buckets, 14-day daily $ series, per-model tokens and $, unpriced-model count
- [x] Billing-cycle start day is clamped to the month's last day (e.g. 31 → Feb 28/29)
- [x] Full formatter: 2 decimals with grouping, `<$0.01` for tiny non-zero, `$0.00` for zero, en_US regardless of locale
- [x] "excludes N unpriced model(s)" beside the $ when N > 0
- [x] Billing-cycle start day is read from `@AppStorage` (default 1) and passed into `UsageCore` as a parameter
- [x] Empty state "no Claude Code logs yet"; scanning indicator with partial totals

## Comments

- **Settings key for ticket 24:** the Billing-cycle start day is `@AppStorage("billingCycleStartDay")`, an Int, default 1 (constant `Usage.billingCycleStartDayKey`). The Popover reads it and passes it to `summarize(..., billingCycleStartDay:)`; a change while the popover is open recomputes. Ticket 24 only needs a 1-31 control on the same key.
- `UsageCore`: `summarize(store, prices:, now:, calendar:, billingCycleStartDay:) -> UsageSummary` and `billingCycleStart(...)` (Aggregation.swift); `fullCurrency` (Formatting.swift). One pass over the records, each priced once. Decisions: the per-model table and the unpriced-model count cover the Billing cycle (the same scope as the $ they sit beside); advisor tokens count under the advisor's model and in the cycle/Today/last-hour token totals; last-hour buckets are the 60 minutes back from `now` (not wall-clock aligned); a model with any unpriced usage is labelled "(unpriced)" in the table and its $ is the priced part only.
- **Measured (release build, real cache, 64,337 records):** `summarize` takes 7-15 ms (the title's `todayCost` takes about 18 ms in the same run). It runs in a detached task, never on the main thread.
- **Recompute policy:** `Usage` keeps the latest `RecordStore` (a cheap copy) after every pass, but computes the summary only while the popover is open, on open, after each pass, on a day change, on a start-day change, and on scan progress. "Open" is the popover window being key (`KeyWindowObserver`), not `onAppear`, which I could not confirm fires on every open of a `.window` MenuBarExtra. Checked the observer on a normal window (false -> true -> false); I could not open the real popover (see below).
- **Scan progress:** `UsageCache.update(..., progress:)` reports `(done, total, partial store)` at most every 250 ms and after the last file; new records now go into the merged store as they are found (so partial totals include cached records), and the merged store is built at the start of a pass instead of the end. Partial totals are shown while "Scanning n/m files" is up; the title stays icon-only until the pass ends.
- **Deviation, axis labels:** `compactCurrency` gives `$50.00` below $100, so the trend axis strips `.00` to read `$0`, `$50`, `$1.2k` as ticket 11 describes.
- **Deviation, verification:** the status item was not reachable on this machine (the menu bar is full; AX press/click opened nothing), so I checked the layout by hosting `Popover` in a temporary borderless-level window with the real logs (not committed). It matches the prototype's variant A: cycle $ and start date, 4-token breakdown, Today, sparkline, 14-day bars with `$0/$100/$200` axis, per-model rows. Model rows show raw ids (`claude-opus-5-5`), not the prototype's display names.
- **Deferred:** no 1-minute timer shifts the sparkline while the popover stays open and logs are idle (the timers belong with the popover-timer work); the empty and scanning states were not shown on screen (empty logic is a plain condition on `scan`/`hasLogs`).
