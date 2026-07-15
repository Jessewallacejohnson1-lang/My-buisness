# Compose "+" speed-dial — design

**Date:** 2026-07-12
**Status:** approved, building
**Trigger:** user handed a screen recording (`Screen Recording 2026-07-12 at 10.39.08 PM.mov`, a Jobber-style FAB that expands into a create-menu) with: "literally copy that video ~99%… then integrate it so every time you press the + it does this. But add: the items come up **one at a time**, super fast, with a little **bubble** effect; and when you click an item it has a little **push-in** animation."

## Reference — measured frame-by-frame

Extracted with AVFoundation (`scratchpad/anim/extract.swift` → contact sheets). Clip is 2.95s @ ~47fps.

- **Rest:** a circular FAB, bottom-right, above the tab bar. (Reference FAB is navy; ours stays coral — see decisions.)
- **Open (~70ms):** tap → the home screen washes to **near-white** and recedes very slightly; the FAB **+ rotates ~135° into ✕**; a **right-aligned column** of items (label on the left, **circular icon button** on the right) appears above it. In the reference all items appear **at once**. Items top→bottom: Request · Task · Expense · Invoice · Quote · Job · Client. The bottom item (nearest the FAB) is a **filled** circle; the rest are **cream/off-white** circles with a line glyph.
- **Hold:** menu steady over the whitened home.
- **Close (~30–60ms, a fast snap):** items vanish, **✕ rotates back to +**, home returns. No graceful reverse-stagger.

## Decisions (locked with the user)

1. **Copy the reference ~99%** for layout + motion: near-white dim backdrop, true-**circle** icon buttons, right-aligned rows, the **+ ↔ ✕** morph, matched timing. Do **not** restyle it (the earlier HTML prototype was only a feel-check).
2. **Two additions** on top of the reference:
   - Items **bubble in one at a time**, **bottom-first** (rising out of the FAB), super fast (~45ms apart), each a `scale 0.4→1` spring with a small overshoot + fade.
   - Each item gets a **press-in** on tap (`scale ≈0.9`, quick spring) — the "push-in" — before it routes.
3. **Everywhere a `+` composes**, with **context-tailored items** per surface.
4. **Palette:** keep the app's skin — **coral** FAB (`Hue.accent`, already coral + the app's one "tappable" color), coral line glyphs on **cream** (`Hue.paper`-ish) circles, the bottom/primary item **coral-filled** with a white glyph (mirrors the reference's filled bottom item). Backdrop is near-white **paper**, matching the reference's wash. (If the user wants the reference's navy FAB instead, it's a one-token change.)

## Design

### 1. `SpeedDial` — one reusable overlay component (`Features/Components/SpeedDial.swift`)
Owns the whole effect, parameterized by items. Mirrors the town-menu pattern: hosted at `MainTabsView` level (like `CornerDrawerOverlay`) so it dims the **whole** screen (incl. the tab bar) and floats above it.

- **Input:** `items: [SpeedDialItem]` — `id`, `title`, SF Symbol, `role` (`.standard` cream / `.primary` coral-filled), `action`. Plus the FAB anchor (bottom-trailing by default; Map overrides).
- **State:** `isOpen`. A per-surface `SpeedDialContext` chooses the item list.
- **Backdrop:** `Hue.paper` veil animating `0 → ~0.9` (`easeOut ~0.26s`); the home content scales `1 → ~0.97` + fades toward the veil (`~0.30s`). Tapping the backdrop closes. (Scale kept subtle; tune to the reference in the loop — if the reference shows no scale, drop it.)
- **FAB morph:** the coral disc's glyph rotates `0° → 135°` (+ → ✕) over `~0.28s` with a light spring; coral throughout. Reuses `ComposeFAB`'s disc styling.
- **Items reveal (the addition):** right-aligned column above the FAB. Each item: `opacity 0→1` + `scale 0.4→1` + small upward `translateY`, spring `cubic-bezier`-style overshoot (`interpolatingSpring`/`spring(bounce:~0.3)`), **staggered bottom-first** via per-index delay (~45ms). Total reveal ~0.45s but each item ~0.30s.
- **Item press-in (the addition):** on tap, the tapped item's icon scales to `~0.9` and springs back (quick), then fires `action`. Extends the existing `PressableStyle` "pop" toward a deeper **push-in** (less overshoot, more depress) for menu items.
- **Close:** fast collapse (~0.16s) — items fade/scale out (no per-item delay), veil fades, ✕→+.
- **Reduce Motion:** cross-fade the menu in/out, no scale/stagger; press-in becomes an opacity tick. Matches app motion conventions (`ShareCenter`, `CornerDrawer`).
- **Haptic:** `Haptics.light()` on open and on each item press (button-like), per the app's press-pop convention.

### 2. Hosting + trigger
- `MainTabsView` gains `@State speedDial: SpeedDialContext?` and renders the `SpeedDial` overlay above the tab content (same z-level as the town-menu overlay).
- The compose **+** on each surface **toggles the speed-dial** instead of calling `onCompose` (open the sheet). Surfaces:
  - **Explore (`ActivitiesView`)** & **Calendar (`CalendarView`)** — the bottom-right `ComposeFAB`.
  - **Map (`SJMapView`)** — the non-admin top-right `+`. Because it's top-anchored, the column drops **downward** (mirrored), items still bottom-first relative to the FAB. Admins keep `QuickAddSheet` (unchanged).
- The `ComposeFAB`'s own coral disc becomes the speed-dial's FAB while open (or the overlay renders the matching disc at the same anchor and the underlying FAB hides), so the morph is seamless.

### 3. Per-surface items (context-tailored)
Reuse the only create-kinds (`AddKind`: event/club/trail) + Invite; the framing/lead differs:
- **Calendar** → `Event` (primary) · `Club` · `Trail` · `Invite a neighbor`  — "add something new"
- **Explore** → `Event` (primary) · `Club` · `Trail` · `Invite a neighbor`
- **Map** → `Pin an event` (primary) · `Add a trail` · `Add a club` · `Invite a neighbor` — same forms, place-framed

### 4. Routing (tap → destination)
- `Event/Club/Trail` → open the composer **pre-scoped to that kind**, skipping `AddView`'s chooser step. `AddView`/`AddModel` gain an optional `initialKind` so the FAB jumps straight into `AddFormView`. The old chooser sheet stays for any caller that doesn't pass a kind.
- `Invite a neighbor` → `ShareCenter.shared.present(.appInvite())` (the existing app-invite reveal).
- Map's `Pin an event` opens the event form (admins may still prefer `QuickAddSheet`; keep admin path as-is for now).

## Final implementation (as built)

`ComposeSpeedDial` (`Features/Components/ComposeSpeedDial.swift`), hosted in `MainTabsView`:
- **Backdrop:** `Hue.canvas` veil `→0.92`; the tab content scales `→0.97` (host, `speedDialOpen`). Tab bar stays put, dimmed by the veil.
- **Disc morph:** the "+" glyph `rotationEffect 0°→135°`. Explore/Calendar = coral 54pt disc (owned by the overlay, replacing `ComposeFAB`). Map = the native 44pt white chrome "+" stays as the tap target; the overlay draws the chrome ✕ (fades + rotates in) only while open. The disc is always in the tree (rotation persists) with `opacity`/`allowsHitTesting` gated so the Map's native "+" takes the closed-state tap.
- **Bubble cascade (added):** each item `opacity 0→1`, `scale 0.25→1` (anchor = the FAB corner), small rise, `spring(response 0.34, damping 0.52)`, **~85ms apart, nearest-the-disc first** — tuned up from 45ms so each bubble is a distinct beat (user: "make the cascade more obvious"). Bottom-anchored → last item nearest; top-anchored → first item nearest.
- **Press-in (added):** every bubble uses `PressableStyle(scale: 0.90, haptic: true)`.
- **Close:** `spring(response 0.26, damping 0.92)` snap, no per-item delay; ✕→+.
- **Reduce Motion:** cross-fade, no scale/stagger.

Per-surface (all reuse `AddKind` event/club/trail + Invite):
- **Calendar / Explore** → `Invite · Trail · Club · Event` (Event primary, nearest the bottom FAB). Tap → `AddFormView(kind:)` direct, or `ShareCenter.present(.appInvite())`.
- **Map** → `Event · Trail · Club · Invite` (Event primary, nearest the top "+"). Non-admin "+" opens the dial (`SJMapView.onCompose`); **admins keep `QuickAddSheet`** unchanged.

DEBUG: `-open-speeddial` (+ `-speeddial-loop`) unfolds/loops the dial headlessly; pair with `-open-tab activities|calendar|map` (and `-force-nonadmin` on the map).

## Verification plan

Same discipline as `MAP_BUILD_LOG.md` / the share-reveal + town-menu specs:
- **Build clean, 0 warnings.**
- **Motion match:** DEBUG launch arg to auto-open the speed-dial headlessly (like `-open-menu`), record the sim, extract frames (AVAssetImageGenerator), build a **REF vs HYG** two-row montage at matching progress, iterate to ~99%.
- **Render:** items/labels/circles correct at rest and fully open on Explore, Calendar, Map; no layout breakage; tab bar dims correctly.
- **Routing:** each bubble opens the right form / invite; back-out closes cleanly.
- **Reduce Motion:** cross-fade path verified.
- `graphify update .` after.

## Out of scope (YAGNI)
- No new backend/create kinds (no "place" object) — Map items reuse the event/trail/club forms.
- Home keeps its town-menu genie (already a corner reveal); not converted to a speed-dial.
- Close stays a fast snap; no elaborate reverse-stagger (matches the reference).

## Addendum (2026-07-13) — all three surfaces anchor TOP-RIGHT

Follow-up from the user: the Map's top-right "+" (drops DOWN) "is in a good spot," but
Explore/Calendar's bottom-right "+" should move to the top too — "same animation
practically just from a different spot." So the bottom-anchored coral FAB is retired;
**every surface now anchors the "+" top-right and drops the dial DOWN**, nearest-item
first (Event · Club · Trail · Invite), identical motion across tabs.

- `ComposeSpeedDial` no longer branches order by surface — one `droppingFromTop()` set
  feeds `calendar()` / `explore()` / `map()` (Event primary, directly under the "+").
- Coral disc is **48pt** at the top-right corner (was a standalone 54 at the bottom);
  Map keeps its 44pt white chrome "+". `discEdge`/`discTrailing`/`discSize` now key off
  `isTop`, not `chromeDisc`.
- The overlay `ZStack` gets an explicit full-screen `.frame(…, alignment: zAlignment)`
  so the resting disc pins to the corner even when the (open-only) wash is absent —
  previously it center-floated at rest.
- Each screen's existing top-right control **tucks LEFT** of the pinned "+" via
  `ComposeSpeedDial.topDiscHeaderClearance` (Explore's search, Calendar's info),
  forming a tidy cluster that mirrors the map's `filter · pill · +`.
- Verified in-sim: rest + open on Explore/Calendar/Map (no Map regression).
