# 15: Today's API list estimate in the menu bar title

**What to build:** On launch the app scans Claude Code logs (`assistant` lines in `~/.claude/projects/**/*.jsonl`, including sub-agent files) in the background, newest files first, dedupes responses globally on `(message.id, requestId)` keeping the largest total, prices them with a bundled Claude-only LiteLLM snapshot, and shows today's API list estimate in the menu bar title with the compact formatter. The title is icon-only while the scan runs and `—` when there are no logs. No persistent cache yet (ticket 16).

**Blocked by:** 14

**Status:** resolved

Spec: [spec.md](../spec.md)

- [x] Parser extracts timestamp, model, sessionId, cwd, input/output/cache read/5m+1h cache write tokens, web search requests, speed and advisor iterations; skips `<synthetic>` and malformed lines without crashing
- [x] Split and streamed partial lines count once, keeping the largest total
- [x] Sub-agent files are included; advisor iterations are priced at their own model
- [x] Price lookup: exact id then `anthropic/<id>`; unknown or `speed: fast` → Unpriced model (tokens counted, excluded from $); web search $0.01/request
- [x] Compact formatter: `$18.42` < $100, `$123` < $1,000, `$1.2k` above, band chosen on the rounded value; `$` with en_US separators regardless of locale
- [x] Title: icon-only during scan, `—` with no logs, today's (local calendar) $ otherwise
- [x] Tests use temp-dir fixture logs and an injected clock, with hand-computed literal expected values

## Comments

- Cache write: `cache_creation_input_tokens` minus the 1h split is priced as 5m. The split fields do not always add up to the total; a real line had 5m=0 and 1h=1523 against a total of 2392, and its iterations put the missing 869 in 5m.
- `speed: fast` makes only the main response Unpriced, along with its web searches. Advisor iterations are still priced at their own model.
- Lines with no `requestId` (22 locally) are keyed on `(message.id, nil)`. ccusage's `(id, sessionId, timestamp)` fallback was not adopted. Lines with no `message.id` are skipped.
- The bundled snapshot (`Sources/UsageCore/Resources/prices.json`) holds the 21 `litellm_provider: anthropic` `claude-*` keys from LiteLLM as of 2026-10-07. It keeps only `input_cost_per_token`, `output_cost_per_token`, `cache_read_input_token_cost`, `cache_creation_input_token_cost` and `cache_creation_input_token_cost_above_1hr`. The `*_above_200k_tokens` rates are ignored. LiteLLM currently has no `anthropic/claude-*` keys, so a test fixture covers the prefix lookup.
- `scripts/bundle.sh` now copies `ClaudeUsageBar_UsageCore.bundle` into `Contents/Resources/`. That is where SwiftPM's `Bundle.module` looks; it has no build-path fallback. `codesign --verify --strict` passes.
- Cold scan on this machine took about 10.6 s for 2.3 GB (64.4k records after dedupe), sequential, release build, with a warm page cache. It runs as a single `.background` detached task. The main cost was the line prefilter (`Data.split` + `firstRange` took 56 s), so it now uses `memchr`/`memmem`. A per-file parallel parse is possible if a cold page cache makes it slow.
- Today's figure cross-checked within cents against a separate Python implementation of the same rules. ccusage was not available offline.
- Deferred to ticket 17, where the popover first needs it: the full formatter (`<$0.01`). Ticket 14 had handed it to this ticket, but the title uses only the compact formatter.
- Deferred to ticket 16: the 62-day cutoff, per-file offsets, the half-line wait (a partial last line currently fails to decode and is skipped) and midnight rollover of the title.
