# Calendar Day-Detail — timeline agenda + staggered entrance (ported from reference)

**Date:** 2026-07-14
**Reference:** `~/Desktop/Screen Recording 2026-07-14 at 1.29.33 PM.mov` (2.115 s, 444×558, a looping preview of the ENTRANCE)

## What the reference shows
A full-screen single-day **timeline agenda**:
- Centered header: ‹  **Weekday** / *Mon d, yyyy*  › with left/right chevrons; a top-right control.
- A vertical **time column** on the left (hour labels) with event blocks and faint "open time" gaps.
- Each event **row** = coral accent bar · **Title** (bold) · subtitle · a filled circular category **icon** · a thin **checkbox** ring.
- **Entrance:** top-down **staggered spring reveal** — each hour-block fades in (opacity 0→1) with a slight rise, and its circular icon **pops** (scale settle). Row-to-row stagger ≈ 60–90 ms; whole cascade ≈ 0.6 s; spring settle.

## Final build (v2 — full 1:1 timeline)
An **hourly ruler**: `DaySlot.build` spans first→last event hour; each hour is an event block or an open "No plans" slot. Event block = colored bar + **title only** (tap → `EventDescriptionSheet` with the real `club_events.description`, plumbed onto `TimelineEvent.details`) + big tinted icon circle (letter badge; multi-color palette by slot order — a reference-fidelity carve-out like the map's) + RSVP checkbox. Open slot = **3 dots + "1 hour → No plans" + "+"**. The **3 dots pulse continuously** (staggered ease-in-out, 0.72 s, scale 0.68→1.12, Reduce-Motion static). Whole ruler reveals top-down (stagger 0.10, duration 0.60, bounce 0.16); icons pop. Wired as `.fullScreenCover(isPresented:)` so chevron day-nav updates in place + replays.

## Adaptation to Hygge (decisions)
- **Real data only** (house rule): bind to `CalendarModel.dayEvents` (real `TimelineEvent`s for the tapped day). No demo "Focus time/Lunch". No fabricated "3" inbox badge.
- `TimelineEvent` has no duration/category → **coral accent** everywhere (palette rule: coral is THE accent); icon-glyph varies by a *real* attribute (location/club) so rows still feel distinct.
- Reference **checkbox → RSVP toggle** (`model.toggleRsvp`), filled coral check when `rsvpd`.
- Reference **time column → real `startTime`s**; empty day → existing "A clear day / Add the first thing" empty state.
- Present **full-screen** (`.fullScreenCover`) — matches the reference; chevrons navigate prev/next day (functional).
- Reuse the app's `SpringReveal` motion recipe for cohesion; tune in the ss-loop.

## Animation — FINAL tuned values (frame-matched to the reference)
Per block index `i`, via `SpringReveal` (extended with `stagger`/`duration`/`bounce` params, defaults unchanged for existing callers): `opacity 0→1`, `offset y: 22→0`, block `scale 0.94→1` (anchor `.top`); icon circle `scale 0.55→1` with `.spring(response:0.4, dampingFraction:0.6).delay(i*stagger+0.04)`.
- **stagger `0.21`**, **duration `0.66`**, **bounce `0.16`** (softer/slower than the app-wide 0.05 / 0.48 / 0.28 — the day has few tall rows and the reference is a deliberate, calm top-down wipe).
- Trigger: `revealed` State true on appear; replays on day-change and the DEBUG loop.
- Reduce Motion → fade only (no movement), `easeOut 0.25`.

## Verify — workflow + two gotchas (both cost real iterations here)
`simctl io recordVideo` (finalize with SIGINT) → AVAssetImageGenerator frames → dark-pixel reset detection → REF/HYG two-row contact sheet. DEBUG `-calendar-open <YYYY-MM-DD> -calendar-sample -calendar-replay` opens a deterministic 3-row day and loops the reveal on the reference's 2.115 s cadence.
1. **Replay needs an instant hide.** `SpringReveal` animates BOTH directions, so flipping `revealed=false` to reset animates the rows *out* over the settle time — they never clear and the cascade is invisible. Reset must pass `animated:false` (instant), then `true` (animate). This is what the `animated` flag is for.
2. **Compare equal-duration windows.** Squashing a 0.83 s HYG window and a 0.6 s REF window to the same N columns makes HYG look ~3× too fast — a pure measurement artifact. Match the capture window to the reference's reveal span (≈0.6 s), reveal-start-aligned, so columns are equal absolute times.
