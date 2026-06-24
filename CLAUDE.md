# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Hygge** — a hyper-local community app for the real town of **St. Joseph, MN**. One calm place for everything happening in town: a daily timeline of local events, a shared calendar anyone can add to, and a daily quest that nudges neighbors to get out and connect.

Built with Next.js (App Router), TypeScript, Tailwind CSS v4, and Supabase.

## Product & principles

The whole app is the **St. Joe community experience** (`/community`). Its core job, in priority order: **① get neighbors together IRL → ② be a calm daily ritual → ③ help people find their people.** Judge every change against ① first.

**On-brand bar — reject a change if it:** feels like a corporate app (notification-spam, growth-hacky, badges/streaks/feeds/follower-counts, performative posting) **or** is too busy / not calm. Keep it warm, quiet, neighborly, hyper-local. Honesty over fake social proof — real counts only, never seeded/inflated numbers. Voice is a neighbor ("— Jesse"), not a brand.

**Design default:** for any new or reshaped UI, invoke a design skill (`frontend-design` / `ui-ux-pro-max`, both installed at project level) rather than hand-rolling defaults, so output stays consistent with the warm-minimal system below.

**Done means verified:** work isn't done until it's confirmed in the running app via the preview tools, matches the design tokens, and clears the on-brand bar — not just written. See `.claude/TOOLKIT.md` for which tool to reach for, and the project memory (`product-vision`, `target-user`, `on-brand-bar`, `definition-of-done`) for the full intent.

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
```

## Architecture

### Routes

| Route | Notes |
|---|---|
| `/` | Marketing landing — server component, session-aware, uses `.grain` texture. Signed-in CTA → `/community`, signed-out → `/login` |
| `/login` | Auth form (email + password, confirmation ON) |
| `/auth/callback` | Exchanges email-confirmation code for a session |
| `/community` | The entire app — auth-gated, a 4-tab mobile-first client experience |

### The `/community` app

A single client component (`app/community/page.tsx`) with a fixed bottom tab bar of four tabs:

- **Timeline** (default) — today's events in chronological order, each with an optimistic RSVP toggle and a live going-count.
- **Calendar** — month grid with a dot on days that have events; tapping a day opens a `.sheet-up` panel of that day's events (reuses the same event card).
- **Add Event** — anyone signed in can post (title, date, time, location required; description optional). No moderation queue — events insert as `approved` and appear immediately.
- **Quest** — today's quest with a live "X people completed" count and a one-tap-per-day Done button. Admin (gated by email) gets a form to set a quest for any date.

Icons are inline `<svg>` defined in-file; there is no shared component/icon module and no emoji.

### Key components (`app/components/`)

- **`Reveal`** — `IntersectionObserver` scroll entrance for the marketing landing; respects `prefers-reduced-motion`.

### Lib layer (`lib/`)

- **`community.ts`** — all event / RSVP / calendar / quest DB helpers. `ADMIN_EMAIL` / `isAdminEmail()` gate admin actions; `firstNameFromEmail()` derives display names from email local-parts; `currentUserId()` is the shared auth helper. Key helpers: `getTodayEvents`, `getEventsByDate`, `getMonthEventDates`, `addEvent`, `rsvpEvent`/`unRsvpEvent`, `getTodayQuest`, `getQuestCompletionCount`, `hasUserCompletedQuest`, `completeQuest`, `setQuest`. (Club helpers remain for future use.)
- **`db.ts`** — `localDate()` only. **Always use `localDate()`, never `toISOString()`** — dates are user-timezone so an evening event stays on today.
- **`haptics.ts`** — thin wrapper for `navigator.vibrate`; `haptic(kind)` where kind is `'tap' | 'select' | 'success' | 'warn' | 'error'`.
- **`supabase/client.ts`** — browser Supabase client for `'use client'` components.
- **`supabase/server.ts`** — server Supabase client for RSC and route handlers.

### Auth & middleware

- **`proxy.ts`** (≡ `middleware.ts`) — refreshes the session and gates `/community` behind `/login`. The file is named `proxy.ts` because Next 16 renamed the middleware convention.

### Database (Supabase)

Run migrations once in the Supabase SQL editor, in order:

1. `supabase/migration-community.sql` — `clubs`, `club_members`, `club_events`, `event_rsvps`, the `is_admin()` function, and per-table RLS
2. `supabase/migration-quests.sql` — adds `location`/`description` to `club_events`, opens event submission to all signed-in users, and creates `daily_quests` + `quest_completions` with RLS

All tables have RLS. Reads of events/quests are public to signed-in users; writes are scoped to `auth.uid()` (and quest authoring to `is_admin()`).

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

- **Next.js 16** (App Router) — `cookies()` is async; middleware file is `proxy.ts` not `middleware.ts`
- **TypeScript**, **Tailwind CSS v4** — CSS-based config via `@theme`, no `tailwind.config` file
- **Supabase** — auth (email+password, confirmation ON) + Postgres, all tables have RLS
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
