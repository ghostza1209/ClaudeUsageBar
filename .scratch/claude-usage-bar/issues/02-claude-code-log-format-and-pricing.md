# What do Claude Code logs contain, and where do API prices come from?

Type: research
Status: resolved

## Question

What is the on-disk format of Claude Code's local logs (`~/.claude/projects/**/*.jsonl` and anything else relevant), and which fields give per-message tokens (input, output, cache read, cache write), model, Session id, cwd, timestamp and tool calls? What pitfalls do existing parsers (e.g. ccusage) handle, such as duplicate entries, streaming partials, sub-agents, or other log locations? Where can a current per-model API price table be sourced so an API list estimate can be computed?

## Answer

Usage lives in `assistant` lines of `~/.claude/projects/<cwd-slug>/<sessionId>.jsonl` plus sub-agent files under `<sessionId>/subagents/**/agent-*.jsonl` (also scan `$CLAUDE_CONFIG_DIR` / `~/.config/claude`). Each line has `timestamp` (UTC ISO), `sessionId`, `cwd`, `isSidechain`, `requestId`, `message.{id, model, content[] (tool_use blocks), usage}` with `input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens` split into `ephemeral_5m/1h`, `server_tool_use.web_search_requests`, `speed`, `iterations[]`. Pitfalls: one response is split over several lines (about 2x overcount if summed), earlier copies hold partial `output_tokens`, so dedupe globally on `(message.id, requestId)` keeping the largest total (as ccusage does); include sub-agents; price `advisor_message` iterations separately at their own model (top-level usage excludes them); skip `<synthetic>` and non-transcript `.jsonl`. Prices: Anthropic's pricing page is the authority (no machine API); LiteLLM's `model_prices_and_context_window.json` is the machine-readable source (matches the page for every local model on 2026-10-07; ccusage also uses models.dev as a fallback). Local scale: 2.3 GB, 2,641 files.

Details and sources: [research/claude-code-log-format-and-pricing.md](../research/claude-code-log-format-and-pricing.md)
