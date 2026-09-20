# AGENTS.md

Orientation for Codex agents working in this repository, and for a human who wants
the short version.

**`CLAUDE.md` is the source of truth.** It carries the project rules, the build and
verification commands, the architecture, and the trap list — all of it, in detail.
This file holds only what an agent needs *before* opening it, plus the handful of
things that differ for Codex. Everything else was deleted from here on 2026-09-19
because two copies of the same guidance drift: this file had a "two-repo rule" while
CLAUDE.md had three, and still described a top bar that was rebuilt the day before.

Precedence, when they disagree: **the code wins, then `CLAUDE.md`, then this file.**
Surface the mismatch rather than inventing a path or an API around it.

## What this repo is

**Block Party** — a native SwiftUI + Mapbox iOS app for St. Joseph, Minnesota. It is
the native twin of the Expo/React Native app in `~/Documents/my-business`, and the
port source for `~/Documents/block-party-android`. Work belongs in the repo that owns
the platform; do not edit a sibling repo as a side effect.

**The app is mid-rebuild.** The 2026-09-17 strip-down emptied the Today feed and
deleted the Activities and Calendar features; `docs/GUTTING-LEDGER.md` records what
went and how to recover it. If a guide describes something you cannot find in the
tree, assume the strip-down took it and say so.

| | |
|---|---|
| Xcode project / scheme / module | `BlockParty.xcodeproj`, `BlockParty` |
| Bundle id | `Jesse.BlockParty` |
| Deployment target | iOS 26.5, Swift 5 |
| Test target | `BlockPartyTests` (app-hosted) |
| Only SPM dependency | `mapbox-maps-ios` |
| Supabase project | `lxdgwhvqjqmqliobwjpi` (shared with the Expo app) |

## Before changing anything

This is the one section to act on before reading further — several sessions share
these checkouts, and the tree is routinely dirty with someone else's work.

```bash
git status --short --branch
git worktree list
git branch -a
```

Preserve unrelated WIP. Never `git add -A` here, stage explicit paths, and re-check
the current branch immediately before every commit and push — a parallel session can
move a worktree onto a different branch mid-task. If the requested change would
overlap another session's uncommitted files, surface the entanglement and let the
user pick the scope. Worktree paths change often, so read `git worktree list` rather
than a remembered name.

## What differs for Codex

- **Tooling is not guaranteed.** Where `CLAUDE.md` says to prefer XcodeBuildMCP
  (`build_run_sim`, `build_sim`, `screenshot`), use it only if it is actually
  present in your session; otherwise take the raw `xcodebuild` / `xcrun simctl`
  fallbacks given alongside it. Same for the graphify and code-review-graph tools.
- **Confirm the checkout before building.** If you are driving XcodeBuildMCP, run
  `session_show_defaults` first: every worktree builds the same bundle id, so
  installing any of them overwrites the same simulator app and the last build wins.
- **Do not read or write another agent's config** as part of a task here.

## Where everything else lives

| You need | Read |
|---|---|
| Build, test, run, install, device builds, first-checkout setup | `CLAUDE.md` |
| Architecture: shell, auth, backend, Today, map, design system | `CLAUDE.md` |
| Conventions, gotchas, and the trap list | `CLAUDE.md` |
| The ~80 DEBUG launch arguments | `docs/debug-flags.md` |
| What was deleted in the strip-down, and how to get it back | `docs/GUTTING-LEDGER.md` |
| Current identifiers, outstanding console work | `DECISIONS.md` |
| Design system, brand, colour and logo rules | `DESIGN.md` |
| Map work, chronologically | `MAP_BUILD_LOG.md` |
| Product and launch strategy | `docs/playbook.md` |
| Parked-but-tested code (utility row, horizon) | `BlockParty/Features/Civic/Parked/README.md` |

`MAP_BUILD_LOG.md`, `REVIEW.md` and the dated files under `docs/superpowers/` are
historical records. Do not rewrite old entries to pretend the app was always called
Block Party; correct only claims presented as current fact.
