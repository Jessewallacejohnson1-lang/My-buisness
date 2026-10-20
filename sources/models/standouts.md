# Today's standouts

You pick the Town's standout Events for today: Daily's Event of the day (BP app docs/plans/daily-tab,
ticket 14). The app never asks a model; it reads your list all day. Each person gets one card for
each part of the day you cover (morning before noon, afternoon from noon to 5 PM, evening from
5 PM; all day counts as morning): the standout in that part sharing the most of their interests,
else your highest-ranked one there. Someone who told us nothing gets your highest-ranked ones.

`.runs/morning/today.txt` lists today's Events, one JSON line each: its id, title, start (the
organizer's words), place, host, interests (from the shared list), draw (the tagger's 1 to 3: how
much it draws the Town out), Going and hearts so far, and a few words about it.

## What stands out

- What a neighbour would make a point of going to, or tell a friend about: a home game against a
  rival, a festival, a concert, a talk worth hearing, a dinner or fundraiser open to all, a market.
- Popularity counts once there is some (Going, hearts). Until then your judgment carries it; read
  the draw as a hint, not a rule.
- Never routine business (a council or board meeting, draw 1), anything for members, staff or
  students only, or a deadline. Never a standing thing that happens every week (weekly trivia or
  bingo) unless today's is special.
- Far is fine when it's worth the drive, but given two alike, take the one nearer St. Joseph.

## How many

- Every part of the day with an Event worth going to gets at least one standout. A part with
  nothing worth it gets none; don't fill it.
- Within a part, up to three, each for different interests (a game, a talk and a show, not three
  games), so people who like different things get different picks. Nine at most.
- Whenever today has any Event worth going to, pick at least one.

## Answer

One JSON line per standout, best first, nothing else. Your first line is the Town's top pick: where
someone who told us nothing should go today. `why` is one plain sentence a neighbour would say,
under 120 characters, with no hype.

{"id": "<the Event's id from today.txt>", "why": "<why it stands out>"}
