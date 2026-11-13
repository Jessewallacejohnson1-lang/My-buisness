# Dates: a page for each thing with nothing scheduled

Each thing in your batch is real (a school's club, team or arts group, a Place, or a Group of neighbours) but has no
Event coming in Block Party, and no page the morning watch reads lists it. Find the page that gives its dates, so the
morning watch can read it every day (BP app docs/plans/nothing-scheduled, ticket 04). You only name pages: nothing is
watched until Jesse ticks it.

Your batch file has one thing per line: its `thing` key, `name`, `what` it is (`club at Sartell High School`, `a place in
St. Joseph MN (restaurant)`, `a group in St. Joseph MN, meets at ...`), `town`, `sites` (its own website, or its
school's), `read` (pages the morning watch already reads for it, which list nothing for it), `between` (the first and
last day that count), and sometimes a `note` (the school's words on it) or `social` (its known Facebook or Instagram).

## The Ladder

For each thing, try the rungs in order and stop at the first page that gives a date for it between `between`'s days:

1. `school` (a school's activity only): the school's own page for this activity: its club, activities, athletics or
   fine arts page. Search the school's site for the activity's name.
2. `broad`: a calendar that covers it: the school's or the district's own calendar, a college department's events page
   (a music department's concerts), the diocese's paper (thecentralminnesotacatholic.org/events), a league's or state
   association's schedule, the calendar of the place it meets at. In the hand walk every date came from one of these.
3. `own`: the thing's own website: its events, calendar or news page.
4. `search`: a web search naming the thing with its school or town and "MN": a page that lists its next date.

A club that gives only a meeting time ("Fridays at 8 AM"), a page with last season's dates, or one with "dates to be
announced" gives no date: go on to the next rung. A Group's regular meetings are not what you look for: only a one-off
Event (a pancake breakfast, a fundraiser, a concert).

## Rules

- Search with WebSearch, "MN" in every query: there are many St. Josephs. At most 4 searches for a thing; a thing with
  nothing after them is `none`.
- Read a page only with `python3 sources/scripts/nothing_scheduled.py read <url>`: the registry's polite fetcher, which
  keeps to each site's robots rules. Never WebFetch, curl or a browser. A page that won't read through it can't be
  watched: try the next rung.
- A page counts only when it names this thing (or its event: a "Tech Choir Concert" for Tech's Chamber Choir) and its
  school or town, and gives the date in its own words. Never a page in `read`, a search results page, or a page you
  haven't read.
- Facebook and Instagram pages are never read and never your answer's `page`: put each one you find for the thing in
  `social` (a later, paid step reads them).
- Give the page's own address, the list or calendar page rather than one event on it when the list gives the date.

## Answer

One JSON line per thing, nothing else:

```
{"thing": "activity:9ed9…", "rung": "broad", "page": "https://tech.isd742.org/calendar", "date": "2026-11-23", "event": "Tech Choir Concert", "social": [], "searches": 2}
{"thing": "group:62846f8a…", "rung": "none", "page": "", "date": "", "event": "", "social": ["https://www.facebook.com/…"], "searches": 4}
```

`rung` is `school`, `broad`, `own`, `search` or `none`; `date` is `YYYY-MM-DD`, the first date the page gives; `event` is
what the page lists that day, in its words; `searches` is how many web searches you made for the thing.
