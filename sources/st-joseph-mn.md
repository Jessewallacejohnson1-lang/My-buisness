---
schema: 1
town: st-joseph-mn
---

<!--
First draft of the St. Joseph registry, 2026-09-22.

Every entry is `status: proposed` — an agent may not set `active` (ADR-008). Jesse
flips the ones worth watching. Nothing here is fetched until he does.

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
status: proposed
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
status: proposed
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
status: proposed
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
status: proposed
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
status: proposed
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
status: proposed
category: bakery
partner: true
added_by: agent:claude
sources:
  - url: TODO
    kind: website
    method: fetch
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
status: proposed
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
status: proposed
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
status: proposed
category: gov
added_by: agent:claude
sources:
  - url: https://www.stjosephmn.gov/calendar.aspx
    kind: gov
    method: search_snippet
    trust: official
```
Notes: Council meetings, public notices, city-run events like Rocktoberfest.
`method: search_snippet` is **mandatory, not a preference** — stjosephmn.gov's
robots.txt disallows automated fetching, so an agent answers with a site-restricted web
search instead of the runner fetching it (ADR-001, ADR-009). Always append "MN" to that
search or the results are St. Joseph, Missouri (ADR-006).

## JoeTown
```yaml
id: joetown
status: proposed
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
status: proposed
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
status: proposed
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
status: proposed
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
