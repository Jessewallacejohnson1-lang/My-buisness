---
name: block-party-brand
description: Use when building, restyling, or reviewing ANY UI in the Block Party iOS app (formerly Hygge). Encodes the ink-on-paper design tokens, type scale, radii, glyph rules, and copy voice so every agent and session stays on-brand. Invoke before writing SwiftUI views, adding colors, or writing user-facing strings.
---

# Block Party — brand system

Block Party is a neighborhood app for St. Joseph, MN. The visual system is
**monochrome ink on warm paper**. Photos carry all the color. Nothing else does.

If you are about to add a color, the answer is almost certainly `ink`,
`inkSecondary`, `hairline`, or `fill`. There is **no accent color**.

## Tokens — single source of truth

Defined in `BlockParty/Theme/BlockPartyColor.swift`. Never hardcode these values
at a call site; always reference the token.

| Token | Hex | Use |
|---|---|---|
| `ink` | `#111111` | Primary text, buttons, FABs, active states, pins, today-marker |
| `paper` | `#FAFAF7` | App background. Warm white — matches the app icon |
| `surface` | `#FFFFFF` | Cards sitting on paper |
| `inkSecondary` | `#6E6E6E` | Secondary text, captions, inactive tab items |
| `hairline` | `#E7E7E4` | 1px borders, dividers, card outlines |
| `fill` | `#F1F1EF` | Inert fills: photo-less placeholders, skeletons, disabled |

**Accent: one, pending.** The shipped rebrand (commits through `54806ff`) is pure
monochrome — that was the original brief. Jesse has since decided to add **one
accent colour, hue not yet chosen**, used ONLY where it carries meaning:

> live events · active filters · selected state · saved pins · primary CTAs

Everything else stays ink on paper. The accent is never decoration, never a
background wash, never applied to body copy, cards, or category glyphs. It must
not be the retired coral `#FF6B57`.

Until that hue is chosen, build monochrome. If a design seems to need colour
somewhere outside that list, it needs hierarchy instead — weight, size, value,
or fill-vs-outline.

### Banned
- Coral `#FF6B57` and the whole legacy `moss`/`honey`/`clay`/`sky` ramp
- Any orange, blue, red, or green as UI chrome
- `.accentColor`, `Color.accentColor`, `.orange`, `.red`, `.blue`, `.green`
- Raw hex at a call site. Add a token instead, or use an existing one.

There are exactly **two** legitimate exceptions, and both are CONTENT rather than
chrome:
1. **Photography** — user and venue photos keep their natural colour, unfiltered.
2. **The map basemap** — parks are green and water is blue, because a town map's
   landmarks are how you orient. See Map-specific below.

That contrast — colourful content inside monochrome chrome — is the entire point
of the system. It is not a licence to colour anything else.

## Type

- **Display — Jost.** Wordmark and headlines only. Bundled with the app.
- **Body / UI — SF Pro.** Everything else: labels, buttons, captions, body copy.

Do not introduce a third family. Do not use Jost for body copy — it is a display
face and gets illegible at small sizes.

Emphasis inside a sentence is **bold ink**, never a color change.

## Radii

| Element | Radius |
|---|---|
| Buttons | `12` — rounded square. **Never a pill/Capsule.** |
| Cards | `20` |
| Tiles | `16` |

One shadow token only, low opacity. Prefer a `hairline` border over a shadow
when separating a surface from paper; reach for shadow only when something
genuinely floats (FAB, sheet).

## Glyphs & marks

- Square-framed marks, not circles, wherever there's a choice.
- The block glyph is the brand mark — it replaces decorative iconography
  (notably the old coffee cup on the brief card).
- Map pins and clusters are `ink` with white content. Category *glyphs* stay and
  keep their family/data model; only their color collapses to ink.
- Photo-less states use a `fill`-gray placeholder with a square-frame mark —
  never an emoji, never a colored illustration.

## Voice

Warm neighbor with block-party energy. Short sentences. Plain words.

- Greeting pattern: **"Evening on the block, Jesse."** (time-of-day + "on the
  block" + first name)
- Write like you're talking to someone you actually know from the street.
- **No cozy-Danish references anywhere** — no "hygge", no candles, no
  blankets/wool/fireplace imagery. That brand is retired.
- Don't over-exclaim. Warmth comes from specificity, not punctuation.

Good: "Three things happening today." / "Nobody's signed up yet — be first."
Bad: "Cozy up with today's events!" / "Your hygge awaits ✨"

## Hard rules

1. **Reskin ≠ rebuild.** Changing brand appearance must never change layout,
   information architecture, navigation, or behavior.
2. **Never change** the bundle identifier `Jesse.Hygge`, the keychain account
   `hygge.session`, the `hygge.*` UserDefaults keys, or the
   `realtime:hygge-*` topic. These are persisted/wire-level identifiers —
   renaming them logs users out or breaks the App Store listing. See
   `DECISIONS.md` in the repo.
3. `supabase/migrations/*` is applied history. Never edit retroactively.
4. New color needed? Add a token to `BlockPartyColor.swift`. Do not inline it.

## Strategy source

`docs/playbook.md` in the repo ("Steal This") is the competitive playbook behind
these decisions — Partiful/Linear/Notion for the visual system, Front Porch
Forum/Nextdoor for community mechanics, Instagram/Airbnb/Twitter for rebrand
execution. Read it before design or launch-strategy work; it explains *why* the
system is monochrome, why buttons are squares not pills, and why empty states
are treated as onboarding.

**Where it conflicts with this file, this file wins.** One live conflict: the
playbook recommends a 3-state status palette (green/amber/red for
Going/Interested/Can't), which the Banned list above rules out. That is an open
decision for Jesse, not a licence to ship colored status chips.

## Map-specific

The migration is DONE: `POILayer.swift` (Mapbox symbol layers) is retired, and
POI rendering is SwiftUI view annotations (`POICluster`, `POIMarkers`,
`SJMapView+POIClustering`), merged from `feat/map-poi-markers`.

**The basemap is COLOURFUL, and that is deliberate — it is the one exception to
the monochrome rule, alongside photography.** The map is *content*, not chrome:
it is a picture of the town, so its natural features keep real colour.

- **Basemap:** `mapbox/light-v11` recoloured once on style load via
  `BasemapPalette.recolor(_:)` — parks `#D9E8C8` (sage), water `#A8D8EE` (soft
  sky). Land takes `Hue.paper` and buildings/roads take `Hue.fill`/`Hue.surface`,
  so colour is spent ONLY on the natural features that carry meaning.
- **Do not make the basemap grayscale.** It was, briefly, and it failed: land,
  parks and water sat within ~6% luminance, so the river and the parks became
  indistinguishable grey shapes on the one screen whose background IS the
  content. Reverted deliberately.
- **Markers stay monochrome** and route through `MonoMarkerPalette`, a role table
  (POI / cluster / civic / live) encoding importance as a VALUE ladder — POI
  lightest, civic darkest — plus shape and motion. Never add hue at a marker
  call site; change the role table.
- Live = a **static ink ring** plus the pulse. The ring is what survives Reduce
  Motion and selection, where the pulse is suppressed or invisible.
- Controls: `Hue.surface` with `hairline` borders; active inverts to ink fill.
