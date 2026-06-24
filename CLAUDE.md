# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Hygge Health** — nutrition-first fitness tracker built for Saint Joseph, MN. Every food is scored 1–100 on how clean it is; workouts count; daily habits turn into growth rings. The community tier (clubs + events) is the flagship launch surface.

Built with Next.js (App Router), TypeScript, Tailwind CSS v4, and Supabase.

## Product & principles

The flagship surface is the **St. Joe community page** (`/community`) for the real town of **St. Joseph, MN**. Its core job, in priority order: **① get neighbors together IRL → ② be a calm daily ritual → ③ help people find their people.** Judge community work against ① first.

**On-brand bar — reject a change if it:** feels like a corporate app (notification-spam, growth-hacky, badges/streaks/feeds/follower-counts, performative posting) **or** is too busy / not calm. Keep it warm, quiet, neighborly, hyper-local. Honesty over fake social proof — real counts only, never seeded/inflated numbers. Voice is a neighbor ("— Jesse"), not a brand.

**Design default:** for any new or reshaped UI, invoke a design skill (`frontend-design` / `ui-ux-pro-max`, both installed at project level) rather than hand-rolling defaults, so output stays consistent with the warm-minimal system below.

**Done means verified:** community work isn't done until it's confirmed in the running app via the preview tools, matches the design tokens, and clears the on-brand bar — not just written. See `.claude/TOOLKIT.md` for which tool to reach for, and the project memory (`product-vision`, `target-user`, `on-brand-bar`, `definition-of-done`) for the full intent.

## Commands

```bash
npm run dev       # Start development server (localhost:3000)
npm run build     # Production build
npm run lint      # Run ESLint
```

## Environment (`.env.local`)

```
NEXT_PUBLIC_SUPABASE_URL=...
NEXT_PUBLIC_SUPABASE_ANON_KEY=...
ANTHROPIC_API_KEY=...        # AI photo scanning (optional)
```

Check setup at `/api/health` — reports which tables, columns, and env vars are present.

## Architecture

### Routes

| Route | Notes |
|---|---|
| `/` | Marketing landing — server component, session-aware, uses `.grain` texture |
| `/login` | Auth form (email + password, confirmation ON) |
| `/onboarding` | Multi-step profile wizard; calls `lib/profile.ts` → saves `profiles` table |
| `/community` | Default landing; clubs + events (no auth required to browse) |
| `/dashboard` | Daily summary: GrowthRings, streak, weekly bar chart |
| `/meal-log` | Log food by search, barcode, photo, or manual entry |
| `/workouts` | Log + track workout sessions |
| `/scan` | Dedicated barcode scanner page |
| `/progress` | Trailing history charts: calories, macros, weight, workout count |
| `/api/analyze` | POST — photo → Anthropic SDK (structured output via Zod) → food estimates |
| `/api/health` | GET — diagnostics: table/column presence + env var check |
| `/auth/callback` | Exchanges email-confirmation code for a session |

### Key components (`app/components/`)

- **`AppShell`** — bottom tab bar (mobile) + side rail (desktop) + sign-out. Never put nav logic in page components.
- **`GrowthRings`** — tri-ring SVG dial (protein/carbs/fat/fibre) + `useCountUp`. Rings animate via `.ring-sweep`.
- **`ScoreRing`** — SVG ring for a 1–100 clean score; color from `scoreTone()` in same file.
- **`FoodScanner`** — zxing barcode → Open Food Facts lookup → log entry. Viewfinder plays `.caught` on lock; `.ping-out` on save.
- **`PhotoAnalyzer`** — captures/uploads image → `/api/analyze` → multi-item confirm UI.
- **`ManualFoodForm`** — fallback manual nutrition entry.
- **`Icons`** — inline SVG set. No emoji anywhere in the UI.
- **`Reveal`** — `IntersectionObserver` scroll entrance; respects `prefers-reduced-motion`.

### Lib layer (`lib/`)

- **`db.ts`** — all DB helpers + `localDate()`. **Always use `localDate()`, never `toISOString()`** — dates are user-timezone so evening logs stay on today. Types: `FoodLog`, `Workout`, `WeightLog`, `DayStat`.
- **`food-search.ts`** — Open Food Facts search + barcode lookup, clean-score algorithm, `toLogEntry()` (strips display-only fields before DB insert).
- **`profile.ts`** — `ProfileAnswers`, `computeTargets()` (Mifflin-St Jeor BMR → macro targets), `FOCUS_OPTIONS`. Also exports `KG_PER_LB` / `CM_PER_IN`.
- **`community.ts`** — all club/event/RSVP DB helpers. `ADMIN_EMAIL` / `isAdminEmail()` gate admin actions (approve clubs, etc.). `firstNameFromEmail()` derives display names from email local-parts.
- **`community-content.ts`** — static copy/seed data for the community page.
- **`manual-food.ts`** — logic for the manual food entry flow.
- **`whole-foods.ts`** — curated whole-food reference data used in scoring.
- **`units.ts`** — unit conversion utilities (kg↔lb, cm↔in).
- **`haptics.ts`** — thin wrapper for `navigator.vibrate`; used on key interactions (sign-out, onboarding confirms).
- **`supabase/client.ts`** — browser Supabase client for `'use client'` components.
- **`supabase/server.ts`** — server Supabase client for RSC and route handlers.

### Auth & middleware

- **`proxy.ts`** (≡ `middleware.ts`) — refreshes the session and gates `/dashboard`, `/meal-log`, `/workouts`, `/scan`, `/progress`, `/onboarding` behind `/login`. The file is named `proxy.ts` because Next 16 renamed the middleware convention.

### Database (Supabase)

Run migrations once in the Supabase SQL editor, in order:

1. `supabase/migration-auth.sql` — `user_id` columns + RLS on `food_logs` / `workouts`
2. `supabase/migration-profiles.sql` — `profiles` table (onboarding answers + computed targets)
3. `supabase/migration-community.sql` — `clubs`, `club_members`, `club_events`, `event_rsvps`
4. `supabase/migration-progress.sql` — `weight_logs`
5. `supabase/migration-all.sql` — combined/latest (use this for a fresh setup)

---

## Design system — Hygge

Named for *hygge* (Danish, pron. "hoo-guh"): coziness, warmth, togetherness. Warm white surfaces, near-black ink, color reserved for data and meaning only. Full reference: `DESIGN.md`.

### Three rules

1. **White first.** Default surface is paper-white. Tints lift from it.
2. **Color means something.** Never use an accent decoratively.
3. **Motion confirms, never decorates.** Animations answer "did that work?" — not draw attention.

### Tailwind v4 tokens (defined in `app/globals.css` via `@theme`)

**Surfaces:** `paper` (white) · `paper-50/100/200/300` (warm tints) · borders always `border-black/[0.07]`

**Text:** `ink` (primary) · `ink-2` (secondary) · `ink-3` (tertiary/placeholder)

**Semantic accents — one job each, never swapped:**

| Token | Meaning |
|---|---|
| `moss-*` (buttons: `moss-700`) | Clean / positive / primary action |
| `honey-*` | Moderate / energy / carbs ring |
| `clay-*` | Avoid / warning / fat ring |
| `sky-*` (focus rings, fibre ring) | Brand identity |

**Score tones** — `scoreTone()` in `ScoreRing.tsx`: ≥70 → `moss-600`, 40–69 → `honey-600`, <40 → `clay-700`

### Typography — strict roles, never swapped

| Role | Font | Token | Use |
|---|---|---|---|
| Display | DM Serif Display | `font-display` | Wordmark, H1s, marketing hero |
| UI | Outfit | `font-sans` | All labels, body, buttons |
| Data | Geist Mono | `font-mono` | Every number, score, calorie — always with `tabular-nums` |

### Motion classes (defined in `app/globals.css`)

`.rise` · `.ring-sweep` · `.sheet-up` · `.fade-in` · `.ring-fill` · `.press` · `.pop` · `.bounce-in` · `.flicker` · `.score-draw` · `.caught` · `.ping-out` · `.lift` · `.marquee-track`

All animation durations collapse to `0.01ms` under `prefers-reduced-motion`.

### What not to do

- Don't use accent colors decoratively — moss is not "a nice green," it means clean.
- Don't use `toISOString()` for dates — always `localDate()` from `lib/db.ts`.
- Don't render numbers in `font-sans` — scores, calories, macros always get `font-mono tabular-nums`.
- Don't reference badge `icon`/`color` fields from old DB rows — they are legacy light-theme values; restyle at render time.
- Don't add animation without a stated job; remove it if the job isn't clear.
- `color-scheme: light` is declared on `:root` — dark mode is not supported.

---

## Stack

- **Next.js 16** (App Router) — `cookies()` is async; middleware file is `proxy.ts` not `middleware.ts`
- **TypeScript**, **Tailwind CSS v4** — CSS-based config via `@theme`, no `tailwind.config` file
- **Supabase** — auth (email+password, confirmation ON) + Postgres, all tables have per-user RLS
- **Anthropic SDK** — photo analysis via structured output (Zod schema) in `app/api/analyze/route.ts`
- Read `node_modules/next/dist/docs/` before writing Next.js code — this version may differ from training data.

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
