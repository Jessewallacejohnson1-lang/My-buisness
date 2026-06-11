# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Fitness tracking web app — nutrition logging, workout guidance, and long-term progress tracking. Built with Next.js (App Router), TypeScript, and Tailwind CSS.

## Commands

```bash
npm run dev       # Start development server (localhost:3000)
npm run build     # Production build
npm run lint      # Run ESLint
```

## Architecture

- **`app/`** — App Router pages: `/` (marketing, server component, session-aware), `/login`, `/dashboard`, `/meal-log`, `/workouts`, `/scan`
- **`app/components/`** — `AppShell` (mobile bottom tabs + desktop rail + sign-out), `Icons` (inline SVG set — no emoji in UI), `GrowthRings` (animated tri-ring dial + `useCountUp`), `ScoreRing`/`scoreTone` (clean-score ring), `Reveal` (IntersectionObserver scroll reveal), `FoodScanner` (zxing barcode → lookup → save)
- **`lib/supabase/client.ts` / `server.ts`** — Supabase clients (`@supabase/ssr`); browser client for `'use client'` pages, server client for RSC/route handlers
- **`proxy.ts`** — Next 16 renamed `middleware.ts` → `proxy.ts`. Refreshes the session and gates `/dashboard`, `/meal-log`, `/workouts`, `/scan` behind `/login`
- **`app/auth/callback/route.ts`** — exchanges the email-confirmation code for a session
- **`lib/db.ts`** — typed DB helpers + `localDate()` (always use it, never `toISOString()` — dates are user-timezone)
- **`lib/food-search.ts`** — Open Food Facts search/barcode lookup, clean-score algorithm, `toLogEntry()` (strips display-only fields before insert)
- **`supabase/migration-auth.sql`** — per-user `user_id` columns + RLS policies (run in Supabase SQL editor)

## Design system (white minimal)

Defined as Tailwind v4 `@theme` tokens in `app/globals.css`:
- **Surfaces** `paper` (white) + `paper-50…300` (warm tints), hairline borders `border-black/[0.07]`
- **Text** `ink` (primary), `ink-2` (secondary), `ink-3` (tertiary)
- **Accents** reserved for data only: `moss-*` (clean/positive, buttons moss-700), `honey-*` (energy/moderate), `clay-*` (warnings/avoid)
- **Type roles** `font-display` DM Serif Display (wordmark, H1s) · `font-sans` Outfit (UI) · `font-mono` Geist Mono (all numbers/data, with `tabular-nums`)
- Score tones: ≥70 moss-600, 40–69 honey-600, <40 clay-700 (`scoreTone()` in `ScoreRing.tsx`)
- Stored badge `icon`/`color` fields in old DB rows are light-theme legacy — ignore them and restyle at render time
- Motion: `.rise` entrance (stagger via inline `animationDelay`), `Reveal` for scroll, `prefers-reduced-motion` respected

## Stack

- **Next.js 16** (App Router) — `cookies()` is async; middleware file is `proxy.ts`
- **TypeScript**, **Tailwind CSS v4** (CSS-based config via `@theme`, no tailwind.config)
- **Supabase** — auth (email+password, confirmation ON) + Postgres (`food_logs`, `workouts`, per-user RLS)

## Notes

- Read `node_modules/next/dist/docs/` before writing Next.js code — this version may differ from training data.
- API routes go in `app/api/[route]/route.ts`
