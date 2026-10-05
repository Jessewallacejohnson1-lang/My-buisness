# ADR-019 — A town is its ZIP codes

**Status:** Accepted
**Date:** 2026-10-02
**Depends on:** [ADR-006](ADR-006-one-file-per-town.md)

## Context

ADR-006 gives each town one file, which needs a rule for which places belong in it. A St.
Joseph mailing address (56374) reaches well into the townships around the city, where
farms, contractors and trades sit on county roads. Saint John's University is a short
drive away and feels like part of town, but its address is Collegeville, 56321. A map
box catches neighbouring towns, and city limits leave out half the people who say they
live in St. Joe.

## Decision

**A town is the set of ZIP codes listed for it.** Every place whose address carries one of
those ZIP codes belongs to that town, the countryside included. A place with a
neighbouring town's ZIP belongs to that town, however close it is. A city with several
ZIP codes lists all of them; where two towns share one, the town named in the address
decides.

## Consequences

- St. Joseph includes the rural 56374 trades and farms, and leaves Saint John's to
  Collegeville when Collegeville gets its own file. Google gives Saint John's buildings a
  St. Joseph 56374 address anyway; the true ZIP wins, so they are listed as not belonging
  to St. Joseph in the town's discovery settings.
- A place cannot appear in two town files, so a regional business with an office in each
  town gets one entry per office.
- The rule depends on addresses carrying a ZIP. A place found without one stays on the
  working list until its address is known.
