# ADR-013 — Places and events are separate things, stored separately

**Status:** Accepted
**Date:** 2026-09-23
**Decided by:** Jesse, 2026-09-23 — "set them separately on database, they will be pulled
back together in town tab on app but they will be pulled separately."
**Relates to:** [ADR-010](ADR-010-completeness-is-the-goal.md),
[ADR-011](ADR-011-tiers-and-cadences.md)

## Context

Discovery's first real run proposed 93 entries, and some of them are not places.
joetown.org/explore lists Joetown Rocks, Rocktoberfest, Shop Small Crawl, Woodfired
Wednesdays and Make & Bake Festival in the same grid as the businesses, so the collector
picked them up as though they were shops.

They are not shops, and the difference is not cosmetic. A place has an address, opening
hours and a lifetime measured in years; you can put a pin on it. An event has a date, it
happens and then it is over, and a pin on it is meaningless in November. Modelling them
as one kind of row means every consumer has to ask "is this the sort of row with a date?"
and the answer leaks into the app, the map and every query.

The registry also already has a third relationship between them: an event is usually
*what a place source produces*. Rocktoberfest is a thing the City's calendar feed
announces. Treating the event as a registry entry of its own would mean the registry both
lists the source and holds its output, which is exactly the boundary ADR-002 draws — the
md files say where to look, the database holds what was found.

## Decision

**Places and events are separate kinds, stored in separate tables.** The app joins them
for display — the Town tab shows a neighbour one view — but they are fetched, stored and
reasoned about separately.

**The registry lists places, not events.** An event does not become a registry entry.
Events arrive from a place's sources, and land in their own table. If discovery finds
something that is an event, it does not go in the town file as a shop.

**Discovery routes, and never drops.** When the collector finds a name that looks like an
event, it writes it to a separate `events.md` draft alongside `proposed.md` rather than
discarding it. The test is a heuristic and heuristics are wrong sometimes, so the failure
mode has to be "a human sees it in the wrong pile", never "it silently disappeared". A
missing place is a defect (ADR-010), and that applies to a place misread as an event.

**Entries may carry `entity: place`**, which is additive (ADR-007) and defaults to
`place` when absent. It exists so a future kind — a trail, a public asset — has somewhere
to say so without a migration.

## Consequences

- The town file stays a list of places, which is what its `tier` model assumes: `watched`,
  `listed` and `submitted` all describe places with sources, not dated occurrences.
- Events need their own table and their own shape — at minimum a title, a time, a place
  it belongs to, and the source that announced it. That table does not exist yet, and
  the staging and dedupe questions around it are still parked (`PARKED.md`). This ADR
  decides the split, not the schema.
- Something like the St. Joseph Farmers' Market is both: a recurring event and, on a
  Friday, effectively a place at the Lake Wobegon trailhead. It stays a place in the
  registry — it has a location and a season — and its Fridays are events it produces.
  Millstream Arts Festival is the same shape.
- The heuristic will misfile things in both directions. "Joetown Rocks" is an event that
  reads like a slogan; "Woodfired Wednesdays" is a recurring night at a specific place.
  Both need a human, which is why they are routed rather than deleted.
