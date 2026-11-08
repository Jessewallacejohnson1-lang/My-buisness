# Clean About: what it is and what to expect

Jesse, 2026-11-06 (BP app inside-cards 14): an Event's About says only what the Event is and what
to expect. The price, time, date and place each have their own line on the Event page, so they
come out of the About. You rewrite each About below under that rule and keep every other fact.
Every line you write goes live: cut and move, never add or research.

Each line of the batch is one Event as JSON: `id`, `title`, `date` (its day), `start` (its start
time as the app shows it, empty when none), `end` (its end time, empty when the Event lists none),
`place` (its place line) and `about` (its words now). A line may carry `note`: what the About still says of
the Event's own fields after a first pass ("still names the Event's own place \"Sal's\""): take that out.

## Rules

- Take out of `about` what the Event's own fields hold: the date and the day of the week, the start
  time, the end time when `end` has it, the place and its address, and the price. Keep the sentence
  that is left readable; drop a sentence that said nothing else.
- A time that is not the Event's start or end stays, since it is what to expect: "doors at 6:30",
  "the parade steps off at 11", "Mass at 9 and 11".
- The cost goes to `price`: one short line in the source's own words, at most 60 characters
  ("Free", "$22, $20 seniors, $15 students", "$10 suggested donation", "$5 a plate, kids free").
  "Free" only when the words say so. No cost in the words: `price` empty. The price's conditions
  beyond the amount stay in `about` ("register by Nov 15", "limited to 20", "Registration is
  filled", "tickets at the door").
- An end time the words give when `end` is empty goes to `end` ("9 PM"), so it isn't lost, and
  comes out of `about`.
- A place detail the place line doesn't have stays in `about` when it tells you where to go once
  there ("in the church basement", "meet at the trailhead").
- Keep the writer's facts, order and tone. Nothing to take out: answer with `about` as it is.
  Everything gone: `about` empty (the page shows the date, place and price alone).

## Answer

One JSON line per Event, nothing else:

{"id": "<id>", "about": "<the About>", "price": "<what it costs, or empty>", "end": "<an end time the Event lacked, or empty>"}
