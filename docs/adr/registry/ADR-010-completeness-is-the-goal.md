# ADR-010 — Completeness is the goal, and discovery proposes at scale

**Status:** Accepted
**Date:** 2026-09-23
**Supersedes:** the "deliberate human work" consequence of
[ADR-001](ADR-001-daily-routine-and-trust-tiers.md), and the blanket "only Jesse sets
`active`" rule of [ADR-008](ADR-008-status-lifecycle-and-who-sets-it.md). Both remain in
force in every other respect.

## Context

ADR-001 bounded coverage at whatever a human had bothered to add, and called that growth
path "deliberate human work". ADR-008 put every promotion to `active` through Jesse, one
entry at a time. At twelve entries both were correct and cost nothing.

They do not survive contact with the actual goal. Measured on 2026-09-23:

| Source | Named places | Notes |
| --- | --- | --- |
| OpenStreetMap (Overpass, town bbox) | 69 of 204 features | free, machine-readable |
| joetown.org/explore | ~50 business links | curated, local |
| St. Joseph Chamber of Commerce | ~35 members, 22 categories | Minnesota chamber, confirmed |
| Google Places | most complete of any | `place_id` is all we may store (ADR-001) |

The union is plausibly 150–200 places. The registry had twelve. At one-at-a-time review,
the bottleneck is not research — an agent can do that — it is a human flipping a status
field a hundred and fifty times.

**The harder number is 33%.** Of the 69 named places OpenStreetMap knows about, 23 carry
a website. Two out of every three places in this town have nothing to fetch. A registry
whose unit is "a URL plus how to read it" can therefore never describe more than a third
of St. Joseph, no matter how diligent anyone is. That is not a backlog. It is the shape
of the town, and the format has to answer for it.

Meanwhile a registry that grows also goes stale. An entry collected once and never
re-checked is served to a neighbour as current when it may be a closed business.

## Decision

**Completeness is the goal, not convenience.** The target is every business,
institution, and public-benefit place in the town — including churches, parks, trails,
the library, the food shelf and city services, not businesses alone. A place with no
website and no social media is still a place a neighbour needs, and its absence from
this registry is a defect rather than a limitation. A hard-to-reach place gets a harder
method, never a quiet omission.

**Coverage is measured against an external count, never against ourselves.** The
question is not "how many entries do we have" but "how many places exist that we do not
have". Discovery reports that difference as a number on every run.

**Freshness is part of correctness.** A stale entry is a wrong entry. Every entry carries
a cadence (ADR-011) and a last-verified date. An entry past its cadence is reported as
stale rather than served silently as current.

**The whitelist principle survives unchanged.** The daily routine still reads only this
registry and still does not crawl or follow links off the listed pages (ADR-001).
Discovery makes the whitelist *bigger*; it does not make it open. Discovery is a separate
job on a separate schedule, and its only output is `proposed` entries.

**Batch approval, bounded by whether an entry can publish.** ADR-008 exists because an
agent could otherwise make a source live and it would start publishing to users with
nobody having looked at it. That risk is entirely about publishing, so the line is drawn
there and not at status:

- An entry that **publishes content** — anything that will put words in front of a
  neighbour — is promoted by Jesse, **one at a time**, exactly as ADR-008 requires.
- An entry that **only asserts a place exists** — a name, a location, a category, a pin
  on a map, with nothing fetched and nothing quoted — may be promoted by Jesse **in
  batches by category**.

In tier terms (ADR-011): `watched` and `submitted` are per-entry; `listed` is batchable.
Agents still may not set `active` in either case. The change is the size of the unit
Jesse approves, not who approves it.

## Consequences

- The registry grows by an order of magnitude, and most of it is inert. A `listed` entry
  costs a row and a quarterly re-check.
- Coverage becomes a figure that can be watched and argued about rather than a feeling.
  It will be embarrassing before it is good, which is the point of measuring it.
- Two thirds of the town cannot be reached by fetching anything. That work is phone
  calls, the farmers' market vendor list, and the chamber — outreach, not engineering.
  No script will close it, and a plan that implies otherwise is lying.
- Batch approval means a category can be waved through with a bad entry inside it. The
  containment is that a `listed` entry publishes nothing, so the worst case is a wrong
  pin on a map rather than a false claim in someone's feed. A wrong pin is cheap to fix
  and visible.
- Discovery will surface the same place under several names across sources. Dedupe is
  the hard part of the build, not fetching, and it is still parked (`PARKED.md`) —
  when discovery reaches it, it gets grilled out and written down rather than improvised.
- Google Places remains the most complete list and remains storable only as `place_id`.
  Discovery may use it to learn that a place exists; details are fetched live at display
  time, as ADR-001 already requires.
