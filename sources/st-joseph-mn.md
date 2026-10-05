---
schema: 1
town: st-joseph-mn
---

<!--
First draft of the St. Joseph registry, 2026-09-22.

Every entry is `status: active` — an agent may not set `active` (ADR-008). Jesse
flips the ones worth watching. Nothing here is fetched until he does.

Each entry also carries a `tier` (ADR-011): `watched` has a URL whose content changes and
is read every run; `listed` just says the place exists and is re-verified quarterly;
`submitted` has no web presence and waits on the owner. Tier decides how promotion works
— `watched` and `submitted` are approved one at a time, `listed` in batches by category
(ADR-010), because a `listed` entry publishes nothing.

This seed set is 10 `watched` to 1 `listed`, which is backwards and only because these
are the thirteen places that were easy to find. Two thirds of St. Joseph has no website
at all, so once discovery runs, `listed` should outnumber `watched` roughly five to one.
If it does not, the registry is still only describing the convenient town (ADR-010).

Every URL below was requested and returned 200 on 2026-09-22 before being written
down. Nothing is guessed. Where a real URL could not be confirmed the entry carries
`url: TODO` instead, which is what keeps this file from scraping a stranger's site
under a local business's name (ADR-007).

No `place_id` on any entry yet: those come from a Google Places lookup, and nothing
else from a Places response may be stored here (ADR-001).

Section headings below are `#` on purpose. The parser matches `^## ` followed by a
yaml fence, so an `#` heading is ignored and a `##` one would be swallowed into the
next entry's name.
-->

# Businesses

## Krewe
```yaml
id: krewe
status: active
tier: watched
category: restaurant
added_by: agent:claude
sources:
  - url: https://krewemn.com/
    kind: website
    method: fetch
    trust: official
  - url: https://www.facebook.com/krewerestaurant/
    kind: facebook
    method: search_snippet
    trust: official
```
Notes: Cajun/Creole, in the 24 North Lofts building on College Ave N. The site is the
menu and hours; day-to-day specials and one-off nights go up on Facebook, which is why
both are listed. Named in the skill's own examples, so treat it as a flagship entry.

## The Local Blend
```yaml
id: local-blend
status: active
tier: watched
category: coffee
added_by: agent:claude
sources:
  - url: https://thelocalblend.net/
    kind: website
    method: fetch
    trust: official
  - url: https://www.facebook.com/thelocalblend/
    kind: facebook
    method: search_snippet
    trust: official
```
Notes: Coffee shop on Minnesota St. Runs live music Fri/Sat and an open mic Tuesdays,
which is real recurring event content. **Quirk:** the site returns HTTP 406 to a
default curl user-agent and 200 to a browser one. If a run reports 406 here, that is
the user-agent, not an outage.

## Bad Habit Brewing
```yaml
id: bad-habit-brewing
status: active
tier: watched
category: brewery
added_by: agent:claude
sources:
  - url: http://www.badhabitbeer.com/events
    kind: website
    method: fetch
    trust: official
```
Notes: Taproom on E Minnesota St with a real events calendar page — trivia, live music,
rentals. **Quirk: the URL is `http`, not `https`, and that is deliberate.** The https
version refuses the connection outright; only http answers. Do not "fix" it to https
without re-testing, and re-check occasionally in case they add a certificate.

## Milk & Honey Ciders
```yaml
id: milk-and-honey-ciders
status: active
tier: watched
category: cidery
added_by: agent:claude
sources:
  - url: https://www.milkandhoneyciders.com/events
    kind: website
    method: fetch
    trust: official
```
Notes: Orchard and cidery on County Road 51, outside the downtown core. Hosts its own
event series, so the events page is the right source rather than the homepage.

## Jupiter Moon Ice Cream
```yaml
id: jupiter-moon
status: active
tier: listed
category: dessert
added_by: agent:claude
sources:
  - url: https://www.jupitermoonicecream.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Two locations, St. Joseph and St. Cloud — anything pulled from here needs
checking for which one it refers to before it becomes a St. Joe posting. No events page
found; the site is flavors and hours, so this is a low-frequency source.

## Flour & Flower Bakery
```yaml
id: flour-and-flower
status: active
tier: submitted
category: bakery
partner: true
added_by: agent:claude
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Partner bakery. **`url: TODO` on purpose** — no URL was confirmed on 2026-09-22,
and a guessed one would point the runner at a stranger's site under the bakery's name
(ADR-007). Confirm the real page (site, or Instagram/Facebook if that is where they
actually post) before this is activated; an active entry may not carry a TODO url.

# School

## Kennedy Community School
```yaml
id: kennedy-community-school
status: active
tier: watched
aka:
  - Kennedy Elementary
category: school
added_by: agent:claude
sources:
  - url: https://kennedy.isd742.org/calendar
    kind: website
    method: search_snippet
    trust: official
  - url: https://kennedy.isd742.org/kennedy-news
    kind: website
    method: search_snippet
    trust: official
```
Notes: PK-8, part of St. Cloud Area School District 742, and the only K-12 school in
town — so this is the whole "School" category for St. Joe. Calendar and news are split
across two pages and both matter: concerts and conferences land on the calendar, closings
and announcements on the news page.

**Both are `search_snippet`, not `fetch`, and that is not optional.** The first dry-run
on 2026-09-22 came back `robots.txt disallows` for both URLs. A plain curl returns 200
because it ignores robots; the runner reads it and refuses. Do not switch these back to
`fetch` — the fix for a robots refusal is search_snippet, never a workaround (ADR-001).

## College of Saint Benedict
```yaml
id: csb
status: active
tier: watched
category: college
added_by: agent:claude
sources:
  - url: https://www.csbsju.edu/calendar/
    kind: website
    method: search_snippet
    trust: official
```
Notes: CSB is IN St. Joseph — it is the largest thing in town and a lot of public
events (Benedicta Arts Center shows, lectures, athletics) are open to neighbours.
**Caveat before activating:** this calendar is the joint CSB+SJU feed, and SJU is in
Collegeville, not St. Joseph. Entries will need filtering by campus or this becomes a
Collegeville event firehose in a St. Joe app.

**`search_snippet`, not `fetch`:** csbsju.edu's robots.txt disallows automated fetching,
confirmed by the 2026-09-22 dry-run.

# City

## City of St. Joseph
```yaml
id: city-of-st-joseph
status: active
tier: watched
category: gov
added_by: agent:claude
sources:
  - url: https://www.stjosephmn.gov/common/modules/iCalendar/iCalendar.aspx?catID=25&feed=calendar
    kind: ical
    method: fetch
    trust: official
  - url: https://www.stjosephmn.gov/RSSFeed.aspx?ModID=58&CID=All-calendar.xml
    kind: rss
    method: fetch
    trust: official
  - url: https://www.stjosephmn.gov/common/modules/iCalendar/iCalendar.aspx?catID=14&feed=calendar
    kind: ical
    method: fetch
    trust: official
```
Notes: Council meetings, public notices, city-run events like Rocktoberfest.

**This entry was `search_snippet` on `calendar.aspx` until 2026-09-23, on the belief that
stjosephmn.gov disallows robots. It does not** — see ADR-012. Its robots.txt blocks
`/admin`, `/search`, `/map` and `/currentevents`, and nothing else; `calendar.aspx` is
allowed and returns HTTP 200. The page itself is still the wrong source, because the
event list is rendered client-side and the HTML is chrome only, which is exactly the
"near-empty shell" case the runner warns about.

The feeds are the right source and are what CivicEngage publishes for this:
`catID=25` is **Community Events** — the neighbour-facing calendar, 6 events on the day
it was wired. The RSS calendar feed carries Rocktoberfest and the school reunion.
`catID=14` is the City calendar, 175 entries, mostly council and board meetings and
office holidays — real, but civic rather than social, so it is listed last. `catID=24`
exists and is empty; it is deliberately not listed.

Always append "MN" to any web search about this source or the results are St. Joseph,
Missouri (ADR-006).

## JoeTown
```yaml
id: joetown
status: active
tier: watched
category: town
added_by: agent:claude
sources:
  - url: https://www.joetown.org/events
    kind: website
    method: fetch
    trust: official
  - url: https://www.joetown.org/explore
    kind: website
    method: fetch
    trust: official
```
Notes: The town's promotional/community site, separate from the city government one.
`/events` is the town-wide calendar; `/explore` is effectively a business directory and
is the best single place to find businesses this registry is still missing.

**Do not confuse this with `joetownmn.com`**, which is a different domain that blocks
robots and must use `search_snippet`. `joetown.org` is a Squarespace site whose robots.txt
lists AI user-agents in the same group as `User-agent: *`, so the standard rules apply
and `fetch` is allowed. Checked 2026-09-22 — re-check if a run ever reports a refusal.

# Vendors and artists

## St. Joseph Farmers' Market
```yaml
id: st-joseph-farmers-market
status: active
tier: watched
category: market
added_by: agent:claude
seasonal: true
sources:
  - url: https://www.stjosephfarmersmarket.com/
    kind: website
    method: fetch
    trust: official
  - url: https://www.stjosephfarmersmarket.com/vendors
    kind: website
    method: fetch
    trust: official
```
Notes: Fridays, roughly May through mid-October, at the Lake Wobegon Trailhead. The
`/vendors` page is the single best list of local makers in town — produce, pottery,
soap, baked goods — so it is both an event source and the lead list for future
vendor/artist entries. **Seasonal:** expect it to go quiet from late October, which is
not breakage; `status: paused` is the right call over winter rather than chasing errors.

## Millstream Arts Festival
```yaml
id: millstream-arts-festival
status: active
tier: watched
category: festival
added_by: agent:claude
seasonal: true
sources:
  - url: https://www.millstreamartsfestival.org/
    kind: website
    method: fetch
    trust: official
```
Notes: Juried outdoor art show in downtown St. Joe, last Sunday in August. One day a
year, but it is the town's biggest arts event and its artist roster is a ready-made
list of regional makers. Site is dormant most of the year — a long run of "unchanged"
is the expected result, not a fault.

## Individual vendors and artists
```yaml
id: individual-vendors
status: active
tier: submitted
category: vendors
added_by: agent:claude
sources:
  - url: TODO
    kind: website
    method: submission
    trust: squishy
```
Notes: **Placeholder, and deliberately a TODO.** Individual makers mostly have no
website — they live on Instagram, inside the farmers' market vendor list, or nowhere
online at all. No URL is recorded because none was confirmed, and inventing one would
point the scraper at a stranger's site under a local artist's name (ADR-007).

The honest path is `method: submission`: artists tell Block Party directly. Work the
`/vendors` page and the Millstream roster above into real named entries as they are
confirmed one at a time. This entry exists to hold the category open, and cannot be
activated as-is — an active entry may not carry a TODO url.


# Discovered places — batch-approved 2026-09-24

<!--
Jesse approved every one of these in a single batch on 2026-09-24: "all are in".
That is the batch promotion ADR-010 allows, and it is safe because every entry here is
`tier: listed` — a pin on the map, nothing fetched, nothing published. An entry only
starts putting words in front of a neighbour when it is promoted to `tier: watched`,
and that crosses the publishing line, so it stays a per-entry decision (ADR-010/011).

Sources: OpenStreetMap, joetown.org/explore, and the St. Joseph Chamber member
directory. Roughly half carry `url: TODO` because the place has no website at all —
that is the town, not a gap in the harvest (ADR-010).
-->

## AMS Tax and Accounting Solutions
```yaml
id: accounting-ams-solutions-tax
status: active
tier: listed
category: banking-finance
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from stjosephchamber.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## American Burger Bar
```yaml
id: american-bar-burger
status: active
tier: listed
category: amenity=restaurant
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56394, -94.28999. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## American Legion Post 328
```yaml
id: 328-american-legion-post
status: active
tier: listed
added_by: agent:discover
sources:
  - url: https://stjoelegion.weebly.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Amy Hedtke State Farm
```yaml
id: amy-farm-hedtke-state
status: active
tier: listed
category: insurance
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from stjosephchamber.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Bank Vista
```yaml
id: bank-vista
status: active
tier: listed
category: banking-finance
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from stjosephchamber.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Bello Cucina
```yaml
id: bello-cucina
status: active
tier: listed
category: amenity=restaurant
added_by: agent:discover
sources:
  - url: http://bellocucina.com/st-joseph/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56496, -94.31764. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Benedicta Arts Center
```yaml
id: arts-benedicta-center
status: active
tier: listed
category: amenity=arts_centre
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.55921, -94.32159. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Bo-Diddley's
```yaml
id: bo-diddleys
status: active
tier: listed
category: amenity=fast_food
added_by: agent:discover
sources:
  - url: https://www.bodiddleysdeli.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56522, -94.31836. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Brenny Transportation
```yaml
id: brenny-transportation
status: active
tier: listed
category: transportation-logistics
added_by: agent:discover
sources:
  - url: https://brennytransportation.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from stjosephchamber.com, www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Bruno Press
```yaml
id: bruno-press
status: active
tier: listed
added_by: agent:discover
sources:
  - url: https://www.mcbrunopress.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## CSB Athletic Activities
```yaml
id: activities-athletic-csb
status: active
tier: listed
added_by: agent:discover
sources:
  - url: https://gobennies.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## CSB Events and Catering
```yaml
id: catering-csb-events
status: active
tier: listed
added_by: agent:discover
sources:
  - url: https://www.csbsju.edu/csb-events-and-catering/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Casey's General Store
```yaml
id: caseys-general-store
status: active
tier: listed
category: amenity=fuel
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56680, -94.31022. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Centennial Park
```yaml
id: centennial-park
status: active
tier: listed
category: leisure=park
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56699, -94.32363. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Central MN Realty
```yaml
id: central-mn-realty
status: active
tier: listed
added_by: agent:discover
sources:
  - url: https://www.centralmnrealty.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## China One
```yaml
id: china-one
status: active
tier: listed
category: amenity=restaurant
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56689, -94.30753. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Christine R Panek CPA
```yaml
id: christine-cpa-panek-r
status: active
tier: listed
category: banking-finance
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from stjosephchamber.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Clemens
```yaml
id: clemens
status: active
tier: listed
category: amenity=cafe
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56053, -94.32132. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Clemens Library
```yaml
id: clemens-library
status: active
tier: listed
category: amenity=library
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56036, -94.32088. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Coborn's
```yaml
id: coborns
status: active
tier: listed
category: shop=supermarket
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56811, -94.29717. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Coborn's Liquor
```yaml
id: coborns-liquor
status: active
tier: listed
category: shop=alcohol
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56839, -94.29711. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Consumer Directions
```yaml
id: consumer-directions
status: active
tier: listed
added_by: agent:discover
sources:
  - url: https://consumerdirections.info/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Daisy A Day
```yaml
id: daisy-day
status: active
tier: listed
category: shop=florist
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56824, -94.31916. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Dollar General
```yaml
id: dollar-general
status: active
tier: listed
category: shop=variety_store
added_by: agent:discover
sources:
  - url: https://www.dollargeneral.com/store-directory/mn/saint-joseph/25416
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56853, -94.30881. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Edward Jones
```yaml
id: edward-jones
status: active
tier: listed
category: office=financial_advisor
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56705, -94.31936. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Evenson Decker P.A.
```yaml
id: decker-evenson-p
status: active
tier: listed
category: banking-finance
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from stjosephchamber.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Floor to Ceiling
```yaml
id: ceiling-floor-to
status: active
tier: listed
added_by: agent:discover
sources:
  - url: https://www.floortoceilingmn.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Floral Arts Inc.
```yaml
id: arts-floral
status: active
tier: listed
category: arts-entertainment
added_by: agent:discover
sources:
  - url: https://floralartsmn.com/?srsltid=AfmBOoq5tXNFg4SB4RQvVAGiwVCr3qyx_jk1bQcqOcP1_G_oD-z7RDIT
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from stjosephchamber.com, www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Gary's Pizza
```yaml
id: garys-pizza
status: active
tier: listed
category: amenity=fast_food
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56507, -94.31828. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Golden Hour Tanning
```yaml
id: golden-hour-tanning
status: active
tier: listed
category: hospitality-tourism
added_by: agent:discover
sources:
  - url: https://www.goldenhourtanning.org/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from stjosephchamber.com, www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Groundsman LLC
```yaml
id: groundsman
status: active
tier: listed
category: construction-contractors
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from stjosephchamber.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Hansen & Company Woodworks
```yaml
id: hansen-woodworks
status: active
tier: listed
added_by: agent:discover
sources:
  - url: https://hcowoodworks.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Hedtke Insurance
```yaml
id: hedtke-insurance
status: active
tier: listed
added_by: agent:discover
sources:
  - url: https://www.statefarm.com/agent/us/mn/saint-joseph/amy-hedtke-8jzc2b342al
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Holiday
```yaml
id: holiday
status: active
tier: listed
category: amenity=fuel
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56807, -94.31814. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Hometown Title
```yaml
id: hometown-title
status: active
tier: listed
category: home-services
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from stjosephchamber.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Hudson & Co
```yaml
id: hudson
status: active
tier: listed
category: shop=gift
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56484, -94.31817. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Jolie Olie's Sweet Shoppe
```yaml
id: jolie-olies-shoppe-sweet
status: active
tier: listed
category: shop=bakery
added_by: agent:discover
sources:
  - url: https://www.jolieolies.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56506, -94.31790. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Justina Massage
```yaml
id: justina-massage
status: active
tier: listed
category: shop=massage
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56454, -94.31962. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## KPower Yoga
```yaml
id: kpower-yoga
status: active
tier: listed
added_by: agent:discover
sources:
  - url: https://kpoweryogastudio.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Kay's Kitchen
```yaml
id: kays-kitchen
status: active
tier: listed
category: amenity=restaurant
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56795, -94.31925. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Kensington Bank
```yaml
id: bank-kensington
status: active
tier: listed
category: banking-finance
added_by: agent:discover
sources:
  - url: https://www.kensington.bank/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from stjosephchamber.com, www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Klinefelter Park
```yaml
id: klinefelter-park
status: active
tier: listed
category: leisure=park
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.55721, -94.30302. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Kwik Trip
```yaml
id: kwik-trip
status: active
tier: listed
category: amenity=fuel
added_by: agent:discover
sources:
  - url: https://www.kwiktrip.com/locator/store?id=147
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56700, -94.32239. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## La Jam
```yaml
id: jam-la
status: active
tier: listed
added_by: agent:discover
sources:
  - url: http://laplayettebar.com/service/calendar/view_event/15996
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Lee's Ace Hardware
```yaml
id: ace-hardware-lees
status: active
tier: listed
category: shop=hardware
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56805, -94.31450. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Little Free Library
```yaml
id: free-library-little
status: active
tier: listed
category: amenity=public_bookcase
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56497, -94.31715. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Little Saints Academy
```yaml
id: academy-little-saints
status: active
tier: listed
category: education-training
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from stjosephchamber.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Magnifi Financial
```yaml
id: financial-magnifi
status: active
tier: listed
category: amenity=bank
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56872, -94.30007. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Mary and Tom Darnall Ampitheater
```yaml
id: ampitheater-darnall-mary-tom
status: active
tier: listed
category: amenity=theatre
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.55981, -94.32105. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## McDonald's
```yaml
id: mcdonalds
status: active
tier: listed
category: amenity=fast_food
added_by: agent:discover
sources:
  - url: https://www.mcdonalds.com/us/en-us/location/mn/st-joseph/1180-e-elm-street/35317.html
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56805, -94.30118. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Memorial Park
```yaml
id: memorial-park
status: active
tier: listed
category: leisure=park
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56532, -94.32355. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Midcontinent Communications
```yaml
id: communications-midcontinent
status: active
tier: listed
category: it-technology
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from stjosephchamber.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Millstream Park
```yaml
id: millstream-park
status: active
tier: listed
added_by: agent:discover
sources:
  - url: https://www.cityofstjoseph.com/Facilities/Facility/Details/6
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Minnesota Street Market
```yaml
id: market-minnesota-street
status: active
tier: listed
category: shop=greengrocer
added_by: agent:discover
sources:
  - url: https://mnstreetmarket.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm, www.joetown.org. Mapped at 45.56463, -94.31911. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Newsleaders of St. Joseph and Sartell-St. Stephen
```yaml
id: joseph-newsleaders-of-sartell-st-st-step
status: active
tier: listed
category: advertising-marketing
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from stjosephchamber.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Nichols WD
```yaml
id: nichols-wd
status: active
tier: listed
category: advertising-marketing
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from stjosephchamber.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Northland Park
```yaml
id: northland-park
status: active
tier: listed
category: leisure=park
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.57285, -94.31153. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## O'Reilly Auto Parts
```yaml
id: auto-oreilly-parts
status: active
tier: listed
category: shop=car_parts
added_by: agent:discover
sources:
  - url: https://locations.oreillyauto.com/mn/saintjoseph/autoparts-5771.html
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56874, -94.30113. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Obbink Distillery
```yaml
id: distillery-obbink
status: active
tier: listed
added_by: agent:discover
sources:
  - url: https://www.obbinkdistilling.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Ocean Tobacco
```yaml
id: ocean-tobacco
status: active
tier: listed
category: shop=tobacco
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56799, -94.31383. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Omann Insurance Agency, LLC
```yaml
id: agency-insurance-omann
status: active
tier: listed
category: business-services
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from stjosephchamber.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Pavlov Media
```yaml
id: media-pavlov
status: active
tier: listed
category: uncategorized
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from stjosephchamber.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Pierce Agency Inc.
```yaml
id: agency-pierce
status: active
tier: listed
category: insurance
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from stjosephchamber.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Pierce Insurance
```yaml
id: insurance-pierce
status: active
tier: listed
added_by: agent:discover
sources:
  - url: https://www.pierceinsurance.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## River of Life Church
```yaml
id: church-life-of-river
status: active
tier: listed
category: nonprofits-charities
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from stjosephchamber.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Rock for Alzheimers
```yaml
id: alzheimers-for-rock
status: active
tier: listed
added_by: agent:discover
sources:
  - url: https://www.rock4alz.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Rodeway Inn
```yaml
id: inn-rodeway
status: active
tier: listed
category: tourism=motel
added_by: agent:discover
sources:
  - url: https://www.choicehotels.com/minnesota/st-cloud/country-inn-suites-hotels
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56464, -94.29214. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## SERVPRO Team Hickman
```yaml
id: hickman-servpro-team
status: active
tier: listed
category: construction-contractors
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from stjosephchamber.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## SJU Athletic Activities
```yaml
id: activities-athletic-sju
status: active
tier: listed
added_by: agent:discover
sources:
  - url: https://gojohnnies.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Sacred Heart Chapel
```yaml
id: chapel-heart-sacred
status: active
tier: listed
category: amenity=place_of_worship
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56313, -94.31892. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Saint Joeseph Government Building
```yaml
id: building-government-joeseph-st
status: active
tier: listed
category: office=government
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56179, -94.31603. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Saint Joseph Fire Department
```yaml
id: department-fire-joseph-st
status: active
tier: listed
category: amenity=fire_station
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56621, -94.31090. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Saint Joseph Meat Market
```yaml
id: joseph-market-meat-st
status: active
tier: listed
category: shop=butcher
added_by: agent:discover
sources:
  - url: https://stjosephmeatmarket.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm, www.joetown.org. Mapped at 45.56529, -94.31973. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Saint Joseph Park & Ride
```yaml
id: joseph-park-ride-st
status: active
tier: listed
category: amenity=parking
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56131, -94.33454. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Saint Joseph Police Department
```yaml
id: department-joseph-police-st
status: active
tier: listed
category: amenity=police
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56173, -94.31605. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Saint Joseph Post Office
```yaml
id: joseph-office-post-st
status: active
tier: listed
category: amenity=post_office
added_by: agent:discover
sources:
  - url: https://tools.usps.com/locations/details/1380378
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56564, -94.32153. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Sal's Bar and Grill
```yaml
id: bar-grill-sals
status: active
tier: listed
category: amenity=bar
added_by: agent:discover
sources:
  - url: https://salsbarstjoe.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm, stjosephchamber.com, www.joetown.org. Mapped at 45.56454, -94.32060. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Sisters of the Order of Saint Benedict
```yaml
id: benedict-of-of-order-sisters-st
status: active
tier: listed
category: nonprofits-charities
added_by: agent:discover
sources:
  - url: https://sbm.osb.org/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from stjosephchamber.com, www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Speedway
```yaml
id: speedway
status: active
tier: listed
category: shop=convenience
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56730, -94.32002. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## St Joseph Off-Sale Liquor
```yaml
id: joseph-liquor-off-sale-st
status: active
tier: listed
category: shop=alcohol
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56802, -94.31309. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## St Jospeh’s Church
```yaml
id: church-jospehs-st
status: active
tier: listed
category: amenity=place_of_worship
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56410, -94.31887. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## St. Cloud Area Chamber of Commerce
```yaml
id: area-chamber-cloud-commerce-of-st
status: active
tier: listed
category: business-services
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from stjosephchamber.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## St. Joseph Health & Wellness
```yaml
id: health-joseph-st-wellness
status: active
tier: listed
added_by: agent:discover
sources:
  - url: https://stjoewellness.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## St. Joseph Joes
```yaml
id: joes-joseph-st
status: active
tier: listed
added_by: agent:discover
sources:
  - url: https://www.facebook.com/stjosephjoes/?ref=py_c
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## St. Joseph Vet Clinic
```yaml
id: clinic-joseph-st-vet
status: active
tier: listed
category: amenity=veterinary
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56492, -94.29403. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Stearns Electric Association
```yaml
id: association-electric-stearns
status: active
tier: listed
category: professional-services
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from stjosephchamber.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Stearns History Museum
```yaml
id: history-museum-stearns
status: active
tier: listed
category: nonprofits-charities
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from stjosephchamber.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Subway
```yaml
id: subway
status: active
tier: listed
category: amenity=fast_food
added_by: agent:discover
sources:
  - url: https://restaurants.subway.com/united-states/mn/st-joseph/217-nw-county-rd
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56811, -94.32049. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Sunny Mary Meadow
```yaml
id: mary-meadow-sunny
status: active
tier: listed
added_by: agent:discover
sources:
  - url: https://sunnymarymeadow.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Taco John's
```yaml
id: johns-taco
status: active
tier: listed
category: amenity=fast_food
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56811, -94.32009. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## The Estates Bed & Breakfast
```yaml
id: bed-breakfast-estates
status: active
tier: listed
category: tourism=guest_house
added_by: agent:discover
sources:
  - url: https://www.estatesbedandbreakfast.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm, www.joetown.org. Mapped at 45.56510, -94.31650. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## The House
```yaml
id: house
status: active
tier: listed
category: amenity=restaurant
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56414, -94.32192. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## The House Food & Tap
```yaml
id: food-house-tap
status: active
tier: listed
added_by: agent:discover
sources:
  - url: https://www.thehousefoodandtap.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## The La Playette
```yaml
id: la-playette
status: active
tier: listed
added_by: agent:discover
sources:
  - url: http://laplayettebar.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## The Middy
```yaml
id: middy
status: active
tier: listed
category: amenity=pub
added_by: agent:discover
sources:
  - url: https://visitstcloud.com/dine/the-middy/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm, www.joetown.org. Mapped at 45.56472, -94.31871. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## The Wandering Cow
```yaml
id: cow-wandering
status: active
tier: listed
category: amenity=ice_cream
added_by: agent:discover
sources:
  - url: https://wanderingcowmn.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm, www.joetown.org. Mapped at 45.56515, -94.31794. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Thomsen’s Garden Center
```yaml
id: center-garden-thomsens
status: active
tier: listed
category: agriculture-farming
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from stjosephchamber.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Tiremaxx/Mid-State Wholesale Tire
```yaml
id: mid-state-tire-tiremaxx-wholesale
status: active
tier: listed
category: automotive
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from stjosephchamber.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Trobec’s Bus Service
```yaml
id: bus-service-trobecs
status: active
tier: listed
added_by: agent:discover
sources:
  - url: https://www.trobecsbus.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Uptown Styles Hair Salon
```yaml
id: hair-salon-styles-uptown
status: active
tier: listed
category: shop=hairdresser
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from osm. Mapped at 45.56455, -94.31949. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Urban Oasis
```yaml
id: oasis-urban
status: active
tier: listed
added_by: agent:discover
sources:
  - url: https://www.vrbo.com/4757153?dateless=true
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Wacosa
```yaml
id: wacosa
status: active
tier: listed
category: nonprofits-charities
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from stjosephchamber.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Well & Company
```yaml
id: well
status: active
tier: listed
added_by: agent:discover
sources:
  - url: https://wellandcomn.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## White Peony Boutique
```yaml
id: boutique-peony-white
status: active
tier: listed
added_by: agent:discover
sources:
  - url: https://whitepeonyboutique.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Williams Dingmann Funeral Homes
```yaml
id: dingmann-funeral-homes-williams
status: active
tier: listed
category: funeral-homes
added_by: agent:discover
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from stjosephchamber.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Woodcrest of Country Manor
```yaml
id: country-manor-of-woodcrest
status: active
tier: listed
category: healthcare-medical
added_by: agent:discover
sources:
  - url: https://www.woodcrestofcountrymanor.org/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from stjosephchamber.com, www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## W|R Home Company
```yaml
id: home-r-w
status: active
tier: listed
added_by: agent:discover
sources:
  - url: https://www.weatheredrevivals.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed by discovery on 2026-09-24 from www.joetown.org. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## 24 North: Lofts on College Avenue
```yaml
id: 24-north-lofts-on-college-avenue
status: proposed
tier: listed
category: "historic_site"
place_type: "Business"
address: "24 N College Ave"
phone: "+13202573992"
added_by: agent:town-verify
sources:
  - url: https://www.svngcre.com/apartments/24-north-lofts
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.94). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## 2nd Avenue Cuts
```yaml
id: 2nd-avenue-cuts
status: proposed
tier: listed
place_type: "Business"
address: "17 2nd Ave NW"
phone: "3207611089"
added_by: agent:town-verify
sources:
  - url: http://www.2ndavecuts.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## 7 Hills Staurolites
```yaml
id: 7-hills-staurolites
status: proposed
tier: listed
category: "hardware_home_and_garden_store"
place_type: "Business"
address: "115 9th Ave SE"
phone: "+17632600737"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: 7 Hills Jewelry Company LLC was filed July 2025 and is active at this exact address; also in recent Overture map data.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Adam McArthur Agency LLC
```yaml
id: adam-mcarthur-agency
status: proposed
tier: listed
category: "financial_service"
place_type: "Business"
address: "15 E Minnesota St Ste 105A"
phone: "+13202519144"
added_by: agent:town-verify
sources:
  - url: https://www.amfam.com/agents/minnesota/saint-joseph/adam-mcarthur
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Adara Home Health
```yaml
id: adara-home-health
status: proposed
tier: listed
category: "medical_service"
place_type: "Business"
address: "710 County Road 75 E Suite 104"
phone: "+13202551882"
added_by: agent:town-verify
sources:
  - url: https://adarahomehealth.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.66). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Alderink Custom Landscaping
```yaml
id: alderink-custom-landscaping
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: http://www.youryardmn.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed. Named by its own website, http://www.youryardmn.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## All Occasion Floral and Gifts
```yaml
id: all-occasion-floral-gifts
status: proposed
tier: listed
category: "flowers_and_gifts_store"
place_type: "Business"
address: "38 E Birch St"
phone: "3202532298"
added_by: agent:town-verify
sources:
  - url: http://www.saukrapidsflorist.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Amcon Block & Precast
```yaml
id: amcon-block-precast
status: proposed
tier: listed
category: "hardware_home_and_garden_store"
place_type: "Business"
address: "8644 Ridgewood Rd"
phone: "+13203630905"
added_by: agent:town-verify
sources:
  - url: http://www.amconblock.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Overture lists it open (confidence 0.66). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## American Manufacturing Co Group
```yaml
id: american-manufacturing-group
status: proposed
tier: listed
category: "technical_service"
place_type: "Business"
address: "736 19th Ave NE"
phone: "13203637273"
aka: ["American Manufacturing Inc"]
added_by: agent:town-verify
sources:
  - url: https://www.american-manufacturing.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 9 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## American Technology Group
```yaml
id: american-technology-group
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://americantechnologygroup.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Named by its own website, https://americantechnologygroup.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## AMI
```yaml
id: ami
status: proposed
tier: listed
place_type: "Business"
address: "30865 Kohler Court"
phone: "(320) 363-4650"
added_by: agent:town-verify
sources:
  - url: http://www.amiauction.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. Verified 2026-10-02: Live site amiauction.com shows the St. Joseph address and RV inventory photos dated 2025-2026.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Ami Auction
```yaml
id: ami-auction
status: proposed
tier: listed
category: "specialty_store"
place_type: "Business"
address: "30865 Kohler Ct"
phone: "13203634650"
added_by: agent:town-verify
sources:
  - url: https://www.amiauction.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Amplified Electric
```yaml
id: amplified-electric
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://www.amplified-electric.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Named by its own website, https://www.amplified-electric.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Ams Electric, Inc.
```yaml
id: ams-electric
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-05: MapQuest lists Ams Electric Inc at the same County Road 51 address; no closure sign found.. Named by MapQuest listing (Ams Electric Inc, 14317 County Road 51, Saint Joseph, phone 320-290-1792) (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Amy Johnson Realty
```yaml
id: amy-johnson-realty
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://amyjohnsonrealty.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed. Named by its own website, https://amyjohnsonrealty.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Anfinson Thompson & Company, Pa
```yaml
id: anfinson-thompson-pa
status: proposed
tier: listed
category: "financial_service"
place_type: "Business"
address: "710 County Road 75 E  Ste 102"
phone: "13204412989"
added_by: agent:town-verify
sources:
  - url: https://anfinsonthompson.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-02: Firm's live website lists the St. Joseph office with staff and current phone.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Angela Larcom Counseling
```yaml
id: angela-larcom-counseling
status: proposed
tier: listed
category: "behavioral_or_mental_health_clinic"
place_type: "Business"
address: "1511 E Minnesota St"
phone: "+13202603471"
added_by: agent:town-verify
sources:
  - url: http://www.angelalarcomcounseling.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Closed · Opens 8 AM Mon). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Angel's Touch Massage
```yaml
id: angels-touch-massage
status: proposed
tier: listed
category: "wellness_service"
place_type: "Business"
address: "1511 E Minnesota St"
phone: "+13203637460"
added_by: agent:town-verify
sources:
  - url: http://www.angelstouchmassagemn.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 4 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Anne Renee Bridal Co.
```yaml
id: anne-renee-bridal
status: proposed
tier: listed
category: "fashion_and_apparel_store"
place_type: "Business"
address: "33 1st Ave NW"
phone: "+13205570034"
added_by: agent:town-verify
sources:
  - url: https://linktr.ee/annereneebridalco
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Annette Auer Massage
```yaml
id: annette-auer-massage
status: proposed
tier: listed
category: "wellness_service"
place_type: "Business"
phone: "+13204930375"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Google listing still open (Sept 2026 snapshot, newest review Jan 2024) and her LinkedIn, crawled Sept 2026, shows her as current owner at 1511 E Minnesota St; soft evidence, no 2025-26 review.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Arlington Place of St Joseph
```yaml
id: arlington-place-of-st-joseph
status: proposed
tier: listed
category: "senior_living_facility"
place_type: "Business"
address: "21 16th Ave SE"
phone: "+13203631313"
aka: ["Arlington Place Assisted Living"]
added_by: agent:town-verify
sources:
  - url: http://www.arlingtonplacemn.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open 24 hours). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Armor Animal Health
```yaml
id: armor-animal-health
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://www.armoranimalhealth.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed. Named by its own website, https://www.armoranimalhealth.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Artisan Renovation & Design
```yaml
id: artisan-renovation-design
status: proposed
tier: listed
category: "building_or_construction_service"
place_type: "Business"
address: "34788 95th Ave"
phone: "+13202491005"
added_by: agent:town-verify
sources:
  - url: http://www.artisanrd.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Artistic Stone & Concrete
```yaml
id: artistic-stone-concrete
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: http://www.artisticstoneandconcrete.com/contact/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Named by its own website, http://www.artisticstoneandconcrete.com/contact/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Asphalt Surface Technologies Corp
```yaml
id: asphalt-surface-technologies
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://www.astechmn.com/contact
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 4:30 AM Sat). Named by its own website, https://www.astechmn.com/contact (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Astech Corp
```yaml
id: astech
status: proposed
tier: listed
category: "b2b_service"
place_type: "Business"
address: "8348 Ridgewood Rd"
phone: "3203638500"
added_by: agent:town-verify
sources:
  - url: http://www.astechmn.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Overture lists it open (confidence 0.85). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Audio Video Extremes
```yaml
id: audio-video-extremes
status: proposed
tier: listed
category: "electronics_store"
place_type: "Business"
address: "718 19th Ave NE"
phone: "+13202175877"
added_by: agent:town-verify
sources:
  - url: http://audiovideoextremes.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Auto Body 2000
```yaml
id: auto-body-2000
status: proposed
tier: listed
category: "automotive_service"
place_type: "Business"
address: "611 19th Ave NE"
phone: "+13203631116"
aka: ["Autobody 2000 Inc"]
added_by: agent:town-verify
sources:
  - url: http://autobody2011161494-422835.hibustudio.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5:30 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Auto Color & Industrial Supply
```yaml
id: auto-color-industrial-supply
status: proposed
tier: listed
category: "vehicle_parts_store"
place_type: "Business"
address: "718 19th Ave NE"
phone: "3203631055"
added_by: agent:town-verify
sources:
  - url: http://www.autocolor.cc/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Avon Ag-Lime
```yaml
id: avon-ag-lime
status: proposed
tier: listed
place_type: "Business"
address: "13266 Collegeville Road"
phone: "(320) 363-7915"
added_by: agent:town-verify
sources:
  - url: http://www.avonaglime.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. Verified 2026-10-02: MN SOS assumed name 'Avon Ag Lime' (Huls Bros Trucking) active, renewed 4/29/2026 at this address; old avonaglime.com domain no longer resolves.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Baldwin Supply Company - St Cloud
```yaml
id: baldwin-supply-st-cloud
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: http://www.baldwinsupply.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Named by its own website, http://www.baldwinsupply.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## The Barn
```yaml
id: barn
status: proposed
tier: listed
category: "farm"
place_type: "Business"
address: "30233 Lilac Rd"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Overture lists it open (confidence 0.54). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Barrett’s Music
```yaml
id: barretts-music
status: proposed
tier: listed
category: "books_music_and_video_store"
place_type: "Business"
address: "708 Elm St E"
added_by: agent:town-verify
sources:
  - url: https://barrettsmusic.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.75). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## BDH Service & Performance Inc.
```yaml
id: bdh-service-performance
status: proposed
tier: listed
category: "professional_service"
place_type: "Business"
address: "7402 Ridgewood Rd"
phone: "+13204920545"
added_by: agent:town-verify
sources:
  - url: http://bdhservice.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Bee Line Auto & Sport
```yaml
id: bee-line-auto-sport
status: proposed
tier: listed
category: "auto_dealer"
place_type: "Business"
address: "8805 Ridgewood Ct"
phone: "+13203631270"
added_by: agent:town-verify
sources:
  - url: https://www.beelineautoandsport.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Best-Way Fabricating
```yaml
id: best-way-fabricating
status: proposed
tier: listed
category: "supplier_or_distributor"
place_type: "Business"
address: "710 15th Avenue"
phone: "3203634600"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Google Maps lists it, not closed (Closed · Opens 6 AM Mon). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Better Design Enterprises LLC
```yaml
id: better-design-enterprises
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: http://www.latchblocker.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Named by its own website, http://www.latchblocker.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Beumer Outdoors
```yaml
id: beumer-outdoors
status: proposed
tier: listed
place_type: "Business"
address: "15517 Fruit Farm Road"
phone: "(320) 356-2252"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: BBB profile shows it active with no closure; same Beumer family farm runs Collegeville Orchards, open for the 2026 season.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Birchwood Electric, Security and Home Technology
```yaml
id: birchwood-electric-security-home-technol
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "8551 County Road 75"
phone: "(320) 363-8228"
added_by: agent:town-verify
sources:
  - url: http://www.birchwoodstandard.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Birdie’s Pizza & Garden Bar
```yaml
id: birdies-pizza-garden-bar
status: proposed
tier: listed
category: "restaurant"
place_type: "Business"
address: "13 2nd Ave NW"
phone: "+13202823492"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## BL Grafx
```yaml
id: bl-grafx
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "126 16th Ave SE"
phone: "+13202004893"
added_by: agent:town-verify
sources:
  - url: http://blgrafx.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 7 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Bliss Direct Media
```yaml
id: bliss-direct-media
status: proposed
tier: listed
category: "professional_service"
place_type: "Business"
address: "641 15th Ave NE"
phone: "13202711600"
added_by: agent:town-verify
sources:
  - url: https://www.blissdirect.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 4:30 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## The Bloom Room
```yaml
id: bloom-room
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://www.sunnymarymeadow.com/bloomroom
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed. Named by its own website, https://www.sunnymarymeadow.com/bloomroom (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

##  Bloom Styling & Events
```yaml
id: bloom-styling-events
status: proposed
tier: listed
place_type: "Business"
address: "St Joseph"
phone: "+13202916307"
aka: [" Bloom Styling & Events"]
added_by: agent:town-verify
sources:
  - url: https://www.bloomstyledevents.com/photobooth
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-02: Bloom Styling & Events website (copyright 2026) says it is based in St. Joseph and offers The Bloom Booth DSLR photo booth; nominated best new business 2026.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Blush Salon
```yaml
id: blush-salon
status: proposed
tier: listed
category: "personal_or_beauty_service"
place_type: "Business"
address: "106 2nd Ave NW"
phone: "+13202678958"
added_by: agent:town-verify
sources:
  - url: http://www.blushsalonmn.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 8 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Boulder Ridge Apartments
```yaml
id: boulder-ridge-apartments
status: proposed
tier: listed
category: "historic_site"
place_type: "Business"
address: "535 Northland Dr"
phone: "+13203634900"
added_by: agent:town-verify
sources:
  - url: http://www.boulderridgestjoseph.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Overture lists it open (confidence 0.99). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Breth-zenzen Fire Protection
```yaml
id: breth-zenzen-fire-protection
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "8053 Sterling Dr  Ste 101"
phone: "13203630900"
added_by: agent:town-verify
sources:
  - url: https://brethzenzen.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.75). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Brinkman Excavating LLC
```yaml
id: brinkman-excavating
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-05: BuildZoom and septic-contractor directories list Brinkman Excavating LLC at 13865 287th St, St. Joseph, with an active MN DLI license L3063.. Named by BuildZoom; septicandwell.com (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Brush & Roll Painting & Deck Refinishing
```yaml
id: brush-roll-painting-deck-refinishing
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "206 9th Ave SE"
phone: "3204202625"
added_by: agent:town-verify
sources:
  - url: https://brushandrollpainting.net/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## BSN SPORTS
```yaml
id: bsn-sports
status: proposed
tier: listed
place_type: "Business"
aka: ["Game Day Athletic"]
added_by: agent:town-verify
sources:
  - url: http://www.bsnsports.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 6 PM). Named by its own website, http://www.bsnsports.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Builders Millwork Inc.
```yaml
id: builders-millwork
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://buildersmillworkinc.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Named by its own website, https://buildersmillworkinc.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## C & L Excavating Inc
```yaml
id: c-l-excavating
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "7939 Ridgewood Rd"
phone: "13203631221"
added_by: agent:town-verify
sources:
  - url: https://clexcavating.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-02: Live website clexcavating.com with the same phone (320-363-1221) and St. Joseph address.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Capital Storage Rental of St Joseph
```yaml
id: capital-storage-rental-of-st-joseph
status: proposed
tier: listed
category: "storage_facility"
place_type: "Business"
address: "8850 Ridgewood Ct"
phone: "+13202533488"
added_by: agent:town-verify
sources:
  - url: http://www.capitalstoragerental.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open 24 hours). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Caribou Coffee
```yaml
id: caribou-coffee
status: proposed
tier: listed
category: "coffee_shop"
place_type: "Business"
address: "1500 Elm St E"
phone: "+13203630011"
added_by: agent:town-verify
sources:
  - url: https://locations.cariboucoffee.com/us/mn/st-joseph/1500-elm-st-east
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 7 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Carlson Crossing Townhomes
```yaml
id: carlson-crossing-townhomes
status: proposed
tier: listed
category: "real_estate_service"
place_type: "Business"
address: "912 E Baker St"
phone: "+13205570195"
added_by: agent:town-verify
sources:
  - url: https://brutgerequities.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Overture lists it open (confidence 0.59). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Cedar Street Salon and Spa
```yaml
id: cedar-street-salon-spa
status: proposed
tier: listed
category: "personal_or_beauty_service"
place_type: "Business"
address: "235 Cedar St E"
phone: "+13203630200"
added_by: agent:town-verify
sources:
  - url: https://www.aveda.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Closed · Opens 9 AM Mon). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Cedar Trails Apartments
```yaml
id: cedar-trails-apartments
status: proposed
tier: listed
place_type: "Business"
address: "133 Cedar Street NW"
phone: "(320) 363-4525"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## CentraCare Clinic - St. Joseph
```yaml
id: centracare-clinic-st-joseph
status: proposed
tier: listed
category: "diagnostics_imaging_or_lab_service"
place_type: "Business"
address: "1360 Elm St E"
phone: "3203637765"
added_by: agent:town-verify
sources:
  - url: http://www.centracare.com/locations/profile/?id=11
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Central Canvas Manufacturing
```yaml
id: central-canvas-manufacturing
status: proposed
tier: listed
category: "manufacturer"
place_type: "Business"
address: "636 19th Ave NE"
phone: "+13203631065"
added_by: agent:town-verify
sources:
  - url: https://wearepoparts.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Overture lists it open (confidence 0.65). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Central Lakes Mutual Insurance Co
```yaml
id: central-lakes-mutual-insurance
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: http://www.clmutual.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Closed · Opens 8 AM Mon). Named by its own website, http://www.clmutual.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Central Minnesota Detailing
```yaml
id: central-minnesota-detailing
status: proposed
tier: listed
category: "automotive_service"
place_type: "Business"
address: "803 21st Ave NE #3"
phone: "+13208030849"
added_by: agent:town-verify
sources:
  - url: https://www.centralminnesotadetailing.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-02: Live paid Wix site with services, phone and staff emails at this address (footer still says 2023).. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Charlie Walker Construction
```yaml
id: charlie-walker-construction
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "8068 Sterling Dr"
phone: "+13203634301"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Chem-Dry of St. Cloud
```yaml
id: chem-dry-of-st-cloud
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "33078 County Rd Ste 2"
phone: "3202529799"
added_by: agent:town-verify
sources:
  - url: http://www.chem-dry.net/stcloud.mn
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-02: Live website chemdryofstcloud.com, current hours and reviews on Yelp/Birdeye at the same address and phone.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Chiropractic Connection, PC
```yaml
id: chiropractic-connection-pc
status: proposed
tier: listed
category: "complementary_and_alternative_medicine"
place_type: "Business"
address: "709 County Road 75"
phone: "+13203634694"
added_by: agent:town-verify
sources:
  - url: http://drschleper.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Closed · Opens 7:30 AM Mon). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## CMS Autobody
```yaml
id: cms-autobody
status: proposed
tier: listed
category: "automotive_service"
place_type: "Business"
address: "109 Cedar St E"
phone: "+13203637575"
aka: ["CMS Auto Body"]
added_by: agent:town-verify
sources:
  - url: https://cmsautobody0.wixsite.com/website
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Cole Papers
```yaml
id: cole-papers
status: proposed
tier: listed
place_type: "Business"
address: "30701 Pearl Drive # 1"
phone: "(320) 251-5312"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Cole Papers' own contact page lists its St. Cloud branch at 30701 Pearl Drive, St. Joseph.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Collegeville Brokerage
```yaml
id: collegeville-brokerage
status: proposed
tier: listed
category: "real_estate_service"
place_type: "Business"
address: "15 E Minnesota St"
phone: "+13203637656"
added_by: agent:town-verify
sources:
  - url: http://www.collegevillebrokerage.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Collegeville Communities Llc
```yaml
id: collegeville-communities
status: proposed
tier: listed
category: "real_estate_service"
place_type: "Business"
address: "24 College Ave N"
added_by: agent:town-verify
sources:
  - url: https://www.collegevillecu.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.95). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Collegeville Orchards
```yaml
id: collegeville-orchards
status: proposed
tier: listed
category: "farm"
place_type: "Business"
address: "15517 Fruit Farm Rd"
phone: "+13203567609"
added_by: agent:town-verify
sources:
  - url: http://collegevilleorchardsmn.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-02: Official website advertises the 2026 season, 10AM-6PM, same phone.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Complete Coverage Rental LLC
```yaml
id: complete-coverage-rental
status: proposed
tier: listed
category: "event_or_party_service"
place_type: "Business"
address: "8274 Delta Cir"
phone: "3204120623"
added_by: agent:town-verify
sources:
  - url: https://completecoveragerental.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 8 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Computer Repair Unlimited
```yaml
id: computer-repair-unlimited
status: proposed
tier: listed
category: "technical_service"
place_type: "Business"
address: "24 W Birch St"
phone: "+13203098645"
added_by: agent:town-verify
sources:
  - url: http://www.computerrepairunlimited.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open now). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Concrete Plus
```yaml
id: concrete-plus
status: proposed
tier: listed
place_type: "Business"
address: "15 W Minnesota Street"
phone: "(320) 363-8866"
added_by: agent:town-verify
sources:
  - url: http://www.concreteplus.info
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. Verified 2026-10-02: Concrete Plus, Inc. active in MN SOS, annual renewal filed 9/28/2026; principal office 15 E Minnesota St.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Cone Castle
```yaml
id: cone-castle
status: proposed
tier: listed
category: "casual_eatery"
place_type: "Business"
address: "118 1st Ave NW"
phone: "(320) 363-4406"
added_by: agent:town-verify
sources:
  - url: http://conecastle.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Contardo Laser Dentistry
```yaml
id: contardo-laser-dentistry
status: proposed
tier: listed
category: "dental_clinic"
place_type: "Business"
address: "26 2nd Ave NW"
phone: "(320) 363-4468"
added_by: agent:town-verify
sources:
  - url: http://www.laserdentistrymn.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Cost Cutters
```yaml
id: cost-cutters
status: proposed
tier: listed
category: "personal_or_beauty_service"
place_type: "Business"
address: "710 Highway 75 E Ste 6, St Joseph Business Center"
phone: "3202714247"
added_by: agent:town-verify
sources:
  - url: http://costcutters.regiscorp.com/salondetail/default.asp?salonid=16700
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Overture lists it open (confidence 0.85). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Crafted Skin Clinic
```yaml
id: crafted-skin-clinic
status: proposed
tier: listed
category: "wellness_service"
place_type: "Business"
address: "15 E Minnesota St #107"
phone: "+13204798500"
added_by: agent:town-verify
sources:
  - url: https://www.craftedskinclinic.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Creamery Lofts
```yaml
id: creamery-lofts
status: proposed
tier: listed
category: "historic_site"
place_type: "Business"
address: "120 2nd Ave NW"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Creations In Candles
```yaml
id: creations-in-candles
status: proposed
tier: listed
category: "flowers_and_gifts_store"
place_type: "Business"
address: "32716 Pamela Ln"
phone: "+13203637557"
added_by: agent:town-verify
sources:
  - url: http://www.creationsincandles.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-02: Creations in Candles, LLC is active with its 2026 annual renewal filed at this address; still listed with Mon-Sat hours.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Creative Custom Building LLC
```yaml
id: creative-custom-building
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-05: BBB lists Creative Custom Builders, LLC in St. Joseph with phone 320-363-7206; MN license BC447879 valid to 2028.. Named by BBB profile (as Creative Custom Builders, LLC); MN contractor license (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Creekwood Acres
```yaml
id: creekwood-acres
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: http://www.floorguy.net/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed. Named by its own website, http://www.floorguy.net/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Curtis Marketing Group
```yaml
id: curtis-marketing-group
status: proposed
tier: listed
place_type: "Business"
address: "38 E Birch Street"
phone: "(320) 363-0210"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Same phone on live curtisgroup.com (dental marketing); site pages updated Sept 2026; now at a rural St. Joseph address.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Custom Vinyl Graphics and Signs
```yaml
id: custom-vinyl-graphics-signs
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-05: Business site is live, lists the same phone and vinyl wrap and sign services; no closure sign.. Named by Own website (customvinylgraphicsandsigns.godaddysites.com, same phone 320-339-4247) (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Cutters Lawn Service
```yaml
id: cutters-lawn-service
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "36271 County Road 2"
phone: "(320) 333-8387"
added_by: agent:town-verify
sources:
  - url: http://www.saintcloudmnlawncare.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.77). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## D R Construction
```yaml
id: d-r-construction
status: proposed
tier: listed
place_type: "Business"
address: "314 Pondview Lane"
phone: "(320) 363-4361"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: DR Construction, LLC is active, renewed 9/14/2026, registered office 314 Pond View Ln E (manager's principal office now listed in Cold Spring).. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Dan DeMark Realtor
```yaml
id: dan-demark-realtor
status: proposed
tier: listed
category: "real_estate_service"
place_type: "Business"
address: "38 E Birch St"
phone: "+13204283124"
added_by: agent:town-verify
sources:
  - url: http://demarkcentralmnhomes.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open 24 hours). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Dancing Bears Company B&B
```yaml
id: dancing-bears-b-b
status: proposed
tier: listed
category: "bed_and_breakfast"
place_type: "Business"
address: "12822 County Road 51"
phone: "(320) 363-7723"
added_by: agent:town-verify
sources:
  - url: http://www.dancingbearscompany.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Dancing Pines Retreat
```yaml
id: dancing-pines-retreat
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-05: Vacation rental in the Avon Hills, Collegeville Township, with two units listed on Vrbo and resellers showing 2026 availability.. Named by Vrbo listings (Dancing Pines Suite and Log Bear Den at Dancing Pines Retreat, St. Joseph) (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Daniel Funeral Home
```yaml
id: daniel-funeral-home
status: proposed
tier: listed
category: "family_service"
place_type: "Business"
address: "120 College Ave S"
phone: "+13203637783"
added_by: agent:town-verify
sources:
  - url: http://www.danielfuneralhome.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Darling Dog Care
```yaml
id: darling-dog-care
status: proposed
tier: listed
category: "animal_or_pet_service"
place_type: "Business"
address: "12463 Co Rd 160"
phone: "+13204910522"
added_by: agent:town-verify
sources:
  - url: http://www.darlingdogcare.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Closed · Opens 3 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Dented K Auto Body
```yaml
id: dented-k-auto-body
status: proposed
tier: listed
place_type: "Business"
address: "33202 County Road 3 (Avon/St. Joseph), MN"
phone: "(320) 363-8697"
aka: ["Dented K Auto Ranch"]
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Same Kaeter family place on County Rd 3 now posts as Dented K Auto Body, with car-restoration posts through Aug 2026.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Deters Accounting and Tax Service
```yaml
id: deters-accounting-tax-service
status: proposed
tier: listed
category: "financial_service"
place_type: "Business"
address: "111 College Ave N Ste 6"
phone: "+13204054741"
added_by: agent:town-verify
sources:
  - url: http://www.deterstax.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Closed · Opens 9 AM Mon). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Diamond Energy Systems
```yaml
id: diamond-energy-systems
status: proposed
tier: listed
category: "hardware_home_and_garden_store"
place_type: "Business"
address: "601 County Road 75 W"
phone: "(320) 363-8338"
added_by: agent:town-verify
sources:
  - url: http://diamondenergysystems.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Diesel Knight Repairs
```yaml
id: diesel-knight-repairs
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://www.dieselknightrepairs.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 7 PM). Named by its own website, https://www.dieselknightrepairs.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## DJ's Flower Bar & Tea
```yaml
id: djs-flower-bar-tea
status: proposed
tier: listed
category: "flowers_and_gifts_store"
place_type: "Business"
address: "38 E Birch St"
phone: "+13203637920"
added_by: agent:town-verify
sources:
  - url: https://www.saukrapidsflorist.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-02: Own website (c) 2026 lists 38 E Birch St with current hours and delivery.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## DKT Auto & Diesel Repair
```yaml
id: dkt-auto-diesel-repair
status: proposed
tier: listed
category: "automotive_service"
place_type: "Business"
address: "545 8th Ave NE"
phone: "+17632503039"
added_by: agent:town-verify
sources:
  - url: http://dktautoanddiesel.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-02: DKT Auto & Diesel Repair LLC formed April 2025 and is active with MN Secretary of State; has an active Facebook page and truck-service listings (its website is currently down).. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Dovetail Design & Remodeling
```yaml
id: dovetail-design-remodeling
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "31820 Cedar Ridge Rd"
phone: "+13205570043"
added_by: agent:town-verify
sources:
  - url: http://www.dovetaildesignremodel.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-02: Live website with 2026 copyright; Dovetail Kitchen Designs, LLC active at this address; CMBA member.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## DPF Alternatives St Joseph MN
```yaml
id: dpf-alternatives-st-joseph-mn
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://dpfalternatives.com/locations/st-joseph-mn
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Named by its own website, https://dpfalternatives.com/locations/st-joseph-mn (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Dr. Lisa Platt
```yaml
id: dr-lisa-platt
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-05: Doximity and WebMD list psychologist Lisa Platt at 15 E Minnesota St #107, St. Joseph; LinkedIn profile updated Aug 2026.. Named by Doximity; WebMD; NPI registry (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Drew's Adjusting Service
```yaml
id: drews-adjusting-service
status: proposed
tier: listed
place_type: "Business"
address: "PO Box 547"
phone: "(320) 363-1342"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Active USDOT record with MCS-150 filed April 2026 and insurance verified Oct 2026; same 363-1342 phone in adjuster listings.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## DSL Saint Joseph
```yaml
id: dsl-st-joseph
status: proposed
tier: listed
place_type: "Business"
address: "21 College Ave N"
phone: "2183034404"
added_by: agent:town-verify
sources:
  - url: http://www.dslsaintjoseph.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.85). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Ehlinger Lawn Service
```yaml
id: ehlinger-lawn-service
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "8232 Delta Cir"
phone: "+13202509337"
added_by: agent:town-verify
sources:
  - url: http://www.EhlingerLawn.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Elite Refrigeration Heating & Air Conditioning
```yaml
id: elite-refrigeration-heating-air-conditio
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "9324 November Dr"
phone: "+13204060864"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Google Maps lists it, not closed (Open 24 hours). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Emerald Companies
```yaml
id: emerald-companies
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "30659 Pearl Dr"
phone: "13202515296"
aka: ["Emerald Lawn Care"]
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Overture lists it open (confidence 0.75). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## EmptyPageStudios
```yaml
id: emptypagestudios
status: proposed
tier: listed
category: "media_service"
place_type: "Business"
address: "602 2nd Ave NE"
phone: "+13204202105"
added_by: agent:town-verify
sources:
  - url: http://www.EmptyPageStudios.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 10 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Exclusive Bat Proofing
```yaml
id: exclusive-bat-proofing
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://www.batproof.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Named by its own website, https://www.batproof.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Executive Express
```yaml
id: executive-express
status: proposed
tier: listed
category: "travel_and_transportation"
place_type: "Business"
address: "1111 Elm St E"
phone: "+13202532226"
added_by: agent:town-verify
sources:
  - url: http://www.ExecutiveExpress.biz/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Exponential Chiropractic Healing Center
```yaml
id: exponential-chiropractic-healing-center
status: proposed
tier: listed
category: "complementary_and_alternative_medicine"
place_type: "Business"
address: "103 N College Ave"
phone: "+13203634573"
added_by: agent:town-verify
sources:
  - url: http://www.jlwchiro.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Closes soon · 1 PM · Opens 9 AM Sat). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Fabral
```yaml
id: fabral
status: proposed
tier: listed
category: "supplier_or_distributor"
place_type: "Business"
address: "600 15th Ave"
phone: "+19295217326"
added_by: agent:town-verify
sources:
  - url: http://www.fabral.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-02: Fabral's own contact page lists the St. Joseph, MN plant among its eight current facilities.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Fieldstone Farm
```yaml
id: fieldstone-farm
status: proposed
tier: listed
category: "sport_or_fitness_facility"
place_type: "Business"
address: "31746 Collegeville Rd"
phone: "+13203630135"
added_by: agent:town-verify
sources:
  - url: http://fieldstonefarmmn.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Fifth Gear Repair
```yaml
id: fifth-gear-repair
status: proposed
tier: listed
place_type: "Business"
address: "8274 Delta Circle"
phone: "(320) 363-7250"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Fifth Gear Repair Inc. is active/in good standing with MN Secretary of State, renewed July 2025, principal office 8274 Delta Circle.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Fine Line Entertainment
```yaml
id: fine-line-entertainment
status: proposed
tier: listed
category: "event_or_party_service"
place_type: "Business"
address: "109 17th Ave SE"
phone: "+13204286064"
added_by: agent:town-verify
sources:
  - url: http://finelineentertainment.net/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Finken Companies
```yaml
id: finken-companies
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "628 19th Ave NE"
phone: "+17634935288"
added_by: agent:town-verify
sources:
  - url: https://www.finkens.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.55). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Five Star Transport Solutions
```yaml
id: five-star-transport-solutions
status: proposed
tier: listed
category: "travel_service"
place_type: "Business"
address: "617 19th Ave NE"
phone: "3204334391"
added_by: agent:town-verify
sources:
  - url: https://www.fivestarlogistics.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Flaten Taxidermy
```yaml
id: flaten-taxidermy
status: proposed
tier: listed
category: "technical_service"
place_type: "Business"
address: "11843 Co Rd 51"
phone: "+13202600441"
added_by: agent:town-verify
sources:
  - url: http://flatentaxidermy.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.58). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Forest Mushrooms
```yaml
id: forest-mushrooms
status: proposed
tier: listed
category: "food_and_beverage_store"
place_type: "Business"
address: "14715 Co Rd 51"
phone: "+13203637956"
added_by: agent:town-verify
sources:
  - url: http://www.forestmushrooms.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-02: Live website with customer reviews dated through September 2026; corporation active at this address.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## FORM Charge
```yaml
id: form-charge
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://www.formcharge.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 4:30 PM). Named by its own website, https://www.formcharge.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Frontgate Inc.
```yaml
id: frontgate
status: proposed
tier: listed
category: "travel_service"
place_type: "Business"
address: "8274 Delta Circle"
phone: "3204334391"
added_by: agent:town-verify
sources:
  - url: https://www.fivestarlogistics.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Full Circle - Photo Booth
```yaml
id: full-circle-photo-booth
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://www.full360mn.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 2 AM). Named by its own website, https://www.full360mn.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Full Circle Water
```yaml
id: full-circle-water
status: proposed
tier: listed
category: "b2b_service"
place_type: "Business"
address: "30801 Pearl Dr"
phone: "3205294035"
aka: ["Avista"]
added_by: agent:town-verify
sources:
  - url: https://fullcirclewater.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 4 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## G & A Builders Inc
```yaml
id: g-builders
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-05: Contractor directory lists G & A Builders Inc as a St. Joseph general building contractor; no closure found.. Named by minnesota.building-us.org (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## A and G Corn Maze
```yaml
id: g-corn-maze
status: proposed
tier: listed
category: "food_and_beverage_store"
place_type: "Business"
address: "10448 345th St"
phone: "+13203210006"
added_by: agent:town-verify
sources:
  - url: https://www.aandgcornmaze.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.96). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Donabauer Taxidermy
```yaml
id: donabauer-taxidermy
status: proposed
tier: listed
place_type: "Business"
address: "910 Dale St"
phone: "(320) 363-8215"
aka: ["Donabauer Taxidermy", "Gary Donabauer Taxidermy"]
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Google Maps listing (via Composio search), same address, open with hours. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Geri's Country Kennels
```yaml
id: geris-country-kennels
status: proposed
tier: listed
category: "animal_or_pet_service"
place_type: "Business"
address: "7704 322nd St"
phone: "+13202400458"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Live website with a 2026 footer, daily hours and the same address and phone.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## GM Drilling
```yaml
id: gm-drilling
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "8914 Ridgewood Ct"
phone: "3203637453"
aka: ["G M Drilling"]
added_by: agent:town-verify
sources:
  - url: https://www.gmdrilling.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Gold Country Trucking
```yaml
id: gold-country-trucking
status: proposed
tier: listed
category: "b2b_transportation_and_storage_service"
place_type: "Business"
address: "7924 Sterling Dr"
phone: "13202710161"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 4 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Golden Hill Doodles
```yaml
id: golden-hill-doodles
status: proposed
tier: listed
category: "animal_or_pet_service"
place_type: "Business"
address: "10474 Norway Rd"
phone: "3202605717"
added_by: agent:town-verify
sources:
  - url: https://goldenhilldoodlesofmn.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 10 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Golden Rule Real Estate
```yaml
id: golden-rule-real-estate
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://www.goldenrulerealestateservices.com/contact-us/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed. Named by its own website, https://www.goldenrulerealestateservices.com/contact-us/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Goodin Company
```yaml
id: goodin
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://www.goodinco.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open now). Named by its own website, https://www.goodinco.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Graceview Estates
```yaml
id: graceview-estates
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://www.inhproperties.com/apartments/mn/st-joseph/graceview-estates/default
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed. Named by its own website, https://www.inhproperties.com/apartments/mn/st-joseph/graceview-estates/default (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Grandview Buildings
```yaml
id: grandview-buildings
status: proposed
tier: listed
category: "hardware_home_and_garden_store"
place_type: "Business"
address: "8850 Ridgewood Ct"
phone: "3203634435"
added_by: agent:town-verify
sources:
  - url: http://grandviewbuildings.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 2 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Granite City Gymnastics
```yaml
id: granite-city-gymnastics
status: proposed
tier: listed
category: "sport_or_fitness_facility"
place_type: "Business"
address: "922 21st Ave NE"
phone: "+13202513547"
added_by: agent:town-verify
sources:
  - url: http://www.granitecitygymnastics.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 1.0). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Granite City Motor Car
```yaml
id: granite-city-motor-car
status: proposed
tier: listed
category: "auto_dealer"
place_type: "Business"
address: "8055 Co Rd 75"
phone: "+13202819007"
added_by: agent:town-verify
sources:
  - url: http://www.granitecitymotorcar.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 6 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Granite City Window Cleaning Inc
```yaml
id: granite-city-window-cleaning
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "Polar Ct"
phone: "3202176319"
added_by: agent:town-verify
sources:
  - url: http://granitecitywindow.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Overture lists it open (confidence 0.85). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Granite Services Llc
```yaml
id: granite-services
status: proposed
tier: listed
category: "supplier_or_distributor"
place_type: "Business"
address: "30736 Pearl Dr"
phone: "13203634640"
added_by: agent:town-verify
sources:
  - url: https://www.graniteservicesllc.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-02: Live website with same phone, St. Joseph chamber member; current listings (Yelp updated March 2026) show it moved down Pearl Drive.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Greg Muehring Construction
```yaml
id: greg-muehring-construction
status: proposed
tier: listed
place_type: "Business"
address: "8821 349th Street"
phone: "(320) 654-9091"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Minnesota residential contractor licenses verified active in March/April 2026; LLC in good standing.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Grilled Cravings & Quality Ice Cream
```yaml
id: grilled-cravings-quality-ice-cream
status: proposed
tier: listed
category: "casual_eatery"
place_type: "Business"
address: "118 1st Ave NW"
phone: "3203634776"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Overture lists it open (confidence 0.96). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Gutter Shutter of St. Cloud
```yaml
id: gutter-shutter-of-st-cloud
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "8856 Ridgewood Ct"
phone: "3205601100"
added_by: agent:town-verify
sources:
  - url: https://www.guttershutterofstcloud.com/?utm_source=yext&utm_medium=local&utm_campaign=yextlisting&y_source=1_NjA1ODM0OTYtNDgzLWxvY2F0aW9uLndlYnNpdGU%3D
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 4:30 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Hair by Hanna
```yaml
id: hair-by-hanna
status: proposed
tier: listed
category: "personal_or_beauty_service"
place_type: "Business"
address: "33 W Minnesota St Ste 101"
phone: "+13204291838"
added_by: agent:town-verify
sources:
  - url: https://www.vagaro.com/hairbyhanna1
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-02: Its Vagaro booking page is active, with service records edited Feb–Mar 2026, at 33 Minnesota St W Unit 101.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Hair By Mel LLC
```yaml
id: hair-by-mel
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://hairbymelllc.square.site/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Named by its own website, https://hairbymelllc.square.site/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## HCo 2.0
```yaml
id: hco-2-0
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://hcowoodworks.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Closed · Opens 8 AM Mon). Named by its own website, https://hcowoodworks.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## HD Specialties LLC
```yaml
id: hd-specialties
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-05: FMCSA lists HD Specialties LLC (USDOT 3554922) in St. Joseph with phone 320-309-3816; directories list shop, mobile repair and towing at 30890 County Road 2.. Named by FMCSA motor-carrier record (USDOT 3554922); autoyas.com (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Hdc Development Co
```yaml
id: hdc-development
status: proposed
tier: listed
category: "building_or_construction_service"
place_type: "Business"
address: "703 19th Ave NE"
phone: "13203634733"
added_by: agent:town-verify
sources:
  - url: https://www.hdcdevelopment.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.65). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Heartland Door Sales Inc
```yaml
id: heartland-door-sales
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "30489 Pearl Dr."
phone: "3203637423"
added_by: agent:town-verify
sources:
  - url: http://heartlanddoorsales.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-02: Own website (c) 2026 with the same address and phone.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Heim-kins Rescued Treasures
```yaml
id: heim-kins-rescued-treasures
status: proposed
tier: listed
category: "second_hand_store"
place_type: "Business"
address: "219 Cedar St E"
phone: "+13202481944"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Heinen Photography
```yaml
id: heinen-photography
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-05: Non-Google directory names Heinen Photography run by Robin Heinen, but at a Rice address with a near-identical phone (393 vs 363); no dated sign of life outside Google, so the address is worth a recheck.. Named by photo-studio.co directory (Heinen Photography, Robin Heinen, but at 9635 Sucker Creek Rd, Rice MN 56367) (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Heirborn Kennels
```yaml
id: heirborn-kennels
status: proposed
tier: listed
category: "animal_or_pet_service"
place_type: "Business"
address: "28982 Kelp Rd"
phone: "+13207615856"
added_by: agent:town-verify
sources:
  - url: http://heirbornkennel.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Her Hair Studio
```yaml
id: her-hair-studio
status: proposed
tier: listed
category: "personal_or_beauty_service"
place_type: "Business"
address: "21 1st Ave NW"
phone: "+13204433899"
added_by: agent:town-verify
sources:
  - url: http://www.herhairstudiomn.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 7 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Hi-tec Electric
```yaml
id: hi-tec-electric
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "833 19th Ave NE"
phone: "13203638808"
added_by: agent:town-verify
sources:
  - url: https://www.hitecelectricstcloud.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 4 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Holistic Flower Farm
```yaml
id: holistic-flower-farm
status: proposed
tier: listed
category: "flowers_and_gifts_store"
place_type: "Business"
address: "33026 Nettle Rd"
added_by: agent:town-verify
sources:
  - url: http://holisticflowerfarm.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-05: Own website is live with a current events page (Mondays at the St. Cloud VA farmers market) and names the Nettle Rd farm.. Named by holisticflowerfarm.com (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Huls Bros Trucking Inc
```yaml
id: huls-bros-trucking
status: proposed
tier: listed
category: "travel_and_transportation"
place_type: "Business"
address: "13266 Collegeville Rd"
phone: "+13203637915"
added_by: agent:town-verify
sources:
  - url: https://hulstrucking.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 10 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## illuminet, LLC
```yaml
id: illuminet
status: proposed
tier: listed
category: "b2b_office_and_professional_service"
place_type: "Business"
address: "38 E Birch St"
phone: "+13203330865"
added_by: agent:town-verify
sources:
  - url: https://myilluminet.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Iman Carrier, Inc.
```yaml
id: iman-carrier
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://safer.fmcsa.dot.gov/query.asp
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Named by its own website, https://safer.fmcsa.dot.gov/query.asp (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Impressions Hair Studio
```yaml
id: impressions-hair-studio
status: proposed
tier: listed
category: "personal_or_beauty_service"
place_type: "Business"
address: "36585 County Road 2"
phone: "+13202529960"
added_by: agent:town-verify
sources:
  - url: http://www.yelp.com/biz/impressions-hair-studio-saint-joseph
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-02: MN Board of Cosmetology lists salon license 1507902 for Impressions Hair Studio at 36585 Co Rd 2 as Active (checked 10/2/2026, ZIP 56374 search).. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Innovative Concrete construction
```yaml
id: innovative-concrete-construction
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "20 3rd Ave SE"
phone: "3204926733"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Insurance Advisors: St. Joseph
```yaml
id: insurance-advisors-st-joseph
status: proposed
tier: listed
place_type: "Business"
address: "26 E Birch St"
phone: "3203630007"
added_by: agent:town-verify
sources:
  - url: http://www.divingrates.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 4:30 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Interstate Bearing Systems
```yaml
id: interstate-bearing-systems
status: proposed
tier: listed
category: "manufacturer"
place_type: "Business"
address: "622 Elm St E"
phone: "+13202550804"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## J.G. Auto Detail
```yaml
id: j-g-auto-detail
status: proposed
tier: listed
category: "automotive_service"
place_type: "Business"
address: "806 Morningside Loop"
phone: "+16128761281"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: JG Auto Detail LLC formed Sept 2024 at this address and is active; current Facebook/Yelp listings and 2025 promotions.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## JR's Mobil & Radiator Repair
```yaml
id: jrs-mobil-radiator-repair
status: proposed
tier: listed
place_type: "Business"
address: "13 2nd Ave NW, St. Joseph, MN 56374"
phone: "(320) 363-7500"
aka: ["J R's Auto Repair"]
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Same address and 363-7500 phone now listed as JR's Mobil & Radiator Repair with weekday hours (Yelp updated Jan 2026).. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Jet Black
```yaml
id: jet-black
status: proposed
tier: listed
place_type: "Business"
address: "30593 Pearl Drive # 5"
phone: "(320) 529-0697"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Jet-Black's current national locations page lists Jet-Black of St. Cloud MN with the same phone 320-529-0697 (street address not shown).. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## JK Monuments LLC*
```yaml
id: jk-monuments
status: proposed
tier: listed
category: "family_service"
place_type: "Business"
address: "34194 83rd Ave"
phone: "3203872350"
added_by: agent:town-verify
sources:
  - url: https://info2851788.wixsite.com/jkmonumentsmn
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Joe's Auto Parts
```yaml
id: joes-auto-parts
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: http://www.joesautowrecking.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Named by its own website, http://www.joesautowrecking.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Joe's Auto Wrecking
```yaml
id: joes-auto-wrecking
status: proposed
tier: listed
place_type: "Business"
address: "8503 320th Street"
phone: "(320) 229-5803"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Live website (Joe's Auto Parts, LLC) shows current hours and phones at 31005 County Road 133, not the 320th Street address in the input.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Joe's Countryside Excavating
```yaml
id: joes-countryside-excavating
status: proposed
tier: listed
place_type: "Business"
address: "9462 Tallow Road"
phone: "(320) 253-6756"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Joe's Countryside LLC active in MN SOS, annual renewal filed 3/19/2026 at 9462 Tallow Rd.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Joetown Apartments
```yaml
id: joetown-apartments
status: proposed
tier: listed
category: "historic_site"
place_type: "Business"
address: "1055 College Ave S"
phone: "+13202586000"
added_by: agent:town-verify
sources:
  - url: https://inhproperties.com/property/joe-town-apartments/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## John Mondloch Remodeling
```yaml
id: john-mondloch-remodeling
status: proposed
tier: listed
place_type: "Business"
address: "8046 Sterling Dr"
phone: "3202591244"
added_by: agent:town-verify
sources:
  - url: http://mondlochremodeling.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.85). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Jon Mueller Roofing
```yaml
id: jon-mueller-roofing
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-05: Jon Mueller Roofing LLC appears in an OSHA/MN DLI inspection record and a business directory at 32672 Meadow Ln with phone 320-493-6259; no closure sign.. Named by OSHA establishment inspection record (Jon Mueller Roofing LLC, MN DLI 2014) and localbusinessfinder411 directory listing with same address and phone (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## K&A Autobody
```yaml
id: k-autobody
status: proposed
tier: listed
category: "automotive_service"
place_type: "Business"
address: "30659 Pearl Dr #2"
phone: "+13202376004"
added_by: agent:town-verify
sources:
  - url: https://www.kandaautobodyshop.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## K & L Lawncare
```yaml
id: k-l-lawncare
status: proposed
tier: listed
place_type: "Business"
address: "11768 280th St"
phone: "3202488839"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Overture lists it open (confidence 0.85). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## K Welz Counseling and Coaching
```yaml
id: k-welz-counseling-coaching
status: proposed
tier: listed
category: "behavioral_or_mental_health_clinic"
place_type: "Business"
address: "1511 E Minnesota St"
phone: "+13202161654"
added_by: agent:town-verify
sources:
  - url: https://kwelz.clientsecure.me/#home
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## KD Performance Horses
```yaml
id: kd-performance-horses
status: proposed
tier: listed
category: "animal_or_pet_service"
place_type: "Business"
address: "12564 County Road 160"
phone: "+13202606519"
added_by: agent:town-verify
sources:
  - url: http://www.kdperformancehorses.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Keltic Konstruction
```yaml
id: keltic-konstruction
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "10213 345th St"
phone: "(320) 492-6609"
added_by: agent:town-verify
sources:
  - url: http://keltickonstruction.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## King of Hearths
```yaml
id: king-of-hearths
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "8646 Ridgewood Rd"
phone: "+13203634671"
added_by: agent:town-verify
sources:
  - url: http://thekingofhearths.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## King's Kennels
```yaml
id: kings-kennels
status: proposed
tier: listed
category: "animal_or_pet_service"
place_type: "Business"
address: "14797 325th St"
phone: "+13202490465"
added_by: agent:town-verify
sources:
  - url: http://www.kingskennelsmn.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-02: Live website taking reservations at same address and phone; Yelp listing updated June 2026.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Klein Builders
```yaml
id: klein-builders
status: proposed
tier: listed
category: "building_or_construction_service"
place_type: "Business"
address: "15703 Fruit Farm Rd"
phone: "+13203567233"
added_by: agent:town-verify
sources:
  - url: http://www.kleinbuildersmn.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 4 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Knife River
```yaml
id: knife-river
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://www.kniferiver.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open now). Named by its own website, https://www.kniferiver.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Kostreba Appliance Services Center
```yaml
id: kostreba-appliance-services-center
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "545 8th Ave NE"
phone: "17633906267"
aka: ["Kostreba Appliance Services Center"]
added_by: agent:town-verify
sources:
  - url: https://omegaforceappliancerepair.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.95). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Kraft Mechanical St Cloud
```yaml
id: kraft-mechanical-st-cloud
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://www.kraftcm.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 4 PM). Named by its own website, https://www.kraftcm.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Kwik Trip #575
```yaml
id: kwik-trip-575
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://www.kwiktrip.com/locator/store
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open 24 hours). Named by its own website, https://www.kwiktrip.com/locator/store (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Lacey Eidem Art
```yaml
id: lacey-eidem-art
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-05: June 2026 Newsleaders story covers a show at Eidem Studio; studio at 235 E Cedar St #101 with posted hours.. Named by The Newsleaders story (June 2026); own website lacey-eidem.squarespace.com (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Lake Country Land Egg
```yaml
id: lake-country-land-egg
status: proposed
tier: listed
place_type: "Business"
address: "11312 County Road 5"
phone: "(320) 654-9262"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Active LLC (manager Christopher Marthaler), renewed every year including Feb 2025, now due 12/31/2027.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Lake Wobegon Visitor Center
```yaml
id: lake-wobegon-visitor-center
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-05: Same place as the city's Wobegon Trail Welcome Center/trailhead building at 605 1st Ave NE; the phone is City Hall's main line.. Named by Newsleaders 2024-25 St. Joseph Resource Guide (Wobegon Trail Welcome Center, 605 First Ave NE); City of St. Joseph parks page (Wobegon Trailhead); lakewobegontrail.com trailheads (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Lakeland Excavating Inc
```yaml
id: lakeland-excavating
status: proposed
tier: listed
place_type: "Business"
address: "11455 380th Street"
phone: "(320) 654-8720"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Lakeland Excavating, Inc. is active and in good standing, renewed 1/24/2026 at 11455 380th St, St. Joseph.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Lane Marie Hair
```yaml
id: lane-marie-hair
status: proposed
tier: listed
category: "wellness_service"
place_type: "Business"
address: "106 2nd Ave NW"
added_by: agent:town-verify
sources:
  - url: http://www.blushsalonmn.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.91). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Leaps and Bounds Childcare & Preschool
```yaml
id: leaps-bounds-childcare-preschool
status: proposed
tier: listed
category: "family_service"
place_type: "Business"
address: "110 E Able St"
phone: "3202674202"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Lilac Retreat
```yaml
id: lilac-retreat
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-05: Lakefront vacation rental on Big Watab Lake listed on Vrbo and Airbnb, with resellers showing 2026 dates.. Named by Vrbo listing (Lilac Retreat lake house, St. Joseph, p4893413) (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Little Shop Welding & Repair
```yaml
id: little-shop-welding-repair
status: proposed
tier: listed
place_type: "Business"
address: "31247 County Road 2"
phone: "(320) 363-0485"
aka: ["Little Shop Welding, LLC"]
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com, overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Google Maps lists it, not closed (Closed · Opens 9 AM Tue). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Lookin Good Tint
```yaml
id: lookin-good-tint
status: proposed
tier: listed
category: "automotive_service"
place_type: "Business"
address: "819 19th Ave NE"
phone: "+13203637690"
added_by: agent:town-verify
sources:
  - url: http://WWW.lgtint.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Mainstay
```yaml
id: mainstay
status: proposed
tier: listed
category: "financial_service"
place_type: "Business"
address: "235 Cedar St E Ste 103"
phone: "+13203586000"
added_by: agent:town-verify
sources:
  - url: http://www.mainstayinsure.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Making Creative Connections
```yaml
id: making-creative-connections
status: proposed
tier: listed
category: "arts_crafts_and_hobby_store"
place_type: "Business"
phone: "+13202823669"
added_by: agent:town-verify
sources:
  - url: https://www.creativememories.com/user/sarahblommer
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-02: Sarah Blommer's LinkedIn (Sept 2026) lists her as a current Creative Memories advisor in St. Joseph, and her advisor link still works (made-up advisor links 404); the business name itself shows up nowhere.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Marissa's Manes
```yaml
id: marissas-manes
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://marissasmanes.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed. Named by its own website, https://marissasmanes.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Mark's Wallcoating Inc
```yaml
id: marks-wallcoating
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "12564 Co Rd 160"
phone: "+13203634714"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Google Maps lists it, not closed (Open now). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Marquee Apparel
```yaml
id: marquee-apparel
status: proposed
tier: listed
place_type: "Business"
address: "PO Box 56374"
phone: "(320) 251-2848"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Google Maps listing (via Composio search), same phone, St. Joseph listing with hours. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## The Master Engraving Shoppe
```yaml
id: master-engraving-shoppe
status: proposed
tier: listed
category: "fashion_and_apparel_store"
place_type: "Business"
address: "507 1st Ave NW"
phone: "+17633335410"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Overture lists it open (confidence 0.95). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Mathew Hall Components
```yaml
id: mathew-hall-components
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://www.simonson-lumber.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Named by its own website, https://www.simonson-lumber.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Mattressota
```yaml
id: mattressota
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-05: Non-Google directory names Mattressota at its older Waite Park address; Google now puts it in a multi-tenant industrial building at 30659 Pearl Dr, and mattressota.com no longer resolves, so recheck the address.. Named by wheretobuyamattress.com store directory (Mattressota, but at 810 Sundial Dr, Waite Park; data Aug 2025) (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Metro Plumbing & Heating, Inc.
```yaml
id: metro-plumbing-heating
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "545 8th Ave NE"
phone: "13203637761"
added_by: agent:town-verify
sources:
  - url: http://www.metroplumbingmn.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Midwest Deer Trees Nursery and Orchard LLC
```yaml
id: midwest-deer-trees-nursery-orchard
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-05: Own site lists 9967 380th St and phone, says inventory updates late Oct 2026 and Spring 2027 orders open in January.. Named by Own website midwestdeertrees.com (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Michelich Granite (Sunburst Memorials)
```yaml
id: michelich-granite-sunburst-memorials
status: proposed
tier: listed
place_type: "Business"
address: "7808 County Road 75, St. Cloud, MN 56301"
phone: "(320) 363-7779"
aka: ["Mihelich Jones Granite Co"]
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Same site and phone (320-363-7779) now run as Michelich Granite by Monumental Sales/Sunburst Memorials; MN assumed name renewed 12/2025.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Mike's Electric
```yaml
id: mikes-electric
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "210 Jasmine Ln"
phone: "3203333110"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Milbert, Johnson & Cotton Family Dentistry
```yaml
id: milbert-johnson-cotton-family-dentistry
status: proposed
tier: listed
category: "dental_clinic"
place_type: "Business"
address: "1514 E Minnesota St"
phone: "+13203637729"
added_by: agent:town-verify
sources:
  - url: http://www.stjoedds.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Closed · Opens 7:30 AM Mon). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Mill Stream Village
```yaml
id: mill-stream-village
status: proposed
tier: listed
category: "lodging"
place_type: "Business"
address: "308 College Ave N"
phone: "+13203637656"
added_by: agent:town-verify
sources:
  - url: http://www.millstreamvillage.net/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 3 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Millan Brothers Construction Inc.
```yaml
id: millan-brothers-construction
status: proposed
tier: listed
category: "building_or_construction_service"
place_type: "Business"
address: "109 Iris Ln E"
phone: "+13209053499"
added_by: agent:town-verify
sources:
  - url: http://millanbrothers.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-02: Live website, copyright 2026, with current projects and hours.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Millstream Communications
```yaml
id: millstream-communications
status: proposed
tier: listed
category: "park"
place_type: "Business"
address: "710 County Road 75"
phone: "+13203634562"
added_by: agent:town-verify
sources:
  - url: http://www.dgcoursereview.com/course.php?id=1561
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Minnesota Association of Farm Mutual Insurance Companies
```yaml
id: minnesota-association-of-farm-mutual-ins
status: proposed
tier: listed
category: "social_or_community_service"
place_type: "Business"
address: "601 Elm St E E"
phone: "+13202710909"
aka: ["Minnesota Association of Farm Mutual"]
added_by: agent:town-verify
sources:
  - url: http://www.mafmic.org/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Closed · Opens 8 AM Mon). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Minnesota Home Improvements
```yaml
id: minnesota-home-improvements
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "8850 Ridgewood Ct"
phone: "3204348804"
aka: ["Minnesota Home Improvement"]
added_by: agent:town-verify
sources:
  - url: https://www.mnhomeimprovements.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 4:30 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Minnesota Public Radio
```yaml
id: minnesota-public-radio
status: proposed
tier: listed
place_type: "Business"
address: "31802 County Road 159"
phone: "(320) 363-7702"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: St. Cloud Area Chamber lists MPR KSJR/KNSR at this St. John's University address with the same phone; stations broadcast now.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## MinnWebb
```yaml
id: minnwebb
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: http://www.minnwebb.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 12 AM). Named by its own website, http://www.minnwebb.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Mission Nutrition
```yaml
id: mission-nutrition
status: proposed
tier: listed
category: "personal_or_beauty_service"
place_type: "Business"
address: "235 Cedar St E Ste 103"
phone: "+13205570190"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 2 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## MN HEAVY TOWING
```yaml
id: mn-heavy-towing
status: proposed
tier: listed
category: "automotive_service"
place_type: "Business"
address: "30890 Co Rd 2"
phone: "3204295634"
aka: ["MN HEAVY TRUCK REPAIR"]
added_by: agent:town-verify
sources:
  - url: https://mn-heavy-towing-llc.business.site/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open 24 hours). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Morningside Townhomes
```yaml
id: morningside-townhomes
status: proposed
tier: listed
place_type: "Business"
address: "198 Iverson Street W"
phone: "(320) 363-4887"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Current rental listings (RentCafe, Zillow, Apartment Finder) show units and pricing at this address.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Mortgages on Main
```yaml
id: mortgages-on-main
status: proposed
tier: listed
place_type: "Business"
address: "710 County Road 75 # 102"
phone: "(320) 271-4666"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Google Maps listing in St. Joseph, open; moved from County Road 75 to 303 Cedar St E. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Malibu Tan
```yaml
id: malibu-tan
status: proposed
tier: listed
place_type: "Business"
address: "708 Elm St E, St. Joseph, MN 56374"
phone: "(320) 363-8485"
aka: ["Movies Etc & Tanning"]
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Movies Etc ended movie rentals in 2024; Malibu Tan's site lists 708 Elm St E, St. Joseph with the same phone 320-363-8485.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## NAMI Solutions, Inc.
```yaml
id: nami-solutions
status: proposed
tier: listed
place_type: "Business"
address: "30593 Pearl Dr Ste 3"
phone: "3202305297"
added_by: agent:town-verify
sources:
  - url: http://www.namisolutions.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.96). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Neighbors Route 75
```yaml
id: neighbors-route-75
status: proposed
tier: listed
category: "restaurant"
place_type: "Business"
address: "2010 County Road 75"
phone: "+13205570268"
added_by: agent:town-verify
sources:
  - url: http://Neighborsroute75.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 10 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## North Central Distributing
```yaml
id: north-central-distributing
status: proposed
tier: listed
category: "auto_dealer"
place_type: "Business"
address: "575 15th Ave NE"
phone: "+18008928561"
added_by: agent:town-verify
sources:
  - url: https://truckaccessoriesdirect.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open now). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## North Floors
```yaml
id: north-floors
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-05: Owner Cody Ferreira's LinkedIn (Aug 2026) lists North Floors, St. Joseph, as current since Mar 2023; site northfloorsmn.com exists.. Named by LinkedIn (owner Cody Ferreira) (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## The North Table
```yaml
id: north-table
status: proposed
tier: listed
category: "restaurant"
place_type: "Business"
address: "11738 Co Rd 51"
phone: "+19524655931"
added_by: agent:town-verify
sources:
  - url: https://order.toasttab.com/online/the-north-table-5810-5th-st-ne
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Closed · Opens 3 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Nrg Savers LLC
```yaml
id: nrg-savers
status: proposed
tier: listed
place_type: "Business"
address: "9805 320th Street"
phone: "(320) 363-4614"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Own site is live and still takes orders at the 320th St address (last updated June 2024, newer phone 320-247-0563), though its LLC lapsed in 2005.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## The Oaks on 20th
```yaml
id: oaks-on-20th
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://www.prairielakesmanagement.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Named by its own website, https://www.prairielakesmanagement.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## The Oasis Bar and Pit
```yaml
id: oasis-bar-pit
status: proposed
tier: listed
category: "restaurant"
place_type: "Business"
address: "22 12th Ave SE"
phone: "+13205555555"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Overture lists it open (confidence 0.56). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## One Hour Heating & Air Conditioning
```yaml
id: one-hour-heating-air-conditioning
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "545 8th Ave NE"
phone: "3202476607"
added_by: agent:town-verify
sources:
  - url: http://www.onehourheatandairstcloud.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Opie's Gold
```yaml
id: opies-gold
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://opiesgold.com/about-us/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open now). Named by its own website, https://opiesgold.com/about-us/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Opus Motorcar Company
```yaml
id: opus-motorcar
status: proposed
tier: listed
category: "vehicle_dealer"
place_type: "Business"
address: "417 1st Ave NE"
phone: "13204061529"
added_by: agent:town-verify
sources:
  - url: https://opusmotorcar.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Outlet Bait & Tackle
```yaml
id: outlet-bait-tackle
status: proposed
tier: listed
category: "sporting_goods_store"
place_type: "Business"
address: "641 15th Ave NE"
phone: "+18002665134"
added_by: agent:town-verify
sources:
  - url: https://www.overstockbait.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.52). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Paquin Seasonal/Self Storage
```yaml
id: paquin-seasonal-self-storage
status: proposed
tier: listed
category: "storage_facility"
place_type: "Business"
address: "7230 322nd St"
phone: "+13202679067"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Overture lists it open (confidence 0.59). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Party Bus
```yaml
id: party-bus
status: proposed
tier: listed
category: "rental_service"
place_type: "Business"
address: "205 Hickory St E"
phone: "+13202930670"
added_by: agent:town-verify
sources:
  - url: https://www.thepartybusonline.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-02: Own website (c) 2026 with phone 320-293-0670; directory lists 205 Hickory St NE, St. Joseph.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Patents Minnesota
```yaml
id: patents-minnesota
status: proposed
tier: listed
category: "legal_service"
place_type: "Business"
address: "30884 1st Ave NE"
phone: "3203637296"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Overture lists it open (confidence 0.85). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Patricia A. Martini, MA
```yaml
id: patricia-martini-ma
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-05: NPI 1598979346 lists Patricia A. Martini, MA LP at 100 W Minnesota St, St. Joseph, phone 320-363-7163.. Named by NPI registry (opennpi.com); WebMD; Doximity (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Paul Eisenschenk-LakePlace.com
```yaml
id: paul-eisenschenk-lakeplace-com
status: proposed
tier: listed
category: "real_estate_service"
place_type: "Business"
address: "14724 325th Street"
phone: "(320) 293-9585"
added_by: agent:town-verify
sources:
  - url: https://www.paulsellsmn.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.77). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Paul Kollmann Monuments, LLC
```yaml
id: paul-kollmann-monuments
status: proposed
tier: listed
category: "family_service"
place_type: "Business"
address: "1403 E Minnesota St"
phone: "+16128069695"
added_by: agent:town-verify
sources:
  - url: https://paulkollmann.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Overture lists it open (confidence 0.72). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Peaceful Village Imports Inc.
```yaml
id: peaceful-village-imports
status: proposed
tier: listed
place_type: "Business"
aka: ["Peaceful Village"]
added_by: agent:town-verify
sources:
  - url: http://www.peacefulvillage.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Named by its own website, http://www.peacefulvillage.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## the Perfect Fit
```yaml
id: perfect-fit
status: proposed
tier: listed
category: "gym"
place_type: "Business"
address: "32 1st Ave NW"
phone: "3208287788"
added_by: agent:town-verify
sources:
  - url: https://www.theperfectfitmn.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Closes soon · 1 PM · Opens 10 AM Mon). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Petrek Law Office
```yaml
id: petrek-law-office
status: proposed
tier: listed
category: "attorney_or_law_firm"
place_type: "Business"
address: "710 County Road 75 E"
phone: "+13202711113"
added_by: agent:town-verify
sources:
  - url: https://www.petrekcriminallaw.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open now). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Phillipp Construction
```yaml
id: phillipp-construction
status: proposed
tier: listed
place_type: "Business"
address: "123 9th Avenue SE"
phone: "(320) 267-4869"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Phillipp Construction, Inc. is in good standing with its annual renewal current at this address (state record is the only evidence found).. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Piper's Plumbing
```yaml
id: pipers-plumbing
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "30659 Pearl Dr  Ste 1"
phone: "13203630379"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Google Maps lists it, not closed (Open now). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Powerhouse Outdoor Equipment
```yaml
id: powerhouse-outdoor-equipment
status: proposed
tier: listed
category: "sporting_goods_store"
place_type: "Business"
address: "207 Cedar St E"
phone: "+13203637478"
added_by: agent:town-verify
sources:
  - url: http://www.powerhouse.cc/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Prairie Supply, Inc.
```yaml
id: prairie-supply
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://www.prairiesupply.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 4 PM). Named by its own website, https://www.prairiesupply.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## PrairieScapes
```yaml
id: prairiescapes
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "29641 95th Ave"
phone: "+13203335931"
added_by: agent:town-verify
sources:
  - url: https://www.prairie-scapes.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Precise Heating, A/C, Plumbing & Refrigeration
```yaml
id: precise-heating-c-plumbing-refrigeration
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "628 19th Ave NE"
phone: "13203637401"
added_by: agent:town-verify
sources:
  - url: https://precisemn.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open 24 hours). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Precision Motorsports
```yaml
id: precision-motorsports
status: proposed
tier: listed
category: "vehicle_parts_store"
place_type: "Business"
address: "109 Cedar St E"
phone: "+13203634637"
aka: ["Precision Motor Sports"]
added_by: agent:town-verify
sources:
  - url: https://www.precision-motorsports.net/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 6 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Premier Stone Design
```yaml
id: premier-stone-design
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "2050 Jasmine Ct"
phone: "+13202508492"
added_by: agent:town-verify
sources:
  - url: https://www.psdgranite.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Closes soon · 1 PM · Opens 8 AM Mon). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Pristine Environmental
```yaml
id: pristine-environmental
status: proposed
tier: listed
category: "manufacturer"
place_type: "Business"
address: "30801 Pearl Dr"
phone: "13205294035"
added_by: agent:town-verify
sources:
  - url: http://www.fullcirclewater.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 4 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Pro-Tech Forklift Service Inc.
```yaml
id: pro-tech-forklift-service
status: proposed
tier: listed
category: "vehicle_dealer"
place_type: "Business"
address: "32653 County Road 2"
phone: "3203637474"
added_by: agent:town-verify
sources:
  - url: http://protechforklift1.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-02: Google Maps listing (via Composio search), same address and phone, open, 20 reviews. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Promotional Resources
```yaml
id: promotional-resources
status: proposed
tier: listed
category: "professional_service"
place_type: "Business"
address: "702 19th Ave NE"
phone: "+18663630177"
added_by: agent:town-verify
sources:
  - url: http://www.promotionalresourcesinc.net/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Closed · Opens 8 AM Mon). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Protrim of Central Minnesota
```yaml
id: protrim-of-central-minnesota
status: proposed
tier: listed
place_type: "Business"
address: "9493 Watab Drive"
phone: "(320) 363-8609"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: ProTrim of Central Minnesota, Inc. active in MN SOS, annual renewal filed 4/11/2026 at 9493 Watab Dr.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Quill & Disc
```yaml
id: quill-disc
status: proposed
tier: listed
category: "legal_service"
place_type: "Business"
address: "30844 1st Ave NE"
phone: "3206403271"
added_by: agent:town-verify
sources:
  - url: http://quilldisc.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## R J's Auto Repair
```yaml
id: r-js-auto-repair
status: proposed
tier: listed
place_type: "Business"
address: "30999 115th Avenue"
phone: "(320) 363-4540"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Google Maps listing (via Composio search), same address and phone, open with hours. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Reading Resources, LLC
```yaml
id: reading-resources
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-05: D&B lists the LLC at this address; its likely site readingresources.us (dyslexia reading help since 2010) currently returns an error, but no sign of closing.. Named by Dun & Bradstreet business directory (dandb.com) at 704 W Birch St (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Reliable Rolloff
```yaml
id: reliable-rolloff
status: proposed
tier: listed
place_type: "Business"
address: "919 College Avenue S"
phone: "(320) 363-1194"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Still operating with same phone at a new St. Joseph address; joined Tom Kraemer Inc in 2018 and its site now redirects to TKI's Reliable Roll-off page.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Renner Roofing Inc.
```yaml
id: renner-roofing
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: http://rennerroofingmn.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Named by its own website, http://rennerroofingmn.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Restoring Hope Individual & Family Therapy LLC
```yaml
id: restoring-hope-individual-family-therapy
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://www.restoringhopetherapyllc.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Closed · Opens 10 AM Mon). Named by its own website, https://www.restoringhopetherapyllc.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Riff City Guitar & Music Company
```yaml
id: riff-city-guitar-music
status: proposed
tier: listed
category: "musical_instrument_and_pro_audio_store"
place_type: "Business"
address: "708 Elm St E"
phone: "18772607301"
added_by: agent:town-verify
sources:
  - url: https://www.riffcityguitaroutlet.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Rivers Bend Cottage Homes
```yaml
id: rivers-bend-cottage-homes
status: proposed
tier: listed
category: "apartment"
place_type: "Business"
address: "209 Keystone Ct"
phone: "3206569324"
added_by: agent:town-verify
sources:
  - url: http://www.riversbendmn.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Roadway Sport-N-Trailer
```yaml
id: roadway-sport-n-trailer
status: proposed
tier: listed
category: "vehicle_dealer"
place_type: "Business"
address: "9 17th Ave SE"
phone: "+13203638430"
added_by: agent:town-verify
sources:
  - url: http://www.roadwaysport-n-trailer.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Rockhouse Productions
```yaml
id: rockhouse-productions
status: proposed
tier: listed
category: "media_service"
place_type: "Business"
address: "23 W Minnesota St"
phone: "+13203631000"
added_by: agent:town-verify
sources:
  - url: http://www.rockhousepro.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Rocky Acre Gardens
```yaml
id: rocky-acre-gardens
status: proposed
tier: listed
category: "hardware_home_and_garden_store"
place_type: "Business"
address: "35282 CR-2"
phone: "+13202507928"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Overture lists it open (confidence 0.72). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Roger Preusser Inc
```yaml
id: roger-preusser
status: proposed
tier: listed
place_type: "Business"
address: "8822 349th Street"
phone: "(320) 267-6068"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Roger Preusser Construction, Inc. is active/in good standing at this address, last renewed February 2026.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Roger Tamm Photography
```yaml
id: roger-tamm-photography
status: proposed
tier: listed
category: "professional_service"
place_type: "Business"
address: "203 Cedar St E"
phone: "+13203637406"
added_by: agent:town-verify
sources:
  - url: https://www.rtammphotography.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Rolling Ridge Wedding & Event Center
```yaml
id: rolling-ridge-wedding-event-center
status: proposed
tier: listed
category: "event_or_party_service"
place_type: "Business"
address: "31101 Co Rd 133"
phone: "+13202577755"
added_by: agent:town-verify
sources:
  - url: http://www.RollingRidgeEvents.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open 24 hours). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Rosenberger Cleaning Services LLC
```yaml
id: rosenberger-cleaning-services
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://www.rosenbergercs.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open 24 hours). Named by its own website, https://www.rosenbergercs.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Rosie's Gyps Ranch
```yaml
id: rosies-gyps-ranch
status: proposed
tier: listed
category: "sports_and_recreation"
place_type: "Business"
address: "12564 County Road 160"
phone: "+13202606519"
added_by: agent:town-verify
sources:
  - url: http://www.kdperformancehorses.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.69). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Ross Nesbit Agencies
```yaml
id: ross-nesbit-agencies
status: proposed
tier: listed
place_type: "Business"
address: "33 W Minnesota St"
phone: "3203637350"
added_by: agent:town-verify
sources:
  - url: http://www.rossnesbitagenciesstjoseph.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Rothstein Christmas Tree Farm
```yaml
id: rothstein-christmas-tree-farm
status: proposed
tier: listed
category: "farm"
place_type: "Business"
address: "29765 156th Ave"
phone: "+13203639499"
added_by: agent:town-verify
sources:
  - url: https://rothsteinchristmastreefarm.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Rpm Athletics
```yaml
id: rpm-athletics
status: proposed
tier: listed
category: "manufacturer"
place_type: "Business"
address: "30753 Pearl Dr"
phone: "13205570707"
added_by: agent:town-verify
sources:
  - url: http://rpmtf.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Russell Eyecare & Associates
```yaml
id: russell-eyecare-associates
status: proposed
tier: listed
category: "vision_or_eye_care_clinic"
place_type: "Business"
address: "15 E Minnesota St  Ste 107"
phone: "13204334326"
added_by: agent:town-verify
sources:
  - url: https://www.russelleyecaremn.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Rustic River Gear
```yaml
id: rustic-river-gear
status: proposed
tier: listed
category: "fashion_and_apparel_store"
place_type: "Business"
address: "636 19th Ave NE"
phone: "3203631065"
added_by: agent:town-verify
sources:
  - url: http://www.rusticrivergear.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 3:30 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Sam's Outdoor & More
```yaml
id: sams-outdoor-more
status: proposed
tier: listed
category: "sporting_goods_store"
place_type: "Business"
address: "219 Cedar St E"
phone: "+13205570090"
added_by: agent:town-verify
sources:
  - url: https://samsoutdoorsllc.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Scenic Specialties Landscape Professionals
```yaml
id: scenic-specialties-landscape-professiona
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "31101 County Road 133"
phone: "+13203637479"
aka: ["Scenic Specialties Landscape"]
added_by: agent:town-verify
sources:
  - url: http://www.scenicspecialties.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-02: Live website with a 2026 footer and news posts from January 2026, at the same address.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Scherer Trucking and Sons
```yaml
id: scherer-trucking-sons
status: proposed
tier: listed
category: "travel_and_transportation"
place_type: "Business"
address: "1007 E Minnesota St"
phone: "+13203638846"
added_by: agent:town-verify
sources:
  - url: http://www.scherertrucking.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 4:30 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Schwegel's Landscaping & Tree Service
```yaml
id: schwegels-landscaping-tree-service
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: http://www.schwegelsllc.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 7 PM). Named by its own website, http://www.schwegelsllc.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Scott Investigation
```yaml
id: scott-investigation
status: proposed
tier: listed
category: "financial_service"
place_type: "Business"
address: "9047 Crestview Dr"
phone: "(320) 363-7559"
added_by: agent:town-verify
sources:
  - url: http://www.piscott.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Seed to Glass
```yaml
id: seed-to-glass
status: proposed
tier: listed
category: "hardware_home_and_garden_store"
place_type: "Business"
phone: "+13203183316"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Google Maps lists it, not closed (Open 24 hours). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Semi Legal Service
```yaml
id: semi-legal-service
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-05: Loc8NearMe lists Semi Legal Service, truck repair at 30890 County Road 2, St. Joseph; it shares phone and address with HD Specialties LLC.. Named by loc8nearme.com (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Sentry Bank
```yaml
id: sentry-bank
status: proposed
tier: listed
category: "bank_or_credit_union"
place_type: "Business"
address: "400 4th Ave NE"
phone: "+13203637721"
added_by: agent:town-verify
sources:
  - url: https://mysentrybank.com/about-us/contact/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5:30 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Serenity Place on 7th
```yaml
id: serenity-place-on-7th
status: proposed
tier: listed
category: "senior_living_facility"
place_type: "Business"
address: "329 7th Ave SE"
phone: "+13202713400"
added_by: agent:town-verify
sources:
  - url: https://serenityon7.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open 24 hours). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Shamrock Leathers
```yaml
id: shamrock-leathers
status: proposed
tier: listed
place_type: "Business"
address: "9722 320th Street"
phone: "(320) 363-7441"
added_by: agent:town-verify
sources:
  - url: http://www.shamrockleathers.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. Verified 2026-10-02: Active Shopify store at shamrockleathers.com selling trapshooting gear; Yelp listing at same address updated August 2026.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Sisters & Company
```yaml
id: sisters
status: proposed
tier: listed
category: "second_hand_store"
place_type: "Business"
address: "31 W Minnesota St"
phone: "+13202829598"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 4:30 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Six · Twelve Boutique
```yaml
id: six-twelve-boutique
status: proposed
tier: listed
category: "shopping"
place_type: "Business"
address: "11 N College Ave"
phone: "+13202375683"
added_by: agent:town-verify
sources:
  - url: http://www.sixtwelveboutique.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-02: Its Square website, updated Sept 2026, lists the store at 11 College Ave N with hours and phone 320-237-5683 (sister gift shop Gifted at 13 W Minnesota St).. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Snap Fitness
```yaml
id: snap-fitness
status: proposed
tier: listed
category: "gym"
place_type: "Business"
address: "708 Elm St E"
phone: "+13203637757"
added_by: agent:town-verify
sources:
  - url: https://www.snapfitness.com/us/gyms/st-joseph-mn/?utm_source=fb&utm_medium=yext
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open 24 hours). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Sojourn Counseling Group
```yaml
id: sojourn-counseling-group
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-05: Own site and the state Help Me Connect directory list the St. Joseph office at 111 College Ave N, Door 2.. Named by sojourncounselinggroup.com; MN Dept of Health Help Me Connect (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Solar Nails of St Joseph
```yaml
id: solar-nails-of-st-joseph
status: proposed
tier: listed
category: "personal_or_beauty_service"
place_type: "Business"
address: "710 Co Rd 75 #107"
phone: "+13202713117"
added_by: agent:town-verify
sources:
  - url: https://solarnailsmn.com/home
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 9 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Sound Connection
```yaml
id: sound-connection
status: proposed
tier: listed
category: "automotive_service"
place_type: "Business"
address: "8055 County Road 75"
phone: "3202711916"
added_by: agent:town-verify
sources:
  - url: http://soundconnectioninc.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.97). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Spectrum Supply Co
```yaml
id: spectrum-supply
status: proposed
tier: listed
category: "hardware_home_and_garden_store"
place_type: "Business"
address: "700 15th Ave NE"
phone: "3202533305"
added_by: agent:town-verify
sources:
  - url: http://dacotahpaper.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## St. Cloud Acoustics
```yaml
id: st-cloud-acoustics
status: proposed
tier: listed
category: "hardware_home_and_garden_store"
place_type: "Business"
address: "833 19th Ave NE"
phone: "8552082830"
added_by: agent:town-verify
sources:
  - url: http://stcloudacoustics.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Overture lists it open (confidence 0.93). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## St Joe Mini-Storage
```yaml
id: st-joe-mini-storage
status: proposed
tier: listed
category: "storage_facility"
place_type: "Business"
address: "8480 Co Rd 75"
phone: "+13203634953"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: St. Joe Mini-Storage, LLC is active/in good standing (renewed January 2025) and the site appears in current Overture place data.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## St Joe Sand & Gravel
```yaml
id: st-joe-sand-gravel
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-05: Federal motor-carrier record lists St. Joseph Sand & Gravel, LLC on County Road 2 with the same phone, status active (record data from 2021); no closure sign.. Named by USDOT/FMCSA carrier registry (USDOT 2884266, St. Joseph Sand & Gravel, LLC, same phone 320-363-4953) (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## St. Joseph Equine Clinic
```yaml
id: st-joseph-equine-clinic
status: proposed
tier: listed
category: "animal_or_pet_service"
place_type: "Business"
address: "809 County Road 75"
phone: "+13203634908"
added_by: agent:town-verify
sources:
  - url: http://saintjosephequineclinic.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 4 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## St Joseph Laundromat
```yaml
id: st-joseph-laundromat
status: proposed
tier: listed
category: "laundry_service"
place_type: "Business"
address: "31 West MN Street"
phone: "+13203634953"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 9 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## St Joseph Plumbing Heating & Irrigation
```yaml
id: st-joseph-plumbing-heating-irrigation
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "217 16th Ave SE"
phone: "(320) 363-7224"
aka: ["St. Joseph Plumbing & Heating"]
added_by: agent:town-verify
sources:
  - url: http://stjosephplumbing.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open now). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## St. Stephen Storage
```yaml
id: st-stephen-storage
status: proposed
tier: listed
place_type: "Business"
address: "9301 Tallow Road"
phone: "(320) 654-0850"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: St. Stephen Storage, LLC is in good standing with its 2026 annual renewal filed at this address.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Heymans Design
```yaml
id: heymans-design
status: proposed
tier: listed
place_type: "Business"
address: "29641 95th Ave"
phone: "(320) 363-0132"
aka: ["Steve Heyman's Word & Design"]
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Google Maps listing (via Composio search), same address and phone, listed as Heymans Design, open. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Steve's Landscape Service
```yaml
id: steves-landscape-service
status: proposed
tier: listed
place_type: "Business"
address: "29641 95th Avenue"
phone: "(320) 333-5931"
aka: ["Steve's Landscape Services"]
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Google Maps lists it open at the same address and phone; its LLC ended in 2018, so it likely runs without one. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## StorageLink
```yaml
id: storagelink
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://www.storagelink.net/locations/saint-joseph-mn-56374/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 10 PM). Named by its own website, https://www.storagelink.net/locations/saint-joseph-mn-56374/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Strack Construction Co Inc
```yaml
id: strack-construction
status: proposed
tier: listed
category: "building_or_construction_service"
place_type: "Business"
address: "715 15th Ave NE"
phone: "13202515933"
added_by: agent:town-verify
sources:
  - url: https://strackco.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 4 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Straight And Square Distributing Llc
```yaml
id: straight-square-distributing
status: proposed
tier: listed
category: "vehicle_parts_store"
place_type: "Business"
address: "30659 Pearl Dr  Ste 3"
phone: "13203634107"
added_by: agent:town-verify
sources:
  - url: http://www.straight-square.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.75). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Styledbykyliep
```yaml
id: styledbykyliep
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://styledbykyliep.glossgenius.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Closed · Opens 10 AM Mon). Named by its own website, https://styledbykyliep.glossgenius.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Sunset Manufacturing / Sunset Equipment
```yaml
id: sunset-manufacturing-sunset-equipment
status: proposed
tier: listed
category: "b2b_service"
place_type: "Business"
address: "417 1st Ave NE"
phone: "18003283841"
added_by: agent:town-verify
sources:
  - url: http://www.sunset-eq.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 4:30 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## T & R Glass & Woodworks
```yaml
id: t-r-glass-woodworks
status: proposed
tier: listed
category: "specialty_store"
place_type: "Business"
address: "104 Hill St W"
phone: "+13203631486"
added_by: agent:town-verify
sources:
  - url: http://www.trglassandwoodworks.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Tamarack Materials
```yaml
id: tamarack-materials
status: proposed
tier: listed
category: "hardware_home_and_garden_store"
place_type: "Business"
address: "31068 County Road 133"
phone: "3203634442"
aka: ["Tamarack Materials Northland"]
added_by: agent:town-verify
sources:
  - url: http://tamarackmaterials.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 4 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Tanner Systems Inc
```yaml
id: tanner-systems
status: proposed
tier: listed
category: "manufacturer"
place_type: "Business"
address: "625 19th Ave NE"
phone: "+18004616454"
added_by: agent:town-verify
sources:
  - url: http://www.tannersystems.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Tastefully Simple Independent Consultant Lori Tiffany
```yaml
id: tastefully-simple-independent-consultant
status: proposed
tier: listed
category: "professional_service"
place_type: "Business"
address: "9634 Wildwood Dr"
phone: "(320) 363-1009"
aka: ["Tastefully Simple Independent"]
added_by: agent:town-verify
sources:
  - url: https://www.tastefullysimple.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## TCC Materials
```yaml
id: tcc-materials
status: proposed
tier: listed
category: "manufacturer"
place_type: "Business"
address: "8646 Ridgewood Rd"
phone: "13203634671"
added_by: agent:town-verify
sources:
  - url: https://www.borgertproducts.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 4 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Teddy Bear Family Daycare
```yaml
id: teddy-bear-family-daycare
status: proposed
tier: listed
place_type: "Business"
address: "27 4th Avenue SE"
phone: "(320) 363-1093"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Owner Jenifer Schmitz's family child care license 235737 (listed as Teddybear Daycare) is active, renewed 1/1/2026, reviewed 4/29/2026, now at 425 7th Ave SE.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Terwey Brothers
```yaml
id: terwey-brothers
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-05: Farm partnership at this address listed in a farmers' directory with USDA dairy/crop payments; no sign of closing.. Named by StarvingFarmer.com Farmers' Directory (Terwey Brothers Prtn, Arnold & Jacob Terwey, 11468 282nd St); SubsidyLookup USDA payment records (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Thunder Valley Classic Cars Inc.
```yaml
id: thunder-valley-classic-cars
status: proposed
tier: listed
place_type: "Business"
aka: ["Thunder Valley Performance"]
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-05: Facebook page (facebook.com/1478722339012678), MapQuest and Speed Shop Source list it at 9778 385th St, St. Joseph.. Named by Facebook page; MapQuest; Speed Shop Source (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## TMT Integrity Flooring, LLC
```yaml
id: tmt-integrity-flooring
status: proposed
tier: listed
category: "hardware_home_and_garden_store"
place_type: "Business"
address: "13127 County Road 160"
phone: "+13203637926"
aka: ["TMT Vintage LLC"]
added_by: agent:town-verify
sources:
  - url: http://www.floorguy.net
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Traut Companies
```yaml
id: traut-companies
status: proposed
tier: listed
category: "water_utility_provider"
place_type: "Business"
address: "32640 County Road 133"
phone: "+13202515090"
added_by: agent:town-verify
sources:
  - url: http://www.trautcompanies.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Truck Accessories Direct
```yaml
id: truck-accessories-direct
status: proposed
tier: listed
category: "vehicle_parts_store"
place_type: "Business"
address: "575 15th Ave"
phone: "+13205574394"
added_by: agent:town-verify
sources:
  - url: https://truckaccessoriesdirect.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Truck & Trailer 24HR Mobile Repair
```yaml
id: truck-trailer-24hr-mobile-repair
status: proposed
tier: listed
category: "agricultural_service"
place_type: "Business"
address: "30890 County Road 2"
phone: "3202913202"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## True Freedom Physical Therapy
```yaml
id: true-freedom-physical-therapy
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://truefreedomphysicaltherapy.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Named by its own website, https://truefreedomphysicaltherapy.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Two Bits Mens Grooming Salon
```yaml
id: two-bits-mens-grooming-salon
status: proposed
tier: listed
category: "personal_or_beauty_service"
place_type: "Business"
address: "21 1st Ave NW"
phone: "+13204692861"
added_by: agent:town-verify
sources:
  - url: http://www.twobitsgrooming.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 3 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Underground Water Locating
```yaml
id: underground-water-locating
status: proposed
tier: listed
place_type: "Business"
address: "28391 Kelp Road"
phone: "(320) 363-7564"
added_by: agent:town-verify
sources:
  - url: http://www.undergroundwaterlocating.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. Verified 2026-10-02: Google Maps listing (via Composio search), same address and phone, listed open. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Unwind
```yaml
id: unwind
status: proposed
tier: listed
category: "complementary_and_alternative_medicine"
place_type: "Business"
address: "19 Ash St E"
phone: "+13203044873"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Google Maps lists it, not closed (Closed · Opens 9 AM Thu). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## V-Twin Tavern
```yaml
id: v-twin-tavern
status: proposed
tier: listed
category: "bar"
place_type: "Business"
address: "520 7th Ave SE"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Overture lists it open (confidence 0.86). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Verizon Wireless Zone
```yaml
id: verizon-wireless-zone
status: proposed
tier: listed
category: "electronics_store"
place_type: "Business"
address: "710 County Road 75 E Ste 105"
phone: "3203634562"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Overture lists it open (confidence 0.85). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Victory Nutrition
```yaml
id: victory-nutrition
status: proposed
tier: listed
place_type: "Business"
address: "14 College Ave N Ste B"
added_by: agent:town-verify
sources:
  - url: https://victory-nutrition.business.site/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.85). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Viking Log Furniture
```yaml
id: viking-log-furniture
status: proposed
tier: listed
place_type: "Business"
aka: ["Viking Industries"]
added_by: agent:town-verify
sources:
  - url: https://www.vikinglogfurniture.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 4:30 PM). Named by its own website, https://www.vikinglogfurniture.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Vista Apartments
```yaml
id: vista-apartments
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: http://www.move2vista.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Named by its own website, http://www.move2vista.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Von Meyer Publishing Inc
```yaml
id: von-meyer-publishing
status: proposed
tier: listed
place_type: "Business"
address: "209 E Cedar Street"
phone: "(320) 363-4195"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Google Maps listing (via Composio search), same address and phone, listed open. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## W Gohman Construction Co
```yaml
id: w-gohman-construction
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "815 County Road 75"
phone: "+13203637781"
added_by: agent:town-verify
sources:
  - url: http://www.wgohman.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 5 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Watab Inc-Environmental
```yaml
id: watab-environmental
status: proposed
tier: listed
place_type: "Business"
address: "14234 Fruit Farm Road"
phone: "(320) 363-1300"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Watab Inc. active in MN SOS, annual renewal filed 1/16/2026; watab.net is live with this address.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## We Haul For You
```yaml
id: we-haul-for-you
status: proposed
tier: listed
place_type: "Business"
address: "PO Box 75"
phone: "(320) 250-2855"
aka: ["We Haul"]
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Google Maps listing (via Composio search), same phone, open, 198 reviews. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Wendy Loso
```yaml
id: wendy-loso
status: proposed
tier: listed
category: "real_estate_service"
place_type: "Business"
address: "111 College Ave N"
phone: "+13209805920"
added_by: agent:town-verify
sources:
  - url: http://wendyloso.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open 24 hours). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## West Apartments
```yaml
id: west-apartments
status: proposed
tier: listed
category: "real_estate_service"
place_type: "Business"
address: "710 County Road 75"
phone: "+13202711222"
added_by: agent:town-verify
sources:
  - url: http://east-westrealty.com
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.5). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## West Suburban Tree Care
```yaml
id: west-suburban-tree-care
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: https://westsuburbantreecare.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 7 PM). Named by its own website, https://westsuburbantreecare.com/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Whitby Gift Shop & Gallery
```yaml
id: whitby-gift-shop-gallery
status: proposed
tier: listed
place_type: "Business"
address: "104 Chapel Lane"
phone: "(320) 363-7113"
aka: ["Art and Heritage Place | Whitby Gift Shop and Gallery/Haehn Museum"]
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: Saint Benedict's Monastery site lists current hours (Tue-Sat) and same phone for the shop.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## The Whole You Wellness Collective
```yaml
id: whole-you-wellness-collective
status: proposed
tier: listed
category: "complementary_and_alternative_medicine"
place_type: "Business"
address: "32 1st Ave NW #72"
phone: "+13204062888"
added_by: agent:town-verify
sources:
  - url: https://thewholeyouwellnesscollective.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-02: Live website lists the St. Joseph address, founder Trisha Kubasek and current services.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Wildwood Ranch Maple Syrup
```yaml
id: wildwood-ranch-maple-syrup
status: proposed
tier: listed
category: "farm"
place_type: "Business"
address: "29709 Kipper Rd"
phone: "+13203637784"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Overture lists it open (confidence 0.86). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Winston's Doggy Motel
```yaml
id: winstons-doggy-motel
status: proposed
tier: listed
place_type: "Business"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-05: Pet directories list Winston's Doggy Motel at 809 County Road 75, St. Joseph, 320-363-7917; no closure found.. Named by dogdog.org; petgroominginfo.com (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Winters Family Chiropractic
```yaml
id: winters-family-chiropractic
status: proposed
tier: listed
category: "complementary_and_alternative_medicine"
place_type: "Business"
address: "1511 E Minnesota St"
phone: "+13202020284"
added_by: agent:town-verify
sources:
  - url: https://wintersfamilychiro.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Closes soon · 1 PM · Opens 12 PM Wed). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Yamry Construction
```yaml
id: yamry-construction
status: proposed
tier: listed
category: "home_service"
place_type: "Business"
address: "33117 CR-2"
phone: "+13203634159"
added_by: agent:town-verify
sources:
  - url: http://yamryconstruction.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 7 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Grey Face Rescue & Retirement
```yaml
id: grey-face-rescue-retirement
status: proposed
tier: listed
category: "animal_or_pet_service"
place_type: "Community group"
address: "30593 Pearl Dr"
phone: "+13202246156"
added_by: agent:town-verify
sources:
  - url: http://www.greyfacerescue.org/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Closed · Opens 5 PM Mon). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## St Joe Rod and Gun Club
```yaml
id: st-joe-rod-gun-club
status: proposed
tier: listed
category: "social_or_community_service"
place_type: "Community group"
address: "29495 Kraemer Lake Rd"
added_by: agent:town-verify
sources:
  - url: http://stjoerodandgunclub.org/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 9 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## St. Joseph Community Food Shelf
```yaml
id: st-joseph-community-food-shelf
status: proposed
tier: listed
category: "food_bank"
place_type: "Community group"
address: "18 E Birch St"
phone: "+14782132700"
added_by: agent:town-verify
sources:
  - url: https://st-joseph-community-food-shelf.square.site/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Closed · Opens 1 PM Tue). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Tour of Saints (run by Bicycle Alliance of Minnesota)
```yaml
id: tour-of-saints-run-by-bicycle-alliance-o
status: proposed
tier: listed
place_type: "Community group"
address: "524 College Ave S, St. Joseph, MN 56374"
phone: "(320) 363-1311"
aka: ["Tour Of Saints Cycling Assn"]
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: tourofsaints.com now redirects to BikeMN, which runs the ride from the St. Ben's Athletic Complex; 2026 ride held, 2027 set for July 18.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Baha'i Faith Baha'is-Stearns
```yaml
id: bahai-faith-bahais-stearns
status: proposed
tier: listed
place_type: "Church"
address: "29422 Kiwi Court"
phone: "(320) 363-4479"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: The Stearns County Bahá'í community is still listed on bahai.us (contact via the national office); 29422 Kiwi Ct is a private home, not a public venue.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Redeeming Love Lutheran Church
```yaml
id: redeeming-love-lutheran-church
status: proposed
tier: listed
category: "christian_place_of_worship"
place_type: "Church"
added_by: agent:town-verify
sources:
  - url: http://redeeminglovelutheranchurch.placeweb.site
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.57). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Resurrection Lutheran Church
```yaml
id: resurrection-lutheran-church
status: proposed
tier: listed
category: "christian_place_of_worship"
place_type: "Church"
address: "610 Stearns 2 County"
phone: "+13203634232"
added_by: agent:town-verify
sources:
  - url: http://rlcstjoe.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Overture lists it open (confidence 1.0). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## St John the Baptist Parish
```yaml
id: st-john-baptist-parish
status: proposed
tier: listed
category: "christian_place_of_worship"
place_type: "Church"
address: "14241 Fruit Farm Rd"
phone: "+13203632569"
aka: ["St. John the Baptist Church"]
added_by: agent:town-verify
sources:
  - url: https://stjohnthebaptistparish.org/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Greater Minnesota Mentoring Academy
```yaml
id: greater-minnesota-mentoring-academy
status: proposed
tier: listed
category: "education"
place_type: "School / college"
address: "111 College Ave N Ste 9"
phone: "+10123456789"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Kidstop
```yaml
id: kidstop
status: proposed
tier: listed
category: "coffee_shop"
place_type: "School / college"
address: "1300 Jade Rd"
phone: "(320) 363-4737"
added_by: agent:town-verify
sources:
  - url: http://bgcmn.org/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Overture lists it open (confidence 0.92). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Lillian Leonard Primary
```yaml
id: lillian-leonard-primary
status: proposed
tier: listed
category: "elementary_school"
place_type: "School / college"
address: "124 1st Ave SE"
phone: "+13202917099"
added_by: agent:town-verify
sources:
  - url: http://www.LillianLeonardPrimary.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.9). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Meyer Farm Project
```yaml
id: meyer-farm-project
status: proposed
tier: listed
place_type: "School / college"
address: "29482 Co Rd 121"
phone: "+13208280019"
added_by: agent:town-verify
sources:
  - url: http://meyerfarmproject.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.78). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## St. Joseph Catholic School
```yaml
id: st-joseph-catholic-school
status: proposed
tier: listed
category: "place_of_learning"
place_type: "School / college"
address: "32 W Minnesota St"
phone: "+13203637769"
added_by: agent:town-verify
sources:
  - url: https://www.stjosephparish.org
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Overture lists it open (confidence 0.96). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## City of St. Joseph Dog Park
```yaml
id: city-of-st-joseph-dog-park
status: proposed
tier: listed
category: "dog_park"
place_type: "Government"
address: "31015 County Rd 3"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 4:30 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## St. Joseph Government Center
```yaml
id: st-joseph-government-center
status: proposed
tier: listed
place_type: "Government"
added_by: agent:town-verify
sources:
  - url: https://www.stjosephmn.gov/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 4:30 PM). Named by its own website, https://www.stjosephmn.gov/ (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## St. Joseph Maintenance Department
```yaml
id: st-joseph-maintenance-department
status: proposed
tier: listed
place_type: "Government"
address: "500 NW 2nd Avenue"
phone: "(320) 363-7727"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from lakesnwoods.com. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-02: City site lists Public Works/Maintenance (Director Ryan Wensmann) at 75 Callaway St E, phone 320-363-7201.. Unreviewed — tier `listed`, so it publishes nothing until promoted.

## St. Joseph Township Hall
```yaml
id: st-joseph-township-hall
status: proposed
tier: listed
category: "government_office"
place_type: "Government"
address: "935 College Ave S"
phone: "+13203638825"
added_by: agent:town-verify
sources:
  - url: https://www.sjct.org
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 4:30 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## US Army Reserve Training
```yaml
id: us-army-reserve-training
status: proposed
tier: listed
category: "military_site"
place_type: "Government"
address: "110 20th Ave SE"
phone: "+13202517942"
added_by: agent:town-verify
sources:
  - url: https://rapids-appointments-scheduler.dmdc.osd.mil
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Google Maps lists it, not closed (Opens soon · 1 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## City of St. Joseph Archery Range
```yaml
id: city-of-st-joseph-archery-range
status: proposed
tier: listed
place_type: "Park / historic"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-05: City range at the water-treatment-plant site off Kelp Road opened May 2013; Park Board in 2025 was getting bids for a shelter at the range.. Named by City of St. Joseph Park Board minutes (May 2025); Newsleaders 2013 grand-opening story (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Cloverdale Park
```yaml
id: cloverdale-park
status: proposed
tier: listed
place_type: "Park / historic"
added_by: agent:town-verify
sources:
  - url: https://www.cityofstjoseph.com/Facilities/Facility/Details/2
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 10 PM). Named by its own website, https://www.cityofstjoseph.com/Facilities/Facility/Details/2 (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Hollow Park Tot Lot
```yaml
id: hollow-park-tot-lot
status: proposed
tier: listed
place_type: "Park / historic"
added_by: agent:town-verify
sources:
  - url: https://www.cityofstjoseph.com/Facilities/Facility/Details/3
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 10 PM). Named by its own website, https://www.cityofstjoseph.com/Facilities/Facility/Details/3 (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Kraemer Lake-Wildwood County Park
```yaml
id: kraemer-lake-wildwood-county-park
status: proposed
tier: listed
category: "park"
place_type: "Park / historic"
address: "12857 Co Rd 51"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Google Maps lists it, not closed (Open · Closes 11 PM). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## Lions Park
```yaml
id: lions-park
status: proposed
tier: listed
place_type: "Park / historic"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from a Google Maps sweep. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-05: The pin sits about 180 m from the Township Hall at 935 College Ave S (Co Rd 121), where the township park's Lions-funded shelter and playground are; officially called St. Joseph Township Park.. Named by Newsleaders 2024-25 St. Joseph Resource Guide and stjosephtownship.org (as St. Joseph Township Park and Shelter); St. Joseph Lions Club projects page (ADR-016). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## St Benedicts Art & Heritage
```yaml
id: st-benedicts-art-heritage
status: proposed
tier: listed
category: "museum"
place_type: "Park / historic"
address: "104 Chapel Ln"
phone: "+13203637098"
added_by: agent:town-verify
sources:
  - url: http://www.cityseekr.com/st-joseph/museums-galleries/poi-haehn-museum-934496.html
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Overture lists it open (confidence 0.95). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## St. Joseph Blockhouse
```yaml
id: st-joseph-blockhouse
status: proposed
tier: listed
category: "monument"
place_type: "Park / historic"
address: "190 2nd Ave NW"
added_by: agent:town-verify
sources:
  - url: TODO
    kind: website
    method: submission
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. No URL was found, so this is `submission`: it waits on the owner rather than guessing an address (ADR-007). Verified 2026-10-04: Overture lists it open (confidence 0.95). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## St Joseph Manufactured Home Community
```yaml
id: st-joseph-manufactured-home-community
status: proposed
tier: listed
category: "real_estate_service"
place_type: "Park / historic"
address: "407 1st Ave NW"
phone: "+13203631004"
added_by: agent:town-verify
sources:
  - url: https://www.summitproperties.info/st-joseph-mobile-home-community
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture, lakesnwoods.com. Verified 2026-10-04: Overture lists it open (confidence 0.85). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## St. Joseph Trailhead of Lake Wobegon Trail
```yaml
id: st-joseph-trailhead-of-lake-wobegon-trai
status: proposed
tier: listed
category: "sports_and_recreation"
place_type: "Park / historic"
address: "605 1st Ave NE"
phone: "+13202939364"
added_by: agent:town-verify
sources:
  - url: http://lakewobegontrail.com/
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.98). Unreviewed — tier `listed`, so it publishes nothing until promoted.

## St. Wendel Tamarack Bog Scientific & Natural Area
```yaml
id: st-wendel-tamarack-bog-scientific-natura
status: proposed
tier: listed
category: "political_organization"
place_type: "Park / historic"
address: "County Road 4"
phone: "6512595800"
added_by: agent:town-verify
sources:
  - url: http://www.dnr.state.mn.us/snas/detail.html?id=sna02038
    kind: website
    method: fetch
    trust: official
```
Notes: Proposed on 2026-10-05 from overture. Verified 2026-10-04: Overture lists it open (confidence 0.85). Unreviewed — tier `listed`, so it publishes nothing until promoted.
