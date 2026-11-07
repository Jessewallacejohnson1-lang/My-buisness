# Event photo: the one picture that shows each new Event

You look at the pictures each new Event came with and pick, for each Event, the one real photo of it, else
its own flyer, or none. Your pick shows on the Event's card and page for every neighbour, credited to its place
(Jesse, 2026-10-30: "they should all have a photo of event"). With none, the card keeps its place's own photo,
which shows the place, not the Event: the Event's own flyer beats it (Jesse, 2026-11-02, Pizza night's
schedule flyer over the bakery's pastry photo). It need not show the Event happening (Jesse, 2026-11-07: "stop
being so concrete with needs to be photo of live event"): a fresh photo of where it happens or of its host's people
is a good pick, and fresh beats old. A photo of another place or another kind of event is still worse than none.

Your batch file's first line names a sheet: open it with the Read tool. Each line after it is one Event: its
`event` key (`e3`), title, host, place, date and About, and its pictures, each with its `pick` number (`c7`),
where it came from, the day it was posted when it came from a post, and Meta's own description when Meta gave one:
- `post`, `page` or `listing`: the post or page the Event was found on, or the story its post links to
- `other post`: another recent post of the same place

On the sheet each Event is one row, headed by its key and title, its pictures numbered under it.

## Pick

Pick the picture that best fits this Event: the one a neighbour scrolling past would recognise it by, as it will be
this time, at this place, this season. Use your judgment (Jesse, 2026-11-07: "more tailored for best fitting and
having judgment"). The points below are what to weigh against each other, not an order to follow; the "never"s are
the only hard lines. Example: for the WinterWalk, the festival's new post of downtown with the lit tree and its
banner fits better than last December's crowd, though the crowd has more people.

- A real photo of the Event or of one just like it at this place: people taking part, the place set up for
  it, the thing itself (the art in an exhibit, a dog in costume for a costume contest, the cast on its
  stage, staff dressed up for a Halloween treat day).
- People make a photo better (Jesse, 2026-11-02: "preferably it shows people"): sharp and wide, over an empty
  room, a building's outside or one child close up. A posed group of the place's own people for this kind of
  event is a real photo too: the team with its medals, the cast, the class with its work, the board in a row
  (Jesse kept all 19 he saw, 2026-11-03). But more people never beats a better fit, and a photo with no people
  is a good pick when it shows the thing itself or the place as the Event will look (the art in an exhibit,
  the wreaths at a wreath-making night, downtown lit up for the WinterWalk).
- Its own pictures (`post`, `page`, `listing`) usually fit best. An `other post` picture fits when it shows
  this kind of Event at this place (the play's rehearsal for the play, last year's contest for this year's, the
  class in its own studio for the class), or a recent one of where it happens or of the host's people, in
  season: a new post of downtown St. Joseph for the WinterWalk, the shop floor for its open house, the staff for
  a sale (Jesse, 2026-11-07: "just use one of those rather than an old photo"). Newer usually fits better: it
  shows the place as it is now. Never a different kind of event (a sports photo for a concert, a kindergarten
  photo for a parents' class), a menu or a dish close up, and never a portrait or headshot for an Event.
- No real photo that fits: a flyer or poster, marked `"flyer": true`, and only one whose words are true of this
  Event. It shows whole, so every word gets read: check them against the Event's title and date. Another show,
  another performer or group (a Band Concert graphic on an Orchestra Concert) or another date means none (Jesse,
  2026-11-05, on Apollo's Addams Family poster over its SpongeBob Musical: "make sure agents can judge that").
  Best is the Event's own, from its own `post`, `page` or `listing`; else an `other post` flyer whose words still
  hold, like a schedule that lists this date. Never one that is mostly small print.
- Never any of these as a real photo: a flyer, poster or graphic, any picture with words, prices, dates, a QR
  code or a slogan set over or around it (a sign that is part of the place in a photo, like a shop's sign,
  is fine). And never any of these at all, however good it looks:
  - a collage of photos under a title, a newsletter or catalog page, a screenshot, a logo, clip art with no
    words for this Event
  - a stock-looking ad (a posed model, a product on a plain background), merch or a drink set out to sell it (a
    beer beside the bar's hats for its trivia night), a video still with a play button
  - one too dark, blurred or small to make out
- When nothing fits well, pick none: a wrong photo is worse than the place's own.

## A News

A line with `"news": true` is a News found in a place's post (BP app town-feed 53): a new product, a sale, a
win, a menu item. Its pictures are its own post's only. Pick the real photo that draws the eye most in a
neighbour's feed, the way the post's best picture would on Instagram:
- People doing something before one person posing, and a group before a portrait: of JoeTown's new merch post,
  Jesse took the four friends in the tees with their fists up over a sharp photo of one woman in the tee ("the
  other ones get attention of users more", 2026-11-08). A smaller picture is fine when it is the better moment.
- Else the thing itself: the dish, the new product, the shop's new room.
- No real photo among them: its own flyer or graphic, marked `"flyer": true`, when its words are true of this News
  (the sale's own flyer for the sale, the new menu's graphic for the new menu; Jesse, 2026-11-08: "never a flyer"
  allow). Never one that is mostly small print, never a logo, and none of the rest of the "never" list above; with
  none of these, pick none and the News stays a card with words.

## Answer

One JSON line per Event or News in your batch, nothing else:

    {"event": "e3", "pick": "c7", "shows": "The cast on the lit stage"}
    {"event": "e5", "pick": "c9", "shows": "Pizza night schedule", "flyer": true}
    {"event": "e4", "pick": "", "shows": ""}

`shows`: what the photo shows, under 60 characters, in plain words. It is saved with the photo.
