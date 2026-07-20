# Design

Visual system for Block Party, captured from `BlockParty/Theme/` (`BlockPartyColor.swift`, `BlockPartyFont.swift`, `BlockPartyMetrics.swift`) and the shipped screens. Source of truth is the Swift tokens; this document mirrors them for design work. When they drift, the code wins — update this file.

## Theme

**Ink on paper, monochrome (July 2026 rebrand).** White cards lift off a warm near-white page; near-black ink carries text, buttons, active states and pins. **There is no accent colour** — photographs carry all the colour in the app, and that contrast against monochrome chrome is the point of the system. The earlier coral accent, the warm-linen surfaces, and the green buttons are all retired; do not reintroduce any of them. Warmth comes from the paper tone and the copy.

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
`Features/Map/BasemapPalette.swift`, whose grayscale cartography ramp (land `#FAFAF7`,
parks `#EFEFEC`, water `#E4E4E0`, building `#F1F1EF`, roads `#FFFFFF`) must stay
separable by value now that hue is gone.

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

## Bans (this project)

- No accent colour of any kind. No coral, no cream/linen/sand body background, no green primary button — all retired.
- No pill-shaped buttons; buttons are rounded squares at `Radius.button`.
- No fabricated counts or seeded demo data in any surface.
- No AI-drawn mascots/illustrations as final art (real photos or vector UI only).
- No decorative gradient text, no side-stripe accent borders, no nested cards.
