# ADR-006 — One file per town, named `<town>-mn.md`

**Status:** Accepted
**Date:** 2026-09-22

## Context

Block Party starts in St. Joseph and is meant to spread across Central Minnesota. A
single registry file for every town would turn into a merge-conflict magnet the moment
two towns are worked on at once, and it makes "what does Block Party know about this
town" an exercise in scrolling.

There is also a specific trap. St. Joseph, Minnesota shares its name with St. Joseph,
Missouri and St. Joseph, Michigan. Both are bigger, and both dominate an unqualified
web search. Any file, search or filename that just says "st-joseph" is an ambiguity
waiting to be resolved wrongly.

## Decision

**One file per town: `sources/<town>-mn.md`.** The **`-mn` suffix is mandatory**, even
when the town name is unambiguous today.

Adding a town means adding a file. Nothing else in the registry is per-town.

## Consequences

- Two people working on two towns never touch the same file.
- The state is visible in the filename, so a St. Joseph Missouri page can never be
  filed under the Minnesota registry by accident without it looking wrong.
- The same discipline extends to searching: any web search for a St. Joseph source
  appends "MN", or the results are the wrong state.
- A validator can enforce the suffix mechanically, and does.
