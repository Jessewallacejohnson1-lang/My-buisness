# Map Intro — onboarding crescendo (design)

**Date:** 2026-07-06 · **Branch:** mapbox-map-tab · **Status:** approved, ready to build

## Goal
A first-run introduction to the **Map** feature of Block Party (St. Joseph, MN). Adapts the
Life360 "Now you can create your Circle" reference ~90–95% into Block Party's coral+white
brand, with rich, alive animation. Since Block Party is a *town* map (not a family locator),
the pins are the real St. Joe venues — which also teaches the actual map UI.

## Decisions (locked with user)
- **Placement:** a new third onboarding step — Welcome → Interests → **Map intro**.
- **Porthole:** a **stylized SwiftUI** map (no Mapbox in onboarding), fully animatable.
- **Scope:** a **single rich screen**, carried by motion.
- **Field:** **solid coral** (`Hue.accent` #FF6B57), white content — echoes the splash.
- **Copy:** title "Everything in town, on one map" · button "Explore the map".

## Composition (top → bottom, mirrors the reference)
1. **Title** — centered white, 2 lines, `.display(34)`: "Everything in town, on one map".
2. **Porthole** — ~280pt light disc (`Hue.paper`, hairline rim) containing a hand-drawn
   St. Joe: muted-green park patch, thin gray downtown street grid, the **Wobegon Trail**
   as a curving dashed path. Understated so pins are the stars.
3. **5 venue pins** around/over the disc rim (Life360-style overlap), using the real map
   badge look (white circle, category SF Symbol, hairline, float shadow):
   **Downtown, Saint Ben's, Sacred Heart Chapel, Wobegon Trail, Millstream Park**.
   **Downtown is live** — coral rim/glyph/dot + the real pulse ring.
4. **Support line** — centered white, `.sans(16)`: "Trails, cafés, and gatherings across
   St. Joe — all in one place. When a pin glows coral, it's happening right now."
5. **Button** — full-width white pill, coral label "Explore the map" → `finish()`.

## Choreography (all gated by `accessibilityReduceMotion`, like PulseRing/SkeletonBar)
1. Porthole springs up from 0.8 scale + fades in.
2. Wobegon Trail path draws itself (trim 0→1).
3. Pins drop in staggered (spring from scale 0, slight settle).
4. When Downtown lands, its pulse ring begins beating.
5. Title → support → button fade-and-rise in sequence.
6. Whisper-slow breathing glow behind the disc so it's never static.
Under Reduce Motion: everything renders in its final state, no pulse/bob.

## Files
- **New** `BlockParty/Features/Onboarding/MapIntroView.swift` — self-contained; local `IntroPin`
  mirrors the real badge (no Mapbox import). Takes `onContinue: () -> Void`.
- **Edit** `BlockParty/Features/Onboarding/OnboardingView.swift` — add `.map` step; Interests
  "Continue" advances to `.map`; the map step renders `MapIntroView { finish() }`.
- **Edit** `BlockParty/App/RootView.swift` — DEBUG `-show-map-intro` launch arg (mirrors
  `-show-splash`) to render `MapIntroView` for headless screenshot verification.

## Verify
Builds clean (0 warnings) + confirmed in the simulator via screenshots (`-show-map-intro`),
per CLAUDE.md — there is no XCTest target.
