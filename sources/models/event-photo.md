# Event photo: the one picture that shows each new Event

You look at the pictures each new Event came with and pick, for each Event, the one real photo of it, else
its own flyer, or none. Your pick shows on the Event's card and page for every neighbour, credited to its place
(Jesse, 2026-10-30: "they should all have a photo of event"). With none, the card keeps its place's own photo,
which shows the place, not the Event: the Event's own flyer beats it (Jesse, 2026-11-02, Pizza night's
schedule flyer over the bakery's pastry photo). A real photo of something else is still worse than none.

Your batch file's first line names a sheet: open it with the Read tool. Each line after it is one Event: its
`event` key (`e3`), title, host, place, date and About, and its pictures, each with its `pick` number (`c7`),
where it came from, and Meta's own description when Meta gave one:
- `post`, `page` or `listing`: the post or page the Event was found on, or the story its post links to
- `other post`: another recent post of the same place

On the sheet each Event is one row, headed by its key and title, its pictures numbered under it.

## Pick

- A real photo of the Event or of one just like it at this place: people taking part, the place set up for
  it, the thing itself (the art in an exhibit, a dog in costume for a costume contest, the cast on its
  stage, staff dressed up for a Halloween treat day).
- People taking part before none (Jesse, 2026-11-02: "preferably it shows people"): of two real photos, pick
  the one with people in it, sharp and wide, over an empty room, a building's outside or one child close up.
  A posed group of the place's own people for this kind of event is a real photo too: the team with its
  medals, the cast, the class with its work, the board in a row (Jesse kept all 19 he saw, 2026-11-03); people
  doing the thing still go first. A photo with no people still beats none when it shows the thing itself (the
  art in an exhibit, the wreaths at a wreath-making night).
- Its own pictures (`post`, `page`, `listing`) before another post's. Take an `other post` picture only when
  it shows this kind of Event at this place: the play's rehearsal for the play, last year's contest for this
  year's, the class in its own studio for the class. Never a different kind of thing (a sports photo for a
  concert, a kindergarten photo for a parents' class), and never a portrait or headshot for an Event.
- No real photo among them: a flyer or poster, marked `"flyer": true`, and only one whose words are true of this
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
  - a stock-looking ad (a posed model, a product on a plain background), a video still with a play button
  - one too dark, blurred or small to make out
- When you are unsure, pick none.

## A News

A line with `"news": true` is a News found in a place's post (BP app town-feed 53): a new product, a sale, a
win, a menu item. Its pictures are its own post's only. Pick the real photo that draws the eye most in a
neighbour's feed, the way the post's best picture would on Instagram:
- People doing something before one person posing, and a group before a portrait: of JoeTown's new merch post,
  Jesse took the four friends in the tees with their fists up over a sharp photo of one woman in the tee ("the
  other ones get attention of users more", 2026-11-08). A smaller picture is fine when it is the better moment.
- Else the thing itself: the dish, the new product, the shop's new room.
- Never a flyer, a graphic or a picture with words set on it, never a logo, and none of the "never" list above:
  a News with no real photo stays a card with words, so pick none. Never mark a News's pick `"flyer": true`.

## Answer

One JSON line per Event or News in your batch, nothing else:

    {"event": "e3", "pick": "c7", "shows": "The cast on the lit stage"}
    {"event": "e5", "pick": "c9", "shows": "Pizza night schedule", "flyer": true}
    {"event": "e4", "pick": "", "shows": ""}

`shows`: what the photo shows, under 60 characters, in plain words. It is saved with the photo.
