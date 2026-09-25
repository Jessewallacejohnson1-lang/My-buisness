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

## Per-surface direction lives with the surface

Jesse's direction for a specific screen sits in that screen's own file, reached from the
`AGENTS.md` trigger table, so it is not paid for on every turn:

- **The full-screen map** — `docs/rules/map.md`, *Direction* section.
- **The Town feed's intended shape** — `PRODUCT.md`, *The Town feed*. Every module in it was
  deleted in the strip-down; `docs/GUTTING-LEDGER.md` says how to get each one back.
- **Onboarding** — `ONBOARDING.md`, *Direction* section, alongside its locked rules and bans.

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
