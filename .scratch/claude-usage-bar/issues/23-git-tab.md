# 23: Git tab

**What to build:** The Git tab lists repos Claude Code worked in during the last 14 days, newest first, at most 15: name, dirty count, ahead/behind, then branch, last commit subject and age. Repos come from cache cwds plus running-session cwds. Scans run when the tab is shown and every 15 s while visible; previous rows stay during a rescan.

**Blocked by:** 16

**Status:** resolved

Spec: [spec.md](../spec.md)

- [x] cwd → repo via `git -C <cwd> rev-parse --show-toplevel`, cached per cwd; subdirectories collapse; worktree is its own row labelled with its name; non-git, deleted, `/tmp`, `/private/tmp` dropped
- [x] Per repo `git status --porcelain=v2 --branch` + `git log -1 --format=%s%x00%ct`; max 4 concurrent; 3 s timeout → "timed out" row; `GIT_OPTIONAL_LOCKS=0`; never fetch
- [x] No upstream → no ahead/behind shown
- [x] States: "git not found" with fix hint; "no repos yet" with no logs
- [x] Tests use real `git` in temp repos: worktree, upstream ahead/behind, dirty file, caps and ordering, timeout, git-not-found

## Comments

- `UsageCore/Git.swift`: `activeRepoCandidates(records, sessions:now:)` (distinct cwd, latest record timestamp, running-session cwd = now, 14 days inclusive, newest first), `GitScanner` actor (`scan(candidates)` returns `.gitNotFound` or `.repos([RepoStatus])`), `findGit(path:)` (PATH entries, then `/usr/bin`). The git path and per-repo timeout are injectable through `GitScanner.init`; the 15 cap and the 4 concurrency are constants.
- Cap decision: cwds are resolved and deduped by repo root first, then the first 15 repos (newest) are scanned, so a repo with many subdirectory cwds counts once. Tested with 16 repos and 18 candidates.
- Worktree: `rev-parse --path-format=absolute --show-toplevel --git-dir --git-common-dir` in one call; worktree when git-dir differs from common-dir. Row name is the toplevel directory name plus a "worktree" badge.
- Per-cwd cache lives for the app lifetime, including "not a repo". A cwd whose resolve timed out is not cached. Relative and empty cwds are skipped (`git -C ""` would scan the app's own cwd; a test caught this).
- Timeout: one 3 s deadline per repo shared by `status` and `log`; the process is sent SIGTERM and the row reads "timed out". A repo whose `status` fails (vanished) is dropped.
- "git not found": no executable found, the binary cannot be launched, or `rev-parse` exits with anything but 0 or 128. The last case covers the `/usr/bin/git` shim without the Command Line Tools (exit 1). Not tested against the real shim without CLT (cannot reproduce here), only a fake `git` that exits 1.
- Detached HEAD shows `detached @<7 hex>`; a repo without commits shows the branch and "no commits yet".
- App: `GitMonitor` (`GitTab.swift`) is driven by `Popover` like Processes: `open && tab == 2` starts a scan plus a 15 s timer. Records are taken as the cache's copy-on-write `RecordStore`; distinct cwd extraction and the scan run off the main actor (`Task.detached`). A scan still running at the next tick makes the tick skip. The last result stays across a close until the next open replaces it.
- Verified on the real machine (temporary test, removed): 115 candidates (62 deleted dirs, the rest inside 5 repos) gave 5 rows in 0.58 s cold, 0.27 s warm. Branch, dirty count, ahead/behind (including `0/0` with upstream, none without) and last commit subject/time matched `git status` / `git log` run by hand in 4 of them. No worktree, `/tmp` or timed-out rows occurred naturally. The three states and the row layout were rendered with `ImageRenderer` (temporary test, not committed); the live popover tab switch and the 15 s timer were not observed.
- Sanity-broken and seen red: ahead/behind parse swapped, cap 15 to 16, cap applied before dedupe, timeout kill removed.
- Not done: no concurrency-limit test (4 is a constant in `mapLimited`); a cold resolve of every candidate cwd is bounded only by the 14-day window (0.5 s for 115 cwds); the `/usr/bin/git` shim may show the macOS install dialog when run on a machine without the Command Line Tools.
