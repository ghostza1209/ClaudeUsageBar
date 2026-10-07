# Which repos does the Git tab show, and how are they scanned cheaply?

Type: grilling
Status: resolved

## Question

"Repos Claude Code recently worked in": where does the repo list come from (cwds in the logs, `~/.claude/sessions/*.json`, project dir names), what counts as "recently" and how many repos are capped, how is a cwd mapped to a repo root (subdirectories, worktrees, non-git dirs, deleted dirs), and how is `git status --porcelain=v2 --branch` / `git log -1` run across them without making the machine sluggish (concurrency limit, timeout per repo, skip when nothing changed)? Whether ahead/behind ever triggers a `git fetch` (recommendation to probe: never).

## Answer

- **Source**: distinct `cwd`s from the log record cache (latest record timestamp = last activity) unioned with `cwd`s of running sessions from `~/.claude/sessions/*.json` (a fresh session counts as active now). `~/.claude/projects` dir names are not used (lossy `/`→`-` encoding).
- **Recency and cap**: repos with activity in the last 14 days, newest first, at most 15; the rest are neither shown nor scanned.
- **cwd → repo**: `git -C <cwd> rev-parse --show-toplevel`, cached per cwd for the app's lifetime. Subdirectories collapse into their repo; non-git and deleted cwds are dropped silently; each worktree is its own row (it has its own branch and dirty state), labelled with the worktree name; cwds under `/private/tmp` or `/tmp` are skipped.
- **Scan**: per repo `git status --porcelain=v2 --branch` (branch, ahead/behind, dirty count) plus `git log -1 --format=%s%x00%ct` (subject, age); at most 4 repos concurrently; 3 s timeout per repo, the row then reads "timed out"; `GIT_OPTIONAL_LOCKS=0` so the scan never contends for `index.lock` with Claude Code. No skip-if-unchanged check: 15 repos of `git status` is cheap; add one only if measured slow. When scans run is left to the refresh-cadence ticket.
- **Fetch**: never. Ahead/behind compares against the local remote-tracking ref; a branch without upstream shows no ahead/behind.
