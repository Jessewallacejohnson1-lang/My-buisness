# MEMORY.md

Standing corrections from Jesse. Read before every task. When Jesse corrects you, add the
lesson here as one dated line — a rule, not a story. Newest at the top of its section.

Rules here outrank `AGENTS.md` where they overlap, because they are more recent. Where a
line below is marked **supersedes**, the older version is dead: do not resurrect it from
an old file, an old comment, or an old screenshot still sitting in the repo.

---

## How to work with Jesse

- 2026-09-21 — Plan first for anything bigger than a quick fix. Show the plan, wait.
- 2026-09-21 — Never say something is done without showing it working. Screenshot or number.
- 2026-09-21 — Explain in plain English. Jesse is not a developer.
- 2026-09-21 — No loose files at the repo root. Every project in its own folder.
- 2026-09-21 — Show drafts before anything is sent, committed, pushed, or deployed.
- Jesse reviews as the CEO, not as an engineer. He judges whether the output is right for
  the customer. Do not hand him code to read; hand him the screen, the number, the result.
- UI prompts must be quantifiable and spec-level. Exact spring response and damping,
  durations in ms, scale factors, hex colors, px. Never adjectives like "premium feel" —
  they produce nothing usable.
- He works in short voice-to-text messages. Read intent, not typos.

## What this product is

- Block Party is a hyperlocal community app for Saint Joseph, MN ("St. Joe", "JoeTown") —
  local events, clubs, and around-town and civic news. Feed, map, calendar, activities.
- **It is NOT a wellness or health app.** Any diet score, fitness metric, health content,
  or progress-ring framing is dead code from the Hygge/Korina era. Delete it, never
  extend it, and flag it if you find it.
- Names Hygge, Hygge Health, Korina, and Grove are all retired. The product is Block Party.
- Four tabs: Today, Activities (discover new things — clubs, trails), Calendar
  (personalized — what the user signed up for or reserved), Map.
- Rollout is town by town. St. Joseph first, then St. Cloud, Sauk Rapids, Cold Spring,
  Waite Park. Nothing in the shared UI, copy, or icon may be St. Joe–specific.
- App Store target is spring 2027. The months before that are networking and local
  partnerships, not features.
- Main features are free for everyone. A paid tier is still being shaped, priced around
  a Costco food court item ($2–5).

## Numbers and copy that keep going stale

- 2026-09-11 — Current public estimate: **200+ events a month across 150+ places** in
  JoeTown. **Supersedes** the earlier "300+ monthly events". Pitch line: Block Party
  combines all of it into one community app.
- Onboarding screen 13 still reads "30+ St. Joe happenings a month". Known mismatch.
  Verify against seeded content before ship rather than silently editing it.
- Always search "St. Joseph MN" with the state appended. Without it you get Missouri or
  Michigan results.
- `stjosephmn.gov` and `joetownmn.com` block direct robot fetches. Use web search
  snippets instead of trying to fetch them again.

## Brand

- 2026-09-06 — App icon glyph is **three rooftops in a row**: three roof peaks only, no
  walls, doors, or windows, middle peak slightly taller, one solid color on a solid
  ground. **Supersedes** the water tower, the crossed street sign, and the wave figure.
  A single house was rejected as too occupied (Nextdoor, Zillow, Redfin).
- 2026-09-10 — Logo is the plain name for now: "BlockParty." (no space, trailing period),
  heavy rounded retro serif, black on bright yellow. No additional mark.
- App palette comes from the Joetown city logo: orange `#E67633` (buttons, progress,
  splash), teal `#72C5B6` (selected states — locked), gray `#707174` (secondary,
  disabled).
- The old cream / terracotta / sage / rosewood hand-drawn earthy palette is dead in the
  app. Ask for the current direction rather than reusing it. The waitlist site is the one
  exception — it still runs cream with a terracotta accent.
- The app is not monochrome. Color is part of the design direction, not an exception.
- Jesse dislikes the current static splash (coral script wordmark on black). Direction
  under consideration is Duolingo-style: BP mark centered, full wordmark near the bottom.

## Map tab

- Keep the existing light Mapbox style. Do not switch to satellite imagery.
- Pins have exactly two visual states: rest (6pt low-contrast dot, no label) and awake
  (full marker plus label) for live, selected, or saved pins. Labels only render past a
  zoom threshold.
- Categories come from Google Places (`primaryType` / `types`), mapped to a family and
  stored in Supabase next to `place_id`. One shared color per category group (business
  group is blue); glyphs differ per place.
- Cluster merge and split animation must feel Apple-level smooth. Cluster bubbles are
  black, not grey.
- The bottom sheet is an extension of the four-icon glass tab bar, pulled up. A pin tap
  morphs the detail inside that glass bar. Never a separate floating card.
- References: Snapchat Map and Life360 for interaction, Apple Maps for glyph markers,
  gestures, and green tone, Flighty's airport detail sheet for the overlay and its
  plain-language text.

## Today tab

- The feed hard-stops at "all caught up" for the day. That stop is the point; do not add
  infinite scroll behind it.
- The colored utility tile row (weather, garbage, road) is removed. It stole attention.
- The almanac card stays at the top, but it must be tailored to the user's RSVP'd events
  and feel alive. It was too static and kept recommending the Lake Wobegon Trail.
- News: five stories. Tapping the card opens a summary; a separate tap opens the exact
  source story. The focused reader is the signature interaction of the tab — the card
  grows out of its own position, backdrop dims and blurs, card sits vertically centered,
  swipe sideways between stories, drag down to dismiss.
- Module 4 is not "this or that". It surfaces new postings matching the categories a user
  signed up for and has not joined yet.
- "Your day" shows strictly today's events. A future RSVP appearing there is a bug.
- The "Your day" horizon card is a sky above a horizon line that doubles as the timeline
  baseline; all text sits below the line. The ground below is a flat fill that shifts with
  time of day and flips at sunset — never the sky gradient. The rail is solar-anchored:
  exact sunrise to exact sunset, no rounding, so its width changes with the season.
- Civic content lives in its own tab, not in the feed. No time-of-day reordering.
- The feed must be genuinely useful and habit-forming without being manipulative.

## Onboarding

- It is a near 1:1 clone of Duolingo's iOS onboarding — interactions, button feel, top
  progress bar. Only colors and question content change.
- **Any deviation from Duolingo must be raised as a question. Jesse approves every
  change.** Do not improve it on your own judgment.
- Reference is 20 Mobbin screenshots in the Figma team library, file
  `BHomEEi7JSfHOiw9DOY6IF`, frame `3311:2` (screens `3311:3`–`3311:22`).
- The Block Party mark replaces Duo as the guide on every screen. Voice is "we" — the mark
  stays a logo, never a named character.
- All 20 screens are decided, 6 questions. Screen 4 reads "Just 6 quick questions and
  you're in." Taglines: "Join the neighborhood." (screen 2), "JOIN THE PARTY" (screen 20).

## Data and backend

- Supabase anon key ships in the app for reads. The service role key is server-side only
  and never enters the client, a screenshot, or a commit.
- Both repos share one Supabase project. Logic belongs in Supabase and edge functions —
  do not re-implement server behavior in the client.
- Google Places API (New) at `places.googleapis.com/v1`, with field-mask headers for cost
  control. Only `place_id`s are persisted. `authorAttributions` must be displayed wherever
  a Places photo appears.
- Weather comes from Open-Meteo at St. Joe coordinates.
- Content trust is two-tier: official sources auto-publish on a single mention, squishier
  sources need 2+ corroborating mentions, with a seeded evergreen pool as the backstop.

## Android port

- The Android repo is `~/Documents/block-party-android`, package `com.jesse.blockparty`,
  min SDK 26, Kotlin + Compose. This repo (branch `integration/block-party`) is the 1:1
  spec for it.
- One screen per phase. The phase gate is a side-by-side iOS and Android screenshot,
  judged by Jesse. Do not batch screens.
- Keep exact animation values across the port. `.spring(response: r, dampingFraction: d)`
  becomes `spring(dampingRatio = d, stiffness = (2π/r)²)`.

## References and tooling

- Mobbin is the primary UI reference source. Animated references come in as screen
  recordings with frames pulled by ffmpeg.
- Use the `design-match-loop` skill for replicating UI from screenshots and `ref-finder.md`
  for UI gallery research.
- Claude Code cannot see the UI without screenshot tooling. Take the screenshot and read
  it; never claim a visual result you have not looked at.
