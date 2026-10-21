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
- **Games:** `<School> <Sport> vs <Opponent>`, then `: <name>` when the game has one ("CSB
  Soccer vs Hamline: Senior Night"). Keep the team's level words (JV, varsity, girls,
  boys): the merge rule tells games apart by them.
- **High school teams as neighbours say them:** "Apollo", "Tech", "Cathedral" (not "St. Cloud
  Apollo"), "Kimball" (not "Kimball Area"); a co-op joined with a hyphen ("Sartell-Sauk
  Rapids"); "Girls Swim", and no "Girls" on volleyball. A meet or tournament keeps its own name,
  with its sport when the name lacks one ("Central Lakes Conference Swim Meet"). Two long team
  names may run past 40 characters; both stay whole (read_events.py writes these).
- **The colleges are CSB and SJU.** Both together are "CSB SJU", written with a space only
  (Jesse, 2026-10-14). When the host line already names both, leave them out of the title.
  Host names follow the same rule: "CSB SJU Campus Events".
- **Plain characters.** Words joined by spaces or a colon; the title stays free of slashes.
- **One fact per spot.** The date, time, host, place, year and price live in their own spots
  (a price goes in the blurb), so the title holds the name alone.
- **The source's own capitals,** except a title written all in capitals, which gets ordinary
  ones.
- **News** follows the same rules, with what happened first ("County offices open Oct 12").

## The place line

- **The venue's name, then the town when it isn't St. Joseph:** "Clemens Stadium,
  Collegeville"; inside St. Joseph, the venue alone: "CSB Stadium".
- **A street address only when the place has no name.** When the page gives an address and
  the page or the host names the place at it, use the name: "104 Chapel Lane" is "Saint
  Benedict's Monastery".
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

## Done

Every title is the name alone in 40 characters or fewer, and every place line is a venue
(and town outside St. Joseph), a bare address only when nothing names the place, or
"Online". Check the writer's dry-run listing: the titles it prints are the cards.

## When Jesse corrects a title or place

The correction is a rule. Add it here in one line, and add its before and after to `WORDING`
in `write_judged.py`; when the code can make the change itself, make it in `tidy_title` or
`tidy_place` and run `python3 sources/scripts/write_judged.py --selftest`.
