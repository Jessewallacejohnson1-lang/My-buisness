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
