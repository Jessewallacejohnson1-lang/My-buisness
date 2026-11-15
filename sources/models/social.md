# The social watch

Places' public Facebook and Instagram posts become Events and News in the Town feed (registry
ADR-020, amended 2026-10-22 and 2026-11-11). Apify reads the pages on its own schedule (the busy list at 9:30am
and 7pm Chicago; every other page once a week, a seventh of them each day at 3pm, each day a mix of kinds; and
JoeTown's Instagram stories once a day, with the 7pm run) and saves what it finds; two routines follow
this file in the cloud half an hour or more later, each in a fresh copy of this repository, and
read what Apify saved: `busy` at 10:30am and 7:30pm, `weekly` every day at 3:45pm. The
routine's prompt names which. Scripts read Apify and write the
database; the cheap model reads the posts and you judge what it flags, exactly as the morning job
does. Work through the steps in order. A step that fails for one source is a line in the summary;
carry on with the rest.

## Steps

**Ready.** Run `python3 sources/scripts/ready.py social`, and install nothing
   any other way. It installs the libraries the scripts need and checks the database takes the
   routine's key; their values stay out of every command's output and your answer. When its line says `not ready`,
   stop and say so.
   Apify's key is the environment's network secret for `api.apify.com`, which the session never
   sees: check it with `python3 sources/scripts/social.py spend`. A line saying Apify refused
   the request means the secret is missing or wrong: stop and say so.

**Prepare.** Run `python3 sources/scripts/social.py prepare <busy|weekly>` with a 600000 ms
   timeout. It reads every Apify run of this list that finished since the last check, waits for
   one still going, and lays out each new post as a page in `.runs/morning/batches/`. A post whose
   caption is under 30 words or gives no time of day also gets up to 3 of its pictures downloaded
   into `.runs/morning/pictures/`, named at the end of its page (Jesse, 2026-10-26: Obbink's Oct 29
   trivia night was on its picture alone). Its `[social] pictures` line says what that added to
   the cost. It works in parts of about 6 minutes: while it prints `[social] run again`, or is stopped at
   the timeout, run it again, and it carries on where it stopped. Run it in the foreground, one call at a
   time: no loop and no background start (Oct 29's weekly check spent 49 minutes that way). It starts nothing paid. Done when it prints its
   `[social] busy: …` or `[social] weekly: …` line. No batches means nothing new was posted: run
   `social.py done` (Mark it read), answer with the `[social]` lines and stop.

**Read and judge, then Save.** Follow `sources/models/morning.md`'s **Read and judge** and
   **Save**: the cheap model flags each batch (`flag.md`), you judge the flags (`judge.md`),
   shorten long titles, ask a helper which News repeat what a place already has (`repeat.md`),
   and `morning.py save` writes them (on a social check it only writes).
   Each page is one post, and its first line says who posted it and when: read "tonight",
   "tomorrow" and "this Friday" from the day it was posted, not from today.

   *Keep everything (Jesse, 2026-10-22).* Social posts follow one rule that overrides
   `flag.md`'s and `judge.md`'s "standing menu, product, ad or sales post" exclusions: every
   post with something a neighbour could know or do is kept, because people who care about it
   will want it. Only a plain ad is dropped, in judging (below). Add this to each cheap-model helper's prompt: "These pages are a place's
   social posts. Flag every post with anything to know or do, including specials, deals, sales,
   new products, menu and seasonal items, pre-orders, contests and hours; only a post with
   nothing to know or do is none. When the post shows a town that `place` doesn't name, a hashtag
   or a signature included, start `place` with it exactly as written, then a colon: '#duluthmn: The
   Harbor Lofts'. This overrides 'as written' for `place`. Some pages name pictures at their end:
   open each with the Read tool and read every word on it as part of the post, and write what a
   flag takes from a picture in its note, starting 'From the picture:'." In judging:
   - A page that opens "Found by searching Facebook's events" is an event its host listed in public: its
     `source_name` is the host `pages.json` names, and `area` is where it happens, `town` or `campus`, else
     `outside`, never `announced` (the host isn't a St. Joseph source). When that page's "Where" is empty, the
     place is in the event's name or words: write it in `place`. It is in St. Joseph only when
     `sources/st-joseph-mn.md` lists it (search the file); if not, the event is `outside`. Drop one hosted only
     by a private person: a birthday, a party, a sale at home (ADR-020: a neighbour's post is a tip, never content).
   - A page that opens "… shared this in its Instagram story" is a story: its words are on its picture, and most
     pass on another account's post, whose @name is on the picture (BP app watch-every-place 25). An item from one
     belongs to that account's place: its `source_name` is that place's name when `sources/social/st-joseph-mn.json`
     or `sources/st-joseph-mn.md` has it (search for the @name), else the story's own account. Judge it like a post.
   - A post's pictures are part of it: a flag from a picture is judged like one from the caption,
     and a caption that only teases ("come out to the cocktail lounge…") is not a teaser when its
     picture says what. Before keeping an item whose day, time or place comes only from a
     picture, open that picture yourself and check it.
   - An event stays an event. A sale with its own dates is an event.
   - Everything else is News: `category` `business` for a place's own offers (a special, a
     deal, a new product or menu item, a pre-order, a contest, a weekly night), `announcement`
     for town news, `campus` for CSB and SJU. A sponsor's post about a school's team or athletes (The
     House sharing CSB's player of the week) is the school's news: its `source_name` is that school's
     athletics place, `CSB Athletic Activities` or `SJU Athletic Activities` (Jesse, 2026-11-10). Give a standing weekly special one item, not one
     per week, and fold many product posts from one place in one check into one item ("new fall
     arrivals").
   - A plain ad is not News: a post that only says come and buy this (a dish, a product, a menu, a
     listing), with no sale, deal, date or happening in it, is dropped. Jesse, 2026-11-08, on The House's
     "Joetown Burger and fries": "ads are fine as long as its a sale or something involved rather than just
     saying come buy this". A new sale or deal, a new product (one the place didn't sell before),
     a seasonal item (Collegeville Orchards' pumpkins and apples in fall: Jesse, "its new and seasonal"), a
     limited-time item or a date to order by is still News; a post being new doesn't count (Jesse: "new
     product or new sale not new post").
   - A post that gives the place's own hours for every week from now on (winter hours, new days, new
     times) also gets one `hours` item beside its News: `{"kind": "hours", "page": "<the flag's page id>",
     "days": {"mon": "Closed", "thu": "4 PM to 9 PM", "sat": "10 AM to 9 PM"}}`, with every day the post
     states, `mon` to `sun`, each written as Google writes hours ("Closed", "12 PM to 9 PM", two ranges with
     a comma). A post giving its whole week writes all seven, "Closed" for each day it leaves out. Open the
     post and its pictures and read the week there, not from the flag's line. `save` puts the week in the
     app on its own and says what changed (Jesse, 2026-11-07; BP app business-hours 02). Hours for one day or a few dates (closing early tonight, a private event, a holiday, a snow day,
     a season's first or last day) are never an `hours` item: the app's hours are a week. Neither are an
     event's times.
   - Drop only: a post with nothing to know or do (a quote, a joke, nostalgia, a thank-you,
     behind-the-scenes, a plain photo); something already over; a teaser that doesn't say what;
     a place's daily "here's what we've got" list; anything in another town that isn't an event
     (a job at another location); and anything at a business's location in another town,
     events included (Jesse, 2026-10-24: Neighbors' Albertville bar is out of the area); and any post about a private person's health or troubles
     (ADR-020).

**Photos.** Run `python3 sources/scripts/event_photos.py prepare`. For each
   `.runs/morning/photos/batch-N.txt`, start one helper on your own model, at most 10 at once (Jesse, 2026-11-07:
   Sonnet picks every photo, BP app dig-deeper 08), with:
   "Read `sources/models/event-photo.md` and follow it for `.runs/morning/photos/batch-N.txt`. Answer with
   the JSON lines only." Write their lines to `.runs/morning/event_photos.jsonl`, then run
   `python3 sources/scripts/event_photos.py keep`. Each new Event that isn't a game gets the real photo of
   it a helper picked from its post or its place's other posts, else its own flyer, or none (event-photos 09);
   each new News from a post gets the real photo from its own post that draws the eye most, else its post's own
   flyer, or none (BP app town-feed 53).

**Mark it read.** Only after `morning.py save` has printed its summary, run
   `python3 sources/scripts/social.py done`. It marks this check's Apify runs read, so the next
   one starts after them; runs a check stopped before this line on (a usage limit, a failure)
   are read by the next. Run it once, at the end, and never before the write.

**Answer** with the summary as `save` printed it, keep's `[photos]` line, `done`'s lines (the pictures line is what
   reading pictures added to the cost), every `[social] FAILED` line
   from Prepare, then one line per flag you dropped that a neighbour might have wanted, and why. A
   page Apify says is not available, or returns nothing for, three reads in a row sets itself aside
   and is named once in the summary, as is a weekly page with no new post four reads in a row (read
   once a month from then on); fixing its address or hiding it in
   `sources/social/st-joseph-mn.json` is the registry job's, with Jesse's yes.

## Rules

- Pictures are read for their facts only, except the one a Photos helper picks as an Event's or a News's photo:
  it is saved, credited to its place and taken down on request (Jesse, 2026-10-30 and 2026-11-08; ADR-020). No other
  picture is shown, uploaded or kept past this check. `.runs/` goes with the copy.
- Apify's own schedules start every paid run, each task with its own spending cap; the routine
  starts none. A run that failed or is still going is a line in the answer.
- The database is written only by `morning.py save` and `event_photos.py keep`. SQL by hand stays unused.
- Nothing is committed or pushed; `.runs/` is scratch.
