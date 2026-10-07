# How can the app read Plan limits?

Research for [issue 01](../issues/01-plan-limits-data-source.md). Researched 2026-10-07 against Claude Code 2.1.292 (installed locally).

## Summary

| # | Source | Auth | Official? | Verdict |
|---|--------|------|-----------|---------|
| 1 | Claude Code statusline stdin `rate_limits` | None (Claude Code passes it) | **Yes, documented** | Primary source |
| 2 | `GET https://api.anthropic.com/api/oauth/usage` | Claude Code OAuth access token (Keychain) | No, undocumented | Optional opt-in fallback |
| 3 | `GET https://claude.ai/api/organizations/{org}/usage` | claude.ai `sessionKey` browser cookie | No, undocumented | Avoid |
| 4 | Scrape `/usage` from a `claude` process in a PTY | None extra | No (UI scraping) | Avoid, too fragile |
| 5 | `anthropic-ratelimit-unified-5h-*` / `7d-*` response headers | Only visible to the process doing inference | Undocumented | Not practical |
| 6 | ccusage-style local JSONL analysis | None | n/a | Does not answer the question: gives an estimate, not Plan limits |

## 1. Statusline stdin `rate_limits` (official)

Source: [Claude Code docs: Customize your status line](https://code.claude.com/docs/en/statusline)

- Claude Code runs the configured `statusLine.command` and passes session JSON to it on stdin. That JSON includes:
  - `rate_limits.five_hour.used_percentage`, `rate_limits.seven_day.used_percentage`: "Percentage of the 5-hour or 7-day rate limit consumed, from 0 to 100".
  - `rate_limits.five_hour.resets_at`, `rate_limits.seven_day.resets_at`: "Unix epoch seconds when the 5-hour or 7-day rate limit window resets".
- When it is present: "appears only for claude.ai Pro and Max subscribers ... and only after the first API response in the session. Each window ... may be independently absent, and Claude Code drops a window once its `resets_at` time passes."
- When the script runs: on events, debounced at 300 ms. It also runs when a window in the last data reaches its `resets_at`, and on an optional `refreshInterval` timer (minimum 1 s).
- Example shape:
  ```json
  "rate_limits": {
    "five_hour": { "used_percentage": 23.5, "resets_at": 1738425600 },
    "seven_day": { "used_percentage": 41.2, "resets_at": 1738857600 }
  }
  ```

**How a menu bar app uses it.** The app cannot read Claude Code's stdin directly. It needs a small statusline wrapper script that:
1. writes `rate_limits` plus a capture timestamp to a file, for example under `~/Library/Application Support/<app>/`, and
2. passes stdin on to the user's existing statusline command and prints that command's output.

The app then watches or polls that file.

**Local constraint.** There is only one `statusLine` slot. On this machine `~/.claude/settings.json` already points it at the claude-hud plugin, so the wrapper has to chain to it rather than replace it.

**Limits.**
- Data is only as fresh as the last Claude Code turn. When no Claude Code session is running, values go stale. Usage from claude.ai web or the desktop app does not show up until the next Claude Code response.
- When a window passes its `resets_at`, treat it as 0% used.
- It needs no credentials and carries no ToS risk.

**Signal from existing tools.** claude-hud v0.0.11 `CHANGELOG.md`, Unreleased section (local copy at `~/.claude/plugins/cache/claude-hud/claude-hud/0.0.11/CHANGELOG.md`; upstream [jarrodwatts/claude-hud](https://github.com/jarrodwatts/claude-hud)):
- "Simplify usage display to rely only on Claude Code's official stdin `rate_limits` fields."
- "Remove the background OAuth usage API fallback ..."

Its parser is in `src/stdin.ts` and the types are in `src/types.ts`. Before this, users asked for the feature in [anthropics/claude-code#29604](https://github.com/anthropics/claude-code/issues/29604) and [#55333](https://github.com/anthropics/claude-code/issues/55333).

## 2. OAuth usage endpoint (undocumented)

Primary source: CodexBar, a macOS menu bar app, at commit `eda352c` ([steipete/CodexBar](https://github.com/steipete/CodexBar)):
- `Sources/CodexBarCore/Providers/Claude/ClaudeOAuth/ClaudeOAuthUsageFetcher.swift`
- [`docs/claude.md`](https://github.com/steipete/CodexBar/blob/main/docs/claude.md)

**Request.** `GET https://api.anthropic.com/api/oauth/usage?cedar_ember=1`. CodexBar retries without `?cedar_ember=1` on a 400 or 403. Headers:
- `Authorization: Bearer <accessToken>`
- `anthropic-beta: oauth-2025-04-20` (the source comment says the endpoint "currently requires the beta header")
- `Accept: application/json`
- A Claude-Code-like `User-Agent` (`claude-cli/<ver> (external, cli)`)

**Response.** Top-level windows `five_hour`, `seven_day`, `seven_day_opus`, `seven_day_sonnet`, `seven_day_oauth_apps`, and others. Each window is `{ "utilization": <0–100 number>, "resets_at": "<ISO-8601 string>" }`.
- Note that `resets_at` is an ISO string here, but epoch seconds in source 1.
- CodexBar passes `utilization` straight through as `usedPercent`.
- A newer `limits[]` array exists with entries `{kind, group, percent, resets_at, scope, is_active}`.
- A `/api/oauth/profile` endpoint returns account and plan details.

**Credential.**
- Claude Code stores its login in the macOS Keychain, generic password, service `Claude Code-credentials` ([Claude Code docs: Authentication → Credential management](https://code.claude.com/docs/en/authentication)). It falls back to `~/.claude/.credentials.json` (mode 0600) when the Keychain write fails. With `CLAUDE_CONFIG_DIR` set, the item is keyed to that directory.
- On this machine the Keychain item exists (account `ysz`, login keychain) and the JSON file does not. I did not read the secret value.
- Per CodexBar's models, the payload holds `claudeAiOauth.{accessToken, refreshToken, expiresAt, scopes, subscriptionType, rateLimitTier}`.
- CodexBar notes that on Claude Code 2.1.x the item may hold only `mcpOAuth`, with no `claudeAiOauth`.

**Scope.** The token needs the `user:profile` scope. CodexBar docs: "tokens with only `user:inference` cannot access usage data". So a `claude setup-token` / `CLAUDE_CODE_OAUTH_TOKEN` token, which "can only make model requests", will not work.

**Risks.**
- **Undocumented.** The beta header, query flag and response shape can change without notice. CodexBar already handles two response shapes.
- **429 rate limiting.** CodexBar has a whole `ClaudeOAuthUsageRateLimitGate` that honours `Retry-After`, and claude-hud's changelog mentions "repeated `429`" failures. Poll slowly (minutes, not seconds) and back off.
- **Keychain ACL.** Reading another app's Keychain item triggers a macOS prompt. CodexBar's docs: "Claude Code periodically rotates its `Claude Code-credentials` Keychain item and can replace the ACL grant", so the user gets prompted again.
- **Token refresh.** The app must never refresh the token itself. Using the refresh token rotates it and can log Claude Code out. CodexBar instead delegates refresh to the `claude` CLI. Its token endpoint is `https://platform.claude.com/v1/oauth/token` and its client ID is Claude Code's own; using those means impersonating Claude Code.
- **ToS.** [Claude Code docs: Legal and compliance](https://code.claude.com/docs/en/legal-and-compliance), "Authentication and credential use", says OAuth "is designed to support ordinary use of Claude Code and other native Anthropic applications", and that "developers may not collect, store, or intermediate Claude.ai credentials or session tokens". Anthropic "may [enforce] without prior notice". A personal app that reads the user's own token on their own machine and only calls a read-only usage endpoint is a grey area, not clearly allowed. Never persist or send the token anywhere else.

## 3. claude.ai web API with session cookie (undocumented)

Source: CodexBar `docs/claude.md` and `Sources/CodexBarCore/Providers/Claude/ClaudeWeb/ClaudeWebAPIFetcher.swift`.

- `GET https://claude.ai/api/organizations` returns the org UUID. Then `GET https://claude.ai/api/organizations/{orgId}/usage` returns the same `five_hour` / `seven_day` objects with `utilization` and ISO `resets_at`.
- Auth: the `sessionKey` cookie (`sk-ant-...`) for `claude.ai`, pulled from browser cookie stores:
  - Safari `~/Library/Cookies/Cookies.binarycookies`, which needs Full Disk Access.
  - Chrome `.../Google/Chrome/*/Cookies`, which needs the "Chrome Safe Storage" Keychain entry to decrypt.
  - Firefox `cookies.sqlite`.
- Risks: the same ToS clause ("session tokens"). Cloudflare challenges block requests (CodexBar has dedicated guidance for this). Cookie extraction is invasive, and the session cookie gives full account access. Advise against.

## 4. CLI `/usage` scraping

CodexBar runs `claude` in a PTY with `--allowed-tools ""`, sends `/usage`, and parses the rendered "Current session" / "Current week" percentages and reset text. This depends on terminal UI text, spawns a full Claude Code process, and may itself count as a session. `claude --help` (2.1.292) has no non-interactive usage subcommand. It is a last resort only.

## 5. Unified rate-limit response headers

Inference responses carry `anthropic-ratelimit-unified-5h-utilization`, `-5h-reset`, `-7d-*`, and `-representative-claim` ([anthropics/claude-code#12829](https://github.com/anthropics/claude-code/issues/12829), [#55333](https://github.com/anthropics/claude-code/issues/55333)). Claude Code reads these to fill source 1.

An external app would only see them by proxying all of Claude Code's traffic through `ANTHROPIC_BASE_URL`, or by making its own inference calls with the subscription token, which is plainly against the ToS clause above. Not practical.

## 6. ccusage (for comparison)

[ccusage blocks report](https://ccusage.com/guide/blocks-reports) groups local Claude Code JSONL logs into 5-hour blocks starting at the first message. `--token-limit max` compares against your own past peak block. It never queries Anthropic. That is an API list estimate (see GLOSSARY), not Plan limits, and it cannot know the real percent used or the server's reset time.

## Recommendation

1. **Primary: statusline sidecar (source 1).**
   - Official, documented field names and units, no credentials, no ToS risk.
   - Cost: installing a wrapper into `statusLine` that chains to the user's existing command (claude-hud here).
   - Shows a "last updated" age, because data goes stale when Claude Code is idle.
2. **Optional, opt-in fallback: OAuth usage endpoint (source 2).** Only to refresh while Claude Code is idle. Read the token from the Keychain only:
   - never refresh or store it,
   - poll at most every few minutes,
   - honour 429 / `Retry-After`,
   - accept that it is undocumented and in a ToS grey area.
3. **Skip** cookies (3), PTY scraping (4) and headers (5).
