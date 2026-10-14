# ADR-018 — When two sightings are one place

**Status:** Accepted
**Date:** 2026-10-02
**Depends on:** [ADR-010](ADR-010-completeness-is-the-goal.md),
[ADR-017](ADR-017-a-place-is-the-organisation.md)

## Context

ADR-010 parked place dedupe until discovery reached it, to be settled rather than
improvised. The 2026-10-02 St. Joseph run reached it: six sources named the same places
differently ("Coborn's" and "Coborn's Grocery Store", "Bo-Diddley's" and "Bo Diddley's
Deli", "KIA Insurance Inc" and "Insurance Advisors: St. Joseph"). About seventy pairs were
settled by hand that day, and Jesse confirmed every call.

The two failures are not equal. A missed duplicate shows one place twice, which is
visible and cheap to fix. A wrong merge silently deletes a real place from the town,
which is the failure ADR-010 exists to prevent.

## Decision

Two sightings are merged automatically only when one of these holds:

- their names are the same once spelling, punctuation and filler words are folded away;
- they share a phone number, their names share a distinctive word, and their street
  addresses don't disagree;
- they share a street number and street, and their names clearly overlap.

A phone alone was the first draft of this rule and failed on the first run (2026-10-04):
city hall's number also answers for police, fire and three parks, one owner's number
covers a storage yard, a laundromat and a gravel pit, and two Kwik Trips share the
corporate line. A phone number from a stale directory never counts, because numbers get
reassigned. And a merge is checked against every known-distinct pair in both groups, so a
bare "Kwik Trip" sitting beside two stores cannot chain them together.

Everything less certain goes on a **same place?** list for Jesse. A pair he settles is
saved: as `aka` on the entry when it is one place, or as a known-distinct pair when it is
two. Either way it is never asked again.

## Consequences

- Discovery will show some places twice until Jesse settles them. That is the intended
  side to err on.
- The settled pairs grow into a per-town memory, so each run asks fewer questions.
- Two businesses run by one person under similar names can still share a phone and a
  word. When one turns up, the pair is recorded as known-distinct and stays apart.
