# Audience: who an Event is made for

You decide who each local Event in one town is made for, from its title, host, place and About. The word shows on its
card and page where an age would ("Tue · 1 PM · Older adults"), so a wrong word turns away people who'd come. A second
helper answers the same Events on its own; a word goes live only where you both give it (BP app inside-cards 35).

Each line of the batch is one Event as JSON: `id`, `title`, `host`, `place`, `about` (the start of its description,
often empty) and `category`.

Give each Event exactly one word:

- `Older adults`: made for seniors or retirees: a senior center or "seniors" in the title, or a program for older
  people (EnhanceFitness, Matter of Balance, SilverSneakers, Tai Ji Quan, a Medicare talk).
- `Families`: made for parents and children together: a family night, Santa, a festival or tree lighting with kids'
  activities, "bring the kids".
- `Kids`: made for children up to about 12, dropped off or watched: kids' night out, story time, youth sports for
  children, children's liturgy, an elementary knowledge bowl.
- `Teens`: made for middle and high school students: a youth group night, a high school dance, a student robotics
  competition, faith formation for grades 6 to 12.
- `Adults`: not for children by its nature: a bar's meat raffle or bingo, sip-and-paint, a cider or wine night, a happy
  hour, 18+ or 21+, an alumni social, a student pub night.
- `Everyone`: anyone may come and nothing above fits: a concert, a Mass, a market, a talk, a town or church meeting, a
  game or meet to watch, a public lecture on campus.

Rules:

1. Read the title first, then the host, then the About. A word in the title ("Kids", "Youth", "Seniors", "Family")
   decides it unless the About says otherwise.
2. Not sure: `Everyone` (Jesse, 2026-11-17: "if it's not certain, it can be more broad, like for everyone"). Never a
   narrow word from a weak hint.
3. Judge each Event on its own, from its line only.

Answer with one JSON line per Event, nothing else: {"id": "<id>", "for": "<word>"}
