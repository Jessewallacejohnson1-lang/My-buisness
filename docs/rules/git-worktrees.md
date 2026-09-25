# Worktrees, branches and committing

Several Claude sessions share these checkouts at once. Every rule here exists because a
parallel session cost somebody work.

## Before you change anything

The router's *Before you change anything* names the three commands to run first; this file
is what they are protecting. Preserve WIP that is not yours. `[prose]` Worktree paths change
often, so read `git worktree list` rather than a remembered name. `[prose]` A `git status` in
one checkout reveals nothing about the others, so check before building a feature — a prior
session may already have built it in a sibling worktree. Adopt that work rather than
duplicating it. `[prose]`

## Set up once per checkout

Git hooks are per-clone, not per-repo — no worktree in this workspace has the pre-commit
hook until you run it there. `[prose]` Run `bash scripts/install-git-hooks.sh` once per
checkout. It refuses a commit whose generated `AGENTS.md`/`CLAUDE.md` have drifted from
`rules/`. CI checks the same thing and is not bypassable, so skipping this install is
survivable but slower — the drift surfaces at push time instead of commit time.

## The traps

- **Never `git add -A` or `git commit -a` here.** `[hook]` A blanket stage takes another
  session's in-flight work; it swept 45 foreign files on 2026-09-19. Stage explicit paths,
  and read `git show --stat` before pushing.
- **Re-check the branch immediately before every commit and push.** `[hook]` A parallel
  session can move this worktree onto a different branch mid-task; on 2026-09-19 a commit
  landed on a sibling's `feat/dynamic-type`. `git-guard.sh` refuses a commit or push on a
  branch the session did not start on.
- **Give `git worktree add` an explicit start-point.** `[hook]` Without one it branches from
  the **current HEAD**, so the new worktree starts exactly as stale as this one. Name the
  remote branch: `git worktree add <path> -b <branch> origin/main` (fetch first).
- **Work you cannot isolate is not yours to commit.** `[prose]` When a change is woven into
  another session's uncommitted files — adjacent hunks, or a shared untracked file — surface
  the entanglement and let Jesse pick the scope instead of guessing or sweeping unrelated
  work in. When the tree is merely dirty, isolate yours in its own worktree/branch so it
  stays cleanly committable, and offer to commit each finished feature rather than letting
  changes pile up.
- **"My change isn't showing / the app looks outdated" = you built the wrong worktree**, or
  Xcode is open on one. `[prose]` Every worktree builds the same bundle id `Jesse.BlockParty`,
  so installing any of them overwrites the app on the sim — whichever you built **last**
  wins. Confirm the active project path before building, and quit stray Xcode windows on
  sibling worktrees; the tell-tale that Xcode still has one open is its
  `BlockParty.xcodeproj/xcuserdata` getting rewritten. Run `session_show_defaults` before an
  XcodeBuildMCP build so the tool compiles the checkout you actually edited.
- **`feat/upcoming-personal-insights` predates the Hygge→BlockParty folder rename.**
  `[prose]` It still exists on origin and needs a re-port, not a blind merge.
- **Two merge-conflict conventions**, settled in the 2026-08-19 integration pass: `[prose]`
  brand-asset PNG conflicts resolve to the Aug-12 lowercase "bp" render, and pbxproj
  test-registration conflicts resolve as the **union of both sides**.

Every `[hook]` guard above (and `sim-guard.sh`, `token-guard.sh` in the other leaves) honours
`BP_GUARD_OFF=1` as an escape hatch — set it and say why when a guard is genuinely wrong for
what you're doing, not just when it's inconvenient. `[prose]`
