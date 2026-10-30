# ADR-020 — Social pages are read through Apify, on purpose

**Status:** Accepted
**Amended 2026-10-18 (Jesse):** a place's Facebook **cover photo** is treated like a photo
from its own website: it can be shown as the place's picture before the place says yes,
credited to its page and taken down on request, like every place photo. Its file is
downloaded from Facebook's image server right after the Apify read, under this same
exception. Posts, their photos and their words still wait for the place's yes.
**Amended 2026-10-22 (Jesse, in a grilling session on how often to read social pages):**
- **Budget.** Jesse is on Apify's $19-a-month plan, so "free monthly credit only, never
  upgraded" below no longer holds: the budget is the monthly cap set in Apify, whatever
  `social.py spend` reports. It was the plan's $19; Jesse raised it to $25 on 2026-10-28 (the
  plan's $19 of credit stays, so up to $6 is overage). Scheduled checks run on their own within
  it. One-off jobs (a Google Maps pass, logo fetches) still show their price first. Each morning
  report carries one line ("Apify: $X of $25"), with a heads-up at $15 and at the cap. There is
  no automatic slowdown; Jesse decides what to change.
- **What a check costs, measured 2026-10-22.** The posts scrapers bill every page they
  check, new posts or not: a page with nothing new still writes a `no_items` or
  `not_available` row, billed as a post. That is about 0.5¢ per Facebook page and 0.23¢ per
  Instagram account per check, so frequency is budgeted per page per check, not per post.
- **Schedule.** A busy list (26 places that post events, town pages included, approved by
  Jesse on 2026-10-22: 24 Facebook pages and 13 Instagram accounts) is checked at 6pm and
  9pm Chicago time; every other place on Thursday at 3pm. Both Facebook and Instagram are
  checked where a place has both. Each check asks only for posts since the last one. The
  busy list's Facebook Events tabs are read weekly, and public town groups weekly for tips.
  Estimated $19 a month with real page counts (busy list $9.40, everyone else weekly $8.50,
  Events tabs about $1); a noon check was dropped because it took the total to about $24.
  If the cap is hit early, Jesse rethinks the schedule. Checking every 15 minutes was priced
  at about $590 a month and dropped.
- **Route.** A Claude routine like the 6am job, "Block Party social watch", starts the
  checks and reads them right away (`sources/models/social.md`, `sources/scripts/social.py`):
  each post goes through the morning job's own cheap-model flags, judge and writer, so the
  title, place, merging and trust rules are the same for every source. Not Make.com (weighed
  and skipped, as a second place for the logic that cannot be tested here), and not a
  Supabase function calling the Anthropic API (first approved, then dropped the same day:
  Jesse, "Yes, run the social watch as a routine like the 6am job", because it would have
  rewritten or skipped the writer's rules). The routine reaches Apify with `APIFY_TOKEN` in
  its cloud environment and runs on Jesse's Claude plan.
- **Finding pages.** One Apify Google Maps pass per town, with its contact-details add-on,
  refreshes and fills places' Facebook and Instagram links. The naming rule below (same
  phone or street, or a link to the place's own website) still decides.
- **Hidden pages stay unread.** Pages Facebook shows only to signed-in viewers (bars'
  21+ pages, pages the owner limited, deleted pages behind an old link) come back
  `not_available`. A search of Apify's store found that every tool that reads them signs in
  with a real account's login cookies; the no-login rule stands. These places are reached
  through a refreshed link, their Instagram or website, and are first in line for Meta's
  official connection.
- **Profile pictures.** A place's own Facebook or Instagram profile picture may become its
  logo where it has none, treated like the cover photo above.
- **Keep everything.** From social posts, every item a neighbour could know or do is kept:
  events as Events, and specials, deals, new products, menu items, pre-orders and contests as
  News (category `business`), shown to the people who care rather than dropped (Jesse: "we
  kind of want everything"). Only posts with nothing to know or do, things already over, and
  posts about a private person's health or troubles are dropped (`sources/models/social.md`).
  Still facts in Block Party's words with a link to the post: the post itself waits for the
  place's yes.
**Amended 2026-10-26 (Jesse):** when a post's caption is short or gives no time, the check
reads the words on the post's pictures too: Obbink's Oct 29 trivia night was on its picture
alone, and the caption-only read dropped it as a teaser. The pictures are downloaded from
Meta's image servers at the addresses Apify already returned (no extra Apify cost), read for
their facts like the caption, and deleted with the check's scratch folder: never shown,
uploaded or kept, so "posts, their photos and their words still wait for the place's yes"
stands. Each check reports what the pictures cost on the Claude plan
(`sources/models/social.md`).
**Amended 2026-10-29 (Jesse):** photos in a school team's own Facebook page's posts (rocorihoops,
ROCORI boys' basketball) may show as event photos on that team's event cards, before the team
says yes: credited to the post and taken down on request, like a photo from a place's website.
The page is read through Apify like any other, each photo is picked by eye and saved to Block
Party's storage (BP app `docs/plans/event-photos`). Every other page's posts, their photos and
their words still wait for the place's yes.
**Amended again 2026-10-29 (Jesse, "Yes to all"):** the same holds for a school club's or program's own
page (its theatre, choir, band, dance team, knowledge bowl): its posts' photos may show on its own events'
cards, credited and taken down on request.
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
