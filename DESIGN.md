# Design

Visual system for Block Party, captured from `BlockParty/Theme/` (`BlockPartyColor.swift`, `BlockPartyFont.swift`, `BlockPartyMetrics.swift`) and the shipped screens. Source of truth is the Swift tokens; this document mirrors them for design work. When they drift, the code wins — update this file.

## Theme

**Coral + white, "Strava-clean" (July 2026 rebrand).** Pure-white cards lift off a near-white canvas; charcoal ink for text; a single warm **coral** accent carries everything live or tappable. The older warm-linen surfaces and green buttons are retired — do not reintroduce a cream/linen body background or a green primary. Warmth now comes from the coral accent and copy, not from a tinted surface.

Mood: a calm community bulletin board in daylight. Light mode only today.

## Color

All values are sRGB hex from `Hue` (`BlockPartyColor.swift`).

### Surfaces
| Token | Hex | Role |
|---|---|---|
| `Hue.paper` / `surface` | `#FFFFFF` | Default surface — pure white cards, floating elements |
| `Hue.paper100` | `#F6F7F8` | Raised tint |
| `Hue.paper200` | `#EFF1F3` | Muted surface |
| `Hue.paper300` | `#E5E7EB` | De-emphasized / dividers |
| `Hue.canvas` / `bgSubtle` | `#F6F7F8` | App page background — white cards lift off it |

### Text — charcoal ink ramp (WCAG-verified on paper)
| Token | Hex | Role |
|---|---|---|
| `Hue.ink` | `#2A2A28` | Primary text (AAA) |
| `Hue.ink2` | `#5E5D56` | Secondary / body (AA) |
| `Hue.ink3` | `#828077` | Tertiary / placeholder |

### Accent — coral (the one job: live + tappable)
| Token | Hex | Role |
|---|---|---|
| `Hue.accent` / `moss700` | `#FF6B57` | **Primary accent** — live indicators, primary buttons, active/selected, tappable |
| `Hue.accentPressed` / `moss500` | `#E5503C` | Pressed state |
| `Hue.moss400` | `#FF8A79` | Light coral |
| `Hue.moss800` | `#C7452F` | Deepest pressed |
| `Hue.accentSoft` | `#FFF0EC` | Soft coral tint (backgrounds behind coral content) |

> Naming note: the `moss*` keys are historical (green→coral rebrand kept the key names to avoid churning ~30 call sites). They are coral now. Reach for `Hue.accent`/`accentSoft`/`accentPressed` in new code.

### Secondary hues (use sparingly, one job each)
| Token | Hex | Role |
|---|---|---|
| `Hue.sky600` | `#6B7B84` | Brand / focus / calm-day signal |
| `Hue.honey600` | `#B07D2B` | Warmth (sparingly) |
| `Hue.clay700` | `#B0573A` | Warning / error only |
| `Hue.hairline` | `black @ 7%` | Hairline borders |
| `Hue.mapInk` | `#1A1D21` | Text/icons on the map |

**Contrast rule:** body text stays at `ink`/`ink2`. Never lighten body copy toward `ink3` "for elegance." Placeholder text is the only `ink3` body use.

## Typography

**Platform system font (SF Pro) everywhere — weight carries hierarchy.** Helpers in `BlockPartyFont.swift` map straight onto `.system(size:weight:)`:

| Helper | Maps to | Use |
|---|---|---|
| `Font.display(_)` | system **bold** | Display / headings |
| `Font.displaySemi(_)` | system **semibold** | Section titles (e.g. "Today", 22pt) |
| `Font.sans(_)` | system regular | Body |
| `Font.sansMedium/Semibold/Bold(_)` | system medium/semibold/bold | UI emphasis |
| `Font.mono(_)` / `Font.monoMedium(_)` | system regular/medium | Data — **pair with `.monospacedDigit()`** for tabular figures |

- **Numbers are always tabular** (`.monospacedDigit()` at the call site). This is a house rule — times, temps, counts.
- Small labels/eyebrows use `Font.mono(11)` with `.tracking(1.5)` in `Hue.ink3` (e.g. `ALMANAC`, `TODAY IN ST. JOE`). This tracked-mono micro-label is an established in-app pattern, not the banned generic eyebrow.
- **One custom face:** `Font.logo` → **Atkinson Hyperlegible Bold**, used only by `BlockPartyLogoBadge`. Fixed size (a logo never scales with Dynamic Type). Do not reintroduce a bundled UI font (Spectral/DM Sans/Geist Mono were removed in the rebrand).

## Layout, radii & elevation

From `BlockPartyMetrics.swift`.

- **Radius scale:** `sm 8` (chips), `md 12` (inputs/buttons), `lg 16` (cards), `xl 20` (sheets/hero). Always `.continuous`.
- **One elevation:** a single soft warm lift — `CardShadow` = `#2A241C @ 10%`, radius 11, y 6. Everything else stays flat, leaning on fill + hairline border.
- **`blockPartyCard(radius:padding:)`** — the house card: white fill, hairline border, `lg` radius, the one shadow. Default padding 16.
- **`blockPartyHairline(radius:)`** — bordered surface, no shadow (chips, inputs, flat tiles).
- **Map shadows:** `mapFloatShadow` (y2, blur10, 10%) and `mapSheetShadow` (y−2 upward, blur16, 8%) — softer/diffuse, no hard edges.
- **Spacing:** Home stack uses ~18pt section spacing and 18pt horizontal insets; vary rhythm rather than one uniform gap. Cards are used deliberately; **never nest cards**.

## Motion

- **Staggered spring reveal** (`.springReveal(index, revealed:animated:)`) — the signature entrance: sections cascade in on appear / after pull-to-refresh. Springy, warm, staggered by index.
- **Ease-out, no bounce/elastic** for transitions.
- **Reduce Motion is mandatory:** every reveal/animation must degrade to a crossfade or instant appearance under the system setting (the ShareCenter reveal is the reference implementation). Reveals enhance already-visible content — never gate visibility on an animation that won't fire in a headless render.

## Iconography

SF Symbols, small and quiet (`.font(.system(size: 12–13, weight: .medium))`), tinted to signal meaning — coral (`Hue.accent`) for get-out/live days, `Hue.sky600` for calm/rest/indoor. Icons support the copy; they don't decorate.

## Bans (this project)

- No cream/linen/sand body background; no green primary button (retired in the coral rebrand).
- No fabricated counts or seeded demo data in any surface.
- No AI-drawn mascots/illustrations as final art (real photos or vector UI only).
- No decorative gradient text, no side-stripe accent borders, no nested cards.
