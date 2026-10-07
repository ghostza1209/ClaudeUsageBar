# How does the API price table stay current?

Type: grilling
Status: resolved

## Question

Prices come from LiteLLM's `model_prices_and_context_window.json` (models.dev as fallback). Does the app bundle a snapshot, fetch it at runtime (how often, cached where), or both? What happens with a model missing from the table (show tokens without $, warn, fall back to a family price)? Are past responses re-priced when the table changes, or priced once at parse time? Does the UI show the table's age?

## Answer

- **Source**: LiteLLM `model_prices_and_context_window.json` only. A snapshot trimmed to Claude keys is bundled in the app; the full table is fetched at launch and every 24 h and cached atomically at `~/Library/Application Support/ClaudeUsageBar/prices.json`. Precedence: fetched cache, then bundled snapshot. A failed fetch keeps the current table silently and retries next cycle.
- **No models.dev fallback**: the bundled snapshot is the fallback (models.dev lacks the 1h cache-write rate; a second parser buys nothing).
- **Re-pricing**: already settled by ticket 08 (priced at display time), so a new table re-prices everything immediately.
- **Lookup**: exact model id, then `anthropic/<id>`; no fuzzy or family matching.
- **Unpriced model** (no match, or `speed: "fast"`): tokens still counted, excluded from the API list estimate; the popover shows "excludes N unpriced model(s)" beside the $; the menu bar title shows the partial sum without a marker. No family-price guessing.
- **Extras**: web search hardcoded at $0.01/request; `inference_geo` multiplier ignored; fast mode stays unpriced until a fast line actually appears.
- **Table age**: shown in the popover only when older than 7 days ("prices updated 12 days ago"), always shown in Settings (input to ticket 13).
