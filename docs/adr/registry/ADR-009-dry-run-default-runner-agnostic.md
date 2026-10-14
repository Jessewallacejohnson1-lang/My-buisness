# ADR-009 — Dry-run is the default; the registry is runner-agnostic

**Status:** Accepted
**Date:** 2026-09-22

## Context

The runner fetches real websites and writes to a production database. Those two things
have very different blast radii, and the dangerous default is the one where testing a
change quietly mutates prod. This matters most when an agent is driving, because an
agent will happily run the command it was given.

Where the routine executes is also not settled. Today it is a script on a Mac. Later it
is likely Amplify plus the Claude Agent SDK. If the registry format encodes anything
about the current runner, the move rewrites the registry.

## Decision

**Runners default to dry-run.** A dry-run fetches for real and writes nothing to
production. **Writing to prod requires an explicit `--write` flag.**

Dry-run output — snapshots and reports — goes to **`.runs/`, which is gitignored**.

**The registry is runner-agnostic.** The md files describe sources, not schedules,
hosts, credentials or execution environments. Nothing in `sources/` assumes a Mac, and
nothing will assume Amplify.

## Consequences

- The worst outcome of a wrong command is wasted fetches, not corrupted production data.
- Dry-runs still cost real requests against small local sites, so scoping flags exist
  and worker counts stay low. Polite beats fast.
- `.runs/` is local and disposable. Anything worth keeping from a run has to be written
  down somewhere else deliberately.
- Moving the routine to Amplify and the Agent SDK is a runner change. The registry comes
  along untouched, which is the whole point.
