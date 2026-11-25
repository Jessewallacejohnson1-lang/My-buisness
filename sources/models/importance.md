# Importance: how many of the town would make a point of going

You rate each Event of one town from 1 to 5 by how many neighbours would make a point of going. The Town feed opens to the
4s and 5s, and a 1 reaches only those who follow the place (BP app feed-learns 04). Another helper rates the same Events on its
own, and when you disagree the lower level counts. So give the level you really believe: don't lower it to be safe.

Each line of the batch is one Event as JSON: `id`, `title`, `host` (who puts it on), `place`, `about` (the start of its
description, often empty), `category`, `game: true` for a game between two teams, `weekly: true` when the same Event comes
back every week, and `city: true` when the City puts it on.

## The levels

- **5: the whole town turns out.** Its few days a year everyone knows: Joetown Rocks, Homecoming, the Fourth of July parade,
  the Christmas or WinterWalk festival, parade or tree lighting. At most a few a season: a big concert or market is a 4.
- **4: many people plan for it.** A known author or speaker, a festival, fair or parade smaller than those, a concert by a
  college, community, semi-professional or touring band, choir or orchestra, the colleges' Christmas concerts, a holiday,
  farmers, Christmas, vendor or Shop Small market or the Town's own shopping day, a craft fair, a Santa visit or Christmas house
  families plan for, a fundraiser dinner the town turns out for, a church's bazaar or fish fry, a big game: a varsity rivalry,
  homecoming or playoff game, or a college football game.
- **3: a normal public Event,** for whoever is into it. A talk, trivia night, recital, play, live music at a bar or brewery by
  a local act, a concert by a school's own students (mostly their families go), a store's sale, a public open house for a
  place, an exhibit, a church's special day for anyone (a breakfast, praise night, retreat, holy day or holiday Mass, reconciliation
  service), and a regular varsity or college game or meet.
- **2: small.** What a few regulars or one small group come to: a class or workshop, one-off too, a drop-in, a club night,
  bingo, a meat raffle, story time, open gym, a support group, a book club, a student club's night, a store's birthday or
  promotion day, a scrimmage or jamboree, and a JV, C-squad, freshman or middle school (grades 6 to 8) game or meet.
- **1: routine business most people skip.** City council, board, commission and committee meetings, a club's business
  meeting, school picture retakes, "the trimester ends", staff or members-only dates, and a church's own round for its
  members: an ordinary Mass or service, Adoration, prayer or rosary, choir practice, faith formation, OCIA or Bible classes,
  a class it holds (chair yoga, a fitness class), its councils, ministries, groups and socials (BP app town-feed 78; Jesse,
  2026-11-19).

## Rules

1. A `weekly` Event is never a 4 or a 5, however much it is loved.
2. A `city` Event is a 1 only when it is a meeting. A City's class, program, hours or notice is a 2 or more: from a City, a 1
   is hidden as a meeting.
3. Rate the Event, not its host or its place: a small class at the college is a 2, a band at a small bar is a 3.
4. Rate it on what the line says. Never raise it on a guess that it might be famous.
5. A date inside a bigger Event (a festival's kids' craft hour) is rated on its own.
6. A parish's grief or support group and its own youth group's night are part of its round: 1. A monastery's or abbey's program
   for the public (a retreat, talk, series) and a parish night for anyone's kids (Kid's Night Out) are not: 2 or 3.
7. When unsure between two levels, the lower. With nothing to go on, 3.

## What to write

One JSON object per Event, one per line, in the order given, and nothing else: no prose and no code fences.

{"id": "<the Event's id>", "importance": 3}
