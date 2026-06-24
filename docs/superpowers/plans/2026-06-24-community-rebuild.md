# Community Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove all fitness/nutrition functionality and rebuild the app as a focused community events platform with four tabs: Timeline, Calendar, Add Event, and Quest.

**Architecture:** The existing auth, Supabase schema, and `lib/community.ts` helpers are kept and extended. The community page UI is rebuilt from scratch with a 4-tab shell. All fitness routes and components are deleted.

**Tech Stack:** Next.js 16 App Router, TypeScript, Tailwind CSS v4 (`@theme` tokens in `app/globals.css`), Supabase (browser client via `lib/supabase/client.ts`)

## Global Constraints

- All dates via `localDate()` from `lib/db.ts` — never `toISOString()`
- Numbers always `font-mono tabular-nums`
- No emoji anywhere in UI — inline SVG only
- Accent colors have meaning: `moss-*` = primary action, `honey-*` = moderate, `clay-*` = warning
- `color-scheme: light` — no dark mode
- `cookies()` is async in Next.js 16
- No new dependencies — use what's already installed
- Motion classes from `globals.css`: `.rise`, `.fade-in`, `.sheet-up`, `.press`, `.pop`

---

## File Map

| File | Action |
|---|---|
| `app/dashboard/` | Delete entire directory |
| `app/meal-log/` | Delete entire directory |
| `app/workouts/` | Delete entire directory |
| `app/scan/` | Delete entire directory |
| `app/progress/` | Delete entire directory |
| `app/onboarding/` | Delete entire directory |
| `app/components/AppShell.tsx` | Delete |
| `app/components/FoodScanner.tsx` | Delete |
| `app/components/GrowthRings.tsx` | Delete |
| `app/components/ManualFoodForm.tsx` | Delete |
| `app/components/PhotoAnalyzer.tsx` | Delete |
| `app/components/ScoreRing.tsx` | Delete |
| `app/components/ScoreWhy.tsx` | Delete |
| `lib/community-content.ts` | Delete |
| `proxy.ts` | Slim PROTECTED list to `/community` only |
| `supabase/migration-quests.sql` | Create — adds location/description to club_events, quest tables, RLS |
| `lib/community.ts` | Extend — add event helpers, quest helpers |
| `app/community/page.tsx` | Full rewrite — 4-tab shell |

---

### Task 1: Delete fitness routes and slim middleware

**Files:**
- Delete: `app/dashboard/`, `app/meal-log/`, `app/workouts/`, `app/scan/`, `app/progress/`, `app/onboarding/`
- Delete: `app/components/AppShell.tsx`, `app/components/FoodScanner.tsx`, `app/components/GrowthRings.tsx`, `app/components/ManualFoodForm.tsx`, `app/components/PhotoAnalyzer.tsx`, `app/components/ScoreRing.tsx`, `app/components/ScoreWhy.tsx`
- Delete: `lib/community-content.ts`
- Modify: `proxy.ts`

- [ ] **Step 1: Delete fitness route directories**

```bash
rm -rf app/dashboard app/meal-log app/workouts app/scan app/progress app/onboarding
```

- [ ] **Step 2: Delete fitness-only components**

```bash
rm app/components/AppShell.tsx \
   app/components/FoodScanner.tsx \
   app/components/GrowthRings.tsx \
   app/components/ManualFoodForm.tsx \
   app/components/PhotoAnalyzer.tsx \
   app/components/ScoreRing.tsx \
   app/components/ScoreWhy.tsx \
   lib/community-content.ts
```

- [ ] **Step 3: Slim the middleware PROTECTED list**

In `proxy.ts`, replace:
```ts
const PROTECTED = ['/dashboard', '/meal-log', '/workouts', '/scan', '/onboarding', '/progress', '/community']
```
With:
```ts
const PROTECTED = ['/community']
```

- [ ] **Step 4: Verify the build has no import errors**

```bash
npm run build 2>&1 | grep -E "error|Error" | head -20
```

Expected: errors only in `app/community/page.tsx` (from the deleted `community-content` import). Everything else should be clean.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: remove fitness routes and components; slim middleware"
```

---

### Task 2: Database migration — quests + event fields

**Files:**
- Create: `supabase/migration-quests.sql`

**Interfaces:**
- Produces: `daily_quests` table, `quest_completions` table, `location` + `description` columns on `club_events`, updated RLS allowing all authed users to insert approved events

- [ ] **Step 1: Create the migration file**

Create `supabase/migration-quests.sql`:

```sql
-- Add location and description to club_events
alter table public.club_events
  add column if not exists location    text,
  add column if not exists description text;

-- Allow all authenticated users to submit events as approved (no moderation queue)
drop policy if exists "submit events" on public.club_events;
create policy "submit events" on public.club_events for insert with check (
  submitted_by = auth.uid()
);
-- Note: status defaults to 'pending' at DB level but we insert 'approved' from the app.
-- The read policy already shows rows where submitted_by = auth.uid(), so the submitter
-- always sees their own event immediately.

-- daily_quests: one per day, set by admin
create table if not exists public.daily_quests (
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  description text,
  date        date not null unique,
  created_by  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now()
);

alter table public.daily_quests enable row level security;

create policy "read quests" on public.daily_quests
  for select using (true);

create policy "write quests" on public.daily_quests
  for all using (public.is_admin()) with check (public.is_admin());

-- quest_completions: one row per user per quest
create table if not exists public.quest_completions (
  id           uuid primary key default gen_random_uuid(),
  quest_id     uuid not null references public.daily_quests (id) on delete cascade,
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  completed_at timestamptz not null default now(),
  unique (quest_id, user_id)
);

alter table public.quest_completions enable row level security;

create policy "read completions" on public.quest_completions
  for select using (true);

create policy "insert completion" on public.quest_completions
  for insert with check (user_id = auth.uid());

create index if not exists quest_completions_quest_idx on public.quest_completions (quest_id);
```

- [ ] **Step 2: Run migration in Supabase SQL editor**

Open your Supabase project → SQL Editor → paste and run `supabase/migration-quests.sql`.

Expected: no errors. Confirm by checking Table Editor — you should see `daily_quests` and `quest_completions` tables, and `club_events` should have `location` and `description` columns.

- [ ] **Step 3: Commit the migration file**

```bash
git add supabase/migration-quests.sql
git commit -m "feat: add quest tables and location/description to events"
```

---

### Task 3: Extend lib/community.ts with new helpers

**Files:**
- Modify: `lib/community.ts`

**Interfaces:**
- Consumes: existing `supabase` client, `localDate()` from `lib/db.ts`
- Produces:
  - `NewEventInput` type
  - `EventsByDate` type  
  - `DailyQuest` type
  - `addEvent(input: NewEventInput): Promise<void>`
  - `getEventsByDate(date: string): Promise<TimelineEvent[]>`
  - `getMonthEventDates(year: number, month: number): Promise<string[]>` — returns array of YYYY-MM-DD strings that have events
  - `getTodayQuest(): Promise<DailyQuest | null>`
  - `getQuestCompletionCount(questId: string): Promise<number>`
  - `hasUserCompletedQuest(questId: string, userId: string): Promise<boolean>`
  - `completeQuest(questId: string): Promise<void>`
  - `setQuest(title: string, description: string, date: string): Promise<void>`

- [ ] **Step 1: Add `location` to the TimelineEvent type and update getTodayEvents**

In `lib/community.ts`, find the `TimelineEvent` type and add the `location` field:

```ts
/** One timeline row: a club event with the viewer's RSVP state + going count. */
export type TimelineEvent = {
  id: string
  title: string
  start_time: string | null
  location: string | null          // ← add this line
  going_count: number
  rsvpd: boolean
  from_joined_club: boolean
}
```

Then in `getTodayEvents`, update the `.map()` to include location:

```ts
return (events ?? []).map((e) => ({
  id: e.id,
  title: e.title,
  start_time: e.start_time,
  location: e.location ?? null,   // ← add this line
  going_count: counts.get(e.id) ?? 0,
  rsvpd: mine.has(e.id),
  from_joined_club: e.club_id ? joinedClubs.has(e.club_id) : false,
}))
```

- [ ] **Step 2: Add new helpers to lib/community.ts**

Append to the end of `lib/community.ts`:

```ts
// ── Event submission ─────────────────────────────────────────────────────────

export type NewEventInput = {
  title: string
  event_date: string   // YYYY-MM-DD
  start_time: string   // display string e.g. '7pm'
  location: string
  description?: string
}

export async function addEvent(input: NewEventInput): Promise<void> {
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Not signed in')
  const { error } = await supabase.from('club_events').insert({
    ...input,
    submitted_by: user.id,
    status: 'approved',
    club_id: null,
  })
  if (error) throw error
}

// ── Calendar helpers ─────────────────────────────────────────────────────────

/** All events on a specific date, with RSVP state. */
export async function getEventsByDate(date: string): Promise<TimelineEvent[]> {
  const uid = await currentUserId()
  const { data: events, error } = await supabase
    .from('club_events')
    .select('*')
    .eq('status', 'approved')
    .eq('event_date', date)
    .order('start_time', { ascending: true })
  if (error) throw error
  const ids = (events ?? []).map((e) => e.id)
  const counts = new Map<string, number>()
  const mine = new Set<string>()
  if (ids.length) {
    const { data: rsvps } = await supabase
      .from('event_rsvps')
      .select('event_id, user_id')
      .in('event_id', ids)
    ;(rsvps ?? []).forEach((r) => {
      counts.set(r.event_id, (counts.get(r.event_id) ?? 0) + 1)
      if (uid && r.user_id === uid) mine.add(r.event_id)
    })
  }
  return (events ?? []).map((e) => ({
    id: e.id,
    title: e.title,
    start_time: e.start_time,
    location: e.location ?? null,
    going_count: counts.get(e.id) ?? 0,
    rsvpd: mine.has(e.id),
    from_joined_club: false,
  }))
}

/** Returns YYYY-MM-DD strings that have at least one approved event in the given month. */
export async function getMonthEventDates(year: number, month: number): Promise<string[]> {
  // month is 1-indexed
  const from = `${year}-${String(month).padStart(2, '0')}-01`
  const lastDay = new Date(year, month, 0).getDate()
  const to = `${year}-${String(month).padStart(2, '0')}-${String(lastDay).padStart(2, '0')}`
  const { data, error } = await supabase
    .from('club_events')
    .select('event_date')
    .eq('status', 'approved')
    .gte('event_date', from)
    .lte('event_date', to)
  if (error) throw error
  return [...new Set((data ?? []).map((e) => e.event_date))]
}

// ── Quests ───────────────────────────────────────────────────────────────────

export type DailyQuest = {
  id: string
  title: string
  description: string | null
  date: string
}

export async function getTodayQuest(): Promise<DailyQuest | null> {
  const today = localDate()
  const { data, error } = await supabase
    .from('daily_quests')
    .select('id, title, description, date')
    .eq('date', today)
    .maybeSingle()
  if (error) throw error
  return data
}

export async function getQuestCompletionCount(questId: string): Promise<number> {
  const { count, error } = await supabase
    .from('quest_completions')
    .select('*', { count: 'exact', head: true })
    .eq('quest_id', questId)
  if (error) throw error
  return count ?? 0
}

export async function hasUserCompletedQuest(questId: string, userId: string): Promise<boolean> {
  const { data, error } = await supabase
    .from('quest_completions')
    .select('id')
    .eq('quest_id', questId)
    .eq('user_id', userId)
    .maybeSingle()
  if (error) throw error
  return data !== null
}

export async function completeQuest(questId: string): Promise<void> {
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Not signed in')
  const { error } = await supabase
    .from('quest_completions')
    .insert({ quest_id: questId, user_id: user.id })
  if (error) throw error
}

export async function setQuest(title: string, description: string, date: string): Promise<void> {
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('Not signed in')
  const { error } = await supabase
    .from('daily_quests')
    .upsert({ title, description, date, created_by: user.id }, { onConflict: 'date' })
  if (error) throw error
}
```

- [ ] **Step 2: Verify TypeScript compiles**

```bash
npx tsc --noEmit 2>&1 | head -30
```

Expected: no errors in `lib/community.ts`.

- [ ] **Step 3: Commit**

```bash
git add lib/community.ts
git commit -m "feat: add event submission, calendar, and quest helpers to community lib"
```

---

### Task 4: Community page shell + Timeline tab

**Files:**
- Modify: `app/community/page.tsx` (full rewrite)

**Interfaces:**
- Consumes: `getTodayEvents`, `rsvpEvent`, `unRsvpEvent`, `getCurrentUser`, `isAdminEmail`, `TimelineEvent` from `lib/community`
- Produces: working 4-tab shell with Timeline functional; Calendar/AddEvent/Quest tabs show placeholder text

- [ ] **Step 1: Replace app/community/page.tsx with the shell + Timeline**

```tsx
'use client'

import { useCallback, useEffect, useState } from 'react'
import {
  getTodayEvents,
  rsvpEvent,
  unRsvpEvent,
  getCurrentUser,
  isAdminEmail,
  type TimelineEvent,
} from '@/lib/community'
import { haptic } from '@/lib/haptics'

type Tab = 'timeline' | 'calendar' | 'add' | 'quest'

// ── Icons ────────────────────────────────────────────────────────────────────

function TabIcon({ id, active }: { id: Tab; active: boolean }) {
  const c = active ? '#1a1a1a' : '#9ca3af'
  const sp = {
    fill: 'none' as const,
    stroke: c,
    strokeWidth: '1.8',
    strokeLinecap: 'round' as const,
    strokeLinejoin: 'round' as const,
  }
  if (id === 'timeline')
    return (
      <svg width="22" height="22" viewBox="0 0 24 24" {...sp} aria-hidden>
        <line x1="8" y1="6" x2="21" y2="6" />
        <line x1="8" y1="12" x2="21" y2="12" />
        <line x1="8" y1="18" x2="21" y2="18" />
        <line x1="3" y1="6" x2="3.01" y2="6" strokeWidth="2.5" strokeLinecap="round" />
        <line x1="3" y1="12" x2="3.01" y2="12" strokeWidth="2.5" strokeLinecap="round" />
        <line x1="3" y1="18" x2="3.01" y2="18" strokeWidth="2.5" strokeLinecap="round" />
      </svg>
    )
  if (id === 'calendar')
    return (
      <svg width="22" height="22" viewBox="0 0 24 24" {...sp} aria-hidden>
        <rect x="3" y="4" width="18" height="18" rx="2" />
        <line x1="16" y1="2" x2="16" y2="6" />
        <line x1="8" y1="2" x2="8" y2="6" />
        <line x1="3" y1="10" x2="21" y2="10" />
      </svg>
    )
  if (id === 'add')
    return (
      <svg width="22" height="22" viewBox="0 0 24 24" {...sp} aria-hidden>
        <circle cx="12" cy="12" r="9" />
        <line x1="12" y1="8" x2="12" y2="16" />
        <line x1="8" y1="12" x2="16" y2="12" />
      </svg>
    )
  // quest
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" {...sp} aria-hidden>
      <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2" />
    </svg>
  )
}

// ── Event card ────────────────────────────────────────────────────────────────

function EventCard({
  event,
  onRsvp,
}: {
  event: TimelineEvent & { location?: string | null }
  onRsvp: (id: string, rsvpd: boolean) => void
}) {
  return (
    <div
      className="rise"
      style={{
        background: 'var(--color-paper)',
        border: '1px solid rgba(0,0,0,0.07)',
        borderRadius: 12,
        padding: '14px 16px',
        display: 'flex',
        flexDirection: 'column',
        gap: 6,
      }}
    >
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 8 }}>
        <div style={{ flex: 1 }}>
          {event.start_time && (
            <p className="font-mono" style={{ fontSize: 11, color: 'var(--color-ink-3)', marginBottom: 2, letterSpacing: '0.04em' }}>
              {event.start_time.toUpperCase()}
            </p>
          )}
          <p className="font-sans" style={{ fontSize: 15, fontWeight: 600, color: 'var(--color-ink)', lineHeight: 1.3 }}>
            {event.title}
          </p>
          {event.location && (
            <p className="font-sans" style={{ fontSize: 13, color: 'var(--color-ink-2)', marginTop: 2 }}>
              {event.location}
            </p>
          )}
        </div>
        <button
          onClick={() => { haptic('light'); onRsvp(event.id, event.rsvpd) }}
          className="press"
          style={{
            flexShrink: 0,
            padding: '6px 14px',
            borderRadius: 20,
            border: event.rsvpd ? 'none' : '1.5px solid rgba(0,0,0,0.15)',
            background: event.rsvpd ? 'var(--color-moss-700)' : 'transparent',
            color: event.rsvpd ? '#fff' : 'var(--color-ink-2)',
            fontSize: 13,
            fontWeight: 500,
            cursor: 'pointer',
            fontFamily: 'var(--font-sans)',
          }}
        >
          {event.rsvpd ? 'Going ✓' : 'RSVP'}
        </button>
      </div>
      <p className="font-mono" style={{ fontSize: 11, color: 'var(--color-ink-3)', tabularNums: true } as React.CSSProperties}>
        <span style={{ fontVariantNumeric: 'tabular-nums' }}>{event.going_count}</span> going
      </p>
    </div>
  )
}

// ── Timeline tab ─────────────────────────────────────────────────────────────

function TimelineTab() {
  const [events, setEvents] = useState<TimelineEvent[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    getTodayEvents().then(setEvents).finally(() => setLoading(false))
  }, [])

  const handleRsvp = useCallback(async (id: string, rsvpd: boolean) => {
    setEvents((prev) =>
      prev.map((e) =>
        e.id === id
          ? { ...e, rsvpd: !rsvpd, going_count: e.going_count + (rsvpd ? -1 : 1) }
          : e
      )
    )
    try {
      if (rsvpd) await unRsvpEvent(id)
      else await rsvpEvent(id)
    } catch {
      // revert on error
      setEvents((prev) =>
        prev.map((e) =>
          e.id === id
            ? { ...e, rsvpd, going_count: e.going_count + (rsvpd ? 1 : -1) }
            : e
        )
      )
    }
  }, [])

  if (loading) {
    return (
      <div style={{ padding: '48px 0', textAlign: 'center', color: 'var(--color-ink-3)', fontFamily: 'var(--font-sans)', fontSize: 14 }}>
        Loading…
      </div>
    )
  }

  const today = new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' })

  return (
    <div style={{ padding: '16px 16px 0' }}>
      <p className="font-sans" style={{ fontSize: 12, color: 'var(--color-ink-3)', marginBottom: 14, textTransform: 'uppercase', letterSpacing: '0.06em' }}>
        {today}
      </p>
      {events.length === 0 ? (
        <div style={{ padding: '48px 0', textAlign: 'center' }}>
          <p className="font-sans" style={{ fontSize: 15, color: 'var(--color-ink-3)' }}>Nothing on the calendar today</p>
          <p className="font-sans" style={{ fontSize: 13, color: 'var(--color-ink-3)', marginTop: 6 }}>Add something for the community</p>
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {events.map((e) => (
            <EventCard key={e.id} event={e} onRsvp={handleRsvp} />
          ))}
        </div>
      )}
    </div>
  )
}

// ── Placeholder tabs (filled in later tasks) ──────────────────────────────────

function CalendarTab() {
  return <div style={{ padding: 24, fontFamily: 'var(--font-sans)', color: 'var(--color-ink-3)' }}>Calendar — coming in Task 5</div>
}
function AddEventTab({ onSuccess }: { onSuccess: () => void }) {
  return <div style={{ padding: 24, fontFamily: 'var(--font-sans)', color: 'var(--color-ink-3)' }}>Add Event — coming in Task 6</div>
}
function QuestTab({ isAdmin }: { isAdmin: boolean }) {
  return <div style={{ padding: 24, fontFamily: 'var(--font-sans)', color: 'var(--color-ink-3)' }}>Quest — coming in Task 7</div>
}

// ── Page shell ────────────────────────────────────────────────────────────────

export default function CommunityPage() {
  const [tab, setTab] = useState<Tab>('timeline')
  const [isAdmin, setIsAdmin] = useState(false)

  useEffect(() => {
    getCurrentUser().then((u) => setIsAdmin(isAdminEmail(u?.email)))
  }, [])

  const switchTab = (t: Tab) => { haptic('light'); setTab(t) }

  const TABS: { id: Tab; label: string }[] = [
    { id: 'timeline', label: 'Today' },
    { id: 'calendar', label: 'Calendar' },
    { id: 'add', label: 'Add' },
    { id: 'quest', label: 'Quest' },
  ]

  return (
    <div
      style={{
        minHeight: '100dvh',
        background: 'var(--color-paper)',
        display: 'flex',
        flexDirection: 'column',
        maxWidth: 480,
        margin: '0 auto',
      }}
    >
      {/* Header */}
      <header
        style={{
          padding: '18px 16px 12px',
          borderBottom: '1px solid rgba(0,0,0,0.07)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
        }}
      >
        <span className="font-display" style={{ fontSize: 22, color: 'var(--color-ink)', letterSpacing: '-0.02em' }}>
          Hygge
        </span>
        <span className="font-sans" style={{ fontSize: 12, color: 'var(--color-ink-3)', letterSpacing: '0.05em', textTransform: 'uppercase' }}>
          St. Joseph
        </span>
      </header>

      {/* Tab content */}
      <main style={{ flex: 1, overflowY: 'auto', paddingBottom: 80 }}>
        {tab === 'timeline' && <TimelineTab />}
        {tab === 'calendar' && <CalendarTab />}
        {tab === 'add' && <AddEventTab onSuccess={() => setTab('timeline')} />}
        {tab === 'quest' && <QuestTab isAdmin={isAdmin} />}
      </main>

      {/* Bottom nav */}
      <nav
        style={{
          position: 'fixed',
          bottom: 0,
          left: '50%',
          transform: 'translateX(-50%)',
          width: '100%',
          maxWidth: 480,
          background: 'rgba(255,255,255,0.92)',
          backdropFilter: 'blur(12px)',
          borderTop: '1px solid rgba(0,0,0,0.07)',
          display: 'grid',
          gridTemplateColumns: 'repeat(4, 1fr)',
          padding: '8px 0 max(8px, env(safe-area-inset-bottom))',
        }}
      >
        {TABS.map((t) => (
          <button
            key={t.id}
            onClick={() => switchTab(t.id)}
            style={{
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              gap: 3,
              background: 'none',
              border: 'none',
              cursor: 'pointer',
              padding: '4px 0',
            }}
          >
            <TabIcon id={t.id} active={tab === t.id} />
            <span
              className="font-sans"
              style={{
                fontSize: 10,
                color: tab === t.id ? 'var(--color-ink)' : '#9ca3af',
                letterSpacing: '0.04em',
                fontWeight: tab === t.id ? 600 : 400,
              }}
            >
              {t.label}
            </span>
          </button>
        ))}
      </nav>
    </div>
  )
}
```

- [ ] **Step 2: Run dev server and verify**

```bash
npm run dev
```

Open `http://localhost:3000/community`. Verify:
- Header shows "Hygge" + "St. Joseph"
- 4 tabs in bottom nav: Today, Calendar, Add, Quest
- Today tab loads and shows events (or empty state)
- RSVP button toggles green and updates count optimistically
- Calendar/Add/Quest tabs show placeholder text

- [ ] **Step 3: Commit**

```bash
git add app/community/page.tsx
git commit -m "feat: rebuild community page shell with Timeline tab"
```

---

### Task 5: Calendar tab

**Files:**
- Modify: `app/community/page.tsx` — replace `CalendarTab` placeholder

**Interfaces:**
- Consumes: `getEventsByDate(date: string): Promise<TimelineEvent[]>`, `getMonthEventDates(year, month): Promise<string[]>` from `lib/community`
- Consumes: `rsvpEvent`, `unRsvpEvent` from `lib/community`
- Consumes: `EventCard` component (already defined in page.tsx)

- [ ] **Step 1: Add imports at top of page.tsx**

Add to the import from `@/lib/community`:
```ts
import {
  getTodayEvents,
  getEventsByDate,
  getMonthEventDates,
  rsvpEvent,
  unRsvpEvent,
  getCurrentUser,
  isAdminEmail,
  type TimelineEvent,
} from '@/lib/community'
```

- [ ] **Step 2: Replace the CalendarTab placeholder**

Replace:
```tsx
function CalendarTab() {
  return <div style={{ padding: 24, fontFamily: 'var(--font-sans)', color: 'var(--color-ink-3)' }}>Calendar — coming in Task 5</div>
}
```

With:
```tsx
function CalendarTab() {
  const today = new Date()
  const [year, setYear] = useState(today.getFullYear())
  const [month, setMonth] = useState(today.getMonth() + 1) // 1-indexed
  const [selectedDate, setSelectedDate] = useState<string | null>(null)
  const [eventDates, setEventDates] = useState<Set<string>>(new Set())
  const [dayEvents, setDayEvents] = useState<TimelineEvent[]>([])
  const [sheetOpen, setSheetOpen] = useState(false)
  const [loadingDays, setLoadingDays] = useState(true)
  const [loadingEvents, setLoadingEvents] = useState(false)

  useEffect(() => {
    setLoadingDays(true)
    getMonthEventDates(year, month)
      .then((dates) => setEventDates(new Set(dates)))
      .finally(() => setLoadingDays(false))
  }, [year, month])

  const selectDate = async (ymd: string) => {
    setSelectedDate(ymd)
    setSheetOpen(true)
    setLoadingEvents(true)
    const evs = await getEventsByDate(ymd).finally(() => setLoadingEvents(false))
    setDayEvents(evs)
  }

  const handleRsvp = useCallback(async (id: string, rsvpd: boolean) => {
    setDayEvents((prev) =>
      prev.map((e) =>
        e.id === id ? { ...e, rsvpd: !rsvpd, going_count: e.going_count + (rsvpd ? -1 : 1) } : e
      )
    )
    try {
      if (rsvpd) await unRsvpEvent(id)
      else await rsvpEvent(id)
    } catch {
      setDayEvents((prev) =>
        prev.map((e) =>
          e.id === id ? { ...e, rsvpd, going_count: e.going_count + (rsvpd ? 1 : -1) } : e
        )
      )
    }
  }, [])

  // Build month grid
  const firstDay = new Date(year, month - 1, 1).getDay() // 0=Sun
  const daysInMonth = new Date(year, month, 0).getDate()
  const cells: (number | null)[] = [
    ...Array(firstDay).fill(null),
    ...Array.from({ length: daysInMonth }, (_, i) => i + 1),
  ]
  // pad to complete weeks
  while (cells.length % 7 !== 0) cells.push(null)

  const monthLabel = new Date(year, month - 1, 1).toLocaleDateString('en-US', { month: 'long', year: 'numeric' })
  const todayYmd = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`

  return (
    <div style={{ padding: '16px' }}>
      {/* Month navigation */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 16 }}>
        <button
          onClick={() => {
            if (month === 1) { setYear(y => y - 1); setMonth(12) } else setMonth(m => m - 1)
          }}
          style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 8, color: 'var(--color-ink-2)' }}
          aria-label="Previous month"
        >
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><polyline points="15 18 9 12 15 6" /></svg>
        </button>
        <span className="font-sans" style={{ fontSize: 15, fontWeight: 600, color: 'var(--color-ink)' }}>{monthLabel}</span>
        <button
          onClick={() => {
            if (month === 12) { setYear(y => y + 1); setMonth(1) } else setMonth(m => m + 1)
          }}
          style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 8, color: 'var(--color-ink-2)' }}
          aria-label="Next month"
        >
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><polyline points="9 18 15 12 9 6" /></svg>
        </button>
      </div>

      {/* Day-of-week headers */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', marginBottom: 4 }}>
        {['S','M','T','W','T','F','S'].map((d, i) => (
          <div key={i} className="font-sans" style={{ textAlign: 'center', fontSize: 11, color: 'var(--color-ink-3)', padding: '4px 0', letterSpacing: '0.04em' }}>{d}</div>
        ))}
      </div>

      {/* Calendar grid */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 2, opacity: loadingDays ? 0.5 : 1, transition: 'opacity 0.2s' }}>
        {cells.map((day, i) => {
          if (!day) return <div key={i} />
          const ymd = `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`
          const hasEvent = eventDates.has(ymd)
          const isToday = ymd === todayYmd
          const isSelected = ymd === selectedDate
          return (
            <button
              key={i}
              onClick={() => selectDate(ymd)}
              style={{
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                justifyContent: 'center',
                gap: 3,
                padding: '8px 0',
                borderRadius: 8,
                border: 'none',
                background: isSelected ? 'var(--color-moss-700)' : isToday ? 'var(--color-paper-100)' : 'transparent',
                cursor: 'pointer',
              }}
            >
              <span
                className="font-sans"
                style={{
                  fontSize: 14,
                  fontWeight: isToday ? 700 : 400,
                  color: isSelected ? '#fff' : isToday ? 'var(--color-moss-700)' : 'var(--color-ink)',
                }}
              >
                {day}
              </span>
              {hasEvent && (
                <span style={{
                  width: 4, height: 4, borderRadius: '50%',
                  background: isSelected ? 'rgba(255,255,255,0.7)' : 'var(--color-moss-600)',
                }} />
              )}
            </button>
          )
        })}
      </div>

      {/* Event sheet */}
      {sheetOpen && selectedDate && (
        <div
          className="sheet-up"
          style={{
            position: 'fixed',
            bottom: 0,
            left: '50%',
            transform: 'translateX(-50%)',
            width: '100%',
            maxWidth: 480,
            background: 'var(--color-paper)',
            borderTop: '1px solid rgba(0,0,0,0.1)',
            borderRadius: '16px 16px 0 0',
            padding: '16px 16px max(16px, env(safe-area-inset-bottom))',
            maxHeight: '60dvh',
            overflowY: 'auto',
            zIndex: 10,
          }}
        >
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14 }}>
            <span className="font-sans" style={{ fontSize: 14, fontWeight: 600, color: 'var(--color-ink)' }}>
              {new Date(selectedDate + 'T00:00:00').toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' })}
            </span>
            <button onClick={() => setSheetOpen(false)} style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--color-ink-3)', fontSize: 20, lineHeight: 1 }}>×</button>
          </div>
          {loadingEvents ? (
            <p className="font-sans" style={{ color: 'var(--color-ink-3)', fontSize: 14 }}>Loading…</p>
          ) : dayEvents.length === 0 ? (
            <p className="font-sans" style={{ color: 'var(--color-ink-3)', fontSize: 14 }}>No events this day.</p>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
              {dayEvents.map((e) => <EventCard key={e.id} event={e} onRsvp={handleRsvp} />)}
            </div>
          )}
        </div>
      )}
      {/* Sheet backdrop */}
      {sheetOpen && (
        <div
          onClick={() => setSheetOpen(false)}
          style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.3)', zIndex: 9 }}
        />
      )}
    </div>
  )
}
```

- [ ] **Step 3: Verify**

```bash
npm run dev
```

Open `http://localhost:3000/community` → Calendar tab. Verify:
- Month grid renders with correct days
- Dates with events show a green dot
- Tapping a date opens a sheet with that day's events
- RSVP works from the sheet
- Prev/next month navigation works

- [ ] **Step 4: Commit**

```bash
git add app/community/page.tsx
git commit -m "feat: add Calendar tab with month grid and event sheet"
```

---

### Task 6: Add Event tab

**Files:**
- Modify: `app/community/page.tsx` — replace `AddEventTab` placeholder

**Interfaces:**
- Consumes: `addEvent(input: NewEventInput): Promise<void>` from `lib/community`
- Consumes: `NewEventInput` type from `lib/community`

- [ ] **Step 1: Add NewEventInput to imports**

Update the `lib/community` import to include:
```ts
import {
  getTodayEvents,
  getEventsByDate,
  getMonthEventDates,
  addEvent,
  rsvpEvent,
  unRsvpEvent,
  getCurrentUser,
  isAdminEmail,
  type TimelineEvent,
  type NewEventInput,
} from '@/lib/community'
```

- [ ] **Step 2: Replace the AddEventTab placeholder**

Replace:
```tsx
function AddEventTab({ onSuccess }: { onSuccess: () => void }) {
  return <div style={{ padding: 24, fontFamily: 'var(--font-sans)', color: 'var(--color-ink-3)' }}>Add Event — coming in Task 6</div>
}
```

With:
```tsx
function AddEventTab({ onSuccess }: { onSuccess: () => void }) {
  const todayYmd = (() => {
    const d = new Date()
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
  })()
  const [form, setForm] = useState<NewEventInput>({
    title: '',
    event_date: todayYmd,
    start_time: '',
    location: '',
    description: '',
  })
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const set = (field: keyof NewEventInput) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) =>
    setForm((f) => ({ ...f, [field]: e.target.value }))

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!form.title.trim() || !form.event_date || !form.start_time.trim() || !form.location.trim()) {
      setError('Title, date, time, and location are required.')
      return
    }
    setError(null)
    setSubmitting(true)
    try {
      await addEvent({ ...form, title: form.title.trim(), location: form.location.trim() })
      haptic('medium')
      onSuccess()
    } catch (err) {
      setError('Failed to add event. Try again.')
    } finally {
      setSubmitting(false)
    }
  }

  const fieldStyle: React.CSSProperties = {
    width: '100%',
    padding: '11px 13px',
    borderRadius: 10,
    border: '1.5px solid rgba(0,0,0,0.12)',
    background: 'var(--color-paper)',
    fontSize: 15,
    color: 'var(--color-ink)',
    fontFamily: 'var(--font-sans)',
    outline: 'none',
    boxSizing: 'border-box',
  }
  const labelStyle: React.CSSProperties = {
    fontSize: 11,
    color: 'var(--color-ink-3)',
    textTransform: 'uppercase',
    letterSpacing: '0.06em',
    marginBottom: 5,
    display: 'block',
    fontFamily: 'var(--font-sans)',
  }

  return (
    <div style={{ padding: '20px 16px' }}>
      <h2 className="font-sans" style={{ fontSize: 18, fontWeight: 700, color: 'var(--color-ink)', marginBottom: 20 }}>
        Add an Event
      </h2>
      <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
        <div>
          <label style={labelStyle}>Title *</label>
          <input style={fieldStyle} placeholder="Saturday Farmers Market" value={form.title} onChange={set('title')} />
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
          <div>
            <label style={labelStyle}>Date *</label>
            <input type="date" style={fieldStyle} value={form.event_date} onChange={set('event_date')} />
          </div>
          <div>
            <label style={labelStyle}>Time *</label>
            <input style={fieldStyle} placeholder="7am" value={form.start_time} onChange={set('start_time')} />
          </div>
        </div>
        <div>
          <label style={labelStyle}>Location *</label>
          <input style={fieldStyle} placeholder="Riverside Park" value={form.location} onChange={set('location')} />
        </div>
        <div>
          <label style={labelStyle}>Description</label>
          <textarea
            style={{ ...fieldStyle, minHeight: 80, resize: 'vertical' }}
            placeholder="Tell people what to expect…"
            value={form.description}
            onChange={set('description')}
          />
        </div>
        {error && (
          <p className="font-sans" style={{ fontSize: 13, color: 'var(--color-clay-700)' }}>{error}</p>
        )}
        <button
          type="submit"
          disabled={submitting}
          className="press"
          style={{
            padding: '13px',
            borderRadius: 12,
            border: 'none',
            background: submitting ? 'var(--color-paper-200)' : 'var(--color-moss-700)',
            color: submitting ? 'var(--color-ink-3)' : '#fff',
            fontSize: 15,
            fontWeight: 600,
            cursor: submitting ? 'not-allowed' : 'pointer',
            fontFamily: 'var(--font-sans)',
          }}
        >
          {submitting ? 'Adding…' : 'Add Event'}
        </button>
      </form>
    </div>
  )
}
```

- [ ] **Step 3: Verify**

```bash
npm run dev
```

Open `http://localhost:3000/community` → Add tab. Verify:
- Form renders with all fields
- Submitting with empty required fields shows error message
- Submitting a valid event redirects to Today tab
- The new event appears on the Timeline immediately

- [ ] **Step 4: Commit**

```bash
git add app/community/page.tsx
git commit -m "feat: add Add Event tab with form and Supabase insert"
```

---

### Task 7: Quest tab + admin

**Files:**
- Modify: `app/community/page.tsx` — replace `QuestTab` placeholder

**Interfaces:**
- Consumes: `getTodayQuest(): Promise<DailyQuest | null>`, `getQuestCompletionCount(questId): Promise<number>`, `hasUserCompletedQuest(questId, userId): Promise<boolean>`, `completeQuest(questId): Promise<void>`, `setQuest(title, description, date): Promise<void>` from `lib/community`
- Consumes: `DailyQuest` type from `lib/community`
- Consumes: `getCurrentUser` result (passed in as `isAdmin` prop, already wired in shell)

- [ ] **Step 1: Add quest imports**

Update the `lib/community` import to include:
```ts
import {
  getTodayEvents,
  getEventsByDate,
  getMonthEventDates,
  addEvent,
  rsvpEvent,
  unRsvpEvent,
  getCurrentUser,
  isAdminEmail,
  getTodayQuest,
  getQuestCompletionCount,
  hasUserCompletedQuest,
  completeQuest,
  setQuest,
  type TimelineEvent,
  type NewEventInput,
  type DailyQuest,
} from '@/lib/community'
```

- [ ] **Step 2: Replace the QuestTab placeholder**

Replace:
```tsx
function QuestTab({ isAdmin }: { isAdmin: boolean }) {
  return <div style={{ padding: 24, fontFamily: 'var(--font-sans)', color: 'var(--color-ink-3)' }}>Quest — coming in Task 7</div>
}
```

With:
```tsx
function QuestTab({ isAdmin }: { isAdmin: boolean }) {
  const [quest, setQuest_] = useState<DailyQuest | null>(null)
  const [count, setCount] = useState(0)
  const [done, setDone] = useState(false)
  const [loading, setLoading] = useState(true)
  const [completing, setCompleting] = useState(false)
  // Admin form state
  const [adminTitle, setAdminTitle] = useState('')
  const [adminDesc, setAdminDesc] = useState('')
  const [adminDate, setAdminDate] = useState('')
  const [adminSaving, setAdminSaving] = useState(false)
  const [adminMsg, setAdminMsg] = useState<string | null>(null)

  useEffect(() => {
    async function load() {
      const q = await getTodayQuest()
      setQuest_(q)
      if (q) {
        const [c, user] = await Promise.all([
          getQuestCompletionCount(q.id),
          getCurrentUser(),
        ])
        setCount(c)
        if (user) setDone(await hasUserCompletedQuest(q.id, user.id))
      }
      setLoading(false)
    }
    load()
  }, [])

  const handleComplete = async () => {
    if (!quest || done || completing) return
    setCompleting(true)
    haptic('medium')
    try {
      await completeQuest(quest.id)
      setDone(true)
      setCount((c) => c + 1)
    } finally {
      setCompleting(false)
    }
  }

  const handleSetQuest = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!adminTitle.trim() || !adminDate) return
    setAdminSaving(true)
    setAdminMsg(null)
    try {
      await setQuest(adminTitle.trim(), adminDesc.trim(), adminDate)
      setAdminMsg('Quest saved!')
      setAdminTitle('')
      setAdminDesc('')
      setAdminDate('')
    } catch {
      setAdminMsg('Failed to save.')
    } finally {
      setAdminSaving(false)
    }
  }

  if (loading) {
    return <div style={{ padding: 48, textAlign: 'center', fontFamily: 'var(--font-sans)', fontSize: 14, color: 'var(--color-ink-3)' }}>Loading…</div>
  }

  const fieldStyle: React.CSSProperties = {
    width: '100%',
    padding: '11px 13px',
    borderRadius: 10,
    border: '1.5px solid rgba(0,0,0,0.12)',
    background: 'var(--color-paper)',
    fontSize: 15,
    color: 'var(--color-ink)',
    fontFamily: 'var(--font-sans)',
    outline: 'none',
    boxSizing: 'border-box',
  }
  const labelStyle: React.CSSProperties = {
    fontSize: 11,
    color: 'var(--color-ink-3)',
    textTransform: 'uppercase',
    letterSpacing: '0.06em',
    marginBottom: 5,
    display: 'block',
    fontFamily: 'var(--font-sans)',
  }

  return (
    <div style={{ padding: '20px 16px', display: 'flex', flexDirection: 'column', gap: 24 }}>
      {/* Today's quest card */}
      {quest ? (
        <div
          className="rise"
          style={{
            background: 'var(--color-paper)',
            border: '1px solid rgba(0,0,0,0.07)',
            borderRadius: 16,
            padding: '20px 18px',
          }}
        >
          <p className="font-sans" style={{ fontSize: 11, color: 'var(--color-ink-3)', textTransform: 'uppercase', letterSpacing: '0.06em', marginBottom: 8 }}>
            Today&apos;s Quest
          </p>
          <p className="font-sans" style={{ fontSize: 20, fontWeight: 700, color: 'var(--color-ink)', marginBottom: 6, lineHeight: 1.3 }}>
            {quest.title}
          </p>
          {quest.description && (
            <p className="font-sans" style={{ fontSize: 14, color: 'var(--color-ink-2)', marginBottom: 16, lineHeight: 1.5 }}>
              {quest.description}
            </p>
          )}
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
            <p className="font-mono" style={{ fontSize: 13, color: 'var(--color-ink-3)', fontVariantNumeric: 'tabular-nums' }}>
              <span>{count}</span> {count === 1 ? 'person' : 'people'} completed this today
            </p>
            <button
              onClick={handleComplete}
              disabled={done || completing}
              className="press"
              style={{
                padding: '8px 18px',
                borderRadius: 20,
                border: 'none',
                background: done ? 'var(--color-moss-700)' : 'var(--color-paper-100)',
                color: done ? '#fff' : 'var(--color-ink)',
                fontSize: 14,
                fontWeight: 600,
                cursor: done ? 'default' : 'pointer',
                fontFamily: 'var(--font-sans)',
              }}
            >
              {done ? 'Done ✓' : completing ? '…' : 'Mark Done'}
            </button>
          </div>
        </div>
      ) : (
        <div style={{ padding: '48px 0', textAlign: 'center' }}>
          <p className="font-sans" style={{ fontSize: 15, color: 'var(--color-ink-3)' }}>No quest today</p>
          <p className="font-sans" style={{ fontSize: 13, color: 'var(--color-ink-3)', marginTop: 6 }}>Check back tomorrow</p>
        </div>
      )}

      {/* Admin: set quest */}
      {isAdmin && (
        <div style={{ borderTop: '1px solid rgba(0,0,0,0.07)', paddingTop: 20 }}>
          <p className="font-sans" style={{ fontSize: 12, color: 'var(--color-ink-3)', textTransform: 'uppercase', letterSpacing: '0.06em', marginBottom: 14 }}>
            Set a Quest (Admin)
          </p>
          <form onSubmit={handleSetQuest} style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            <div>
              <label style={labelStyle}>Date</label>
              <input type="date" style={fieldStyle} value={adminDate} onChange={(e) => setAdminDate(e.target.value)} />
            </div>
            <div>
              <label style={labelStyle}>Title</label>
              <input style={fieldStyle} placeholder="Walk to the park" value={adminTitle} onChange={(e) => setAdminTitle(e.target.value)} />
            </div>
            <div>
              <label style={labelStyle}>Description</label>
              <textarea
                style={{ ...fieldStyle, minHeight: 70, resize: 'vertical' }}
                placeholder="Optional details…"
                value={adminDesc}
                onChange={(e) => setAdminDesc(e.target.value)}
              />
            </div>
            {adminMsg && <p className="font-sans" style={{ fontSize: 13, color: adminMsg === 'Quest saved!' ? 'var(--color-moss-700)' : 'var(--color-clay-700)' }}>{adminMsg}</p>}
            <button
              type="submit"
              disabled={adminSaving}
              className="press"
              style={{
                padding: '11px',
                borderRadius: 10,
                border: 'none',
                background: adminSaving ? 'var(--color-paper-200)' : 'var(--color-ink)',
                color: adminSaving ? 'var(--color-ink-3)' : '#fff',
                fontSize: 14,
                fontWeight: 600,
                cursor: adminSaving ? 'not-allowed' : 'pointer',
                fontFamily: 'var(--font-sans)',
              }}
            >
              {adminSaving ? 'Saving…' : 'Save Quest'}
            </button>
          </form>
        </div>
      )}
    </div>
  )
}
```

- [ ] **Step 3: Verify**

```bash
npm run dev
```

Open `http://localhost:3000/community` → Quest tab. Verify:
- If no quest set for today: empty state shows
- As admin (jessewallacejohnson1@icloud.com): admin form shows below
- Set a quest for today → reload page → quest card appears
- Tap "Mark Done" → button turns green, count increments
- Tapping again is disabled

- [ ] **Step 4: Final build check**

```bash
npm run build 2>&1 | tail -20
```

Expected: successful build, no errors.

- [ ] **Step 5: Commit**

```bash
git add app/community/page.tsx
git commit -m "feat: add Quest tab with completion tracking and admin quest setter"
```
