# Hygge

Everything happening in **St. Joseph, MN**, in one calm place. A daily timeline of
local events you can RSVP to, a shared calendar anyone can add to, and a daily quest
that nudges neighbors to get out and connect. Hyper-local, warm, and quiet — built for
the people on your street.

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
```

## Database setup

Run these once in the Supabase SQL editor, in order:

1. `supabase/migration-community.sql` — `clubs`, `club_members`, `club_events`, `event_rsvps` + `is_admin()` + RLS
2. `supabase/migration-quests.sql` — `location`/`description` on `club_events`, opens event submission to all signed-in users, adds `daily_quests` + `quest_completions` + RLS

## Map

- `app/` — routes: `/` landing (server, session-aware), `/login`, `/auth/callback`, and
  `/community` (the whole app: a 4-tab client experience — Timeline, Calendar, Add Event, Quest)
- `app/components/` — `Reveal` (scroll entrance)
- `lib/` — `community.ts` (events/RSVP/quest DB helpers + admin gate), `db.ts` (`localDate()`),
  `haptics.ts`, `supabase/` (browser + server clients)
- `proxy.ts` — middleware gating `/community` behind `/login`
- See `CLAUDE.md` for architecture and `DESIGN.md` for the design system.
