# ADR-002 — The md files own what and how; the database owns runtime state

**Status:** Accepted
**Date:** 2026-09-22

## Context

There are two kinds of information about a source, and they have opposite lifecycles.
One kind is editorial and changes rarely: which places matter, which URL to read, how
to read it, how much to trust it, what is weird about the site. The other kind changes
every single run: when it was last checked, what it hashed to, what error it returned.

Putting both in the same place ruins whichever place is chosen. Runtime state in git
produces a commit every morning and a diff nobody reads. Editorial content in a database
means the "why is this source here" answer lives somewhere with no history and no review.

## Decision

**`sources/*.md` owns WHAT and HOW.** Places, URLs, method, trust, quirks. Edited by
Jesse or by an agent. **Never written by a script.**

**The Supabase `sources` table owns RUNTIME STATE.** `last_checked`, `last_hash`,
`last_error`. Written only by a runner.

**Sync is one-way, md → DB, at the start of every run.** Where the two disagree on a
registry field, the md wins and overwrites the DB.

## Consequences

- Registry changes get code review and a git history. "Why is this source here" is
  answerable in two years by reading the commit.
- Editing a registry field directly in the database is pointless — the next run
  overwrites it. The md is the only place worth editing.
- A script that writes a hash, a timestamp or an error into an md file is a bug, not a
  shortcut.
- Deleting a row from the DB loses only cached state; the next run rebuilds it from the
  md. Losing the md would lose the registry itself, so it is the thing that must be
  backed up by being in git.
