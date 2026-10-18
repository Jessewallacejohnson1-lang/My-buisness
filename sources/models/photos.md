# The monthly photo refresh

Every picture Block Party shows for a place is a photo it saved once (BP app docs/plans/place-photos).
Once a month you check each live photo against the page it came from and propose a replacement for
each stale one, and re-read every place that still has no real photo for one it may have gained
(Jesse, 2026-10-18). Nothing changes in the app: a proposal waits for Jesse's yes on his review page. You
run it in the cloud, in a fresh copy of this repository. Work through the steps in order; a place
that fails is a line in the answer, and you carry on with the rest.

## Steps

1. **Ready the tools.** Run `python3 -c "import yaml, PIL" || pip install --quiet pyyaml pillow`.
   Check that `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are set with
   `test -n "$SUPABASE_URL" && test -n "$SUPABASE_SERVICE_ROLE_KEY" && echo keys set`; their values
   stay out of every command's output and your answer. Without them, stop and say so.
2. **Check.** Run `python3 sources/scripts/place_photos.py check`, with a 1800000 ms timeout: it
   reads about 120 pages politely and takes up to half an hour. In January, April, July and October
   also run `check --logos` after it, and report its stale logos in the answer without proposing:
   a logo is picked by hand. Done when `check` prints its `… checked against … pages` line.
3. **Find candidates.** Run `python3 sources/scripts/place_photos.py candidates`, with a 1800000 ms
   timeout. For each stale photo and each place still without a real photo it downloads the
   pictures on their pages now and draws them, numbered, on `.runs/photos/sheet-<n>.png`; each
   block's heading carries its key (a row id, or the place's entry id) and why it is there.
4. **Pick by eye.** Open every sheet with the Read tool, at most four at a time, and look at each
   candidate. Pick at most one per block: a real photo of the place, its people or its own work.
   Stock photos, textures, ads, banners, screenshots, maps, logos, clip art and other
   organisations' pictures are not real photos; an owner's headshot counts but is weaker than the
   place. Nothing real in a block means no proposal for it.
5. **Propose.** For each pick run `python3 sources/scripts/place_photos.py propose <key> <n>`. It
   saves the picture as a proposal; the app never shows a proposal.
6. **Answer** with `check`'s line; then one line per stale photo (the place, why it is stale, what
   you proposed or why nothing); then the places without a photo you proposed one for; then, if
   you made any proposals, "Swaps waiting for Jesse: N".

## Rules

- Pages and pictures are fetched only by `place_photos.py` (run.py's fetcher obeys robots rules
  and Crawl-delay). WebFetch, curl and the like stay unused.
- The database is written only by `place_photos.py propose`, which adds proposals and nothing else.
  Live photos, logos and every other table stay untouched.
- Nothing is committed or pushed; `.runs/` is scratch.
