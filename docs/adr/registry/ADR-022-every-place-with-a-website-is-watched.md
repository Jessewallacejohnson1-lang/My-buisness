# ADR-022 — Every place with a website is watched, approved in one batch

**Status:** Accepted
**Date:** 2026-10-15
**Decided by:** Jesse, 2026-10-13 to 2026-10-15, in the watch-every-place plan (BP app
`docs/plans/watch-every-place`, SPEC and ticket 06).
**Amends:** [ADR-011](ADR-011-tiers-and-cadences.md) (watched places are promoted one at a
time), [ADR-019](ADR-019-a-town-is-its-zip-codes.md) and
[ADR-021](ADR-021-found-events-are-events.md) (in-town events only).

## Context

ADR-011 made `watched` the tier that publishes, and promoted each entry to it by hand. By
2026-10-13 that had produced 25 watched places out of 494, and the Town feed showed almost
nothing from the places themselves. Reading a page every morning costs nearly nothing when
nothing changed: the runner compares each page with yesterday's fingerprint and only a
changed page reaches a model (ADR-009's runner, ticket 05's morning job). So the cost of
watching a quiet place is a fetch, and the cost of not watching a busy one is a missed
trivia night.

## Decision

**Every place with a readable website is watched, approved by Jesse in one batch.** A
page picker (`find_calendars.py --pick`) chooses up to three pages per place, in this
order: its calendar feed, its news feed, its events page, a specials or news page, else its
homepage. A calendar feed stands in for the events page it feeds. Jesse sees every place and
its pages on one approval page, opens any of them and unticks the ones he doesn't trust; his
approval is the per-place review ADR-011 asked for, given in one sitting
(`find_calendars.py --promote` applies it). A site that blocks bots, won't load or reads
blank stays `listed` and is named. A place whose pages sit on a watched place's website, or
repeat another place's pages, starts unticked so nothing is read twice.

**Each morning, two models read only what changed.** A cheap model flags candidate Events
and News on each changed page; the better model judges the flags (drops junk, Event or
News, size, interest, sure or unsure). Something you can go to at a time and a place is an
Event in the event list; everything else is News for the Town feed.

**An RSS feed is read like a page.** iCal feeds go to the feed reader with exact dates and
never to a model. An RSS or Atom feed is a place's posts, mostly marketing on a business's
blog, so the judge has to sort it like any page; the runner renders its items as dated
blocks, which keeps the dates a plain text cut used to lose. This amends the spec's
"feeds never go to a model" line, which assumed a feed reader for RSS that never existed.

**A page seen for the first time only gets its starting copy.** Its fingerprint is saved
and nothing is read, so a batch of newly watched places doesn't send hundreds of pages to
the model on one morning (Jesse, 2026-10-15). Events already sitting on a new page are
picked up the first time the page changes. Clearing a page's fingerprint by hand still
forces a read.

**The Town feed's area is wider than the town's ZIP codes** (Jesse, 2026-10-14): besides
events in St. Joseph's ZIP codes it carries every CSB/SJU event, high school games played
within 20 miles, and any event a St. Joseph source posts wherever it happens, marked with
its town. ADR-019 still decides which file a *place* belongs in; this widens which *events*
the feed shows, and lifts ADR-021's in-town-only rule.

## Consequences

- St. Joseph goes from 25 watched places to 234 (Jesse approved 212 on 2026-10-15; three were left
  listed after the noise check: a Vrbo rental listing, a parked domain and a site behind a
  Cloudflare bot check). Most are
  shops and trades whose pages rarely change, so a normal morning still reads dozens of
  pages, not hundreds.
- 71 places with a website stay `listed` because their sites can't be read; the approval
  page names why. Pages built by JavaScript wait for Apify (ADR-020).
- A business blog post can reach the judge. The judge drops what isn't news to a neighbour;
  if junk gets through, tighten the judge's instructions rather than unwatch the place.
- New towns follow the same three steps: pick, approve on one page, promote.
