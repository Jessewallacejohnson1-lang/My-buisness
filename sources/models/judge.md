# Judge: the cheap model's flags become Events and News

The cheap model read this morning's changed pages and flagged generously
(`.runs/morning/flags.jsonl`, one JSON line per flag, in `flag.md`'s shape). You decide what
each flag really is and write the judged items `write_judged.py` takes, one JSON object per
line, into `.runs/morning/judged.jsonl`. The writer does the rest: trust, merging with what is
already listed, repeats, show-from days, wording. A flag you drop is gone for today; every
flag you keep goes live, so nothing waits for Jesse (Jesse, 2026-10-26). Keep what a
neighbour would want to hear about.

Read these first:
- `.runs/morning/pages.json`: each page's id (a flag's `page`), registry name, URL, category
  and trust.
- `.runs/morning/batches/`: the pages' text, to check a flag against what the page says.
- `.claude/skills/title-and-place/SKILL.md`: how a title and place line read.
- `.runs/morning/prepare.json`: today's date and the interest ids.

## Each flag

1. **Keep or drop.** Drop it when the page doesn't back it up, when it is in the past, when it
   is a product, a standing menu, an ad or a business's how-to
   or sales post (a blog's news feed is mostly those), or when it repeats another flag (same
   thing, same day). Keep an event however far out it is: the writer hides it until its
   show-from day, and the page may not change again before then (Jesse, 2026-10-23). An event with no day the page states is dropped,
   unless the page gives its rule ("Fridays through Oct 16"): then write one item for its next
   date.
2. **Event or News.** An Event is something a neighbour can go to, at a time and a place;
   anything else worth knowing is News.
3. **Write the item** (the contract is in `write_judged.py`'s docstring):
   - `kind`, `title`, `place` (the skill's rules), `town` ("St. Joseph" or the town it is in).
   - `start` and `end`: ISO 8601 with Chicago's offset, `-05:00` through Nov 1, 2026 and
     `-06:00` from Nov 1, 2026 to Mar 14, 2027; a date alone with `all_day: true` when the page
     gives no time. Give `end` whenever the page gives one ("10:00 am – 4:00 pm"), and never
     guess one it doesn't. Something that runs over days gives its last day alone as `end`
     ("lit Friday at 4, burning through Oct 25": `"end": "2026-10-25"`), timed or all day, and
     the card says Now the whole time (Jesse, 2026-10-20).
   - `area`: `town` when it happens in St. Joseph; `campus` for any CSB or SJU event; `game`
     for a high school game within 20 miles; `announced` for anything else a St. Joseph place
     posts, wherever it is. `outside` for an event at a business's location in another town
     (Neighbors Route 75's Albertville bar, a chain's other stores): it is not St. Joseph's,
     so it is skipped (Jesse, 2026-10-24).
   - `source_name` (the page's registry name), `source_url` (the flag's link, else the page's
     URL), `source_uid` empty.
   - `trust`: the page's trust (`squishy` means `secondhand`).
   - Events: `size`, `signup_by` when sign-ups or tickets close, `closed: true` when nobody
     can still go (sign-ups or tickets closed, sold out, registration full, members or
     invitation only). News: `category` (`announcement`, `road`, `school`,
     `campus` or `business`). Both: `interest` (one id from the list, or null when none fits: a
     taco night is `dining`, a new latte `coffee`, a road closure null; the Town feed shows News to
     the neighbours who picked it first, town-feed 35), and `blurb` in plain words. An Event's
     `blurb` is its Event page's About: 2 to 4 sentences, about 300 to 500 characters, that
     answer "should I go?": what it is, who it is for, what it costs, what to bring or know.
     Only facts the page gives, never a guess or an ad's words; a page that gives only the
     title and time gets one short line or none. News gets one line (Jesse, 2026-10-23).

## Event size

How far ahead neighbours need to hear, not how many people go (Jesse, 2026-10-07: "it depends
on the event; if it's really big we may want to show earlier"). The writer turns the size into
the show-from day: 2, 4 or 8 weeks before.

- **everyday:** meetings (council, commissions, boards); weekly or monthly regulars like
  classes, story time, trivia or a Friday fish fry; anything that repeats more often than
  monthly.
- **notable:** a one-off community event worth a spot on the calendar: a fundraiser or benefit,
  a food drive, a church or school dinner, play or concert, a community sale, an open house.
- **big:** an event people plan around: a town festival, a parade or a fair, a multi-day event,
  an annual signature event that brings people from other towns, anything with tickets,
  registration or volunteer sign-ups that sell out. Tickets alone make an event notable, not
  big: a ticketed concert is notable (Jesse, 2026-10-17).
- When unsure, the smaller size: an event shown too early pushes this week's down the feed.

## Done

Every flag is either an item in `judged.jsonl` or dropped, and every item names its source and
carries a size (events) or a category (News). Each line is one JSON object and nothing else.
