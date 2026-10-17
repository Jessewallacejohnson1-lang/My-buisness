# Judge: the cheap model's flags become Events and News

The cheap model read this morning's changed pages and flagged generously
(`.runs/morning/flags.jsonl`, one JSON line per flag, in `flag.md`'s shape). You decide what
each flag really is and write the judged items `write_judged.py` takes, one JSON object per
line, into `.runs/morning/judged.jsonl`. The writer does the rest: trust, merging with what is
already listed, show-from days, wording. A flag you drop is gone for today; a flag you keep
unsure waits for Jesse. Keep what a neighbour would want to hear about.

Read these first:
- `.runs/morning/pages.json`: each page's id (a flag's `page`), registry name, URL, category
  and trust.
- `.runs/morning/batches/`: the pages' text, to check a flag against what the page says.
- `.claude/skills/title-and-place/SKILL.md`: how a title and place line read.
- `.runs/morning/prepare.json`: today's date and the interest ids.

## Each flag

1. **Keep or drop.** Drop it when the page doesn't back it up, when it is in the past, when it
   is more than 90 days out, when it is a product, a standing menu, an ad or a business's how-to
   or sales post (a blog's news feed is mostly those), or when it repeats another flag (same
   thing, same day). An event with no day the page states is dropped,
   unless the page gives its rule ("Fridays through Oct 16"): then write one item for its next
   date.
2. **Event or News.** An Event is something a neighbour can go to, at a time and a place;
   anything else worth knowing is News.
3. **Write the item** (the contract is in `write_judged.py`'s docstring):
   - `kind`, `title`, `place` (the skill's rules), `town` ("St. Joseph" or the town it is in).
   - `start` and `end`: ISO 8601 with Chicago's offset, `-05:00` through Nov 1, 2026 and
     `-06:00` from Nov 1, 2026 to Mar 14, 2027; a date alone with `all_day: true` when the page
     gives no time.
   - `area`: `town` when it happens in St. Joseph; `campus` for any CSB or SJU event; `game`
     for a high school game within 20 miles; `announced` for anything else a St. Joseph place
     posts, wherever it is. Every page here comes from a St. Joseph place, so nothing is
     `outside`.
   - `source_name` (the page's registry name), `source_url` (the flag's link, else the page's
     URL), `source_uid` empty.
   - `trust`: the page's trust (`squishy` means `secondhand`).
   - `sure`: false when the page leaves the date, time or place in doubt, contradicts itself,
     or may be about another town (a chain's promotion, a business with two locations).
   - Events: `size`, `signup_by` when sign-ups or tickets close, `closed: true` when nobody
     can still go (sign-ups or tickets closed, sold out, registration full, members or
     invitation only), `interest` (one id from the list, or null when none fits). News: `category` (`announcement`, `road`, `school`,
     `campus` or `business`). Both: `blurb`, one line in plain words.

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
