# How can the app read Plan limits?

Type: research
Status: resolved

## Question

What ways exist to read the current Plan limits (5-hour window and Weekly window: percent used and reset time) for a Claude Pro/Max subscription from a local macOS app? For each: endpoint or source, what auth it needs and where that credential lives locally (e.g. Claude Code's OAuth token in the Keychain, a claude.ai session cookie), response shape, how stable/official it is, and rate-limit or ToS risks. Note how existing open-source tools do it.

## Answer

Use **Claude Code's statusline stdin `rate_limits`** as the primary source. It is official and documented: `five_hour` / `seven_day`, each with `used_percentage` (0–100) and `resets_at` (epoch seconds). It is present for Pro/Max after the session's first API response. The app installs a statusline wrapper that writes this JSON to a file the app watches, then chains to the user's existing statusline (claude-hud here). It needs no credentials and carries no ToS risk, but goes stale while Claude Code is idle.

The optional opt-in fallback is the undocumented `GET https://api.anthropic.com/api/oauth/usage`:
- Auth: `Authorization: Bearer` plus `anthropic-beta: oauth-2025-04-20`.
- Response: `five_hour` / `seven_day` with `utilization` 0–100 and ISO `resets_at`.
- Credential: the token sits in the Keychain item `Claude Code-credentials` under `claudeAiOauth` and needs the `user:profile` scope.
- Rules: read only, never refresh the token, poll slowly, and back off on 429.
- ToS: grey area under "may not collect, store, or intermediate Claude.ai credentials".

Avoid the claude.ai `sessionKey` cookie API, `/usage` PTY scraping, and response-header proxying. ccusage only estimates from local logs.

Details and sources: [research/plan-limits-data-source.md](../research/plan-limits-data-source.md)
