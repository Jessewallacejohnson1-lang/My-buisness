# Dig: a photo for each Event the morning left bare

These Events got no fitting photo from the pictures they came with (`event-photo.md`). The dig looks further, on
the free rungs of the Ladder, in this order (BP app docs/plans/dig-deeper, SPEC):

1. `name`: the person or group the Event is about, by name (Jesse, 2026-11-05: "if its a talk a picture of the
   person speaking would be good what would a news artical have")
2. `site`: the place's own site, this Event or this kind of Event there in an earlier year
3. `news`: local news and school or town papers
4. `posts`: the place's own Facebook and Instagram posts of the last year, read through Apify for a title the first
   three left bare (it alone costs money, dig-deeper 23)

A finder names the pages for the first three; a script reads them, and the posts, and lays their pictures out on
sheets; a picker takes one. Your message says which part is yours.

## Find

Your batch file has one Event per line: its `event` key (`d3`), `title`, `dates`, `host`, `place`, `about`,
`found_on` (the page it was found on) and `own_site` (its place's websites, when the registry has them). For each
Event, search the web (WebSearch) and name the pages most likely to hold a real photo of it, at most two on each
rung. Search at least twice for each Event and at most five times: a first search that finds nothing is a reason to
try the name, the place or the paper another way.

- **`name`.** Who is it about? The speaker, author or poet, the teacher, the band, singer or choir, the artist, the
  person it celebrates (Dolly Parton for a Dolly Parton party), the owner teaching a class. The name is usually in the
  title or `about`. Search the name with what they do ("Terrance Hayes poet", "BLT Band Minnesota"): their own site,
  their bio on a college, church or publisher page, a story about them. An Event about no one by name (a sale, a fish
  fry, a Mass, a market): no `name` pages.
- **`site`.** Search the place's own site (`site:` its `own_site`, else the host's site the search finds) for this
  Event or this kind of Event in an earlier year: last year's fish fry, the choir's concert page, the class's gallery.
- **`news`.** St. Joseph Newsleader (thenewsleaders.com), St. Cloud LIVE (stcloudlive.com), WJON (wjon.com), Sauk Rapids
  Herald (saukrapidsherald.com), Tri-County News (tricountynews.com), The Central Minnesota Catholic
  (thecentralminnesotacatholic.org), a school's student paper: a story on this Event in an earlier year, or on its
  person or group. Search with the place's town and "MN": there are many St. Josephs. The same kind of event in
  another town than the Event's `place` is another Event: Sartell's Veterans Day parade is not St. Cloud's.
- A page about this Event, its person or its group. Not a search page, a list of events, or a home page with nothing
  on it.
- Never Facebook, Instagram, Pinterest, Wikipedia, a wire service (AP, Reuters) or a stock site (Getty, Shutterstock):
  none of them is kept.
- Search results only. Pages are read by `event_photos.py dig-sheets` alone: WebFetch and the like stay unused, since
  some sites refuse them.

Answer one JSON line per Event in your batch, nothing else; `why` is under 60 characters:

    {"event": "d1", "pages": [{"from": "name", "url": "https://...", "why": "Hayes's bio, Poetry Foundation"}]}
    {"event": "d2", "pages": []}

## Pick

Read `event-photo.md` first: its bar holds, with these changes for the dig's pictures. Each picture's `from` is its
rung (`name`, `site` or `news`), with the `page` it is on, the `page_title` and `finder_says` (why the finder chose
the page); `meta_says` is that page's own words for the picture (its alt text), often the name of who is in it.

- Take the earliest rung with a fitting photo: `name` before `site` before `news`.
- From `posts` (a batch of its own): the place's own photo of this Event, of this kind of Event at this place, or of
  its own people at it, as event-photo.md's `other post` rule; `page_title` is the post's words. Posts that say the
  title's words come first. A food special, a menu or a product shot is not this Event.
- The person the Event is about counts wherever the photo was taken (event-photo.md's "never a portrait" is for
  anyone else), on a page about them (its `page_title` or `finder_says` names them): a photo of one person doing what
  the Event is about (the speaker speaking, the artist beside their work, the band or singer on stage, the teacher
  teaching), or a portrait the page's words name as them. The artist's own work counts for their show. A headshot
  nobody names (a writer's byline photo), anyone else on the page, a book cover, or a crowd you can't tell is
  theirs: none.
- From `site` or `news`: this Event in an earlier year at this place, or this group (the choir, the team, the class),
  as event-photo.md's `other post` rule. Another place, another kind of thing or another group is none, and so is the
  same kind of event in another town than the Event's place: read the `page_title` (Sartell's Veterans Day parade
  on St. Cloud's).
- A flyer only as event-photo.md says: its words true of this Event and its date.
- When you are unsure, pick none.

Answer as event-photo.md says.
