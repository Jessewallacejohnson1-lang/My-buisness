# MEMORY.md

Standing corrections from Jesse. Read before every task. They outrank `AGENTS.md` where they
overlap.

**One dated line per topic, saying what is true today**: a rule, not a story. When Jesse
changes a rule, rewrite its line; never stack a new one under it. **Supersedes** marks only an
old version still written in another file. A rule that has hardened moves into `AGENTS.md`
or its `docs/rules/` file and leaves here.

---

## How to work with Jesse

- 2026-09-24 — Text-size (Dynamic Type) and dark-mode checks wait until Jesse picks them back
  up: verify at the default text size, in light mode. Keep `TypographyScalingGuardTests` and
  the `Hue` tokens so both come back cleanly; their passes wait in `docs/SHIP-CHECKLIST.md`.
- UI specs and prompts give numbers: spring response and damping, ms, scale, hex, pt. Never
  adjectives like "premium feel".

## What this product is

- Block Party is a hyperlocal community app: local Events, clubs, neighbours, around-town and
  civic news. St. Joseph, MN ("St. Joe", "JoeTown") first, then town by town: St. Cloud, Sauk
  Rapids, Cold Spring, Waite Park. Nothing in the shared UI, copy or icon may be St. Joe–specific.
- It is NOT a wellness or health app. Diet scores, fitness metrics, health content and progress
  rings are dead code from the Hygge/Korina era: delete them, never extend them, flag them.
  Hygge, Hygge Health, Korina and Grove are retired names.
- 2026-11-01 — **Five tabs: Town, Daily, Friends, Search, You** (Jesse, BP app
  `docs/plans/five-tabs/SPEC.md`). **Town**: everything coming up in the Town, today included.
  **Daily**: your today (Event of the day, Suggestions). **Friends**: neighbours and Groups.
  **You**: your own three weeks, seen only by you: a Calendar of what you're Going to, the
  picked day's Agenda under it, and your Profile in Apple's sheet from your photo at the top
  left. Ordered per person: the Town feed, friend suggestions, and Daily's Event of the day and
  Suggestions; every other list keeps a fixed order (BP app town-feed 14). The map is not a
  tab: it opens full-screen from the yellow disc in the Town top bar. Business has no tab.
  Coming: You becomes your Profile with the full Calendar (five-tabs 03); Daily is renamed the
  Block Party tab and Search drops Groups and people (five-tabs 04). **Supersedes** the Town top
  bar's friends mark and You as "the fourth tab" in `docs/rules/architecture.md`.
- App Store target is spring 2027. The months before that are networking and local
  partnerships, not features.
- 2026-11-01 — **Users never pay** (Jesse). Block Party is a passion project, not a
  money-maker: every feature is free for everyone, with no paid tier. Revenue ideas are
  welcome as long as users never pay.

## Numbers and copy that keep going stale

- 2026-09-11 — Current public estimate: **200+ events a month across 150+ places** in
  JoeTown. Pitch line: Block Party combines all of it into one community app.
- Always search "St. Joseph MN" with the state appended. Without it you get Missouri or
  Michigan results.
- `stjosephmn.gov` and `joetownmn.com` block direct robot fetches. Use web search snippets.

## Brand

- 2026-10-22 — Block Party is neutral like Instagram (paper, white, greys), black/ink, Liquid
  Glass and touches of exact BP yellow `#FCE804`. Coral, plum, orange and peach were the old
  Hygge brand: never use or mention them (Jesse).
- 2026-09-27 — The tab bar copies Instagram's: icons only, all ink, the selected one filled;
  the You tab shows the neighbour's photo (Jesse).
- 2026-09-10 — The logo is the plain name: "BlockParty." (no space, trailing period), heavy
  rounded retro serif, black on bright yellow, no other mark. The app icon is "Bp!" in the
  same black on yellow (2026-10-29, Jesse's Icon Composer file `BlockParty/AppIcon.icon`;
  details in `DESIGN.md`).

## Data and backend

- 2026-10-27 — The hello pill is the notification, and the bell keeps it (BP app hello-drop
  05): each kind is a `HelloItem` (`HelloInbox.swift`) whose pill `message` and bell `row` are
  exhaustive switches. At most 3 pills a day, an hour apart (`HelloInbox.mayDrop`), kept 7
  days. The day's lines (`HelloDrop.message`) never reach the bell.
- 2026-10-26 — Every Event and News item the morning and social watches keep goes live on its
  first mention, official or secondhand, sure or not (Jesse: "only hold back if its the exact
  same"). Only a repeat is kept out (`write_judged.repeat_of`, `same_event`). **Supersedes**
  ADR-001's two-tier trust: held items sat unreviewed for six weeks.
- 2026-11-01 — **Apple Maps decides whether a place has closed** (Jesse: "use Apple Maps, Apple Maps
  is correct"): Google still listed Bello Cucina's hours a week after its goodbye post. Each app place
  keeps its Apple Maps id (`places.apple_place_id`); the morning finish reads its Apple Maps page and
  hides a place Apple calls Permanently Closed (`places.closed_at`, `sources/scripts/apple_maps.py`),
  telling Jesse after. Google's closed list, goodbye posts and news stories are only hints.
- 2026-10-26 — From Google, store only the place id, a place's weekly hours and whether it is
  still open (Jesse: "its a fact were not copying", "lets do ur rec"; ADR-016). Hours go in
  `places.hours` via Composio's Google Maps tool, else the place's own site or Facebook, which
  wins when newer (`hours_from: website`). Names, addresses, phones, photos, ratings and
  reviews never come from Google; the monthly accounts check reads a missing registry address
  from the app's `places` row and never writes it back. **Supersedes** "only `place_id`
  persists" in `sources/README.md` and ADR-001.
- 2026-10-19 — Two Events with the same date, start time and place are one Event (Jesse).
  When the titles match, a missing place on either still counts as the same place
  (`write_judged.same_event`).
- 2026-10-17 — Before a migration that drops and remakes a database function, copy that
  function from the newest migration on `origin/main` that makes it, then apply. A copy of an
  older version once took the friends lift out of the live Town feed.
- 2026-10-16 — Venue photos come from our own store (`public.place_photos`), not Google at
  runtime: that cost about $40,000 a month at 10,000 users. Photos from a place's own website
  show before the owner's OK, credited, and come down on request; a refresh only proposes,
  Jesse's yes swaps. Full rule: `docs/rules/design.md`.
- 2026-10-16 — Check the live Town feed the way the app reads it: POST
  `/rest/v1/rpc/get_town_feed` with the app's public key from `SupabaseConfig.swift`. A
  read-only SQL `select ... from get_town_feed()` fails "permission denied" on
  `private.heart_count`.
- 2026-10-13 — Anonymous sign-in is on in the live project, so a POST to `/auth/v1/signup`
  without an email quietly makes an anonymous account. Proof accounts sign up with email and
  password (sign-up confirms itself); delete their avatar files through the Storage API (SQL
  deletes on `storage.objects` are refused) before deleting the users.
- The Supabase anon key ships in the app for reads. The service role key is server-side only
  and never enters the client, a screenshot, or a commit.
- Both apps share one Supabase project. Logic belongs in Supabase and edge functions; do not
  re-implement server behaviour in the client.

## References and tooling

- Mobbin is the main UI Reference. Motion References come as screen recordings, frames pulled
  with ffmpeg. Match UI to a screenshot with the `design-match-loop` skill.
