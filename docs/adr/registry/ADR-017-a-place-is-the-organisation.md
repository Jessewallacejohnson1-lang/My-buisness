# ADR-017 — A place is the organisation, not the building

**Status:** Accepted
**Date:** 2026-10-02
**Depends on:** [ADR-007](ADR-007-entry-format-and-additive-schema.md),
[ADR-008](ADR-008-status-lifecycle-and-who-sets-it.md)

## Context

The 2026-10-02 St. Joseph verification found the same spots under different names across
the years, for different reasons:

- Central MN Credit Union became Magnifi Financial: the same credit union, renamed.
- Loso's Main Street Pub became The Middy: new owners running the same bar.
- Holiday became Circle K: a different company at the same gas station.
- Game Day Athletic became BSN Sports: bought by another company.

An entry can follow the organisation or the building, and the choice decides whether an
entry's history, notes and approvals carry over. ADR-007 already says an entry's id never
changes when a business renames or moves, which only makes sense if the entry is the
organisation.

## Decision

**An entry is the organisation.** When the same organisation takes a new name, the entry
keeps its id, takes the new name, and keeps the old one in `aka`. When a different
organisation takes over the spot, it is a **successor**: it gets a new entry, and the old
entry is proposed for retirement with a note naming the successor.

So Magnifi Financial stays one entry. The Middy, Circle K and BSN Sports are new entries,
and the places they replaced are retired.

## Consequences

- An approval given to an organisation does not pass to whoever moves into its building
  next. A successor is reviewed like any new place.
- Telling a rename from a successor needs evidence about ownership, not just the sign. When
  verification cannot tell, the verdict is Unknown and the place goes to the outreach list.
- Retiring stays Jesse's call (ADR-008): verification proposes it, with the successor named.
