# Dig: a photo for each Event the morning left bare

These Events got no fitting photo from the pictures they came with (`event-photo.md`). The dig looks further, on
the free rungs of the Ladder, in this order (BP app docs/plans/dig-deeper, SPEC):

1. `name`: the person or group the Event is about, by name (Jesse, 2026-11-05: "if its a talk a picture of the
   person speaking would be good what would a news artical have")
2. `site`: the place's own site, this Event or this kind of Event there in an earlier year
3. `news`: local news and school or town papers
4. `posts`: the place's own Facebook and Instagram posts of the last year, newest first, read through Apify for a
   title the first three left bare or gave only a `site` or `news` photo: the place's own post beats an old photo
   from elsewhere (Jesse, 2026-11-07, the WinterWalk's new post of downtown "rather than an old photo"). It alone
   costs money (dig-deeper 23).

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
- **An exhibit** (its line says `"exhibit": true`: an art show, gallery exhibit or museum show) wants the work on
  display (BP app event-photos 24; Jesse, 2026-11-17: "for exhibits we need to be trying to find photos of work
  displayed"). Read the About for every artist and search each one: their own site on `name`, one page per artist. On
  `site`, the host's own page for this show; on `news`, the story about it. And each artist's own Instagram profile
  (`https://www.instagram.com/<handle>`), as `"from": "artist"`: the place's posts step reads it beside the gallery's own
  posts. This is the one Instagram page a finder names.
- A page about this Event, its person or its group. Not a search page, a list of events, or a home page with nothing
  on it.
- Never Facebook, Instagram (but an exhibit's artists), Pinterest, Wikipedia, a wire service (AP, Reuters) or a stock site (Getty, Shutterstock):
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

- Take the photo that best fits, whatever its rung: weigh fit, place, season and freshness by judgment, as
  event-photo.md says. For a talk, reading or show, the person it is about usually fits best.
- From `posts` (a batch of its own): the place's own posts (`page_title` is the post's words, `posted` its day),
  with the free rungs' choice beside them when they had one (`from` `site` or `news`). Keep whichever fits this Event
  best, or none. A post fits when it passes event-photo.md's caption test: this Event or this kind at this place, or
  the place dressed for it (the WinterWalk festival's new post of downtown over last December's crowd). Its own flyer whose words are true of this Event counts (Jesse, 2026-11-07: "keep flyer"). A
  food special, a menu or a product shot is not this Event.
- The person the Event is about counts wherever the photo was taken, on a page about them (its `page_title` or `finder_says` names them): a photo of one person doing what
  the Event is about (the speaker speaking, the artist beside their work, the band or singer on stage, the teacher
  teaching), or a portrait the page's words name as them. The artist's own work counts for their show. A headshot
  nobody names (a writer's byline photo), anyone else on the page, a book cover, or a crowd you can't tell is
  theirs: none.
- An exhibit (`"exhibit": true`): a piece in this show, from the host's page, its story, an artist's site or an
  artist's own post, runs before anything else. A piece runs as the artist made it: a soft or misty painting, or a
  still from the artist's own video work, letterboxed (Bréagán's horse on a misty hill). A reception crowd, the
  gallery's room, or any picture of another show (last spring's senior art show) is another story: none. With no piece
  found, pick none: the Event goes on the morning sheet to be found by hand.
- An exhibit's other pieces: its page swipes through every piece of this show, like an Instagram post (BP app
  event-photos 25; Jesse, 2026-11-17: "port the photos in, so viewers can swipe through them"). After the pick, name
  each other picture that is a different piece of this same show, as the artist made it, in `"pieces"`, in the order its
  page shows them, at most 9: `{"event": "d2", "pick": "c201", "shows": "A horse on a misty hill", "pieces": ["c203",
  "c205"]}`. The same piece twice (a crop, a detail, a smaller copy), the room, a crowd, a portrait of the artist, a
  poster or another show's work is not a piece: leave it out. Only for `"exhibit": true`, and never with a flyer.
- From `site` or `news`: this Event in an earlier year at this place, or this group (the choir, the team, the class),
  as event-photo.md's caption test. Another place, another kind of thing or another group is none, and so is the
  same kind of event in another town than the Event's place: read the `page_title` (Sartell's Veterans Day parade
  on St. Cloud's).
- A flyer only as event-photo.md says: its words true of this Event and its date.
- None, when no picture passes event-photo.md's caption test.

Answer as event-photo.md says.
