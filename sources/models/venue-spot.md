# Venue spot: the street address of a place line

An Event's Map button opens Block Party's own map at a spot, and a place line no registry, hand file or map knows
has none. Your batch holds place lines (`line`) like a sports schedule prints them: a school's gym, an arena, a hall
in Minnesota or near it. You find each one's street address. Another helper does the same on its own and you will not
see its answer; a spot goes live, with no person looking first, only where the two of you agree, so a wrong address
is worse than none: none only leaves the Event opening Apple Maps.

Each line of your batch file is a JSON object:

- `venue`: its key (`v1`). Answer under it.
- `line`: the place line, exactly as the schedule wrote it. The venue is where the game is played.
- `posted_by`: which place posted the schedule. An away game's venue is NOT this place's: "Fergus Falls Ice Arena"
  on Apollo High School's schedule is in Fergus Falls.
- `for_example`: one Event's title, for context (the opponent's town often names the venue's).
- `events`, `first`: how many Events use the line, and the date of the first. Ignore them.

## How

Use WebSearch, at most 3 searches per line, to find a page that names the venue and prints its street address:
the venue's own website first, then its school district's, city's, county's or owner's page, then a school
directory. Read the address from the search result's own words.

## Answer

One JSON line per venue, nothing else:

`{"venue": "v1", "address": "340 N Friberg Ave, Fergus Falls, MN 56537", "page": "https://…", "quote": "the words on the page that name the venue and its address (under 200 characters)", "kind": "venue", "other": ""}`

- `address`: "street, town, MN ZIP", copied as the page prints it. Never fill a street number, a town or a ZIP from
  your own memory: leave a part out when no page prints it (an address with no street number is no answer).
- `kind`: `venue` when the address is the venue's own (an arena, a hall, a center); `school` when the venue is a gym,
  pool or field inside a school, and the address is the school's (right for a pin); `weak` when the only page is a
  ticket seller, real-estate site or listing aggregator; `none` when you found no address (leave `address` empty).
- `quote` must hold the street number as the page prints it: it is checked.
- Make sure the town fits the venue's name or the schedule: a school with the same name in another state or town is
  the wrong school. If two pages disagree, answer with the venue's own or owner's page, and put the other address
  and its page in `other`.
