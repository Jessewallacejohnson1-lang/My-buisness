# The social watch

Places' public Facebook and Instagram posts become Events and News in the Town feed (registry
ADR-020, amended 2026-10-22). Two routines follow this file in the cloud, each in a fresh copy of
this repository: the busy list at 6pm and 9pm Chicago (`busy`), and every other page on
Thursdays at 3pm (`weekly`). The routine's prompt names which. Scripts read Apify and write the
database; the cheap model reads the posts and you judge what it flags, exactly as the morning job
does. Work through the steps in order. A step that fails for one source is a line in the summary;
carry on with the rest.

## Steps

1. **Ready the tools.** Run `python3 -c "import yaml" || python3 -m pip install --quiet pyyaml`.
   Check that `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are set with
   `test -n "$SUPABASE_URL" && test -n "$SUPABASE_SERVICE_ROLE_KEY" && echo keys set`; their
   values stay out of every command's output and your answer. Without them, stop and say so.
   Apify's key is the environment's network secret for `api.apify.com`, which the session never
   sees: check it with `python3 sources/scripts/social.py spend`. A line saying Apify refused
   the request means the secret is missing or wrong: stop and say so.
2. **Prepare.** Start `(python3 sources/scripts/social.py prepare <busy|weekly>; echo "prepare exit $?") >
   /tmp/prepare.log 2>&1` with `run_in_background: true`. It starts the Apify checks, waits for
   them and lays out each new post as a page in `.runs/morning/batches/`. Wait for it in the
   foreground 9 minutes at a time (timeout 600000 ms):
   `for i in $(seq 36); do grep -q '^prepare exit' /tmp/prepare.log && break; sleep 15; done; tail -20 /tmp/prepare.log`.
   Repeat until `prepare exit` shows, without ending your turn in between. Run it once only: each
   run is a paid check. Done when `prepare exit 0` shows under its `[social]` line. No batches
   means nothing new was posted: run step 4's `done`, answer with the `[social]` lines and stop.
3. **Read, judge, title, write.** Follow steps 3 to 6 of `sources/models/morning.md`: the
   cheap model flags each batch (`flag.md`), you judge the flags (`judge.md`), shorten long
   titles, and `morning.py write` writes them. Each page is one post, and its first line says
   who posted it and when: read "tonight", "tomorrow" and "this Friday" from the day it was
   posted, not from today.

   **Keep everything (Jesse, 2026-10-22).** Social posts follow one rule that overrides
   `flag.md`'s and `judge.md`'s "standing menu, product, ad or sales post" exclusions: every
   post with something a neighbour could know or do is kept, because people who care about it
   will want it. Add this to each cheap-model helper's prompt: "These pages are a place's
   social posts. Flag every post with anything to know or do, including specials, deals, sales,
   new products, menu and seasonal items, pre-orders, contests and hours; only a post with
   nothing to know or do is none." In judging:
   - An event stays an event. A sale with its own dates is an event.
   - Everything else is News: `category` `business` for a place's own offers (a special, a
     deal, a new product or menu item, a pre-order, a contest, a weekly night), `announcement`
     for town news, `campus` for CSB and SJU. Give a standing weekly special one item, not one
     per week, and fold many product posts from one place in one check into one item ("new fall
     arrivals").
   - Drop only: a post with nothing to know or do (a quote, a joke, nostalgia, a thank-you,
     behind-the-scenes, a plain photo); something already over; a teaser that doesn't say what;
     a place's daily "here's what we've got" list; anything in another town that isn't an event
     (a job at another location); and any post about a private person's health or troubles
     (ADR-020).
4. **Mark it finished.** Only after `morning.py write` has printed its summary, run
   `python3 sources/scripts/social.py done`. It saves when this check started, so the next one
   reads from there; a check that stops before this line (a usage limit, a failure) is read
   again by the next. Run it once, at the end, and never before the write.
5. **Answer** with the summary as `write` printed it, `done`'s line, every `[social] FAILED` line
   from step 2 (a page Facebook now hides belongs on the hidden list in
   `sources/social/st-joseph-mn.json`), then one line per flag you dropped that a neighbour might
   have wanted, and why.

## Rules

- Apify is reached only by `social.py`, which starts each check once with its own spending cap.
  A check that fails or runs long is a line in the answer, never a second start.
- The database is written only by `morning.py write`. SQL by hand stays unused.
- Nothing is committed or pushed; `.runs/` is scratch.
