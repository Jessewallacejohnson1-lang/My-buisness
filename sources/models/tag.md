# Tag: the interests an Event is about, how much it draws, and what it is

You give each Event of one town every interest it is about, from a fixed list, how much it
draws a town's neighbours out, and what it is in one to three words. The Town feed lifts an Event for each neighbour who picked one of
its interests, so a right tag puts it in front of the people who'd go, and a wrong one puts it in
front of people who won't (BP app docs/plans/town-feed, ticket 33). The draw is everyone's
starting point: interests, friends and follows move each person's feed from there (ticket 34).

Each message gives the interest list, then the Events, one JSON object per line: its `id`,
`title`, `host` (who puts it on), `place`, `about` (the start of its description, often
empty) and `category` (one interest the writer already gave it, or null).

## How to tag

- Tag what the Event is about, as a neighbour would say it: a trivia night at a taproom is
  `games` and `bars`; a fall concert by the college choir is `live_music` and `campus`; a fish
  fry at a church is `dining` and `faith`; a 5K fun run for a school is `play_sports` and
  `families_kids`.
- At least 1 interest and at most 5, only ones it is really about: most Events have one or two,
  a few have three or four. Every extra tag shows the Event to people who may not care, so leave
  out what is only nearby or possible ("people might bring kids" is not `families_kids`).
- Only ids from the list. When nothing fits well, the one that fits best.

What some interests cover (BP app docs/plans/onboarding, tickets 14, 15 and 21):

- `town_meetings`: meetings of a city council, school board, board, commission or committee,
  and a club's business meeting. A city's other dates (compost site hours, a food program) are
  what they are about, not this.
- `campus`: put on by, or held at, the College of Saint Benedict or Saint John's University
  (CSB, SJU, their libraries, Outdoor U, School of Theology, athletics), always with what it is
  about: a CSB volleyball game is `watch_sports` and `campus`.
- `games`: games and trivia to play, not sports: trivia, bingo, a meat raffle, board and card
  games, puzzles, a knowledge bowl or math league meet. Bingo and meat raffles are never
  `dining` unless a meal is the point.
- `talks`: lectures, talks, panels, classes and trainings. A lecture at a church or by a monastery
  is `talks`, and `faith` only when faith is its subject.
- `books`: the library, reading, book clubs and authors. A craft or a game at the library is
  `crafts` or `games`, not `books`, unless it is about books.
- `crafts`: making things: wreaths, knitting, a craft class, a repair clinic. `art_theater` is
  art to look at and shows to watch: exhibits, plays, musicals, dance shows.
- `markets`: farmers markets, craft fairs to shop, and store events: sales, a shop's open house
  or holiday launch, Small Business Saturday. A store's party is `markets`, not `festivals`.
- `festivals`: town festivals, fairs, parades and holidays the town celebrates together.
- `families_kids`: made for children or families: story time, a kids' craft, trick or treat, a
  family day. A school's board meeting is not.
- `watch_sports`: games and meets of any sport, at any level. `play_sports`: ones you take part
  in: a fun run, a league, open gym.
- `health`: fitness, yoga, wellness and health classes. `volunteering`: giving, fundraisers,
  drives and volunteer days.
- `college`, `high_school`, `middle_school`: for students of that age and their parents. A high
  school's game, concert, play, dance or meet is `high_school`; a middle school or junior high's
  (grades 6 to 8, "MS", "JH") is `middle_school`, and a K-8 school's Event is `middle_school` only
  when it is for those grades. `college` is made for college students and their campus alone, and
  only those who picked College see it: a Student Mass or campus ministry night, a student club's
  night, the campus libraries' study breaks (therapy dogs, popcorn, game and craft nights), a
  college night in town. One CSB or SJU puts on for the public, or says all are welcome to (a
  festival, a lecture, a show, a concert, a game), is `campus` without `college`.
- `networking`: business and career Events: a chamber mixer, business after hours, a job fair, a
  small-business or professional workshop, a service club's meeting (Rotary, Lions).
- List what an Event is about first: `campus`, `college`, `high_school` and `middle_school` come
  after it ("Volleyball game" is `watch_sports`, `high_school`).
- Keep the writer's `category` when it fits, and add to it; drop it only when it is wrong.

## How much it draws

The `draw` is how many neighbours would make a point of going, not whether it's worthy:

- **3**: an outing many would plan around. A festival, fair, homecoming, parade, big concert,
  holiday market, a fundraiser dinner the town turns out for, a big game.
- **2**: a normal public event for whoever's into it. A class, talk, trivia night, recital,
  service open to visitors, club night, a regular game, a sale.
- **1**: routine business most people skip. City council, board, commission and committee
  meetings, school picture retakes, "the trimester ends", staff or members-only dates.

When unsure, 2.

## What it is

One to three words naming the kind of thing it is, as a neighbour would say it, sentence case:
"Lecture", "Concert", "Cross country meet", "Volleyball game", "Craft sale", "Mass", "Art exhibit",
"Book club", "Fish fry", "Board meeting". It sits beside the title on the card (BP app event-card
05), so it says what kind of thing, never its name, host or place: "Koch Chair Lecture" is
"Lecture"; "Wind Ensemble fall concert" is "Concert". At most 24 characters.

## What to write

One JSON object per Event, one per line, in the order given, and nothing else: no prose and
no code fences.

{"id": "<the Event's id>", "interests": ["live_music", "dining"], "draw": 2, "what": "Concert"}
