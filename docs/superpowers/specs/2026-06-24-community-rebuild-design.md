# Hygge Community Rebuild — Design Spec
Date: 2026-06-24

## What we're building

A focused rebuild of the Hygge app as a community-first platform for St. Joseph, MN. All nutrition and fitness functionality is removed. The entire app becomes a single community hub: events, calendar, posting, and a daily quest.

## Approach

**Rebuild the UI, keep the DB.** The existing auth, Supabase tables, and `lib/community.ts` helpers are solid — no schema changes except two new tables. The community page UI is gutted and rebuilt with 4 clean tabs. All fitness routes are deleted.

---

## App Structure

### Routes removed
- `/dashboard`
- `/meal-log`
- `/workouts`
- `/scan`
- `/progress`
- `/onboarding`

### Routes kept / rebuilt
| Route | Notes |
|---|---|
| `/` | Marketing landing — keep as-is |
| `/login` | Auth — keep as-is |
| `/auth/callback` | Keep as-is |
| `/community` | The entire app — 4 tabs, auth-gated |

### Middleware
`proxy.ts` gates only `/community`. After login, redirect lands on Timeline tab.

---

## The 4 Tabs

### 1. Timeline (default)
- Chronological list of today's events
- Each card: time, title, location, RSVP count, RSVP toggle button
- Scrollable, newest-first within time slots
- Empty state: "Nothing on the calendar today — add something."

### 2. Calendar
- Month view with dot indicators on dates that have events
- Tap any date → sheet slides up showing that day's event list (same card format as Timeline)
- Defaults to today on open

### 3. Add Event
- Sheet/form: title (required), date + time (required), location (required), description (optional)
- Anyone with an account can post — no approval queue
- On submit: event appears immediately in Timeline/Calendar
- `club_id` is nullable — events don't require a club

### 4. Quest
- Single card showing today's quest: title + description
- Live completion count: "14 people completed this today"
- "Done" button — one tap per user per day, disabled after completion
- Admin view (gated by `ADMIN_EMAIL`): form to set tomorrow's quest
- If no quest is set for today: "No quest today — check back tomorrow."

### Navigation
- Bottom tab bar, mobile-first
- 4 icons: Timeline, Calendar, Add, Quest
- Same visual pattern as existing community nav

---

## Data

### Existing tables (unchanged)
- `clubs`, `club_members` — kept, available for future use
- `club_events` — reused for Timeline + Calendar; `club_id` made nullable
- `event_rsvps` — reused as-is

### New tables

**`daily_quests`**
```sql
id          uuid primary key default gen_random_uuid()
title       text not null
description text
date        date not null unique  -- one quest per day
created_by  uuid references auth.users
created_at  timestamptz default now()
```

**`quest_completions`**
```sql
id           uuid primary key default gen_random_uuid()
quest_id     uuid references daily_quests not null
user_id      uuid references auth.users not null
completed_at timestamptz default now()
unique(quest_id, user_id)  -- one completion per user per quest
```

RLS: users can only insert/read their own `quest_completions` row.

### `lib/community.ts` additions
- `getTodayQuest()` — fetch today's `daily_quests` row
- `getQuestCompletionCount(questId)` — count completions for a quest
- `hasUserCompletedQuest(questId, userId)` — boolean check
- `completeQuest(questId, userId)` — insert completion row
- `setQuest({ title, description, date })` — admin only

---

## What stays from the existing community page
- All club logic and DB helpers (kept but not surfaced in UI yet — future tab)
- Auth pattern (`getCurrentUser`, `isAdminEmail`)
- Bottom nav visual pattern
- Time-of-day mode (morning/evening) — keep the ambient feel

## What gets removed from the community page
- Letter tab
- Hello tab
- Static content from `lib/community-content.ts` (weather, morning/evening copy, Sunday letter)
- The 4-tab structure is rebuilt around the new tabs above

---

## Files changed

| File | Action |
|---|---|
| `app/community/page.tsx` | Full rewrite |
| `lib/community.ts` | Add quest helpers |
| `supabase/migration-quests.sql` | New migration for 2 tables |
| `proxy.ts` | Trim gated routes to `/community` only |
| `app/dashboard/` | Delete |
| `app/meal-log/` | Delete |
| `app/workouts/` | Delete |
| `app/scan/` | Delete |
| `app/progress/` | Delete |
| `app/onboarding/` | Delete |
| `app/components/AppShell.tsx` | Delete or gut (fitness nav gone) |
| `lib/community-content.ts` | Delete |

---

## Success criteria
- User logs in → lands on Timeline showing today's events
- User can RSVP to an event
- User can add an event that appears immediately
- User can tap "Done" on the daily quest once, sees the count go up
- Admin (Jesse) can set the next day's quest
- Calendar shows dots on event days, tapping reveals events
