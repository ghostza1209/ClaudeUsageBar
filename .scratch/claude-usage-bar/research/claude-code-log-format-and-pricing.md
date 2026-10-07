# Claude Code log format and API pricing sources

Researched 2026-10-07. Answers [issue 02](../issues/02-claude-code-log-format-and-pricing.md).

Sources:

- **[LOCAL]** read-only scan of this machine's `~/.claude/projects` (all 2,641 `.jsonl` files, 503,966 lines, parsed with Python; key/shape counts only, no conversation content copied). Claude Code versions in the logs run up to Opus 5.5-era models.
- **[CCU]** ccusage source, `github.com/ryoppippi/ccusage` @ `326df7f` (2026-10-07), now a Rust codebase: `rust/adapters/claude/src/lib.rs`, `rust/adapters/claude/src/paths.rs`, `rust/crates/ccusage-core/src/{cost.rs,pricing.rs,fast-multiplier-overrides.json}`, `docs/guide/cost-modes.md`.
- **[PRICE]** Anthropic pricing page, `https://platform.claude.com/docs/en/about-claude/pricing` (fetched 2026-10-07).
- **[LITELLM]** `https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json` (fetched 2026-10-07).
- **[MDEV]** `https://models.dev/api.json` (fetched 2026-10-07).

## 1. Where the logs are

| What | Path | Notes |
|---|---|---|
| Session transcript | `~/.claude/projects/<cwd-slug>/<sessionId>.jsonl` | `<cwd-slug>` = cwd with `/` and `.` replaced by `-`. 1,512 files. [LOCAL] |
| Sub-agent transcript | `<cwd-slug>/<sessionId>/subagents/agent-<agentId>.jsonl` | 715 files. [LOCAL] |
| Workflow sub-agents | `<cwd-slug>/<sessionId>/subagents/workflows/wf_<id>/agent-<agentId>.jsonl` | 410 files. [LOCAL] |
| Not transcripts | e.g. `<cwd-slug>/vercel-plugin/skill-injections.jsonl`, `<sessionId>/*.json` | Plugins write their own `.jsonl` here; no `type`/`usage`. Must be tolerated. [LOCAL] |
| Other config roots | `$CLAUDE_CONFIG_DIR` (comma-separated list, each a dir containing `projects/`), else `$XDG_CONFIG_HOME/claude` (default `~/.config/claude`) **and** `~/.claude` | ccusage scans both defaults and dedupes across them. [CCU paths.rs `claude_paths`] `~/.config/claude` does not exist on this machine. [LOCAL] |
| Precomputed stats | `~/.claude/stats-cache.json` | Claude Code's own cache: `dailyActivity`, `dailyModelTokens` (`tokensByModel` per day), `modelUsage`, `totalSessions`, `hourCounts`; `lastComputedDate` lags (2026-10-05 on a 2026-10-07 scan). Undocumented. [LOCAL] |

**Size on this machine:** 2.3 GB in `~/.claude/projects`, 2,641 `.jsonl` files, median file 0.53 MB, largest 25 MB, 16 files over 10 MB. 126,254 assistant lines. [LOCAL] A full rescan is a real cost; incremental reading (by file mtime/offset) matters. ccusage skips files whose mtime is before the `--since` window. [CCU lib.rs `load_entries_since`]

## 2. Line format

Every line is one JSON object with a `type`. Observed counts [LOCAL]: `attachment` 199k, `assistant` 126k, `user` 79k, `last-prompt` 20k, `atis-latch`, `mode`, `ai-title`, `system`, `permission-mode`, `queue-operation`, `file-history-snapshot`, `cost-state` 1.3k, `custom-title`, `pr-link`, `agent-name`, and a dozen rarer ones. Unknown types will keep appearing; a parser should only care about `assistant` (and optionally `cost-state`) and skip the rest.

### `assistant` line: the one that carries usage

Fields present on 100% of assistant lines [LOCAL]:

| Need | Field | Shape |
|---|---|---|
| Timestamp | `timestamp` | ISO-8601 UTC string, ms precision, e.g. `2026-09-15T17:06:26.939Z` |
| Session id | `sessionId` | UUID; equals the top-level file's name. Sub-agent files carry the **parent's** `sessionId` (the `<sessionId>` dir) plus `agentId`; verified on all top-level lines and all but 121 sub-agent lines. |
| cwd | `cwd` | absolute path (more reliable than decoding `<cwd-slug>`, which is lossy) |
| Model | `message.model` | e.g. `claude-sonnet-5`, `claude-opus-5-5`, `claude-haiku-4-5-20251001`; `<synthetic>` on 23 local error/placeholder lines |
| Message id | `message.id` | API message id; dedupe key part 1 |
| Request id | `requestId` | API request id; dedupe key part 2 (missing on 22 of 126k lines) |
| Sidechain | `isSidechain` | `true` for every line in `subagents/`, `false` elsewhere (54,130 vs 72,144 lines) |
| Other | `uuid`, `parentUuid`, `version`, `gitBranch`, `entrypoint`, `userType`; often `agentId`, `effort`, `advisorModel`, attribution fields | |

`message.usage` keys (all on 100% of lines unless noted) [LOCAL]:

```
input_tokens                      # uncached input
output_tokens                     # includes thinking
cache_read_input_tokens
cache_creation_input_tokens       # = 5m + 1h below on 99% of lines (124,967/126,254); price the split, fall back to 5m rate on the total if the split is missing (ccusage does)
cache_creation.ephemeral_5m_input_tokens
cache_creation.ephemeral_1h_input_tokens
service_tier                      # "standard"
inference_geo                     # mostly "not_available"
server_tool_use.web_search_requests / web_fetch_requests   (76%)
speed                             # "standard" (76%); "fast" would mean fast-mode pricing
iterations[]                      # (76%) per-sampling-iteration usage, see advisor below
output_tokens_details.thinking_tokens                      (69%)
```

Older logs had a top-level `costUSD` per line; none of the current local lines do. ccusage still honors it in `auto` mode. [CCU cost.rs `calculate_cost_for_usage_at`, docs/guide/cost-modes.md] [LOCAL]

### Tool calls

`message.content[]` blocks on assistant lines: `tool_use` 68.7k, `thinking` 41k, `text` 15k, `server_tool_use` 675, `advisor_tool_result` 633 [LOCAL]. A `tool_use` block has `name` (e.g. `Bash`, `Read`, `Edit`, `mcp__…`) and `id`; the matching result sits on a later `user` line (`toolUseResult`, `sourceToolAssistantUUID`). Usage is per API response, not per tool call.

### `cost-state` line

`{type, sessionId, totalCostUSD, totalAPIDuration, totalToolDuration, totalLinesAdded/Removed, totalDuration, startTime, modelUsage: {<model>: {inputTokens, outputTokens, thinkingTokens, cacheReadInputTokens, cacheCreationInputTokens, webSearchRequests, costUSD}}, hasUnknownModelCost}` [LOCAL]. This is Claude Code's own running cost per session. Only 1,281 lines across 2,641 files, so not every session has one; semantics undocumented. Usable as a cross-check, not as the primary source.

## 3. Pitfalls a parser must handle

1. **One API response is split over several lines.** Each content block (thinking, text, tool_use…) is written as its own `assistant` line with the same `message.id` + `requestId`. Locally: 126,254 assistant lines, only 64,126 unique `(message.id, requestId)` pairs, so naive summing roughly **doubles** usage. [LOCAL]
2. **Streaming partials: duplicate lines do NOT always carry the same usage.** 10,919 of 46,393 duplicate groups have differing usage: earlier lines carry a partial `output_tokens` (e.g. 7) and the final line, with `stop_reason`, carries the real total (e.g. 322). Input/cache counts were equal across the group in the sampled case. So "keep first" undercounts output; keep the line with the **largest token total** (or the last one / the one with `stop_reason`). [LOCAL] ccusage does exactly this: `should_replace_deduped_entry` keeps the candidate with the larger `input+output+cache_creation+cache_read` total. [CCU lib.rs]
3. **Same response in multiple files.** 573 duplicate groups span files (resumed/forked sessions and sub-agent replays copy history). Dedupe globally, not per file. ccusage's key is `(message.id, requestId)`; when `requestId` is missing it falls back to `(message.id, sessionId, timestamp)`; a sidechain replay path also matches on `(message.id, sessionId)`; on conflict it prefers the non-sidechain copy. [CCU lib.rs `usage_dedupe_hash`, `sidechain_replay_dedupe_hash`, `should_replace_deduped_entry`]
4. **Sub-agents.** Their usage is real and billed; it lives in `subagents/**` files with `isSidechain: true` and the parent `sessionId`. Include them (43% of local assistant lines) and attribute to the parent Session.
5. **Advisor iterations use a different model.** When `usage.iterations` contains an `advisor_message` entry, it has its own `model` (e.g. `claude-opus-5`) and token counts. The top-level `usage` equals the sum of the `type: "message"` iterations only and **excludes** the advisor's tokens (verified on all 1,398 local lines that have an advisor iteration). Price the advisor iteration separately at its own model. [LOCAL] ccusage emits one extra entry per advisor iteration with id `<message.id>:advisor:<n>`. [CCU lib.rs `read_usage_file`]
6. **`<synthetic>` model** lines (API errors, placeholders) carry zero/no real usage; ccusage drops the model name. [CCU lib.rs] Also `isApiErrorMessage` lines exist (23 locally).
7. **Fast mode.** `usage.speed == "fast"` means fast-mode pricing; ccusage appends `-fast` to the model and applies a multiplier (`fast-multiplier-overrides.json`: `claude-opus-4-8` → 2.0, Opus 4.6/4.7 → 6.0). [CCU] Official fast prices: Opus 5.5 $8/$40, Opus 5 and 4.8 $10/$50 per MTok (= 2x). [PRICE] No `fast` lines exist locally.
8. **Foreign `.jsonl` files** and unknown `type`s under `projects/` (plugin logs). ccusage pre-filters lines with a `"usage":{` byte search before JSON parsing, which also is its main speed trick. [CCU lib.rs `read_usage_file`]
9. **Timezone.** Timestamps are UTC; day/billing-cycle bucketing must convert to local time. [LOCAL] [CCU `format_date_tz`]

## 4. Where API prices come from

**Authoritative:** the Anthropic pricing page [PRICE]. No machine-readable price endpoint is offered there. Per MTok, for every model seen in local logs:

| Model id in logs | Input | 5m cache write | 1h cache write | Cache read | Output |
|---|---|---|---|---|---|
| `claude-fable-5-1` | $10 | $12.50 | $20 | $0.25 | $50 |
| `claude-opus-5-5` | $4 | $5 | $8 | $0.20 | $20 |
| `claude-opus-5`, `claude-opus-4-8`, `claude-opus-4-7` | $5 | $6.25 | $10 | $0.50 | $25 |
| `claude-sonnet-5-5`, `claude-sonnet-5` | $2 | $2.50 | $4 | $0.20 | $10 |
| `claude-haiku-4-5-20251001` | $1 | $1.25 | $2 | $0.10 | $5 |

Rules [PRICE]: 5m cache write = 1.25x input, 1h cache write = 2x input, cache read = 0.1x input except Fable/Mythos 5.1 (0.025x) and Opus 5.5 (0.05x). Claude 4.6+ models have **no** long-context surcharge (1M window at standard price). `inference_geo: "us"` = 1.1x on 4.6+ models. Web search $10 per 1,000 requests; web fetch free.

**Machine-readable:** LiteLLM's `model_prices_and_context_window.json` [LITELLM], per-token USD with keys `input_cost_per_token`, `output_cost_per_token`, `cache_read_input_token_cost`, `cache_creation_input_token_cost` (5m), `cache_creation_input_token_cost_above_1hr` (1h), and `*_above_200k_tokens` for older long-context models. Spot check on 2026-10-07: it has every model id seen locally (bare and date-suffixed Haiku) and all values match [PRICE]. ccusage uses LiteLLM as primary and `https://models.dev/api.json` [MDEV] as a second source (per-MTok `{input, output, cache_read, cache_write}`, no 1h rate), embedding build-time snapshots of both for offline mode. [CCU pricing.rs `LITELLM_PRICING_URL`, `MODELS_DEV_API_URL`] ccusage hardcodes the 1h write as 2x input (`CACHE_CREATE_1H_INPUT_MULTIPLIER = 2.0`) rather than reading LiteLLM's 1h key. [CCU cost.rs]

**API list estimate formula** (per deduped response, per model):

```
input*in + output*out + cache_read*cr + eph_5m*cw5m + eph_1h*cw1h
+ web_search_requests * 0.01
(+ same for each advisor iteration at the advisor's model price)
```

## 5. Open points

- `cost-state.totalCostUSD` / `stats-cache.json` could replace the scan for some views, but are undocumented and incomplete (not every session has a `cost-state`).
- LiteLLM lags new models by days; an embedded fallback table plus a "model not priced" indicator is what ccusage does (`missing_pricing_model`).
