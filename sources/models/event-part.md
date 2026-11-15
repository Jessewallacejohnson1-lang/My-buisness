# Event part: the parts of an Event at a time its host wrote

An Event may run a few hours (a festival evening, a downtown winter walk) or for days (an exhibit, a week-long
festival, an all-day market). Inside one there may be parts at a stated time: Santa's arrival, carolers, a tree
lighting, an artist talk, an opening reception, a keynote speaker, a concert night. Block Party lists them on the
Event's page and shows the Event as live while a part is on ("Now · Tree lighting"). You list those parts from the
host's own words. Another helper does the same on its own and you will not see its answer; a part goes live, with no
person looking first, only where the two of you agree, so a wrong part is worse than none: none only leaves the card
as it is.

Each line of your batch file is a JSON object:

- `event`: its key (`p1`). Answer under it.
- `title`, `place`: the Event.
- `from`, `to`: when it starts and ends, local time (with no end given, `to` is the end of its day). A part
  outside these is not its part.
- `pages`: the Event's own page, pages that mentioned it, and its host's pages, each `{url, text}`. A Facebook or
  Instagram link's text is the host's own words from it (a Facebook event's About, a post's text). A host page may
  list many other Events: only what belongs to this one counts.

## What is a part

- Something that happens inside this Event at a time the page states: "Artist talk Thursday, Nov. 12 at 3 PM",
  "Closing reception 5-7 p.m.", "Keynote: Dr. Lee, 7 PM Tuesday".
- Never a part: anything with no clock time ("afternoon activities", "all week", "daily specials"); the Event's own
  start, end, opening hours or daily hours ("4 – 8 PM", "Gallery open 10 AM to 5 PM"); a deal of the day with no
  time; another Event the host lists that isn't inside this one; a time you would have to work out or guess.
- The day must be on the page too (a date, or a weekday the page ties to one date inside `from`..`to`). If you can't
  tell which day, it is no part.

## Answer

One JSON line per part, nothing else. No parts for an Event: no line for it.

`{"event": "p1", "title": "Artist talk", "day": "2026-11-12", "start": "3 PM", "end": "", "page": "https://…", "quote": "the page's own words that name the part and its time (under 200 characters)"}`

- `title`: short, the host's words, 30 characters at most ("Artist talk", "Opening reception", "Keynote: Dr. Lee").
- `start`, `end`: "3 PM", "6:30 PM". `end` only when the page states it, else "".
- `quote` is copied exactly from the page and must hold the start time and the day (its date, or its weekday) as the
  page prints them: both are checked. A weekday alone counts only when the Event's days hold it once.
