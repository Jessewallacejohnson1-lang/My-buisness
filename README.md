# Korina

Nutrition-first fitness tracker. Every food you log is scored 1–100 on how clean it is,
every workout counts, and daily habits turn into growth rings you can watch fill.

Built with Next.js (App Router), TypeScript, Tailwind CSS v4, and Supabase.

## Develop

```bash
npm install
npm run dev      # http://localhost:3000
npm run build    # production build
npm run lint
```

## Environment (`.env.local`)

```
NEXT_PUBLIC_SUPABASE_URL=...
NEXT_PUBLIC_SUPABASE_ANON_KEY=...
ANTHROPIC_API_KEY=...        # AI photo scanning (optional)
```

## Database setup

Run these once in the Supabase SQL editor:

- `supabase/migration-auth.sql` — per-user `user_id` columns + RLS on `food_logs` / `workouts`
- `supabase/migration-profiles.sql` — `profiles` table (onboarding answers + computed targets)

Check setup anytime at **`/api/health`** — it reports which tables/columns and env vars are present.

## Map

- `app/` — routes: `/` landing, `/login`, `/onboarding`, `/dashboard`, `/meal-log`, `/workouts`,
  `/scan`, plus `api/analyze` (photo AI) and `api/health` (diagnostics)
- `app/components/` — `AppShell`, `Icons`, `ScoreRing`, `GrowthRings`, `FoodScanner`,
  `PhotoAnalyzer`, `Reveal`
- `lib/` — `db.ts` (DB helpers + `localDate`), `food-search.ts` (Open Food Facts + clean score),
  `profile.ts` (targets from onboarding), `supabase/`
- See `CLAUDE.md` for the design system and architecture notes.
