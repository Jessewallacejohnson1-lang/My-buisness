# ADR-016 — Google can show that a place exists; another source has to name it

**Status:** Accepted
**Date:** 2026-10-02
**Depends on:** [ADR-001](ADR-001-daily-routine-and-trust-tiers.md),
[ADR-010](ADR-010-completeness-is-the-goal.md)

## Context

On 2026-10-02 a category-by-category sweep of Google Maps (through Composio search) found
about ninety open St. Joseph places that no other source had: OpenStreetMap, Overture,
joetown.org, the chamber and an old town directory had all missed them. Google is the
most complete list of what exists, exactly as ADR-010 predicted.

ADR-001 allows only `place_id` to persist from Google. ADR-010 lets discovery use Google to
learn that a place exists. A registry entry needs a name, and copying that name out of a
Google answer is the thing ADR-001 forbids.

## Decision

**A place that only Google knows about does not enter the registry until a non-Google
source confirms it.** Confirmation comes from Overture, OpenStreetMap, the Minnesota
Secretary of State, a town directory or chamber page, or the place's own website or social
page. The entry's name and address are taken from that source, never from Google.

Until then the place stays on the discovery run's working list, outside the town file.

Google may also be used to check whether a known place is still open. A "permanently
closed" flag is a fact about status. The verdict is recorded; Google's text is not.

## Consequences

- Some real places wait outside the registry: the ones whose only footprint is a Google
  listing. Those go to the list of places to confirm by phone or in person.
- An entry's name can differ slightly from what Google shows, because it comes from the
  confirming source.
- Discovery can use Google freely to find candidates, so coverage is measured against the
  most complete count available, as ADR-010 requires.
