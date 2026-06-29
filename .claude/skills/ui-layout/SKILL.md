---
name: ui-layout
description: "Router for designing and building UI — screens, layouts, components, and styling for web and mobile. Use whenever the user wants to design or reshape an app screen, lay out a page, build or style components (shadcn/ui, Tailwind, NativeWind), pick palettes/type/spacing, design mobile flows and navigation, or match/reproduce a reference design pixel-for-pixel. Triggers: design my app, lay out this screen, build the UI, redesign, layout, component, styling, shadcn, Tailwind, mobile screen, onboarding flow, navigation, make it look like this reference."
---

# UI & Layout — Router

Everything about how the app *looks and lays out* — in-product screens, layouts,
components, and styling — routes from here. Read the matching sub-skill's
`SKILL.md`, then build.

> **House rule (from `DESIGN.md`):** Warm-white linen first, charcoal ink, color is
> semantic only (moss = positive/primary, sky = brand, honey = warmth, clay =
> warning). Calm, minimal, neighborly — never busy, never corporate. No
> badges/streaks/feed mechanics. Hold every result to the on-brand bar.

## Pick the sub-skill

| If the task is about… | Read |
|---|---|
| Aesthetic direction & taste — distinctive, intentional UI that doesn't read as templated; typography choices | `ui-layout/frontend-design/SKILL.md` |
| Broad UI/UX intelligence — styles, color palettes, font pairings, product-type patterns, UX guidelines, chart types across React/Next/Vue/Svelte/RN/Flutter/Tailwind/shadcn | `ui-layout/ui-ux-pro-max/SKILL.md` |
| Implementing components & styling — shadcn/ui (Radix + Tailwind), utility-first layout, accessible responsive components | `ui-layout/ui-styling/SKILL.md` |
| **Mobile** app screens, flows, components, onboarding, navigation, mockups | `ui-layout/mobile-app-ui-design/SKILL.md` |
| Reproducing a reference — screenshot/mockup/Figma to "make it look like this," pixel-perfect, build→screenshot→diff→fix loop | `ui-layout/match-design/SKILL.md` |

## How they fit together

1. **Direction first** → `frontend-design` (taste) and/or `ui-ux-pro-max` (palettes, type, patterns) to decide the look.
2. **Mobile screens** → `mobile-app-ui-design` for layout + flow decisions (this app's primary surface is Expo/React Native).
3. **Build it** → `ui-styling` for the actual shadcn/Tailwind/NativeWind components.
4. **Matching a given design** → `match-design` to iterate until it matches the reference exactly.

> Need a real-world reference for a single screen before designing? Use the
> `reference-finder` agent (in `.claude/agents/`).
