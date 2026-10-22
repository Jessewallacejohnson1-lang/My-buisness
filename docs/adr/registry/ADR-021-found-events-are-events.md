# ADR-021 — Found events are events: one list, reviewed first, merged only when certain

**Status:** Accepted; its in-town-events-only rule is lifted by
[ADR-022](ADR-022-every-place-with-a-website-is-watched.md).
**Date:** 2026-10-06
**Decided by:** Jesse, 2026-10-06, in a grilling session on events from sources.
**Settles:** the three items in [PARKED.md](PARKED.md): staging, event dedupe, recurring
events.
**Builds on:** [ADR-013](ADR-013-places-and-events-are-separate.md) (places and events are
separate), [ADR-001](ADR-001-daily-routine-and-trust-tiers.md) (trust tiers),
[ADR-020](ADR-020-social-pages-are-read-through-apify.md) (cancellations and tips)

**Amended 2026-10-07:** review is paused. Jesse: "just let them run without my approval for
now." Found events from the official calendars `read_events.py` reads publish as approved the
moment they are read (one mention is enough for an official source, ADR-001). The Review
queue stays and still takes a decline with its reason, but nothing waits in it, so the
two-week 1-in-20 measurement below is not running. Turning review back on is one word in
`read_events.py` (`approved` back to `pending`).

**Amended 2026-10-22 (Jesse):** events read from places' Facebook and Instagram posts
(ADR-020's schedule) also publish the moment they are read, credited to the post with a
link, and are listed in the Review queue so a wrong one can be declined afterwards. The
point of those checks is same-evening events; waiting for review would defeat it.

## Context

ADR-013 split events from places and left their table, review, dedupe and repeats for
later. Meanwhile the app ships with no real events at all: Daily's Event of the day and
Search's events are DEBUG samples, and the release build hides them. The registry already
fetches the City's three calendar feeds and, since ADR-020, can read places' Facebook
events, but nothing turns either into an event.

The app does have two event-like lists. Club events (`club_events`, 15 live rows) are what
saves, likes, RSVPs, comments, the feed, the map and Daily all hang off. The town board
(`board_items`, 218 live rows) holds fetched news with a staging/published status and a
source, and some earlier sweeps filed events there.

The risk in found events is not trust but reading. A post saying "fish fry this Friday",
written on a Wednesday, read as the wrong Friday sends neighbours to nothing.

## Decision

**A found event is an event, the same kind as a club's.** Neighbours can save, like, RSVP
and comment on it, and it can be Event of the day, whoever announced it. It records where it
came from; a club event records which club posted it.

**Event or news.** An event is something a neighbour can go to, at a time and a place.
Anything else is news, even with dates: a road closure, a new menu. News stays on the town
board and never enters the event list.

**Reviewed first, then automatic.** Every found event first waits for Jesse's yes, on a
review screen inside the app that only his admin account sees: a "Review" row on his own
profile, opening a list in the manner of Instagram's Follow requests (the event, its date,
where it was found; approve or decline; tap to open the source). After two weeks of review,
if fewer than 1 in 20 found events had a wrong date, time, place or title, found events
publish on their own under ADR-001's trust tiers. Otherwise review continues and the
reading is fixed first. Only Jesse approves for now.

**Merged only when certain.** Two mentions are one event when they share the place, start
within an hour of each other and share title words. Every mention is kept, and mentions
count toward ADR-001's two-source rule. Pairs short of that stay separate and go to Jesse,
the way the census's same-place list does. A duplicate stays visible; a wrong merge hides a
real event.

**A repeating event is a series.** It is stored once with its rule, and the app shows each
upcoming occurrence. Cancelling an occurrence cancels that date only. A cancellation is
shown, never deleted.

**An event links to a place when one fits.** Otherwise it keeps its address and still
shows; pop-ups and park events matter.

**In-town events only, for now.** Events outside the town's ZIP codes (ADR-019) are not
shown yet. When they are, the limit is events a St. Joseph source announces, within about
20 minutes' drive, marked as another town.

## Consequences

- Club events grow into the one event list. They lack what found events need: a source, a
  cancelled state, a series rule, a real start time (`start_time` is free text like "7pm")
  and an optional place link. Every feed and briefing function also requires a
  `submitted_by` user, which a found event has none of, so a found event written today
  would be hidden everywhere. The migration has to settle both.
- The review screen is app work (a bp-build idea with Instagram's Follow requests as its
  Reference) and the two-week clock starts when it ships, not when reading starts.
- The 1-in-20 bar needs every decline to say what was wrong, or the rate cannot be measured.
- The town board keeps its own staging for news. Its old event-category rows are a cleanup
  question, not a decision made here.
- A single source and a neighbour tip already have rules (ADR-020); this ADR only adds how
  they collapse into one event.
