# Plan limits from Claude Code's OAuth usage endpoint, refreshing its Keychain token

The statusline capture only refreshes while the Claude Code CLI runs, and the desktop app's Code tab never runs a statusline, so the Plan limits went stale for anyone working there. The app now polls `GET https://api.anthropic.com/api/oauth/usage` (undocumented; the endpoint Claude Code's own `/usage` calls) every 5 minutes, with the OAuth token Claude Code keeps in the Keychain item `Claude Code-credentials`. The statusline capture stays as a fallback, and the newer of the two reads wins. The desktop app signs in with its own token and never refreshes that Keychain item, and the access token lives about 8 hours. So when it expires the app refreshes it itself with Claude Code's client id, re-reading the item first and writing the new token pair back into it.

## Considered Options

- Statusline only, with a clearer stale label: safe, but the gauges stay stale all day for desktop-app users.
- Never refresh, and show stale once the token expires: safe, but it fails the same users about 8 hours after their last CLI run.
- Borrow the desktop app's own token: it is stored encrypted inside that app, so reading it would be fragile.

## Consequences

- Refresh tokens appear to be single-use. A refresh that races the CLI's own can sign the CLI out, and `claude /login` fixes that.
- The endpoint is rate-limited: pollers every 30–60 s have seen 429s for 30+ minutes. So the app polls every 5 minutes and backs off to 30.
- The endpoint, the client id and the Keychain layout are not public API, and an Anthropic change can break any of them. The statusline fallback keeps the gauges working while the CLI runs.
- Only the default Keychain service name is read, matching the app's fixed `~/.claude` (no `CLAUDE_CONFIG_DIR`).
