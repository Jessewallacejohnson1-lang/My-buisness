# ADR-004 — The registry lives at the repo root, and other repos link to it

**Status:** Accepted
**Date:** 2026-09-22

## Context

Block Party is more than one codebase: the iOS app, the Android app, the waitlist site.
All of them care about which local sources exist. Each one keeping its own copy
guarantees three registries that disagree within a month, and no way to tell which is
current.

Burying the registry inside a platform folder would also make it look like an iOS
implementation detail, which it is not — it is product data about a town.

## Decision

**The registry lives at the repo root, in `sources/`.** One copy, not per-platform.

The Android repo's `CLAUDE.md` and the waitlist repo's `CLAUDE.md` **link here** rather
than restating the format or duplicating the files.

## Consequences

- One place to edit, one place to review, one git history.
- A change to the registry is visible to every platform at once.
- The link between repos is a convention, not a build-time dependency: nothing breaks
  if a repo forgets, but its agents will be working from stale instructions. Anyone
  adding a new Block Party repo should add the link on day one.
