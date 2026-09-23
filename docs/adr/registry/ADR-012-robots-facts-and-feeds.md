# ADR-012 — What actually blocks us, and feeds beat pages

**Status:** Accepted
**Date:** 2026-09-23
**Corrects:** a factual claim in [ADR-001](ADR-001-daily-routine-and-trust-tiers.md).
That ADR's decisions stand; one of the facts it rested on was wrong.
**Partly superseded by [ADR-014](ADR-014-a-403-is-slow-down-not-go-away.md):** the rule
below that a 403 on `robots.txt` means the server refuses us, and that such an entry
stays `search_snippet`, is wrong. A 403 from a crawl-delayed host means slow down.
Everything else here — measure robots claims, prefer feeds, a client-rendered page is
not a source, and never impersonate a browser — stands.

## Context

ADR-001 and `sources/README.md` both stated that `stjosephmn.gov` disallows automated
fetching, and the city entry was therefore `method: search_snippet` — a human doing a web
search instead of the runner reading the page. On 2026-09-23 that was measured rather
than assumed, and it is not true.

`stjosephmn.gov/robots.txt` blocks `/admin`, `/search`, `/map`, `/currentevents` and a
handful of `.asp` paths. `calendar.aspx` is not among them. `robotparser.can_fetch`
returns **True** and the page returns HTTP 200. A whole source had been reduced to manual
work on the strength of an unverified sentence.

`stjosephchamber.com` is a different story with the same symptom. Its robots.txt is two
lines — `User-agent: *` and `Crawl-delay: 10` — with **no `Disallow` at all**. It does not
block anyone. But the server returns **HTTP 403 to any non-browser client**, including a
plain `python-urllib` request for `robots.txt` itself. Python's `RobotFileParser` treats a
401 or 403 on `robots.txt` as `disallow_all`, so the checker reports "robots.txt
disallows". The verdict is right and the stated reason is wrong: the site is refusing our
client at the edge, not publishing a rule against us.

Separately, the city calendar turned out to be a client-side shell. The HTML is filter
chrome — "Select a Calendar", "Show Past Events" — and contains no events. Fetching it
successfully would still have yielded nothing.

## Decision

**Robots claims are measured, not asserted.** Before an entry is set to `search_snippet`
on the grounds that a site blocks robots, the robots rule is read and recorded. "It blocks
robots" written in a document is not evidence; a fetch is. A source demoted to manual work
on a wrong belief is invisible, because nothing fails — it just quietly costs a human.

**A 403 on `robots.txt` stays `search_snippet`.** Where a server refuses our client
outright, the answer is still the search index, and the note says *why* — a WAF refusal,
not a robots rule. Retrying with a browser user-agent to get past it is **forbidden**:
that is evading an access control, which is the same workaround ADR-001 and ADR-009 rule
out, just at a different layer.

**Prefer a feed to a page.** Where a site publishes iCal or RSS, those are the source and
the HTML page is not. They are structured, they survive a redesign, and they do not
depend on JavaScript. The city now reads three feeds — Community Events (`catID=25`), the
RSS calendar, and the City calendar (`catID=14`) — instead of one unreadable page.
`catID=24` exists, is empty, and is deliberately not listed.

**An HTML page that renders its content client-side is not a source.** The runner already
warns about near-empty snapshots. The response is to find that site's feed, or to fall
back to `search_snippet` — not to record the shell and call it fetched.

## Consequences

- The city of St. Joseph goes from one manual search task to three fetched feeds, one of
  which is the neighbour-facing community calendar. That is the single biggest source
  upgrade in the registry so far, and it came from checking a sentence nobody had checked.
- Every other `search_snippet` entry in the registry is now suspect until its reason is
  verified the same way. `kennedy.isd742.org` and `csbsju.edu` were measured on 2026-09-22
  and genuinely do disallow; the chamber is measured here. Nothing else has been checked.
- The distinction between "robots.txt says no" and "the server refuses our client" has to
  survive in the notes, because the two look identical in a run report and only one of
  them might be fixed by asking the owner for access.
- Feeds age differently from pages. A `catID` can be retired by the city without warning
  and would show as a source that quietly stops changing. That is a freshness problem
  (ADR-010) and is what the cadence check is for.
