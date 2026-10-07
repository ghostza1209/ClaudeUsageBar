# 17: Usage tab

**What to build:** The Usage tab shows, in TermTracker order: the Billing-cycle API list estimate with its start date, the cycle's token breakdown (input / output / cache read / cache write), Today (cost, tokens, requests), a last-hour tokens/min sparkline, a 14-day trend (Swift Charts, compact $ axis) and a per-model table. Amounts use the full formatter. During the cold scan it shows partial totals with "Scanning n/m files"; with no logs it shows "no Claude Code logs yet".

**Blocked by:** 15

**Status:** ready-for-agent

Spec: [spec.md](../spec.md)

- [ ] `UsageCore` aggregation for a given now/calendar/Billing-cycle start day: cycle $ + breakdown + start date, Today, last-hour per-minute buckets, 14-day daily $ series, per-model tokens and $, unpriced-model count
- [ ] Billing-cycle start day is clamped to the month's last day (e.g. 31 → Feb 28/29)
- [ ] Full formatter: 2 decimals with grouping, `<$0.01` for tiny non-zero, `$0.00` for zero, en_US regardless of locale
- [ ] "excludes N unpriced model(s)" beside the $ when N > 0
- [ ] Billing-cycle start day is read from `@AppStorage` (default 1) and passed into `UsageCore` as a parameter
- [ ] Empty state "no Claude Code logs yet"; scanning indicator with partial totals
