# Detecting running Claude Code sessions on macOS

Question: [issues/03-detect-claude-code-processes.md](../issues/03-detect-claude-code-processes.md)

Tested 2026-10-07 on macOS (Darwin 27.2.0, arm64), Claude Code 2.1.291 and 2.1.292, native installer (`~/.local/bin/claude`). Experiments were read-only. No process was killed: the only signal sent was `kill(pid, 0)`, which checks whether you're allowed to signal a process without delivering anything.

## TL;DR

- **Claude Code keeps its own registry of running Sessions.** It writes `~/.claude/sessions/<pid>.json` for each live interactive Session. Each file holds `pid`, `sessionId`, `cwd`, `startedAt`, `procStart`, `version`, `status` (`busy`/`idle`/`shell`), `name`, `kind` and `entrypoint`. The Session log is at `~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl`. This gives the pid-to-Session mapping directly. Nothing else does it: the `.jsonl` log is not held open (`lsof` does not show it), and the session id is not in argv.
- **libproc gives CPU, RAM, uptime and cwd per pid with no special permissions**, for processes owned by the same user:
  - `proc_pidinfo(PROC_PIDTASKINFO)` gives RSS and CPU time.
  - `proc_pidinfo(PROC_PIDTBSDINFO)` gives the start time.
  - `proc_pidinfo(PROC_PIDVNODEPATHINFO)` gives the cwd.
  - `proc_pidpath` gives the executable path.
- **Stopping a Session is a plain `kill(pid, SIGTERM)`**, followed by `SIGKILL` if needed. It is the same user, so no privileges are needed.
- **App Sandbox rules this out.** In a sandboxed build, reading `~/.claude` and `kill()` are both blocked (verified, see below), and so is `proc_listallpids`. **The app must be non-sandboxed**, which means it ships outside the Mac App Store (Developer ID plus notarization). App Review 2.4.5(i) requires Mac App Store apps to be "appropriately sandboxed" [6].

## What a Claude Code process looks like

| Observation | How seen |
|---|---|
| `ps -o comm` and `pgrep -x claude` show `claude`. This is argv[0], set by the `~/.local/bin/claude` symlink. | `ps -axo pid,ppid,comm` |
| The kernel process name (`p_comm`, `pbi_comm`) is the **version string**, e.g. `2.1.292`, not `claude`. The binary is `~/.local/share/claude/versions/2.1.292`. `ps -o ucomm` also shows `2.1.292`. | `proc_pidinfo(PROC_PIDTBSDINFO)`, `proc_pidpath`, `ps -o ucomm` |
| An interactive Session's argv is just `claude`. Argv carries no session id, cwd or flags unless the user passed them. | `ps -o args=`, `sysctl KERN_PROCARGS2` |
| `KERN_PROCARGS2` also returns the whole **environment** of the target (e.g. `ORCA_AGENT_PANE=…`). Treat it as private: don't log or show it. | sysctl probe |
| Some `claude` processes are not Sessions. Example: `claude --chrome-native-host` (pid 36759) has no `sessions/*.json` file. | `ps`, `ls ~/.claude/sessions` |
| `pgrep` leaves out its own ancestors by default ("the current pgrep or pkill process and all of its ancestors are excluded"; `-a` includes them) [7]. Run from inside a Session, `pgrep claude` misses that Session. This doesn't affect a menu-bar app, but it is a trap when testing from a terminal. | `man pgrep`; pid 2688 was missing from `pgrep` but present in `ps -ax` |
| The Session log is **not** held open. `lsof -p <pid>` shows the cwd but no `.jsonl`, so you can't map a pid to a Session through open files. | `lsof -p 303` |

## Mapping a pid to its Session: `~/.claude/sessions/<pid>.json`

Example (pid 303):

```json
{"pid":303,"sessionId":"3107f00c-bb70-4460-b147-883e558656ee","cwd":"/Users/ysz/Desktop/projects/work/PopDeal",
 "startedAt":1791358345274,"procStart":"Wed Oct  7 07:32:24 2026","version":"2.1.292","kind":"interactive",
 "entrypoint":"cli","messagingSocketPath":"/tmp/cc-socks/303.sock","name":"popdeal-4a","status":"shell",
 "updatedAt":1791361348204, ...}
```

- The matching log exists at `~/.claude/projects/-Users-ysz-Desktop-projects-work-PopDeal/3107f00c-….jsonl`. Find it with the glob `~/.claude/projects/*/<sessionId>.jsonl` rather than re-deriving the directory encoding. `/` and `.` both seem to become `-`, e.g. `--claude-worktrees-…`.
- `procStart` is the process start time in UTC. It matched `ps -o lstart` (14:32:24 local, UTC+7) and `pbi_start_tvsec` (1791358344). `startedAt` (ms) is about 1 s later. Before trusting a file, check that the pid is alive, that its start time matches, and that `proc_pidpath` contains `/claude/versions/`. This guards against stale files and against pid reuse.
- **Caveat: this file format is internal to Claude Code and undocumented.** It could change between versions, so parse it defensively. It is unknown whether `sessionId` is rewritten on `/clear` or `/resume`; re-read the files on every refresh. `CLAUDE_CONFIG_DIR` can move `~/.claude` elsewhere.
- Fallback when no sessions file exists (older versions or other entrypoints): enumerate pids and keep those whose `proc_pidpath` contains `/claude/versions/`. The cwd comes from libproc. The Session can then only be guessed, as the newest `.jsonl` under the project directory for that cwd.

## Per-process stats (verified working on this machine)

Swift probe that enumerates processes and matches them by path. On this machine it found the 3 live Sessions with correct cwd, RSS and CPU:

```
2688 cwd=/Users/ysz/Desktop/projects/personal/claude-usage-bar rss=394MB  /…/claude/versions/2.1.292
303  cwd=/Users/ysz/Desktop/projects/work/PopDeal            rss=275MB  /…/claude/versions/2.1.292
22038 cwd=/Users/ysz/Desktop/projects/personal/app           rss=158MB  /…/claude/versions/2.1.291
```

| Need | API | Notes |
|---|---|---|
| List pids | `proc_listallpids` (libproc), or `sysctl {CTL_KERN, KERN_PROC, KERN_PROC_ALL}` | Not needed when you start from `~/.claude/sessions`. |
| Executable path | `proc_pidpath` | Match on `/claude/versions/`. Don't match on `pbi_comm`, which is the version string. |
| cwd | `proc_pidinfo(pid, PROC_PIDVNODEPATHINFO)` → `pvi_cdir.vip_path` | This is what `lsof -d cwd` uses. |
| RAM | `proc_pidinfo(pid, PROC_PIDTASKINFO)` → `pti_resident_size` | Bytes. Matched `ps -o rss`. |
| CPU | `pti_total_user + pti_total_system` | **These are in Mach absolute-time ticks, not ns, on Apple Silicon.** Multiply by `mach_timebase_info` (125/3 here). Verified: 3 278 364 294 ticks × 125/3 = 136.6 s = `ps` TIME 2:16.63. CPU% is the delta between two samples divided by wall time. |
| Uptime | `proc_pidinfo(PROC_PIDTBSDINFO)` → `pbi_start_tvsec` | Or `startedAt` from the sessions file. |
| Stop | `kill(pid, SIGTERM)`, then `SIGKILL` after a timeout | Same uid, so allowed when unsandboxed. Recheck pid and start time just before signalling. |

Sources: `libproc.h` and `sys/proc_info.h` in the macOS SDK [1]; `sysctl(3)` [2]; `kill(2)` [3].

**`NSRunningApplication` is not usable here.** It describes "a single instance of an app" [4], meaning LaunchServices apps. `NSRunningApplication(processIdentifier: 303)` returned `nil` for a CLI Session.

## App Sandbox: what breaks (verified empirically)

I ad-hoc signed the same probe inside a minimal `.app` bundle with `com.apple.security.app-sandbox = true` and ran it:

| Operation | Unsandboxed | Sandboxed |
|---|---|---|
| `proc_listallpids` | 1060 pids | **0** |
| `sysctl KERN_PROC_ALL` | OK | OK |
| `proc_pidinfo` BSDINFO / TASKINFO / VNODEPATHINFO (cwd), `proc_pidpath`, `KERN_PROCARGS2` for another pid | OK | OK |
| Read `~/.claude/sessions/*.json` | OK | **fails**. `NSHomeDirectory()` points into `~/Library/Containers/<id>/Data`. |
| `kill(22038, 0)` | 0 | **-1 EPERM** |

So a sandboxed app could still see the processes, but it could not:

- **Kill a Session.** There is no public entitlement for signalling other processes.
- **Read the session registry or the logs without user involvement.** The user would have to grant `~/.claude` through an open panel and the app would keep a security-scoped bookmark. Apple: "The sandboxed app doesn't have unrestricted access to the user's home folder" [5]. `~/.claude` is a hidden dot-folder, which makes that flow awkward.

Killing is a hard requirement, and the rest of the app reads the logs anyway. **So: ship non-sandboxed, outside the Mac App Store, with Developer ID and notarization.** The Hardened Runtime (needed for notarization) does not block libproc or `kill` on same-user processes. The unsandboxed probe here was an ordinary unsigned binary, but the Hardened Runtime case has not been separately tested.

## Library options

- **Swift:** call libproc and `Darwin.kill` directly. These are available from `import Darwin`, as the probe used; no dependency needed. Read the JSON with `Foundation.JSONDecoder`.
- **Rust:** the `sysinfo` crate's `Process` has `cwd()`, `cpu_usage()` (needs two refreshes, can exceed 100%), `memory()` (RSS bytes), `run_time()`, `start_time()`, `exe()`, `cmd()`, `kill()` and `kill_with(Signal)` [8]. Its docs say macOS `cwd` "cannot be retrieved due to sandboxing restrictions in app store builds", which agrees with the sandbox finding. The `libproc` crate is a thinner binding over the same calls. Either works when unsandboxed.
- **Shell (prototyping only):** `ps -o pid,etime,%cpu,rss -p …` and `lsof -a -p <pid> -d cwd -Fn`. Spawning these on every poll costs more than the libproc calls, so avoid them in the app.

## Sources

1. macOS SDK headers `libproc.h` (`proc_listallpids`, `proc_pidinfo`, `proc_pidpath`) and `sys/proc_info.h` (`proc_taskinfo`, `proc_bsdinfo`, `proc_vnodepathinfo`). Exercised by the Swift probe in this session's scratchpad.
2. `man 3 sysctl`: `KERN_PROC`, `KERN_PROCARGS2`.
3. `man 2 kill`.
4. Apple, NSRunningApplication: https://developer.apple.com/documentation/appkit/nsrunningapplication
5. Apple, Protecting user data with App Sandbox: https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox
6. App Review Guidelines 2.4.5(i): https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility
7. `man pgrep` (`-a` flag).
8. sysinfo `Process`: https://docs.rs/sysinfo/latest/sysinfo/struct.Process.html
9. Local observation: `~/.claude/sessions/{303,2688,22038}.json` and `~/.claude/projects/*/<sessionId>.jsonl` (Claude Code 2.1.29x, undocumented).
