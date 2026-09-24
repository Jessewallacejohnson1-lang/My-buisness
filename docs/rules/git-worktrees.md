# Worktrees, branches and committing

Several Claude sessions share these checkouts at once. Every rule here exists because a
parallel session cost somebody work.

## Before you change anything

The router's *Before you change anything* names the three commands to run first. This is
what they are protecting.

Preserve unrelated WIP. `[prose]` **Never `git add -A` here** `[hook]`, stage explicit
paths, and **re-check the current branch immediately before every commit and push**
`[hook]` — a parallel session can move a worktree onto a different branch mid-task. If the
requested change would overlap another session's uncommitted files, surface the
entanglement and let the user pick the scope. `[prose]` Worktree paths change often, so
read `git worktree list` rather than a remembered name. `[prose]`

## Set up once per checkout

Git hooks are per-clone, not per-repo — none of this workspace's six worktrees has the
pre-commit hook until you run it here. `[prose]` Run `bash scripts/install-git-hooks.sh`
once per checkout. It refuses a commit whose generated `AGENTS.md`/`CLAUDE.md` have
drifted from `rules/`. CI checks the same thing and is not bypassable, so skipping this
install is survivable but slower — the drift surfaces at push time instead of commit time.

## The traps

- **"My change isn't showing / the app looks outdated" = you built (or Xcode is open on) the WRONG worktree.** `[prose]` Every current worktree builds to the **same bundle id `Jesse.BlockParty`**, so installing any of them *overwrites* the app on the sim/device — whichever you built **last wins**. Confirm the active project path before building, and quit stray Xcode windows on sibling worktrees. Tell-tale that Xcode still has a stale/deleted worktree open: its `BlockParty.xcodeproj/xcuserdata` keeps getting rewritten. As of the 2026-08-19 integration pass, **`main` and `integration/block-party` are the same united baseline** containing every feature branch (daily-feed, briefing, utility entry point, phase-2 sweep, onboarding, poi-logos, control-room spine); new work still branches off it, so re-check with `git branch -a` rather than assuming. Build the branch you intentionally edited, never a remembered "combined" branch name. `feat/upcoming-personal-insights` predates the Hygge→BlockParty folder rename, so it needs a re-port rather than a blind merge. Merge-conflict conventions from that pass: brand-asset PNG conflicts resolve to the **Aug-12 lowercase "bp" render**, and pbxproj test-registration conflicts resolve as the **union of both sides**.
- **Multi-session branch = dirty tree; isolate + commit as you go.** `[prose]` Parallel sessions routinely leave this branch carrying large amounts of *uncommitted, interleaved* WIP across many features (the same reason there are several `BlockParty-<hash>` DerivedData folders). **`git status` at the START of a task, and `git branch --show-current` again immediately before every commit and push** — a parallel session can move this worktree onto a different branch mid-task, so the branch you committed on is not necessarily the one you started on (happened 2026-09-19: a commit landed on a sibling's `feat/dynamic-type`). **Never `git add -A` / `git commit -a` here** `[hook]` — stage explicit paths, and read `git show --stat` before pushing; `add -A` swept 45 files of another session's in-flight work into a commit the same day. If the tree already holds unrelated uncommitted work, isolate the new work in a **git worktree/branch** so it stays cleanly committable, and offer to commit each finished feature rather than letting changes pile up. A feature woven into another session's uncommitted files (adjacent hunks, or an untracked shared file like a new `View`) **can't be committed in isolation** — surface the entanglement and let the user pick scope instead of guessing or sweeping unrelated work into the commit.
- **Before starting a feature, run `git worktree list` + `git branch -a` — a prior session may already have built it in a sibling worktree.** `[prose]` Worktree names and paths change frequently (current examples include `block-party-briefing`, `block-party-map-polish`, `block-party-onboarding`, `block-party-poi-logos`, `block-party-utility-row`, `bp-daily-feed`, and `bp-phase2`), so never rely on a remembered path. A `git status` in one checkout does **not** reveal work in the others. Adopt/merge existing work instead of duplicating it, and run `session_show_defaults` before an XcodeBuildMCP build so the tool compiles the checkout you actually edited.
- **Re-check the branch immediately before every commit and push.** `[hook]` A parallel
  session can move this worktree onto a different branch mid-task; on 2026-09-19 a commit
  landed on a sibling's `feat/dynamic-type`. `git-guard.sh` refuses a commit or push on a
  branch the session did not start on.
- **Never `git add -A` or `git commit -a` here.** `[hook]` A blanket stage takes another
  session's in-flight work; it swept 45 foreign files on 2026-09-19. Stage explicit paths.

Every `[hook]` guard above (and `sim-guard.sh`, `token-guard.sh` in the other leaves) honours
`BP_GUARD_OFF=1` as an escape hatch — set it and say why when a guard is genuinely wrong for
what you're doing, not just when it's inconvenient. `[prose]`
