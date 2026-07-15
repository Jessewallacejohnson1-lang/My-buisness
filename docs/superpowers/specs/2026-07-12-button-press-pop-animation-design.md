# Button press "pop" animation — design

**Date:** 2026-07-12
**Status:** approved, building
**Trigger:** "when you press [buttons], make it have a little animation that is being clicked on" — the share button especially.

## Problem

`PressableStyle` (the app's shared press `ButtonStyle`, `Features/Components/ExploreKit.swift`) scales a button down *only while the finger is held*. On a quick tap the finger is down for a fraction of a second, so the scale barely registers — a fast tap reads as flat/unresponsive. Separately, ~40 buttons use `.buttonStyle(.plain)` and have **no** press feedback at all, including the `InviteButton` share button and the compose **+** FAB.

## Decisions (locked with the user)

1. **Feel:** a satisfying *pop* — press in, then spring back with a small overshoot — plus a light haptic. Must play on a fast tap.
2. **Scope:** app-wide.
3. **Haptic reach:** only button-like controls (share buttons, **+** FAB, chips, icon buttons). Content rows/cards get the visual pop only, no haptic.

## Design

### 1. Upgrade `PressableStyle` in place
- **Motion:** on the press-**down** edge, a `keyframeAnimator` plays a one-shot timeline start-to-finish — scale `1 → scale` (~0.09s ease) then a springy `→ 1` with a tiny overshoot. Because it's keyed to a per-press trigger counter (not to how long `isPressed` stays true), it plays fully even on a fast tap. This is the fix.
- **Haptic:** new `haptic: Bool = false` parameter. When true, `Haptics.light()` fires on press-down. Default off so content rows/cards stay silent; opted-in only on button-like controls.
- **Reduce Motion:** no scale (down target held at 1); haptic still fires. Matches the app's motion conventions.
- Keeps the existing `scale` parameter, so every call site's tuned value (0.9 icon circles, 0.94–0.98 rows/cards) is preserved unchanged.

### 2. Adopt on `.plain` holdouts that are real controls
Convert discrete tappable controls with no bespoke motion — starting with the `InviteButton` share button and the `ComposeFAB` (drop its now-redundant inline `Haptics.light()`), plus other clear action/icon buttons. Pass `haptic: true` on button-like ones.

**Skip** (bespoke motion — would double-animate): the `InlineAction` idle/phase button, animated map pins in `SJMapView`, and content that is not a button (text fields, non-interactive tiles). Onboarding-only styles (`PressableCardStyle`, `WhitePillButtonStyle`) and `CoralPillStyle` keep their own press feedback; left as-is except where a light haptic is clearly warranted on a primary action.

## Final implementation

`PressableStyle` (in `Features/Components/ExploreKit.swift`) is now a nested `Pop` view driven by a per-press counter:
- `.onChange(of: isPressed)` bumps `taps` on the press-**down** edge (and fires `Haptics.light()` when `haptic: true`).
- `.keyframeAnimator(trigger: taps)` plays a 3-phase timeline every press: **press in → `scale`** (0.10s) → **overshoot → 1.05** (0.13s) → **settle → 1.0** (spring, bounce 0.26). Because it's keyed to the down edge, it plays fully even on a fast tap.
- The explicit **overshoot above 1.0** is essential: a shallow press-in (e.g. 0.97 ≈ 1px) is invisible on its own; the bounce past 100% is what actually reads as a "click".
- Reduce Motion flattens the track (no scale); the haptic still fires.

Call-site changes: `haptic: true` added only to button-like controls that lacked a haptic (share-sheet **X**, Login primary). Converted `.plain` holdouts → `PressableStyle`: Masthead **+** (`haptic: true`), Compose **+** FAB, Explore search-clear. Left alone: share buttons (already self-haptic via `ShareCenter.present()`), the `InlineAction` phase button, animated map pins, and the dead `InviteButton`.

## Verification findings

- **Build:** clean, 0 warnings.
- **Render:** all buttons render correctly at rest (Home, Explore, Profile, share reveal). No layout breakage.
- **Share flow:** real tap on the event share circle → reveal springs up (captured via frame montage).
- **Pop rendering — CONFIRMED.** Could not drive a *rendered* button press via computer-use: `mouse_down` on the Simulator does **not** hold a touch (`isPressed` stays false during a host-side hold — proven by a declarative `scaleEffect(isPressed ? 0.6 : 1)` showing full size mid-hold; the click is delivered atomically on release). Verified the keyframe **render path** instead by temporarily swapping to `keyframeAnimator(repeating: true)` and recording hands-off — the **+** visibly cycles press-in → overshoot → settle. On a real finger tap `isPressed` renders true (that's how all pressed feedback works), so `onChange` fires and this animation plays. See the frame-montage note in memory.

Then `graphify update .` (done).
