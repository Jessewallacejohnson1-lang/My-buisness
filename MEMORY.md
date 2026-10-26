# MEMORY.md

Standing corrections from Jesse. Read before every task. When Jesse corrects you, add the
lesson here as one dated line — a rule, not a story. Newest at the top of its section.

Rules here outrank `AGENTS.md` where they overlap, because they are more recent. Where a
line below is marked **supersedes**, the older version is dead: do not resurrect it from
an old file, an old comment, or an old screenshot still sitting in the repo.

**A correction that has hardened into a standing rule moves into `AGENTS.md`** and stops
being repeated here — how Jesse works, what *done* means, and the end-of-production split
all live there now. This file carries what is newer than that, or narrower than that.

---

## How to work with Jesse

- 2026-09-24 — Skip Dynamic Type / accessibility text-size checks (AX3, AX5, `content_size`
  screenshots, layout fixes for big text) until Jesse says to pick them back up. Check
  the default text size only. `TypographyScalingGuardTests` stays; it's a build guard,
  not a manual pass.
- 2026-09-24 — Skip dark-mode checks too (dark screenshots, dark-only colour fixes) until
  Jesse says to pick them back up. Verify in light mode only. Deferred, not dropped: keep
  using `Hue` tokens so dark mode still works when it comes back.
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
- 2026-09-24 — Four tabs: **Town** (the town feed, for everyone), **Daily** (the
  neighbour's own paper: town feed crossed with what they follow), **Business** (the
  owners' side of Main Street), **You** (profile). **Supersedes** Today / Activities /
  Calendar / Map (re-cut 2026-09-18). The map is not a tab: it opens full-screen from
  the yellow disc in the Town top bar.
- 2026-09-29 — **Search** took Business's tab slot: Town, Daily, Search, You (Jesse).
  The Town top bar leads with a friends mark instead. Business has no slot for now.
  **Supersedes** Business in the line above.
- 2026-10-08 — **Town** and **Daily** are both personal (Jesse). The Town feed is everything
  coming up in the Town, today included, in an order worked out for each person; Daily is
  your today. Ordered per person: the Town feed, friend suggestions, and Daily's Event of
  the day and Suggestions; every other list keeps a fixed order. Spec: BP app
  `docs/plans/town-feed/issues/14-which-feeds.md`. **Supersedes** "for everyone" and "the
  neighbour's own paper" in the 2026-09-24 line.
- 2026-10-11 — **You** is the neighbour's own three weeks, not their profile (Jesse): a
  Lapse-style Calendar of what they're Going to, the Agenda for the picked day under it
  (moved off Daily), and Profile in Apple's sheet from their photo at the top left. Only
  they see it. Spec: BP app `docs/plans/you-tab/SPEC.md`. **Supersedes** "**You**
  (profile)" in the 2026-09-24 line and Daily's Agenda.
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
- Always search "St. Joseph MN" with the state appended. Without it you get Missouri or
  Michigan results.
- `stjosephmn.gov` and `joetownmn.com` block direct robot fetches. Use web search
  snippets instead of trying to fetch them again.

## Brand

- 2026-09-27 — The tab bar copies Instagram's: icons only, all ink, the selected one filled;
  the You tab shows the neighbour's photo (Jesse). **Supersedes** the 2026-09-25 yellow
  selected icon.
- 2026-09-25 — Tab bar selected icon is solid BP yellow #FCE804, revealed by a darker grey
  bubble (Jesse); **supersedes** the teal selected-state line for the tab bar.
  **Superseded 2026-09-27** (line above).
- 2026-09-06 — App icon glyph is **three rooftops in a row**: three roof peaks only, no
  walls, doors, or windows, middle peak slightly taller, one solid color on a solid
  ground. **Supersedes** the water tower, the crossed street sign, and the wave figure.
  A single house was rejected as too occupied (Nextdoor, Zillow, Redfin).
- 2026-09-10 — Logo is the plain name for now: "BlockParty." (no space, trailing period),
  heavy rounded retro serif, black on bright yellow. No additional mark.
- 2026-10-22 — Block Party is neutral like Instagram (paper, white, greys), black/ink,
  Liquid Glass and touches of exact BP yellow `#FCE804`. Coral, plum, orange and peach
  were the old Hygge brand: never use or mention them (Jesse: "none of the Coral, Plum, Orange, or Peach should be referenced anymore").

## Per-surface direction lives with the surface

Jesse's direction for a specific screen sits in that screen's own file, reached from the
`AGENTS.md` trigger table, so it is not paid for on every turn:

- **The full-screen map** — `docs/rules/map.md`, *Direction* section.
- **The Town feed's intended shape** — `PRODUCT.md`, *The Town feed*. Every module in it was
  deleted in the strip-down; `docs/archive/GUTTING-LEDGER.md` says how to get each one back.
- **Onboarding** — `ONBOARDING.md`, *Direction* section, alongside its locked rules and bans.

## Data and backend

- 2026-10-26 — Every Event and News item the morning and social watches keep goes live on its first
  mention, official or secondhand, sure or not (Jesse: "only hold back if its the exact same").
  The only thing kept out is a repeat (`write_judged.repeat_of`, `same_event`). **Supersedes** the
  two-tier trust line below: held items sat unreviewed for six weeks.
- 2026-10-26 — From Google, keep only hours and whether a place is still open (Jesse: "lets do
  ur rec"). Addresses, phones and names come from other sources (ADR-016): Google's terms allow
  storing only the place id, and the key the app uses is the risk. A place's own site beats Google
  when its hours are newer (`hours_from: website` in the registry). The monthly accounts check
  reads a missing registry address from the app's `places` row, never writing it to the registry.
- 2026-10-25 — A place's weekly hours may be saved from Google Maps (Jesse: "its a fact were not
  copying"): `places.hours`, read once through Composio's Google Maps tool, else from the place's
  own website or Facebook. **Supersedes**, for hours only, "only `place_id`s are persisted" below
  and in sources/README.md. Photos, names, ratings and reviews still never come from Google.
- 2026-10-19 — Two Events with the same date, start time and place are one Event (Jesse). No place on
  either counts as the same place when the titles match (`write_judged.same_event`): the City's
  calendar feed and its web page each listed six St. Joseph meetings without one (Council Oct 19 and
  Nov 2, EDA Oct 20, Park Board Oct 26).
- 2026-10-17 — Before a migration that drops and remakes a database function, fetch and copy
  that function from the newest migration on `origin/main` that makes it, then apply. Another
  chat had remade `get_town_feed` for friends the evening before; a copy of the older version
  took the friends lift out of the live Town feed for 2 minutes (18:48–18:51 UTC).
- 2026-10-16 — Venue photos come from our own store, not Google at runtime. Real photos
  picked from each place's website (or shot by us) are saved once in the `places` bucket and
  `public.place_photos`, keyed by registry entry id. **Supersedes** `docs/rules/design.md`'s
  "Google Places Photo API at runtime is the default": that rule cost about $40,000 a month
  at 10,000 users. Website photos show without waiting for the owner's OK, credited, and
  come down on request. A refresh only proposes a new photo; Jesse's yes swaps it. Every
  automated event shows its place's photo, else the place's logo.
- 2026-10-16 — Check the live Town feed the way the app reads it: POST
  `/rest/v1/rpc/get_town_feed` with the app's public key from `SupabaseConfig.swift`. A
  read-only SQL `select ... from get_town_feed()` (Composio `SUPABASE_RUN_READ_ONLY_QUERY`)
  fails "permission denied" on `private.heart_count` (tickets 11 and 12).
- 2026-10-13 — Anonymous sign-in is on in the live project, so a POST to `/auth/v1/signup`
  without an email quietly makes an anonymous account. Proof accounts sign up with email and
  password (sign-up confirms itself); delete their avatar files through the Storage API (SQL
  deletes on `storage.objects` are refused) before deleting the users.
- Supabase anon key ships in the app for reads. The service role key is server-side only
  and never enters the client, a screenshot, or a commit.
- Both repos share one Supabase project. Logic belongs in Supabase and edge functions —
  do not re-implement server behavior in the client.
- Google Places API (New) at `places.googleapis.com/v1`, with field-mask headers for cost
  control. Only `place_id`s are persisted. `authorAttributions` must be displayed wherever
  a Places photo appears.
- Weather comes from Open-Meteo at St. Joe coordinates.
- **Superseded 2026-10-26** (top of this section). Content trust is two-tier: official sources auto-publish on a single mention, squishier
  sources need 2+ corroborating mentions, with a seeded evergreen pool as the backstop.

## Android port

- The Android repo is `~/Documents/block-party-android`, package `com.jesse.blockparty`,
  min SDK 26, Kotlin + Compose. This repo is the 1:1 spec for it.
- One screen per phase. The phase gate is a side-by-side iOS and Android screenshot,
  judged by Jesse. Do not batch screens.
- Keep exact animation values across the port. `.spring(response: r, dampingFraction: d)`
  becomes `spring(dampingRatio = d, stiffness = (2π/r)²)`.

## References and tooling

- Mobbin is the primary UI reference source. Animated references come in as screen
  recordings with frames pulled by ffmpeg.
- Use the `design-match-loop` skill for replicating UI from screenshots. (`ref-finder.md`,
  named here until 2026-09-24, does not exist anywhere on this machine — use Mobbin directly.)
- Claude Code cannot see the UI without screenshot tooling. Take the screenshot and read
  it; never claim a visual result you have not looked at.
