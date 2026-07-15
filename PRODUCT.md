# Product

## Register

product

## Users

Residents of the real town of **St. Joseph, Minnesota** — neighbors of every age, not power users. They open the app in ordinary moments: over morning coffee, deciding whether to walk to the trailhead, checking what's on downtown tonight, adding the church rummage sale to the shared calendar. Context is casual, one-handed, often outdoors, frequently glanced-at rather than studied. The job to be done is simple: *"What's happening in town, and is any of it for me today?"*

## Product Purpose

One calm place for everything happening in St. Joseph: a daily timeline (Today), a shared calendar anyone can add to, a live town map, and a daily quest. It exists to make a small town feel legible and connected without the noise of a social network. Success is a neighbor opening it, seeing something real and local, and stepping out the door — not time-on-app, not streaks, not a feed to scroll forever.

This is the **native SwiftUI + Mapbox iOS port** of an Expo/React-Native twin app; the two share one Supabase backend and must keep design tokens and query semantics in sync.

## Brand Personality

Warm, calm, quiet, neighborly, hyper-local. **The voice is a neighbor, not a brand** — plain, honest, unhurried. Three words: *warm, honest, unhurried.* The interface should evoke the feeling of a well-kept community bulletin board in a coffee shop, not a product dashboard. Coral warmth carries the few things that matter (live, tappable); everything else recedes into calm white and charcoal.

## Anti-references

- **No engagement bait.** No badges, streaks, points, leaderboards, or notification-spam. The "roll call" was explicitly conceived as *the anti-streak*.
- **No infinite feed dopamine loop.** Where a social feed exists (the Today remake), it is deliberate and calm, not endless-scroll optimized.
- **No fabricated or inflated numbers — ever.** Real data only. An empty state reads "0", never a seeded or demo count. Reads are filtered to real, submitted content.
- **Not a "brand."** No marketing gloss, no mascots or AI-drawn artwork as final art, no hero-metric SaaS template, no gradient-text shouting.
- **Not gamified wellness.** The daily almanac is the "health" pillar rendered as *place* (real sun + weather → one honest nudge), never a fake goal ring or step count.

## Design Principles

1. **Real data only.** Never seed, inflate, or invent a count. If it isn't true, it isn't shown.
2. **Live-glow is for *now*, not "today".** Coral pulse is reserved for events actually happening (`start ≤ now ≤ start + 2h`). Coral is for live + tappable, nothing decorative.
3. **Weight carries hierarchy.** The UI is the platform system font everywhere (one custom face: the logo). Size and weight do the work; numbers stay tabular.
4. **Warm restraint.** One soft shadow, hairline borders, generous calm spacing. Quiet by default so the few warm/coral moments land.
5. **Backend-twin parity.** Behavior, tokens, and query semantics track the Expo/RN twin and `@hygge/core` 1:1; divergence is a bug, not a feature.

## Accessibility & Inclusion

Target **WCAG AA** for text contrast (the charcoal `ink` ramp is verified on white/paper surfaces; keep body text at `ink`/`ink2`, never lighter for "elegance"). First-class support for:

- **Dynamic Type** — an all-ages town app; UI text should scale with the system font-size setting (the logo is the one intentional fixed-size exception).
- **VoiceOver** — interactive elements (event rows, buttons, map pins/sheet) carry meaningful labels.
- **Reduce Motion** — honor the system setting for the spring-reveal cascades; degrade to a crossfade or instant appearance (the ShareCenter reveal already models this).
- **High-contrast legibility** — the warm coral-on-white system must stay readable in bright outdoor light; contrast is a hard requirement, not a preference.
