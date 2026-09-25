# Product

## Register

product

## Users

Residents of the real town of **St. Joseph, Minnesota** — neighbors of every age, not power users. They open the app in ordinary moments: over morning coffee, deciding whether to walk to the trailhead, checking what's on downtown tonight, adding the church rummage sale to the shared calendar. Context is casual, one-handed, often outdoors, frequently glanced-at rather than studied. The job to be done is simple: *"What's happening in town, and is any of it for me today?"*

## Product Purpose

One calm place for everything happening in St. Joseph: a daily timeline (Today), a shared calendar anyone can add to, a live town map, and a daily quest. It exists to make a small town feel legible and connected without the noise of a social network. Success is a neighbor opening it, seeing something real and local, and stepping out the door — not time-on-app, not streaks, not a feed to scroll forever.

This is the **native SwiftUI + Mapbox iOS port** of an Expo/React-Native twin app; the two share one Supabase backend and must keep design tokens and query semantics in sync.

## Brand Personality

Warm, calm, quiet, neighborly, hyper-local. **The voice is a neighbor, not a brand** — plain, honest, unhurried. Three words: *warm, honest, unhurried.* The interface should evoke the feeling of a well-kept community bulletin board in a coffee shop, not a product dashboard. One meaning-scoped accent carries the few things that matter (live, tappable); everything else recedes into calm white and charcoal. **The accent's actual value lives in `docs/rules/design.md`, not here** — the coral this file used to name was retired.

## Anti-references

- **No engagement bait.** No badges, streaks, points, leaderboards, or notification-spam. The "roll call" was explicitly conceived as *the anti-streak*.
- **No infinite feed dopamine loop.** Where a social feed exists (the Today remake), it is deliberate and calm, not endless-scroll optimized.
- **No fabricated or inflated numbers — ever.** Real data only. An empty state reads "0", never a seeded or demo count. Reads are filtered to real, submitted content.
- **Not a "brand."** No marketing gloss, no mascots or AI-drawn artwork as final art, no hero-metric SaaS template, no gradient-text shouting.
- **Not gamified wellness.** The daily almanac is the "health" pillar rendered as *place* (real sun + weather → one honest nudge), never a fake goal ring or step count.

## Design Principles

1. **Real data only.** Never seed, inflate, or invent a count. If it isn't true, it isn't shown.
2. **Live-glow is for *now*, not "today".** The accent pulse is reserved for events actually happening (`start ≤ now ≤ start + 2h`). The accent is for live + tappable, nothing decorative.
3. **Weight carries hierarchy.** The UI is the platform system font everywhere (one custom face: the logo). Size and weight do the work; numbers stay tabular.
4. **Warm restraint.** One soft shadow, hairline borders, generous calm spacing. Quiet by default so the few accent moments land.
5. **Backend-twin parity.** Behavior, tokens, and query semantics track the Expo/RN twin and `@hygge/core` 1:1; divergence is a bug, not a feature.

## Accessibility & Inclusion

Target **WCAG AA** for text contrast (the charcoal `ink` ramp is verified on white/paper surfaces; keep body text at `ink`/`ink2`, never lighter for "elegance"). First-class support for:

- **Dynamic Type** — an all-ages town app; UI text should scale with the system font-size setting (the logo is the one intentional fixed-size exception).
- **VoiceOver** — interactive elements (event rows, buttons, map pins/sheet) carry meaningful labels.
- **Reduce Motion** — honor the system setting for the spring-reveal cascades; degrade to a crossfade or instant appearance (the ShareCenter reveal already models this).
- **High-contrast legibility** — the accent-on-white system must stay readable in bright outdoor light; contrast is a hard requirement, not a preference.

## The Town feed — intended shape

**Intent, not current state.** The 2026-09-17 strip-down deleted every module below;
`docs/GUTTING-LEDGER.md` says how to get each one back and `docs/rules/architecture.md`
describes the empty shell that remains. Build to this section when a module returns.

- The feed **hard-stops at "all caught up" for the day**. That stop is the point; do not add
  infinite scroll behind it.
- The coloured utility tile row (weather, garbage, road) is removed. It stole attention.
- The almanac card stays at the top, but it must be tailored to the user's RSVP'd events and
  feel alive. It was too static and kept recommending the Lake Wobegon Trail.
- News: five stories. Tapping the card opens a summary; a separate tap opens the exact source
  story. **The focused reader is the signature interaction** — the card grows out of its own
  position, backdrop dims and blurs, card sits vertically centred, swipe sideways between
  stories, drag down to dismiss.
- Module 4 is not "this or that". It surfaces new postings matching the categories a user
  signed up for and has not joined yet.
- **"Your day" shows strictly today's events.** A future RSVP appearing there is a bug.
- The "Your day" horizon card is a sky above a horizon line that doubles as the timeline
  baseline; all text sits below the line. The ground below is a flat fill that shifts with
  time of day and flips at sunset — **never** the sky gradient. The rail is solar-anchored:
  exact sunrise to exact sunset, no rounding, so its width changes with the season.
- Civic content lives in its own tab, not in the feed. No time-of-day reordering.
- The feed must be genuinely useful and habit-forming **without being manipulative**.
