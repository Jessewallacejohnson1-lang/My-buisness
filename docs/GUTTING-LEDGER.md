# Gutting Ledger

A running record of what is being stripped out of the Block Party iOS app, why, and what
replaced it. This file exists so the removals are recoverable knowledge without keeping them
in an agent's working context. **Do not read this file as background.** Open it only when
someone asks what was removed, asks to restore something, or asks why a surface is gone.

Started 2026-09-17 on branch `integration/block-party`.

---

## Round 1 — 2026-09-17

Direction from Jesse: a deep gut of the app's surfaces. The Today tab becomes essentially
blank except the profile picture; two tabs disappear entirely; the map moves from a tab to a
button on Today.

### Today tab — remove

| Surface | Notes |
| --- | --- |
| "JoeTown" header at the top of Today | The colorful script wordmark in the top bar |
| Daily Almanac | The dated greeting block — "Evening on the block, Jesse.", weather line, sunrise/sunset, trash pickup, civic line |
| Your Day | The horizon/scrub card, including the "Nothing posted for today yet." rail |
| Spotlight | The weekly spotlight card |
| The card under Spotlight | Whatever module follows Spotlight in the feed order |
| The text at the bottom | The sign-off / caught-up footer copy |

**Keep:** the profile picture. Everything else on Today goes.

### Tabs — remove

| Tab | Disposition |
| --- | --- |
| Activities | Delete completely. Nothing in it is kept. |
| Calendar | Delete. The *calendar visual style* may be wanted again later — the style is worth remembering, the tab is not. |
| Map | Not deleted — relocated. See below. |

### Map — relocate

The map stops being its own tab. It becomes a **translucent white map button in the top-right
corner of the Today tab**. Tapping it opens the map.

### Deliberately preserved elsewhere

- Uncommitted "Your Day" rail work from the retired main checkout was committed as `f8567eb`
  on branch `worktree-agent-a0a9d032f65fb52bb` before that checkout was deleted. Removing Your
  Day here does not destroy that branch.
- Everything removed in this round remains in git history on `integration/block-party` and its
  ancestors. Recovery is `git log --diff-filter=D --name-only` plus a checkout of the parent
  commit.

---

## Recovering something from a round

1. Find the commit that removed it: `git log --oneline --diff-filter=D -- <path>`
2. Restore the file at its last living state: `git checkout <commit>^ -- <path>`
3. Re-register it if it is a **test** file — the test target uses an explicit source list in
   `project.pbxproj` (4 entries), so a restored test file does not run until it is added back.
   App-target sources under `BlockParty/` are file-system synchronized and need no registration.
