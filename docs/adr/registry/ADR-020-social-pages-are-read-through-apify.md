# ADR-020 — Social pages are read through Apify, on purpose

**Status:** Accepted
**Amended 2026-10-18 (Jesse):** a place's Facebook **cover photo** is treated like a photo
from its own website: it can be shown as the place's picture before the place says yes,
credited to its page and taken down on request, like every place photo. Its file is
downloaded from Facebook's image server right after the Apify read, under this same
exception. Posts, their photos and their words still wait for the place's yes.
**Date:** 2026-10-05
**Decided by:** Jesse, 2026-10-05, in a grilling session on how to use Apify. His reason:
live posts from businesses are Block Party's essential feature, and taking them straight
from the places' own Instagram and Facebook removes the friction of posting twice.
**Makes an exception to:** the ban on getting past a block in
[ADR-012](ADR-012-robots-facts-and-feeds.md) and on impersonating a browser in
[ADR-014](ADR-014-a-403-is-slow-down-not-go-away.md), for Facebook and Instagram only.
Everywhere else both bans stand.
**Relates to:** [ADR-001](ADR-001-daily-routine-and-trust-tiers.md) (trust tiers),
[ADR-008](ADR-008-status-lifecycle-and-who-sets-it.md) (who retires),
[ADR-013](ADR-013-places-and-events-are-separate.md),
[ADR-016](ADR-016-google-finds-another-source-names.md)

## Context

Most St. Joseph places speak through Facebook or Instagram, not a website: of 471 places
verified open on 2026-10-05, 101 have no website at all. Verification needs a recent sign
of life from the place's own channel (ADR-016), and the registry exists to hear what places
announce. Both point at social pages.

Facebook, Instagram and Nextdoor all disallow automated reading. Measured 2026-10-05:
each `robots.txt` has `User-agent: *` / `Disallow: /`, and Facebook's and Instagram's add a
notice that automated collection needs their written permission. Until now the registry
treated that like any other block: search snippets only, never the page.

Apify (connected through Composio) runs scrapers that read those pages anyway, using its
own servers and browser-shaped clients. That is the very thing ADR-012 and ADR-014 forbid.
The alternatives were to keep social pages search-only, which leaves the town's main
channel unread, or to read them narrowly for verification only. Jesse chose broad reading,
because a neighbour-facing app that misses what places post is missing its point.

## Decision

**Block Party reads public Facebook and Instagram through Apify**: places' own social
pages, their posts and events, and public town groups. It never logs in. Private groups
are out for now; a logged-in read would hand an account's cookies to Apify and risk that
account, and members posted for members.

**What a place posts is used in two ways.** The facts (an event, a closure, a
cancellation, a temporary closure) are taken from every place. The post itself, photo and
words, is shown as a live post only once that place has said yes. The page's cover photo
is the exception (amended above). A place that says yes
connects through Meta's official connection rather than Apify.

**What neighbours post is a tip, never content.** A town-group post is secondhand
(`squishy` under ADR-001). Block Party keeps the fact and never the person's name, photo
or words, and skips posts about a private person. A tip sends Block Party to check:

- A place closed for good goes on Jesse's retire list with the proof. Nothing changes in
  the app until he retires it (ADR-008 stands).
- An event is shown cancelled as soon as its own channel says so, or when two separate
  people say so.
- A temporary closure follows the same rule as a cancellation, ends on its own date, and
  never changes the place's verdict.

**A social page counts as naming a place** under ADR-016 only when it shows the same phone
or street as the census, or links to the place's own website. A matching name alone is not
enough; the place stays Unknown with a note.

**Apify runs on its free monthly credit only.** The plan is never upgraded. The price is
shown before each run, and any single run over $1 waits for Jesse.

## Consequences

- The no-workaround rule is no longer absolute. Its exception is exactly two sites, and a
  later chat that finds Apify reading Facebook should read this ADR, not undo it.
- Reading social pages can break at any time: Meta changes its pages, Apify actors change
  hands or prices, and an IP gets blocked. A source that stops returning anything has to
  show up as stale (ADR-011), not as a quiet day.
- The free credit bounds the reading. Each post read costs money, so not every place can
  be watched daily. Places that say yes cost nothing, which makes the official connection
  the long-term route and Apify the bridge until then.
- The "say yes" step needs a business screen the app does not have yet, plus a Meta
  developer app and Meta's review. Until it exists, every place gets facts only.
- Private town groups, where most neighbour chatter lives (Happenings of Saint Joseph,
  about 5,600 members, is private), stay unread until a new ADR decides how.
