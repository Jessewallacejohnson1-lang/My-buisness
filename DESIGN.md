# Design

Visual system for Block Party, captured from `BlockParty/Theme/` (`BlockPartyColor.swift`, `BlockPartyFont.swift`, `BlockPartyMetrics.swift`) and the shipped screens. Source of truth is the Swift tokens; this document mirrors them for design work. When they drift, the code wins — update this file.

## Working mode

Screens here get built in passes, with Jesse directing. A UI request is a step in that direction, not a brief for a finished screen.

- **Build what was asked, at the scope it was asked.** Do not extend a request into a complete, polished design because the current state looks unfinished.
- **Loose ends are intentional.** A placeholder, a stubbed action, a half-wired state, or a screen with one working path is often the deliberate stopping point — "we'll make it work later" is a real plan, not an oversight to repair.
- **Improving the process is welcome; improving the design past the ask is not.** Cleaner structure, reused tokens, fewer files, a faster path to seeing it on device — all good. Inventing layout, states, or polish that was not requested is not.
- **When the instruction and "what a finished screen would need" disagree, follow the instruction.** Name the gap in a line, then stop. Unrequested UI is UI that gets deleted and remade.

## Colour direction (Jesse, 2026-09-18)

**Two colours define the app: white, and the logo's yellow.**

1. **White is the ground.** `Hue.surface` #FFFFFF for cards, `Hue.paper` #FAFAF7 for
   the page. The app reads as white; everything else sits on it.
2. **Yellow is the accent, and it is the app icon's yellow — `#F2B800`.** Sampled from
   the painted 1024 master (`docs/brand/source-logo-1024.png`), the modal value across
   the broadcast arcs. It lives in `BlockPartyColor.swift` as `Hue.brandYellowHex`, and
   **every yellow in the UI derives from it.** There is no second yellow, and no yellow
   hex at a call site.

**Accents are small by rule.** Today the yellow marks exactly one control: the Today
bar's map disc (`Hue.mapWash` — the brand yellow at 68%, the same hue carried at
partial opacity so the disc stays translucent over what is behind it). It is not a
background wash, not body copy, not a card, not a category colour. More yellow is
Jesse's call to scope, not an agent's to spread.

The plum `Hue.accent` (#8E3B6B) still ships where it already carries meaning — live
events, active filters, selected/saved map state — and stays until Jesse says
otherwise. The brand accent going forward is the yellow.

## Theme

**Ink on paper (July 2026 rebrand), now white-and-yellow at the top level.** White cards lift off a warm near-white page; near-black ink carries text, buttons, active states and pins. **The only accent is the brand yellow, scoped small** (see Colour direction above) — photographs otherwise carry all the colour in the app, and that contrast against near-monochrome chrome is the point of the system. The earlier coral accent, the warm-linen surfaces, and the green buttons are all retired; do not reintroduce any of them. Warmth comes from the paper tone and the copy.

If a design seems to need an accent, it needs hierarchy instead — weight, size, value, or fill-vs-outline.

Mood: a calm community bulletin board in daylight. Light mode only today.

## Color

All values are sRGB hex from `Hue` (`BlockPartyColor.swift`). Six tokens, and nothing else.

| Token | Hex | Role |
|---|---|---|
| `Hue.ink` | `#111111` | Primary text, buttons, FABs, active states, pins |
| `Hue.paper` | `#FAFAF7` | App page background (warm white — matches the icon) |
| `Hue.surface` | `#FFFFFF` | Cards |
| `Hue.inkSecondary` | `#6E6E6E` | Secondary text, captions, inactive states |
| `Hue.hairline` | `#E7E7E4` | Borders, dividers |
| `Hue.fill` | `#F1F1EF` | Inert fills — placeholders, skeletons, disabled |
| `Hue.brandYellowHex` | `#F2B800` | **The accent**, sampled from the app icon's arcs. Tints derive from it |
| `Hue.mapWash` | `#F2B800` @ 68% | The Today bar's map disc — the one accent surface today |

> Note the surface/page swap in the rebrand: `Hue.paper` used to mean "white card" and
> `Hue.canvas` meant "page background". `Hue.paper` **is** the page background now, and
> cards are `Hue.surface`. Deleted entirely: `accent`, `accentPressed`, `accentSoft`, the
> `moss`/`sky`/`honey`/`clay` ramps, `paper100/200/300`, `canvas`, `ink2`, `ink3`, `gray`,
> `grayLight`, `bgSubtle`, `mapInk`, `mapHairline`.

**Contrast:** `ink` passes AA everywhere. `inkSecondary` measures 4.88:1 on `paper`,
5.10:1 on `surface`, and **4.51:1 on `fill`** — passing with no margin, so do not add
opacity to secondary text over a filled surface.

**Emphasis is weight, never colour.** Where a state used to be carried by hue it is now
carried by value, weight, shape, or filled-vs-outlined — e.g. calendar days with
happenings are `ink` and empty days `inkSecondary`; `InlineAction` success is filled ink
and error is outlined; live map pins carry a static ring.

**Allowed raw hexes** — only two files: `BlockPartyColor.swift` itself, and
`Features/Map/BasemapPalette.swift`, whose cartography ramp is **deliberately
colourful** (see Map below). The basemap is the one place in the app where hue
survives the monochrome system, because the map is content rather than chrome.

## Typography

**Two faces: Jost for display, SF Pro for everything else.** Helpers live in `BlockPartyFont.swift`:

| Helper | Maps to | Use |
|---|---|---|
| `Font.display(_)` | **Jost** `JostRoman-Bold` | Wordmark, display, headings |
| `Font.displaySemi(_)` | **Jost** `JostRoman-SemiBold` | Section titles (e.g. "Today", 22pt) |
| `Font.sans(_)` | system regular | Body |
| `Font.sansMedium/Semibold/Bold(_)` | system medium/semibold/bold | UI emphasis |
| `Font.mono(_)` / `Font.monoMedium(_)` | system regular/medium | Data — **pair with `.monospacedDigit()`** for tabular figures |

- **Numbers are always tabular** (`.monospacedDigit()` at the call site). This is a house rule — times, temps, counts.
- Small labels/eyebrows use `Font.mono(11)` with `.tracking(1.5)` in `Hue.inkSecondary` (e.g. `ALMANAC`, `TODAY IN ST. JOE`). This tracked-mono micro-label is an established in-app pattern, not the banned generic eyebrow.
- **Jost is a variable font and its PostScript names are inconsistent upstream** — `Jost-Regular`, but `JostRoman-Medium` / `JostRoman-SemiBold` / `JostRoman-Bold`. Use them exactly; a wrong name falls back to the system font **silently**, with no error.
- `Font.logo` is `JostRoman-SemiBold`. Fixed size — a logo never scales with Dynamic Type. `AtkinsonHyperlegible-Bold.ttf` is still bundled but no longer referenced.
- Do not add a third family.

## Layout, radii & elevation

From `BlockPartyMetrics.swift`.

- **Radius scale — three tokens:** `Radius.button 12` (buttons — a **rounded square, never a pill**), `Radius.tile 16`, `Radius.card 20`. Always `.continuous`. The old `sm/md/lg/xl` scale is gone.
- **One elevation:** `CardShadow` = black @ 6%, radius 10, y 4 — neutral, replacing the old warm-brown hex. Prefer a `hairline` border over a shadow; reach for shadow only when something genuinely floats (FAB, sheet).
- **`blockPartyCard(radius:padding:)`** — the house card: `surface` fill, hairline border, `card` radius, the one shadow. Default padding 16.
- **`blockPartyHairline(radius:)`** — bordered surface, no shadow (chips, inputs, flat tiles).
- **Map shadows:** `mapFloatShadow` (y2, blur10, 10%) and `mapSheetShadow` (y−2 upward, blur16, 8%) — softer/diffuse, no hard edges.
- **Spacing:** Home stack uses ~18pt section spacing and 18pt horizontal insets; vary rhythm rather than one uniform gap. Cards are used deliberately; **never nest cards**.

## Motion

- **Staggered spring reveal** (`.springReveal(index, revealed:animated:)`) — the signature entrance: sections cascade in on appear / after pull-to-refresh. Springy, warm, staggered by index.
- **Ease-out, no bounce/elastic** for transitions.
- **Reduce Motion is mandatory:** every reveal/animation must degrade to a crossfade or instant appearance under the system setting (the ShareCenter reveal is the reference implementation). Reveals enhance already-visible content — never gate visibility on an animation that won't fire in a headless render.

## Iconography

SF Symbols, small and quiet (`.font(.system(size: 12–13, weight: .medium))`), always `Hue.ink` or `Hue.inkSecondary` — **meaning is carried by the glyph, not by a tint.** Category, POI family, and pin type all read by glyph now. Square-framed marks are preferred where there's a choice, and the block mark (`building.2.fill`) is the brand glyph; it replaces decorative lifestyle iconography. Photo-less states use a `fill` placeholder with a square-frame mark — never an emoji, never a coloured illustration.

## Logo & app icon

The icon is **the wave figure** (Aug 25, 2026 revision): a painted black figure,
arms raised, inside three concentric yellow broadcast arcs on warm paper. It ships
1:1 from `docs/brand/source-logo-1024.png` — the painted render exactly, brushstroke
texture and all, never redrawn, flattened or reinterpreted as a vector. The earlier
coral "bp" tile render is retired, and with it the tile-crop pipeline in
`scripts/brand/tile.swift` / `exact.swift`, which does not apply to full-bleed art.

The icon is brand **content**, like photography and the basemap — not UI chrome. The
in-app world stays ink on paper; the icon is the glossy front door.

- Assets in `BlockParty/Assets.xcassets`: `AppIcon` (1024, full-bleed, no alpha),
  `LaunchMark` (the same art inset 36/1024 on every side — a 72 inset clips the
  artwork, whose top edge sits 40px from the frame), and `MarkTemplate` (per-pixel
  alpha, so antialiased edges survive tinted renderings).
- `LoaderBlockPartyMark.contentFraction` (0.9727) is the one number that moves when
  the icon is re-exported; the squircle clip is the iOS corner ratio, so the loader
  mark reads as the icon does on the home screen.
- **The paper ground stays on the loader mark.** The loader shows the actual icon,
  background and all. Do not cut the figure out of its paper — decided, not an
  oversight.
- The wordmark ("Block Party" in Jost) is the in-app brand face —
  `BlockPartyLogoBadge`, splash, loading covers.

## Voice

Warm neighbour with block-party energy. Short sentences, plain words, written like
you're talking to someone you actually know from the street.

- The house phrase is **"on the block"** — "Everything happening on the block.",
  "Quiet on the block". Time-of-day plus first name is the greeting register.
- **No cozy-Danish references anywhere** — no "hygge", no candles, no
  blankets/wool/fireplace imagery. That brand is retired.
- Don't over-exclaim. Warmth comes from specificity, not punctuation.

Good: "Three things happening today." / "Nobody's signed up yet — be first."
Bad: "Cozy up with today's events!" / "Your hygge awaits ✨"

## Map

**The basemap is colourful, and that is deliberate** — the one exception to the
monochrome rule alongside photography. The map is a picture of the town, so its
natural features keep real colour. Values live in `BasemapPalette.swift`
(`mapbox/light-v11`, recoloured once on style load via `recolor(_:)`).

- Greens carry the headline: parks `#A9D584`, pitches `#B9DB8F`, woods `#B0D291`,
  lawns `#C3DFA2`, farmland `#DFEAC5`, cemetery `#CBDCB4`. Water is `#7FBFE8`, with
  waterway strokes a shade darker (`#6FB6E2`) because thin lines render optically
  lighter. Campus, commerce and sand take warm tans.
- **Built form stays neutral and on-token:** land is `Hue.paper`, buildings
  `Hue.fill`, roads `Hue.surface`. Colour is spent only on features that carry
  meaning. `light-v11` consolidates every road class into one `road-simple` layer
  differentiated by width, not colour — there is no road hierarchy to style.
- **Do not make the basemap grayscale.** It was, briefly, and it failed: land, parks
  and water sat within ~6% luminance, so the river and the parks became
  indistinguishable grey shapes on the one screen whose background *is* the content.
  Reverted deliberately.
- **Markers stay monochrome** and route through `MonoMarkerPalette`, a role table
  (POI / cluster / civic / live) encoding importance as a value ladder — POI
  lightest, civic darkest — plus shape and motion. Never add hue at a marker call
  site; change the role table.
- POI rendering is SwiftUI view annotations (`POICluster`, `POIMarkers`,
  `SJMapView+POIClustering`). The Mapbox symbol-layer `POILayer` is retired.
- Live is a **static ink ring** plus the pulse. The ring is what survives Reduce
  Motion and selection, where the pulse is suppressed or invisible.
- Map controls are `Hue.surface` with hairline borders; active inverts to ink fill.

## Strategy source

`docs/playbook.md` ("Steal This") is the competitive playbook behind these
decisions — Partiful/Linear/Notion for the visual system, Front Porch
Forum/Nextdoor for community mechanics, Instagram/Airbnb/Twitter for rebrand
execution. It explains *why* the system is monochrome, why buttons are squares
rather than pills, and why empty states are treated as onboarding.

**Where the playbook conflicts with this file, this file wins.** One live conflict:
the playbook recommends a three-state status palette (green/amber/red for
Going/Interested/Can't), which the Bans below rule out. That is an open decision
for Jesse, not a licence to ship coloured status chips.

## Bans (this project)

- No accent colour of any kind. No coral, no cream/linen/sand body background, no green primary button — all retired.
- No pill-shaped buttons; buttons are rounded squares at `Radius.button`.
- No fabricated counts or seeded demo data in any surface.
- No AI-drawn mascots/illustrations as final art (real photos or vector UI only).
- No decorative gradient text, no side-stripe accent borders, no nested cards.
