# ADR-001 — The daily routine reads a whitelist, and trust decides what publishes

**Status:** Accepted
**Date:** 2026-09-22

## Context

Block Party needs to know what is happening in St. Joseph tomorrow. The two obvious
approaches both fail: crawling the open web pulls in noise and scrapes sites nobody
asked us to scrape, and waiting for businesses to submit events means an empty app on
day one.

Local information is also uneven. A cidery's own events page is as close to fact as
this gets. A community Facebook post saying "I heard the market is cancelled" is not.
Treating those two the same either publishes rumours or suppresses real news.

There will also be days when nothing changed anywhere. An app with an empty today
screen reads as broken.

## Decision

A routine runs each morning at 6am and reads a **whitelist** — the sources in this
registry, and nothing else. It does not crawl, and it does not follow links off the
listed pages.

Every source carries a trust tier, and the tier sets the bar for publishing:

- **`official`** — the place's own channel, or a government one. **One mention is
  enough to publish.**
- **`squishy`** — secondhand: a community page, an aggregator, someone else's post.
  **Two or more independent mentions are required.**

Behind the daily pull sits an **evergreen pool**: things that are true most of the
time — standing hours, recurring nights, the trail, the parks. When a day's pull turns
up nothing worth showing, the app draws from the pool rather than showing an empty day.

Google Places is used for lookups, but **only `place_id` is ever stored** — never
names, hours, photos, ratings or reviews, which the Places terms of service forbid
persisting.

## Consequences

- Coverage is bounded by the registry. A place nobody adds is a place Block Party
  cannot see. Adding entries is the growth path, and it is deliberate human work.
- A single `official` source can put something in front of users, so an entry marked
  `official` that is not actually the place's own channel is the expensive mistake.
- Squishy sources rarely publish alone. That is the point; they corroborate.
- The app always has something to show, which means "quiet day" and "the pipeline
  broke" look the same to a user. They must not look the same in the run report.
- Anything from Places beyond `place_id` has to be fetched live at display time.
