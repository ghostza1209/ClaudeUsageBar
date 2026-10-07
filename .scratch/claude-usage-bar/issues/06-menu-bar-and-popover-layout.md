# What should the menu bar title and popover look like?

Type: prototype
Status: resolved
Blocked by: 04

## Question

How do the menu bar title (icon + today's API list estimate) and the popover lay out the Usage, Processes and Git tabs plus Plan limits, starting from the TermTracker Usage screenshot? Where does Plan limits sit, and what does each tab show when there is no data or a source has failed?

## Answer

Variant A (tabs) with the rings header from variant C. Prototype: [`prototypes/menubar-popover-PROTOTYPE/`](../prototypes/menubar-popover-PROTOTYPE/), where the chosen layout is variant A with variant C's header.

- **Menu bar title**: icon + today's API list estimate. It shows `—` when there are no logs yet, and a trailing ⚠ when the statusline wrapper is not installed or Plan limits are unreadable.
- **Popover**: fixed width (about 380 pt). From top to bottom:
  1. **Plan limits header** (from C): two rings, the 5-hour window and the Weekly window. Each shows percent used inside the ring and the reset time beside it, coloured by threshold (accent, then orange at 80%, red at 95%). Under the rings is the data's age ("updated X min ago"), shown in orange when stale.
  2. **Segmented tabs** (from A): Usage / Processes / Git.
- **Usage tab** (TermTracker order): Billing-cycle API list estimate with its start date, then the token breakdown (input / output / cache read / cache write), then Today (cost, tokens, requests), then a last-hour tokens/min sparkline, then a 14-day trend, then the per-model table.
- **Processes tab**: one row per running Claude Code session: project name, cwd truncated in the middle, CPU %, RAM, uptime, and a stop button that sends SIGTERM.
- **Git tab**: one row per repo: name, dirty count, ahead/behind, then on a second line the branch, last commit subject and its age.
- **Empty and failed states**: each state replaces only the area it affects; it never blanks the whole popover.
  - Rings header: three distinct one-line messages: wrapper not installed (with an "Install…" button), no data yet (prompts the user to run Claude Code on Pro/Max), and unreadable (a short error). A window past its `resets_at` shows 0%.
  - Usage: "no Claude Code logs yet".
  - Processes: "no Claude Code sessions running".
  - Git: either "git not found" with a fix hint, or "no repos yet" while there are no logs.

## Comments

- Prototype (throwaway, native SwiftUI `MenuBarExtra`): [`prototypes/menubar-popover-PROTOTYPE/`](../prototypes/menubar-popover-PROTOTYPE/). Variants A (tabs + Plan limits strip), B (one scrolling dashboard), C (rings header + bottom tab bar), each crossed with 7 data states. Run: `swift run --package-path .scratch/claude-usage-bar/prototypes/menubar-popover-PROTOTYPE -- --variant A --state normal`.
