# 23: Git tab

**What to build:** The Git tab lists repos Claude Code worked in during the last 14 days, newest first, at most 15: name, dirty count, ahead/behind, then branch, last commit subject and age. Repos come from cache cwds plus running-session cwds. Scans run when the tab is shown and every 15 s while visible; previous rows stay during a rescan.

**Blocked by:** 16

**Status:** ready-for-agent

Spec: [spec.md](../spec.md)

- [ ] cwd → repo via `git -C <cwd> rev-parse --show-toplevel`, cached per cwd; subdirectories collapse; worktree is its own row labelled with its name; non-git, deleted, `/tmp`, `/private/tmp` dropped
- [ ] Per repo `git status --porcelain=v2 --branch` + `git log -1 --format=%s%x00%ct`; max 4 concurrent; 3 s timeout → "timed out" row; `GIT_OPTIONAL_LOCKS=0`; never fetch
- [ ] No upstream → no ahead/behind shown
- [ ] States: "git not found" with fix hint; "no repos yet" with no logs
- [ ] Tests use real `git` in temp repos: worktree, upstream ahead/behind, dirty file, caps and ordering, timeout, git-not-found
