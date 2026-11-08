---
name: title-and-place
description: Title and place wording for every Block Party posting, Event or News. Use when writing a judged item's title or place (the morning job's judge, a found event or news added by hand), or when Jesse corrects how a card's title or place line reads.
---

# Title and place

A card shows a host line, a title, the date and time, and a place line. The title and place
line are the only words a neighbour reads, so they carry the event's name and where it is,
in the words a neighbour would use. Everything else already has its own spot on the card.

`sources/scripts/write_judged.py` tidies every item on its way in (`tidy_title`,
`tidy_place`): college names, slashes, years, prices, notes in brackets, street addresses
after a venue, state and ZIP. Write the item well and the tidy step changes nothing; this
skill covers the calls the code can't make.

## The title

- **The event's own name, in 40 characters or fewer.** When a page's title runs longer, keep
  the part a neighbour would recognise: the speaker, the show or the main name. Shorten by
  keeping the source's own words, never by cutting mid-word: over 40 is three lines on the Town's
  Event of the day poster (Jesse, 2026-10-21). The morning job lists every one still over 40
  (`morning.py titles`) and its model gives each a short one; the writer keeps a listed short
  title when its source sends the long one again.
- **Games:** `<Home> <Sport> vs <Visitors>`, then `: <name>` when the game has one ("CSB
  Soccer vs Hamline: Senior Night"), or ` · <level>` below varsity ("Apollo Volleyball vs
  Brainerd · JV"). Keep the team's level words (JV, varsity, girls, boys): the merge rule tells
  games apart by them. The school readers write every game's title and About (read_events.py
  `game_title`, `game_about`; smooth-mornings 06), so no game reaches the morning's titles or
  describe work.
- **High school teams as neighbours say them:** "Apollo", "Tech", "Cathedral" (not "St. Cloud
  Apollo"), "Kimball" (not "Kimball Area"); a co-op joined with a hyphen ("Sartell-Sauk
  Rapids"); "Girls Swim", and no "Girls" on volleyball. A meet or tournament keeps its own name,
  with its sport when the name lacks one ("Central Lakes Conference Swim Meet"; the school reader's
  `bound_with_sport` does it for a Bound meet, Jesse, 2026-11-04).
- **A game over 40** gives up a little at a time, never a word cut, until it fits: a school's kind
  ("Willmar MS" is "Willmar"), the host line's own team ("Boys Basketball vs Willmar · C-squad"),
  a co-op's later towns ("Sartell-Sauk Rapids" is "Sartell"), the level's short form ("8th", "MS";
  "C-squad" stays whole, and a school's second C team is "C2-squad"), the boys or girls, then the
  level. Its About keeps all of them. On a
  third school's ground (a section game) neither team is the host's, so both stay.
- **The colleges are CSB and SJU.** Both together are "CSB SJU", written with a space only
  (Jesse, 2026-10-14). When the host line already names both, leave them out of the title.
  Host names follow the same rule: "CSB SJU Campus Events".
- **Plain characters.** Words joined by spaces or a colon; the title stays free of slashes.
- **One fact per spot.** The date, time, host, place, year and price live in their own spots
  (a price goes in the blurb), so the title holds the name alone.
- **The source's own capitals,** except a title written all in capitals, which gets ordinary
  ones.
- **News** follows the same rules, with what happened first ("County offices open Oct 12"), and
  fits its card's 2 lines on a 402 pt phone (Jesse, 2026-11-07; BP app inside-cards 13). The writer
  measures each one in the card's font (`write_judged.headline_fits`): "Johnnies football home
  opener, Sept. 5" fits at 38 characters, "Pumpkin Crafted Cold Brew at Caribou" doesn't at 36.
  30 characters or fewer always fits. The morning job lists every News title past its 2 lines
  (`morning.py titles`), and its model gives each one of 30 at most in the source's own words.

## The place line

- **The venue's name, then the town when it isn't St. Joseph:** "Clemens Stadium,
  Collegeville"; inside St. Joseph, the venue alone: "CSB Stadium".
- **A street address only when the place has no name.** When the page gives an address and
  the page or the host names the place at it, use the name: "104 Chapel Lane" is "Saint
  Benedict's Monastery"; "14215 Fruit Farm Road" is "Episcopal House of Prayer, Collegeville".
- **No word twice in a row:** "ROCORI High School High School Gym" is "ROCORI High School Gym" (Bound
  joins a school and its room; the school reader writes them once, Jesse, 2026-11-04).
- **"Online"** for a webinar or virtual event.
- **City Council and EDA meetings with no room listed are at "City Hall"** (Jesse, 2026-10-20). The
  writer fills it in (`MEETS_AT`); the Park Board moves between City Hall and the parks, so it stays blank.
- **No end at 11:59 PM:** that is a calendar's way of giving no end time, and the writer drops it.
- **Room numbers and buildings stay** when they help someone find it ("Gorecki 204, CSB").

## Examples (read 2026-10-14)

| As the source wrote it | On the card |
|---|---|
| College of Saint Benedict Soccer vs Hamline - Senior Night · St. Joseph, Minn., CSB Stadium | CSB Soccer vs Hamline: Senior Night · CSB Stadium |
| Saint John's University Football vs Concordia (Homecoming) · Collegeville, Minn., Clemens Stadium | SJU Football vs Concordia: Homecoming · Clemens Stadium, Collegeville |
| CSB+SJU Jazz Ensemble (host CSB SJU) | Jazz Ensemble |
| Homecoming 2026 | Homecoming |
| Plant Bingo benefiting Angel Reins Stable ($30) | Plant Bingo for Angel Reins Stable |
| Koch Chair in Catholic Thought and Teaching Presents the Reverend Daniel G. Groody | Rev. Daniel Groody: Koch Chair Lecture |
| Advent Sacred Pause • Virtual · 104 Chapel Lane, Saint Joseph, MN | Advent Sacred Pause · Online |
| Gorecki Center at the College of Saint Benedict, College Avenue South, Saint Joseph, MN | Gorecki Center |
| Anniversary of the Dedication of Sacred Heart Chapel (2026-10-21) | Sacred Heart Chapel Anniversary |
| "What is the price of liberty?" by the Humanities Institute | What is the price of liberty? |
| The Great Pumpkin Returns to Saint John's Abbey! | The Great Pumpkin Returns |
| Christmas Craft Sale at Saint Scholastica Convent (the place line says where) | Christmas Craft Sale |
| Festival of Cultures Student Showcase and Fashion Show | Festival of Cultures Fashion Show |
| Nordic Ski Racing, Boys: Section Championship (Varsity) | Section Nordic Skiing Championship |
| Dance: Edina Invite (Varsity) (Time TBA) | Edina Dance Invite |
| Drama: Apollo Theater Presents: The SpongeBob Musical (Varsity) | The SpongeBob Musical |
| Theatre: vs St. Cloud Cathedral (Winter Show) | Winter Show |

## Done

Every title is the name alone in 40 characters or fewer (a News title fits its 2 lines), and every place line is a venue
(and town outside St. Joseph), a bare address only when nothing names the place, or
"Online". Check the writer's dry-run listing: the titles it prints are the cards.

## When Jesse corrects a title or place

The correction is a rule. Add it here in one line, and add its before and after to `WORDING`
in `write_judged.py`; when the code can make the change itself, make it in `tidy_title` or
`tidy_place` and run `python3 sources/scripts/write_judged.py --selftest`.
