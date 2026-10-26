# ADR-023 — When neither our fetcher nor Firecrawl can read a page, Apify's proxy may

Date: 2026-10-25. Decided by Jesse. Supersedes the ban on a browser identity in ADR-012 and ADR-014.

## Decision

Jesse, 2026-10-25, after Bound (gobound.com) turned out to keep crawlers off its school calendars
(`Disallow: /*/calendar*`) and to answer a headless browser 403: "we're gonna find a way around it",
"use Appify's proxy to get around it", then "remove that rule".

The order stays: our honest fetcher first, then Firecrawl (Jesse, 2026-10-22). When both fail for a
page Jesse wants read, it may be read through Apify (its proxy and browser actors), as the social
pages already are (ADR-020). Each new site read this way is named to Jesse first with what it costs.

## What still holds

- Crawl-delay and one request per host still hold; a 403 is still "slow down" first (ADR-014). The
  chamber's site 403s a Chrome user agent and serves our bot 200: a disguise is not always the way in.
- Only public pages, never a login.
- `mblsportal.sos.mn.gov` stays search-only.
