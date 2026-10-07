# 15: Today's API list estimate in the menu bar title

**What to build:** On launch the app scans Claude Code logs (`assistant` lines in `~/.claude/projects/**/*.jsonl`, including sub-agent files) in the background, newest files first, dedupes responses globally on `(message.id, requestId)` keeping the largest total, prices them with a bundled Claude-only LiteLLM snapshot, and shows today's API list estimate in the menu bar title with the compact formatter. The title is icon-only while the scan runs and `—` when there are no logs. No persistent cache yet (ticket 16).

**Blocked by:** 14

**Status:** ready-for-agent

Spec: [spec.md](../spec.md)

- [ ] Parser extracts timestamp, model, sessionId, cwd, input/output/cache read/5m+1h cache write tokens, web search requests, speed and advisor iterations; skips `<synthetic>` and malformed lines without crashing
- [ ] Split and streamed partial lines count once, keeping the largest total
- [ ] Sub-agent files are included; advisor iterations are priced at their own model
- [ ] Price lookup: exact id then `anthropic/<id>`; unknown or `speed: fast` → Unpriced model (tokens counted, excluded from $); web search $0.01/request
- [ ] Compact formatter: `$18.42` < $100, `$123` < $1,000, `$1.2k` above, band chosen on the rounded value; `$` with en_US separators regardless of locale
- [ ] Title: icon-only during scan, `—` with no logs, today's (local calendar) $ otherwise
- [ ] Tests use temp-dir fixture logs and an injected clock, with hand-computed literal expected values
