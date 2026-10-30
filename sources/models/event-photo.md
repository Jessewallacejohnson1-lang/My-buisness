# Event photo: the one picture that shows each new Event

You look at the pictures each new Event came with and pick, for each Event, the one real photo of it, or
none. Your pick shows on the Event's card and page for every neighbour, credited to its place (Jesse,
2026-10-30: "they should all have a photo of event"). A wrong pick is worse than none: with none, the card
keeps its place's own photo.

Your batch file's first line names a sheet: open it with the Read tool. Each line after it is one Event: its
`event` key (`e3`), title, host, place, date and About, and its pictures, each with its `pick` number (`c7`),
where it came from, and Meta's own description when Meta gave one:
- `post`, `page` or `listing`: the post or page the Event was found on
- `other post`: another recent post of the same place

On the sheet each Event is one row, headed by its key and title, its pictures numbered under it.

## Pick

- A real photo of the Event or of one just like it at this place: people taking part, the place set up for
  it, the thing itself (the art in an exhibit, a dog in costume for a costume contest, the cast on its
  stage, staff dressed up for a Halloween treat day).
- Its own pictures (`post`, `page`, `listing`) before another post's. Take an `other post` picture only when
  it shows this kind of Event at this place: the play's rehearsal for the play, last year's contest for this
  year's, the class in its own studio for the class. Never a different kind of thing (a sports photo for a
  concert, a kindergarten photo for a parents' class), and never a portrait or headshot for an Event.
- Never any of these, however good it looks:
  - a flyer, poster or graphic: any picture with words, prices, dates, a QR code or a slogan set over or
    around it (a sign that is part of the place in a photo, like a shop's sign, is fine)
  - a collage of photos under a title, a newsletter or catalog page, a screenshot, a logo, clip art
  - a stock-looking ad (a posed model, a product on a plain background), a video still with a play button
  - one too dark, blurred or small to make out
- When you are unsure, pick none.

## Answer

One JSON line per Event in your batch, nothing else:

    {"event": "e3", "pick": "c7", "shows": "The cast on the lit stage"}
    {"event": "e4", "pick": "", "shows": ""}

`shows`: what the photo shows, under 60 characters, in plain words. It is saved with the photo.
