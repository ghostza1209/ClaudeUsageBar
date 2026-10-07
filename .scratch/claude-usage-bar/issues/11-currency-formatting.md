# How is the dollar amount formatted?

Type: grilling
Status: resolved

## Question

The menu bar title and Usage tab show the API list estimate in USD. Should it be rendered as `$18.42` regardless of locale or with the locale default (e.g. `US$18.42`), how many decimals (title vs tabs, small values like `$0.004`), and should amounts ≥ $1,000 be abbreviated in the title (`$1.2k`)?

## Answer

- **Symbol and locale**: always `$` with `en_US` grouping and decimal separators (`$3,124.50`), whatever the system locale (avoids `US$` on e.g. `th_TH`). The estimate is USD by definition.
- **Popover** (Billing cycle, Today, per-model rows, chart tooltips): always 2 decimals with thousands grouping. A non-zero amount below $0.01 shows `<$0.01`; exactly zero shows `$0.00`.
- **Menu bar title** (today's API list estimate): below $100 → `$18.42`; $100–$999 → whole dollars `$123`; $1,000 and up → one-decimal thousands `$1.2k`. Bands are chosen on the rounded value, so $999.60 shows `$1.0k`, not `$1,000`. Keeps the title to about 6 characters.
- **14-day trend axis labels**: the same compact formatter as the title (`$0`, `$50`, `$1.2k`).
- So there are two formatters, compact (title, axis) and full (everything else). No glossary change: neither is a domain term.
