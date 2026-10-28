# The monthly photo refresh

Every picture Block Party shows for a place is a photo it saved once (BP app docs/plans/place-photos).
Once a month you check each live photo against the page it came from and propose a replacement for
each stale one, and re-read every place that still has no real photo for one it may have gained
(Jesse, 2026-10-18). Nothing changes in the app: a proposal waits for Jesse's yes on his review page. You
run it in the cloud, in a fresh copy of this repository. Work through the steps in order; a place
that fails is a line in the answer, and you carry on with the rest.

## Steps

1. **Ready the tools.** Run `python3 sources/scripts/ready.py photos`, and install nothing
   any other way. It installs the libraries the scripts need and checks the keys by name; their
   values stay out of every command's output and your answer. When its line says `not ready`,
   stop and say so.
2. **Check.** Run `python3 sources/scripts/place_photos.py check` in the foreground with a 600000 ms
   timeout, never in the background: ending your turn ends the run. It reads about 140 pages
   politely, about 6 minutes at a time, saving what it read; while it prints `… run check again`,
   run it again. In January, April, July and October also run `check --logos` the same way after it, and report its stale logos in the answer without proposing:
   a logo is picked by hand. A photo marked unsure (its page or some pictures didn't answer) gets no
   proposal: name it in the answer. Done when `check` prints its `… checked against … pages` line.
3. **Find candidates.** Run `python3 sources/scripts/place_photos.py candidates` the same way, again
   while it prints `… run candidates again`. For each stale photo and each place still without a real photo it downloads the
   pictures on their pages now and draws them, numbered, on `.runs/photos/sheet-<n>.png`; each
   block's heading carries its key (a row id, or the place's entry id) and why it is there.
4. **Pick by eye.** Open every sheet with the Read tool, at most four at a time, and look at each
   candidate. Pick at most one per block: a real photo of this place, its people or its own work,
   the one that best shows the place (its storefront, room or team before a detail). These are not
   real photos and get no proposal: stock photos (posed models, a smiling couple, a generic
   handshake), a chain's photo used at every store, a realtor's houses for sale, textures, ads,
   banners, screenshots, maps, logos, clip art, and another person's or organisation's picture.
   Nor are: a video's still frame (a play button, a progress bar, a player's controls), a photo with
   words, prices or a slogan printed over it, one carrying another company's name or watermark, and
   one too dark or blurred to make out (Jesse, 2026-10-24, after Trobec's showed a play button).
   `candidates` already leaves out any picture a place shows now, this one's or another's.
   An owner's headshot counts but is weaker than the place. When no candidate is clearly real,
   propose nothing for that block: Jesse sees every proposal, and a wrong one costs his time.
5. **Look over the live photos.** Run `python3 sources/scripts/place_photos.py live-sheets` and open
   every `.runs/photos/live-<n>.png` the same way. Each tile is labelled with its row id and place.
   List every live photo that isn't a real photo by step 4's rules, and every picture shown on two
   places (name both), with the row id and one plain reason. Take nothing down: Jesse decides.
6. **Propose.** For each pick run `python3 sources/scripts/place_photos.py propose <key> <n>`. It
   saves the picture as a proposal; the app never shows a proposal.
7. **Answer** with `check`'s line; then one line per stale photo (the place, why it is stale, what
   you proposed or why nothing); then the places without a photo you proposed one for; then, if
   you made any proposals, "Swaps waiting for Jesse: N"; then step 5's list under "To take down?".
   With any proposals or any photo to take down, also send Jesse one push notification saying how
   many of each wait for him; none otherwise.

## Rules

- Pages and pictures are fetched only by `place_photos.py` (run.py's fetcher obeys robots rules
  and Crawl-delay). WebFetch, curl and the like stay unused.
- The database is written only by `place_photos.py propose`, which adds proposals and nothing else.
  Live photos, logos and every other table stay untouched.
- Nothing is committed or pushed; `.runs/` is scratch.
