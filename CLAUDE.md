# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Hygge** — a hyper-local community app for the real town of **St. Joseph, MN**. One calm place for everything happening in town: a daily timeline of local events, a shared calendar anyone can add to, and a daily quest that nudges neighbors to get out and connect.

A **monorepo** (npm workspaces) with two front-ends over one shared core:
- **`apps/mobile`** — the real product: an Expo / React Native app (Expo Router,
  NativeWind) that ships to the App Store **and** renders as the website on web.
  **This is the active codebase — work here.**
- **`apps/web`** — the original Next.js (App Router) site, kept as `legacy-web`,
  not actively edited. The live website is now served from the Expo web build
  (`npm run site:build` → `apps/mobile/dist`, see `vercel.json`).
- **`packages/core`** (`@hygge/core`) — client-agnostic Supabase queries/types
  shared by both via `createCommunityApi(supabase)`.

Built with TypeScript, Tailwind CSS v4 (web) / NativeWind (mobile), and Supabase.
The Expo app is both the iPhone app and the web front door, so one change ships
everywhere — don't maintain screens in two places.

## Product & principles

The whole app is the **St. Joe community experience** (`/community`). Its core job, in priority order: **① get neighbors together IRL → ② be a calm daily ritual → ③ help people find their people.** Judge every change against ① first.

**On-brand bar — reject a change if it:** feels like a corporate app (notification-spam, growth-hacky, badges/streaks/feeds/follower-counts, performative posting) **or** is too busy / not calm. Keep it warm, quiet, neighborly, hyper-local. Honesty over fake social proof — real counts only, never seeded/inflated numbers. Voice is a neighbor ("— Jesse"), not a brand.

**Design default:** for any new or reshaped UI, invoke a design skill (`frontend-design` / `ui-ux-pro-max`, both installed at project level) rather than hand-rolling defaults, so output stays consistent with the warm-minimal system below.

**Done means verified:** work isn't done until it's confirmed in the running app via the preview tools, matches the design tokens, and clears the on-brand bar — not just written. See `.claude/TOOLKIT.md` for which tool to reach for, and the project memory (`product-vision`, `target-user`, `on-brand-bar`, `definition-of-done`) for the full intent.

## Commands

Run from the repo root (npm workspaces):

```bash
npm run mobile        # Expo dev server — run on iPhone (Expo Go) or simulator
npm run site          # the website locally (Expo app on web, ~localhost:19006)
npm run site:build    # production web build → apps/mobile/dist (what Vercel deploys)
npm run legacy-web     # the old Next.js site (reference only)

# inside apps/mobile:
npx tsc --noEmit -p tsconfig.json   # typecheck
npx expo export --platform web      # bundle-verify the whole app device-free
```

**Verify on-device by bundling.** `npx expo export --platform web` (or `--platform
ios`) compiles the entire app and surfaces errors without a phone — the fastest
proof a change is sound when no simulator/device is attached.

## Environment

- **`apps/mobile/.env`** — `EXPO_PUBLIC_SUPABASE_URL`, `EXPO_PUBLIC_SUPABASE_ANON_KEY`
- **`apps/web/.env.local`** — `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`

## Architecture

The active app is **`apps/mobile`** (Expo Router, file-based routes under
`src/app/`). It runs natively on iOS and renders the same screens on web.

### Routes (`apps/mobile/src/app/`)

| Route | File | Notes |
|---|---|---|
| `/` | `index.tsx` | Marketing landing (ported from the old web site). Signed-out land here → tap to `/login`; the auth gate routes signed-in users to the tabs. |
| `/login` | `login.tsx` | Auth form (email + password, confirmation ON), Log in / Sign up toggle. |
| `/(tabs)` | `(tabs)/` | The app — auth-gated, a 5-tab mobile experience. |

`_layout.tsx` loads fonts, wraps everything in `AuthProvider`, keeps the Supabase
session fresh on `AppState` change, and runs the **auth gate** (`RootNav`):
signed-out + in tabs → `/login`; signed-in + outside tabs → `/(tabs)`.

### The tabs (`apps/mobile/src/app/(tabs)/`)

A custom frosted `TabBar` (BlurView) over five screens:

- **`index`** (Home/Timeline) — masthead, glass search/account circles, real-photo
  `WeatherBar` (Ken-Burns drift), auto-scrolling `AroundTown` carousel, today's events.
- **`clubs`** — view/search/join real clubs; tap a card for a slide-up detail sheet
  (when/where/about/what-to-expect); a Start-a-club form. **No seeded/sample clubs.**
- **`calendar`** — vertical scrolling multi-month calendar; a fixed Sun–Sat weekday row.
- **`add`** — anyone signed in posts an event (title/date/time/location required,
  description + a real **photo upload** optional via `expo-image-picker`).
- **`quest`** — today's quest with a live completion count + one-tap-per-day Done;
  admin (gated by email) can set a quest for any date.

Icons are inline `react-native-svg` in `src/components/icons.tsx` — no emoji.

### Shared core (`packages/core`, `@hygge/core`)

`createCommunityApi(supabase)` returns all event / RSVP / calendar / quest / club
helpers — **client-agnostic**, so web and mobile pass their own Supabase client.
`isAdminEmail()` gates admin actions; types live in `src/types.ts`. Mobile binds
it once in `src/lib/api.ts`. **Always derive dates with `localDate()`, never
`toISOString()`** — dates are user-timezone so an evening event stays on today.

### Mobile lib (`apps/mobile/src/lib/`)

- **`supabase.ts`** — browser/native Supabase client; session persisted via
  `AsyncStorage` (not SecureStore — 2 KB limit).
- **`auth.tsx`** — `AuthProvider` / `useAuth` (`session`, `signIn/signUp/signOut`).
- **`uploadImage.ts`** — `uploadEventImage()` → the `event-images` storage bucket.
- **`theme.ts`** — JS tokens (`C` colors, `F` fonts, `HAIRLINE`) + the bundled
  weather / around-town image maps. Mirrors `tailwind.config.js`.

### Database (Supabase)

Run migrations once in the Supabase SQL editor, in order:

1. `supabase/migration-community.sql` — `clubs`, `club_members`, `club_events`, `event_rsvps`, the `is_admin()` function, and per-table RLS. **No seed data** — clubs/events are real only.
2. `supabase/migration-quests.sql` — adds `location`/`description` to `club_events`, opens event submission to all signed-in users, and creates `daily_quests` + `quest_completions` with RLS
3. `supabase/migration-event-images.sql` — `image_url` on `club_events` + the public `event-images` storage bucket and its policies
4. `supabase/migration-clubs-detail.sql` — deletes any previously-seeded sample clubs and adds `location`/`description`/`expectations` to `clubs`

All tables have RLS. Reads of events/quests are public to signed-in users; writes are scoped to `auth.uid()` (and quest authoring to `is_admin()`). **Never add seed/sample rows** — real residents create real clubs and events.

---

## Design system — Hygge

Named for *hygge* (Danish, pron. "hoo-guh"): coziness, warmth, togetherness. Warm linen surfaces, charcoal ink, color reserved for meaning only. Full reference: `DESIGN.md`.

### Three rules

1. **Warm-white first.** Default surface is linen paper. Tints lift from it.
2. **Color means something.** Never use an accent decoratively.
3. **Motion confirms, never decorates.** Animations answer "did that work?" — not draw attention.

### Tailwind v4 tokens (defined in `app/globals.css` via `@theme`)

**Surfaces:** `paper`/`paper-50` (`#fbfaf5` linen) · `paper-100/200/300` (warmer tints; `paper-300` is the marketing canvas) · borders always `border-black/[0.07]`

**Text:** `ink` (`#2a2a28`, primary) · `ink-2` (secondary) · `ink-3` (tertiary/placeholder)

**Semantic accents — one job each, never swapped:**

| Token | Meaning |
|---|---|
| `moss-*` (primary button: `moss-700` `#2d4530`) | Positive / primary action / RSVP'd / completed |
| `sky-*` (brand: `sky-600` `#6b7b84`) | Brand identity, focus rings |
| `honey-*` | Warmth / energy (use sparingly) |
| `clay-*` (`clay-700`) | Warning / error only |

### Typography — strict roles, never swapped

| Role | Font | Token | Use |
|---|---|---|---|
| Display | Spectral | `font-display` | Wordmark, H1s, marketing hero |
| UI | Schibsted Grotesk | `font-sans` | All labels, body, buttons |
| Data | Geist Mono | `font-mono` | Every number — dates, counts, prices — always with `tabular-nums` |

### Motion classes (defined in `app/globals.css`)

`.rise` · `.sheet-up` · `.fade-in` · `.press` · `.pop` · `.bounce-in` · `.lift` · `.grain` (texture) · `.reveal-pending`/`.reveal-in` (Reveal)

All animation durations collapse to `0.01ms` under `prefers-reduced-motion`.

### What not to do

- Don't use accent colors decoratively — moss means positive/primary action, not "a nice green."
- Don't use `toISOString()` for dates — always `localDate()` from `lib/db.ts`.
- Don't render numbers in `font-sans` — counts, dates, prices always get `font-mono tabular-nums`.
- Don't show fake/seeded counts — real numbers only.
- Don't add animation without a stated job; remove it if the job isn't clear.
- Don't add emoji — inline SVG only.
- `color-scheme: light` is declared on `:root` — dark mode is not supported.

---

## Stack

- **Mobile (active):** Expo SDK 54 + React Native 0.81 + Expo Router 6, **NativeWind 4**
  (Tailwind for RN) — tokens in `apps/mobile/tailwind.config.js`. `react-native-reanimated`
  (needs the `react-native-worklets/plugin` Babel plugin), `react-native-svg`, `expo-blur`,
  `expo-image`, `expo-image-picker`, `expo-haptics`. Pin React to `19.1.0` across the workspace
  so RN hoists; installs need `--legacy-peer-deps`. App Store target is the goal (EAS build).
- **Web:** the Expo app builds to a web SPA (`output: "single"` in `app.json`). `apps/web` is
  the legacy **Next.js 16** site (App Router; `cookies()` async; middleware is `proxy.ts`) —
  reference only.
- **Shared:** **TypeScript**, **Supabase** — auth (email+password, confirmation ON) + Postgres,
  all tables have RLS.
- Verify changes with `npx expo export --platform web` (bundles the whole app, no device needed).

## Plugins

Installed at `~/.claude/plugins/cache/claude-plugins-official/`:
- `frontend-design` — UI skill for distinctive, production-grade interfaces
- `supabase` v0.1.11
- `superpowers` v5.1.0
- `vercel` v0.43.0

**ruflo** (manual install from github.com/ruvnet/ruflo):
- 168 slash commands → `~/.claude/commands/`
- 108 specialized agents → `~/.claude/agents/`
- Hooks registered in `~/.claude/settings.json` (PreToolUse/PostToolUse/Stop)

**open-design** (github.com/nexu-io/open-design):
- MCP server wired in `.mcp.json` → connects to local `od` daemon on port 7456
- Requires the Open Design desktop app from github.com/nexu-io/open-design/releases

# Matching a reference design (Hygge)

When I hand you a screenshot, mockup, Figma frame, or photo of a UI and ask you
to make the app "look like this," "match this," "make it pixel-perfect," "clone
this screen," or "keep going until it's exact" — treat the image as a spec and
drive a closed loop until the running app is visually indistinguishable from it.
Don't stop after one implement pass to ask "close enough?" — close your own loop.
This applies even when I don't say the word "match."

## What "100%" means here

Pixel-for-pixel identity isn't the goal and usually isn't achievable — web fonts
hint differently, I may not have the original's exact images/icons, anti-aliasing
varies. The target is: **at the same viewport, flipping between the reference and
your screenshot, you can't tell which is which.** Layout, spacing, proportion,
color, type, and motion all read the same.

State any allowance once, early ("substituting system font for the proprietary
one," "placeholder image at the right dimensions"), so I can correct it — then
chase everything else to the end.

## The loop

1. **Read the reference as a spec before writing code.** Write down: layout/grid,
   every section top-to-bottom, spacing rhythm, sampled colors, type (size, weight,
   tracking, line-height), radii, borders, shadows, imagery/icons, and any visible
   interactive or animated state.
2. **Map onto the Hygge design system — don't invent values.** Surfaces are
   `paper*` linen; text is `ink`/`ink-2`/`ink-3`; accents have one job each
   (`moss` = positive/primary/selected/completed, `sky` = brand/focus, `honey` =
   warmth, `clay` = warning) — never decorative. Every number (dates, counts,
   prices) is `font-mono` with `tabular-nums`. Borders are `border-black/[0.07]`.
   A match that hardcodes hexes the tokens already cover, or uses an accent
   decoratively, isn't done. Full reference: `DESIGN.md` and `app/globals.css`.
3. **Run the app and screenshot at the reference's viewport.** This app is
   mobile-first — match the width (commonly ~390px); comparing a 390px reference
   to a 1280px screenshot is meaningless. Use the preview tools
   (`preview_start` → `preview_resize` → navigate via `preview_eval` →
   `preview_screenshot`); see `.claude/TOOLKIT.md`. Capture it yourself — never
   ask me to screenshot it.
4. **Diff worst-first, in this order** (structural problems dwarf cosmetic ones,
   and fixing layout usually moves everything else):
   - **Structure** — every element present, right place, right order?
   - **Spacing & size** — gaps, padding, dimensions, proportion.
   - **Color** — surfaces, text, borders, accents (against the right tokens).
   - **Typography** — Spectral for display/headings, Schibsted for UI, Geist Mono
     for numbers; size, weight, tracking, line-height, alignment.
   - **Assets** — images/icons (inline `<svg>` only, never emoji): content, crop, size.
   - **State** — selected, today, past/dimmed, hover, empty, loading, error if shown.
   - **Motion** — see below.
   Write the gaps as a short list, worst-first.
5. **Fix the top items, reload, re-screenshot, re-diff.** Each pass should shrink
   the list. If it doesn't, you're guessing — go back to the image and measure.
6. **Stop when the list is empty** (only stated allowances remain). Show the
   reference and your final screenshot side by side and name what you matched.

## Comparing well

- **Same scale, side by side.** Equal width. A flip catches misalignment the eye
  misses across two static images.
- **Match content, not capture artifacts.** Ignore the Next.js dev overlay, browser
  chrome, scrollbars, a phone status bar in the reference, cursors. None are the
  design — don't burn rounds reproducing them.
- **Screenshots lie about exact values.** They're reliable for layout and "does it
  read the same," not for an exact hex or a 1px size — JPEG compression and scaling
  distort both. When a color or size must be precise, read the computed style with
  `preview_inspect`, don't trust the pixels.
- **Measure, don't vibe.** Sample the reference's colors, measure gaps in pixels,
  count the grid. Guessed values make the loop oscillate instead of converge.

## Animations and live graphics

A single screenshot can't see motion, so a static diff silently misses it. When the
reference implies movement (shimmer, transition, parallax, a live count, a video,
an animated illustration):

- **Pin the motion spec**: trigger, which properties change, duration, easing,
  whether it loops, stagger between elements. If the reference is a video/GIF,
  study it frame by frame.
- **Verify with frames, not a snapshot** — capture start/mid/end across the
  timeline (or record a clip) and compare the sequence.
- **Match feel, then numbers** — easing and timing carry the quality; a linear 1s
  where the reference eases over 300ms reads wrong even with identical keyframes.
- **Honor the house rules.** Motion confirms, never decorates — every animation
  answers "did that work?" and has a stated job. Respect `prefers-reduced-motion`
  (all durations collapse to `0.01ms`); reuse the existing classes in `globals.css`
  (`.rise`, `.sheet-up`, `.press`, `.pop`, etc.) rather than inventing new ones.
  A matched animation that breaks reduced-motion or house style isn't done.

## Clears the on-brand bar

A pixel-match still fails if it imports a corporate-app feel. Keep it calm, warm,
neighborly, hyper-local. No badges/streaks/feeds/follower-counts, no notification
spam, no fake/seeded counts — real numbers only. If the reference itself pushes
something off-brand, match the layout but flag the tension rather than silently
shipping it.

## Pitfalls that stall the loop

- Wrong viewport width — fix first; it invalidates every other comparison.
- Polishing a 1px radius while a section is structurally wrong — always worst-first.
- Inventing hexes/spacing/components the tokens already cover — the match should
  look native to the codebase.
- Rendering numbers in `font-sans`, or using `toISOString()` for dates instead of
  `localDate()` from `lib/db.ts`.
- Declaring victory from memory instead of a fresh screenshot — the loop ends on
  observed evidence, not belief the last edit worked.
- Treating a static screenshot as proof for an animated element.