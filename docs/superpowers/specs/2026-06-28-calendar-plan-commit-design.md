# Calendar tab → "Plan & Commit" — design

**Date:** 2026-06-28
**Surface:** `apps/mobile/src/app/(tabs)/calendar.tsx` (+ `src/components/ExpandedWeek.tsx`, `EventRow.tsx`, shared core)
**Status:** approved in brainstorm, pending spec review

## Problem

Today the Calendar tab is a **viewer**: a 12-month grid where dots mark days that
have events, and tapping a day opens a sheet listing them. The only action is
RSVP, and the most useful week view is hidden behind an undiscoverable pinch.

A town calendar's real job is not "display dates" — it's a **bridge from
"something's happening" → "I'll actually be there."** That bridge is missing.

## Role (decided)

Three tabs, three jobs — no overlap:

- **Home** = today's timeline.
- **Activities** = browse / filter / sort all happenings (Events / Clubs / Trails).
- **Calendar** = **plan ahead across days, and commit.** This is the only tab
  whose job is looking forward in time and turning intent into attendance.

Everything below serves that one job. Judged against product priority ① (get
neighbors together IRL) first.

## Scope

Grid-first stays. We are **adding functions**, not redrawing the screen. Three
groups of work:

### 1. Orientation — answer "what's coming up?" fast

- **"This weekend" chip** and **"Today" jump** in the sticky header.
  - *This weekend* scrolls to (and opens) the upcoming Sat–Sun.
  - *Today* appears only after the user has scrolled past today's row; tapping
    snaps the scroll back to today's month. Visibility is driven by `onScroll`
    offset vs. today's measured offset.
  - Implementation: each `MonthBlock` (and the weekend week) reports its layout
    `y` via `onLayout` into a ref map; a `ScrollView` ref calls `scrollTo({ y })`.
- **Real event density** on each day cell. Replace the single binary dot with up
  to **3 moss dots**, then a `+` glyph for 4+. A 4-event Saturday must read
  heavier than a 1-event Tuesday. **Real counts only** — never inflated.
  - Needs counts per day, which the current `getMonthEventDates` throws away.

### 2. The day sheet becomes the commitment surface

- The existing slide-up day sheet keeps RSVP on each `EventRow`, and gains a
  quiet **action row** beneath each event:
  **Add to calendar · Directions · Tell a neighbor.**
  - Hairline-separated text/icon buttons on `paper` — calm, not loud buttons.
  - Each action **hides itself when it can't fire** (e.g. no `location` →
    no Directions, no Tell-a-neighbor location line).
- **Empty day is no longer a dead end.** When a day has no events, the sheet
  shows a soft `+ Add something on this day` that deep-links to the Add tab with
  that date prefilled (`router.push` with a `date` param; Add reads it).

### 3. The three actions

#### Add to my calendar — the core lever

`start_time` is a **display string** (`'7pm'`, `'7:00p'`), not a machine time, so
the helper must:

- `parseStartTime(start_time): { h: number, m: number } | null` — best-effort
  parse of common forms (`7pm`, `7:00 PM`, `7:00p`, `19:00`). On failure or
  null, the event is written as an **all-day** entry on `event_date`.
- Default duration when a start time exists: **2 hours** (no `end_time` in the
  schema).

Platform split, behind one shared `addEventToCalendar(event)` helper:

- **Web** — build an `.ics` string (VCALENDAR/VEVENT: UID, DTSTART/DTEND or
  all-day DTSTART, SUMMARY, LOCATION, DESCRIPTION) and trigger a Blob download
  via an `<a download>`. **Zero dependencies.**
- **Native (iOS app)** — **decided: `.ics` + OS share sheet.** Write the same
  `.ics` to cache and hand it to the OS share sheet so iOS offers "Add to
  Calendar." Adds `expo-file-system` + `expo-sharing` (both Expo first-party,
  Expo Go-compatible). Install with `--legacy-peer-deps` per the workspace rule.

Confirm with a quiet toast ("Added to your calendar" / "Calendar file ready").
Motion confirms only.

#### Get directions

- Open the OS maps app to `event.location` via a maps URL through the
  already-installed **`expo-linking`** — `https://maps.apple.com/?q=<loc>` on
  iOS, `https://www.google.com/maps/search/?api=1&query=<loc>` elsewhere/web.
- Hidden when `location` is null.

#### Tell a neighbor

- React Native's built-in **`Share.share({ message })`** on the app,
  `navigator.share` (with clipboard fallback) on web. **No new dependency.**
- Message: `"<title> · <when> · <where>"` + the event link. No in-app feed,
  no follower mechanics.

## Shared helpers (one code path for app + web)

New file `apps/mobile/src/lib/eventActions.ts` (or `packages/core` if it stays
client-agnostic — calendar/share touch RN/web APIs, so mobile lib is the right
home):

- `addEventToCalendar(event)` — branches on `Platform.OS`.
- `shareEvent(event)` — branches on `Platform.OS`.
- `openDirections(location)` — `Linking.openURL`.
- `parseStartTime(s)` and `buildIcs(event)` — pure, unit-testable.

## Core change

Add to `createCommunityApi` (`packages/core/src/community.ts`):

- `getMonthEventCounts(year, month): Promise<Record<string, number>>` — same
  query as `getMonthEventDates` but **counts occurrences per `event_date`**
  instead of deduping. The calendar uses counts for density; `getMonthEventDates`
  can be derived from / replaced by it. Client-agnostic, real data only.

## Brand guardrails

- Every number (dates, times, counts) stays `font-mono tabular-nums`.
- **Moss** only for positive/committed state (RSVP'd, added). No accent used
  decoratively.
- Motion **confirms**, never decorates (toast on add, press states). Respect
  `prefers-reduced-motion`.
- **No reminders / notifications** (explicitly cut to stay clear of the
  no-notification-spam bar).
- Inline SVG icons only — no emoji. Reuse `src/components/icons.tsx`; add new
  glyphs there if needed (calendar-plus, directions/pin, share).
- Calm over busy: ship **3 solid actions**, not 6.

## Decisions log

- **Calendar tab role:** plan ahead + commit (Home = today, Activities = browse).
- **Landing view:** grid-first, enhanced (no agenda-first rewrite).
- **Event actions:** RSVP (exists) + Add to calendar + Directions + Tell a
  neighbor. **Reminders explicitly cut.**
- **Native add-to-calendar:** `.ics` + OS share sheet (`expo-file-system` +
  `expo-sharing`). Considered and rejected: `expo-calendar` (permission prompt),
  Google template URL (Google-centric). Web uses a zero-dep `.ics` Blob download.

## Done = verified

- `npx tsc --noEmit` clean **and** `npx expo export --platform web` clean.
- Verified in preview: This-weekend chip scrolls + opens the weekend; Today jump
  appears after scrolling and snaps back; density dots match **real** counts;
  add-to-calendar produces a valid `.ics` (web) / device entry (native);
  Directions opens maps; Tell-a-neighbor opens the share sheet; empty-day
  `+ Add` deep-links with the date prefilled.
- Clears the on-brand bar (calm, neighborly, real counts, no notification spam).
- Dates derived with `localDate()`, never `toISOString()`.
