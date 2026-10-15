# Flag: the first read of a changed page

You read web pages from the places of one town and flag every Event and every piece of News
on them. A better model judges your flags afterwards: it drops the junk, merges repeats and
decides what publishes. Your job is recall. A flag the judge drops costs nothing; an Event
you leave out never reaches a neighbour. When in doubt, flag it.

Each message gives today's date, the town, and a batch of about 12 pages. Every page starts
with `=== PAGE <id> ===` and its URL, then the page's text, which is the site's words with
the menus and buttons left in. Read every page to its end: a calendar often sits below
pages of menu text.

## What to flag

- **Event**: something a neighbour can go to, at a time and a place. A concert, class,
  meeting, fundraiser, market day, game, sale with dates, worship service open to visitors,
  workshop, tour. Flag each date it is listed on, today or later: a page listing "Stitch and
  Sip" on Oct 28, Nov 19 and Dec 17 is three flags. A weekly series listed only by its rule
  ("Fridays 3–6 PM through Oct 16") is one flag with the rule written out.
- **News**: something to know rather than go to, that a neighbour would pass on. A place
  closed, moving or opening; hours that are seasonal, new or changed ("closed Mondays",
  "closed until May"); a seasonal menu, special or promotion; a cancellation; road work; a
  notice. A page whose headline is a change like these is News even when it gives no date.

The page's furniture stays unflagged: its standing menu, product lists, staff bios, contact
details, privacy text, and events whose date has passed.

## What to write

One JSON object per line and nothing else, no prose and no code fences. For each flag:

```
{"page": "<id>", "kind": "event" or "news", "title": "<as the page names it>", "when": "<the date and time exactly as the page writes them>", "date": "<YYYY-MM-DD when you can tell the day, else empty>", "place": "<where, as the page writes it, else empty>", "link": "<a URL on the page that is about this item, else empty>", "note": "<a price, sign-up or other detail worth keeping, else empty>"}
```

A page with nothing to flag gets one line: `{"page": "<id>", "kind": "none"}`. Every page in
the batch gets at least one line.

Write `date` from the page and today's date together: "Saturday, October 24" with today in
2026 is `2026-10-24`. A year the page leaves out is the next time that date comes round.
Copy `title`, `when` and `place` as written; tidying them is the judge's job.

## Done

Every page in the batch has its lines, and every Event date and piece of News on each page
is a flag. Before you answer, go back through each page once more for anything you passed
over.

## Checking this file

`python3 sources/scripts/check_flags.py` runs the cheap model on the saved pages in
`sources/evals/flag/` with these instructions and counts how many of the better model's
findings it catches. Run it whenever this file or the cheap model changes; it must catch at
least 9 of 10 (Jesse, 2026-10-13).
