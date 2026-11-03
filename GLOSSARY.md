# Glossary

**Session**: One Claude Code conversation (one transcript log). Never used for a rate-limit period.

**5-hour window**: The rolling five-hour period over which a Claude subscription plan caps usage.

**Weekly window**: The seven-day period over which a Claude subscription plan caps usage.

**Plan limits**: The windows a plan caps (the 5-hour window and Weekly window, minus any Uncapped window), expressed as percent used and time until reset.

**Uncapped window**: A window the user's plan does not cap, such as the 5-hour window on Ultra. Claude Code leaves it out of the rate limits it reports, so it is not shown. Not the same as a capped window that is merely empty right after a reset.

**API list estimate**: What the logged tokens would have cost at Anthropic's public API prices. Not what the user actually pays on a subscription.

**Billing cycle**: The monthly period, starting on a user-set day, over which cumulative usage totals are counted.

**Unpriced model**: A model with no known API price. Its tokens are still counted, but it is left out of the API list estimate.

**App update**: A newer version of Claude Usage Bar published as a release. Never used for refreshing prices.

**Price refresh**: Downloading the latest model price table that the API list estimate is calculated from.
