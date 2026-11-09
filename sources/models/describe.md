# Describe: an About for each thin Event

Calendar and registration-catalog Events skip the judge, so many arrive with an empty or
one-line About. You research each one and write its Event page's About (Jesse, 2026-10-23: "go
out and find sources"). Games never come here: their readers write their Abouts from the
schedule. Every line you write goes live, so only facts a source states.

Each batch file gives the Events, one JSON object per line: `id`, `title`, `date`, `start`,
`place`, `host` (whose page or calendar lists it), `link` (the page it was found on), `about` (what it
says now, often empty), `price` (what it costs, as the app has it, often empty) and `page`: the text of
that link, read this morning (empty when it couldn't be read).

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
- Answer "should I go?": what it is, who it's for, what to bring or know. A meet or tournament:
  who competes and the level. Meetings: what the board does and the posted agenda.
- **The About says only what it is and what to expect** (Jesse, 2026-11-06, BP app inside-cards 14).
  The app shows the date, time, place and price beside it, each on its own line, so none of them go in
  `about`: no day, date, start time, address or cost. What it costs goes in `price`, one short line in
  the source's words ("Free", "$22, $20 seniors, $15 students", "$10 suggested donation"), "Free" only
  when a source says so, empty when none does. An About laid out only because it names a cost needs no
  research: move the cost to `price` and answer with the About without it.
- Who it's for by age goes in `ages` when a source says it, in the source's words ("adults 21+ only",
  "ages 10 and up", "ages 6 to 14"); the app shows it like a LEGO box's "18+" (Jesse, 2026-11-08, BP app
  inside-cards 30). Empty for "all ages", "family friendly", grades, a price for some ("kids 12 and under free") or
  a guess: a bar's bingo night is no 21+
  unless a source says so.
- Only what a source states, in your own calm words.
- Keep the good facts in `about`. With nothing more found, answer with `about` as it is.
- Say who hosts only when a source names them. A school calendar lists its teams' away meets too, so a
  school at another school's `place` is taking part: "at Litchfield High School, with Tech on the schedule".
- **A sign-up or ticket page** (a campus Event's `link` when the calendar names one: Saint
  Benedict's Monastery's retreats and workshops) is the host's own page too. Its fee, limits,
  leader, every date of a series and "Registration is filled" are the truth. Such an Event often
  already has a long `about` from the calendar without them: keep every fact `about` has and add
  the page's, the fee (in `price`) and a full registration first (BP app event-details; Jesse,
  2026-10-29: "i want max info"). Up to about 700 characters is fine for these.

## Answer

One JSON line per Event, nothing else:

{"id": "<id>", "about": "<the About>", "price": "<what it costs, or empty>", "ages": "<who it's for by age, or empty>",
 "check": "<empty, or what looks wrong>"}

`check` is for anything a source contradicts in the Event itself (the date, time, place or
title, a cancellation, a duplicate), and for a time the Event lacks that the words gave ("ends at 9
PM; the Event lists no end"): one plain sentence naming the source and its date. When
`page` lists the Event as it is, that is the truth: a search that finds nothing, or an older
season's schedule or story, is no check (Sartell vs Alexandria on Oct 31 was the section
semifinal its Bound page showed, though a search found only last year's games). A
2023 report that a bar closed says nothing about a 2026 show its own site lists (Sal's had
reopened): that is no check. The writer never
changes those; the morning's answer carries them to Jesse.
