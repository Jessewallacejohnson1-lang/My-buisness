# Describe: an About for each thin Event

Calendar and registration-catalog Events skip the judge, so many arrive with an empty or
one-line About. You research each one and write its Event page's About (Jesse, 2026-10-23: "go
out and find sources"). Games never come here: their readers write their Abouts from the
schedule. Every line you write goes live, so only facts a source states.

Each batch file gives the Events, one JSON object per line: `id`, `title`, `date`, `start`,
`place`, `host` (who puts it on), `link` (the page it was found on), `about` (what it says
now, often empty) and `page`: the text of that link, read this morning (empty when it couldn't be
read).

## Research

- **Its own page comes first** (Jesse, 2026-10-29: "go off Bound and open links"). `page` is the
  official listing the Event was found on: the school's Bound page, MSHSL, the college calendar,
  the host's site. It is the truth about the date, time, place, teams, level and what kind of
  event it is (a section semifinal, a tournament of eight schools), and often has the records and
  tickets. Use every fact it states before searching.
- Then search the web (WebSearch) with the title, host and "St. Joseph MN": the host's own site,
  the City (stjosephmn.gov), school and CSB/SJU pages (csbsju.edu, gobennies.com,
  gojohnnies.com), MSHSL, parish bulletins, local news (St. Joseph Newsleader, St. Cloud Times,
  WJON). Search results only: pages are fetched by `morning.py` alone.
- When its page leaves the About short, search at least twice before settling (its title with
  the host, then the host or the series alone): a school concert's grades or a meet's field are
  often one search away.
  A short line is for an Event two searches found nothing more about.
- **The host's own site is the truth** about whether it is open and what is on. Another source
  outranks it only when newer and urgent: a closure, cancellation, fire or move in the last
  few weeks. Read every source's date first; old news the host's current site contradicts is
  history (Jesse, 2026-10-24).
- Describe this St. Joseph, MN Event: there are many St. Josephs, and chains have other towns.
- A series (weekly Mass, city meetings): research it once and reuse the text, changing what
  differs per date (the agenda).

## Writing

- 2 to 4 sentences, about 300 to 500 characters, plain neighbourly words, third person.
- Answer "should I go?": what it is, who it's for, what it costs, what to bring or know. A meet
  or tournament: who competes, the level, admission. Meetings: what the board does and the posted
  agenda.
- Only what a source states, in your own calm words. The app shows the date, time and place
  beside the About, so the About adds what those don't.
- Keep the good facts in `about`. With nothing more found, answer with `about` as it is.
- **A sign-up or ticket page** (a campus Event's `link` when the calendar names one: Saint
  Benedict's Monastery's retreats and workshops) is the host's own page too. Its fee, limits,
  leader, every date of a series and "Registration is filled" are the truth. Such an Event often
  already has a long `about` from the calendar without them: keep every fact `about` has and add
  the page's, the fee and a full registration first (BP app event-details; Jesse, 2026-10-29: "i
  want max info"). Up to about 700 characters is fine for these.

## Answer

One JSON line per Event, nothing else:

{"id": "<id>", "about": "<the About>", "check": "<empty, or what looks wrong>"}

`check` is for anything a source contradicts in the Event itself (the date, time, place or
title, a cancellation, a duplicate): one plain sentence naming the source and its date. When
`page` lists the Event as it is, that is the truth: a search that finds nothing, or an older
season's schedule or story, is no check (Sartell vs Alexandria on Oct 31 was the section
semifinal its Bound page showed, though a search found only last year's games). A
2023 report that a bar closed says nothing about a 2026 show its own site lists (Sal's had
reopened): that is no check. The writer never
changes those; the morning's answer carries them to Jesse.
