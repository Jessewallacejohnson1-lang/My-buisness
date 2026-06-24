# Hygge Design System

> Named for *hygge* (Danish, pron. "hoo-guh"): coziness, warmth, togetherness. Warm white surfaces, near-black ink, color reserved for data and meaning only.

---

## Philosophy

Hygge's UI does one thing: get out of the way of the data. The design is calm, minimal, and warm — never cold or clinical. Color is semantic, not decorative. Every hue carries a specific meaning and should never be used outside of it.

The three rules:
1. **White first.** The default surface is paper-white. Tints and cards lift from it.
2. **Color means something.** Moss = clean/positive. Honey = moderate/energy. Clay = avoid/warning. Sky = brand identity. Never use a hue just to fill space.
3. **Motion confirms, never decorates.** Animations should answer the question "did that work?" — not draw attention to themselves.

---

## Color

### Surfaces

| Token | Value | Use |
|---|---|---|
| `paper` | `#ffffff` | Base background |
| `paper-50` | `#fafaf7` | Subtle section backgrounds |
| `paper-100` | `#f4f3ee` | Cards, inputs |
| `paper-200` | `#e9e8e0` | Dividers, borders (low emphasis) |
| `paper-300` | `#d8d7cd` | Borders (medium emphasis), scrollbar |

All borders use `border-black/[0.07]` (opacity-based) so they stay proportional across tints.

### Text

| Token | Value | Use |
|---|---|---|
| `ink` | `#1d1f1c` | Primary text, headings |
| `ink-2` | `#5b6157` | Secondary text, labels |
| `ink-3` | `#9aa093` | Tertiary text, placeholders, metadata |

### Semantic Accents

These four hues are the entire accent palette. Each has one job.

#### Sky — Brand identity
A calm teal used for the wordmark, focus rings, and the fibre macro ring.

| Token | Value |
|---|---|
| `sky-400` | `#5bc0c4` |
| `sky-500` | `#2fa6ac` |
| `sky-600` | `#1d878d` |
| `sky-700` | `#14696f` *(AA contrast on white)* |
| `sky-800` | `#0e4d52` |

#### Moss — Clean / Positive / Primary action
Deep leaf green. Used for high clean-score foods, completed states, and all primary buttons.

| Token | Value |
|---|---|
| `moss-400` | `#74c98c` |
| `moss-500` | `#4aa867` |
| `moss-600` | `#318a4e` |
| `moss-700` | `#237a44` *(primary button — AA contrast)* |
| `moss-800` | `#185c33` |

#### Honey — Moderate / Energy / Carbs
Warm amber. Used for mid-range clean scores and the carbs macro ring.

| Token | Value |
|---|---|
| `honey-600` | `#c6881f` |
| `honey-700` | `#9a6713` |

#### Clay — Avoid / Warning / Fat
Terracotta. Used for low clean scores and the fat macro ring.

| Token | Value |
|---|---|
| `clay-700` | `#b1532e` |
| `clay-800` | `#8b3f22` |

### Score Tones

The `scoreTone()` helper in `ScoreRing.tsx` maps a 1–100 clean score to a color:

| Score | Token | Meaning |
|---|---|---|
| ≥ 70 | `moss-600` | Clean |
| 40–69 | `honey-600` | Moderate |
| < 40 | `clay-700` | Avoid |

---

## Typography

Three font roles, each with a strict purpose. Never swap them.

| Role | Font | Token | Use |
|---|---|---|---|
| Display | DM Serif Display | `font-display` | Wordmark, H1s, marketing hero text |
| UI | Outfit | `font-sans` | All interface labels, body copy, buttons |
| Data | Geist Mono | `font-mono` | Every number, score, calorie count, macro value — always with `tabular-nums` |

The mono rule is strict: if a value changes over time or sits next to other numbers, it's `font-mono`. This prevents layout shift and gives data a consistent feel.

---

## Components

### ScoreRing

An SVG ring that visualizes a clean score 1–100. The stroke color is driven by `scoreTone()`. Animates via `.score-draw` on mount.

Props: `score` (number), `size` (px), optional `label`.

### GrowthRings

A tri-ring dial showing daily macro progress (protein, carbs, fat). Each ring maps to a semantic color:
- Protein → `moss`
- Carbs → `honey`  
- Fat → `clay`
- Fibre → `sky`

Rings sweep in via `.ring-sweep` on data load.

### AppShell

Responsive navigation: bottom tab bar on mobile, side rail on desktop. Contains sign-out. Never put navigation logic in page components.

### Reveal

`IntersectionObserver`-based scroll entrance. Wraps any content. Adds `.reveal-pending` on mount, swaps to `.reveal-in` when the element enters the viewport. Respects `prefers-reduced-motion`.

### FoodScanner

Barcode scanning via `zxing`. On a successful scan, the viewfinder plays `.caught` (a quick squeeze). After the food is logged, a `.ping-out` ring radiates from the confirmation button.

---

## Motion

Every animation has a job. If you can't state the job in one sentence, remove the animation.

| Class | Job | Curve |
|---|---|---|
| `.rise` | Cards enter — stagger with inline `animationDelay` | `cubic-bezier(0.22, 1, 0.36, 1)` 0.55s |
| `.ring-sweep` | Macro rings fill on data load | `cubic-bezier(0.22, 1, 0.36, 1)` 1.1s |
| `.sheet-up` | Bottom sheet slides over backdrop | `cubic-bezier(0.22, 1, 0.36, 1)` 0.32s |
| `.fade-in` | Generic opacity entrance | `ease-out` 0.25s |
| `.ring-fill` | CSS-only ring for server-rendered pages | `cubic-bezier(0.22, 1, 0.36, 1)` 1.3s, 0.3s delay |
| `.press` | Tactile dip on tap — every tappable element | `cubic-bezier(0.22, 1, 0.36, 1)` 0.12s |
| `.pop` | Checkmarks, "Added" confirmations | Spring `cubic-bezier(0.34, 1.56, 0.64, 1)` 0.34s |
| `.bounce-in` | Completion banners | Spring `cubic-bezier(0.34, 1.56, 0.64, 1)` 0.42s |
| `.flicker` | Streak flame — loops while streak is live | `ease-in-out` 2.4s infinite |
| `.score-draw` | Small score rings draw in | `cubic-bezier(0.22, 1, 0.36, 1)` 0.7s |
| `.caught` | Viewfinder squeeze on barcode lock | `ease-out` 0.3s |
| `.ping-out` | Success glow radiates from logged item | `cubic-bezier(0, 0, 0.2, 1)` 0.6s |
| `.lift` | Marketing cards rise on hover | `cubic-bezier(0.22, 1, 0.36, 1)` 0.35s |
| `.marquee-track` | Food-score ticker | `linear` 42s infinite, pauses on hover |

All animations are disabled under `prefers-reduced-motion`. The `.rise` class additionally resets to `opacity: 1` so content stays visible without animating.

---

## Texture

### Paper Grain

The `.grain` class applies a subtle SVG noise texture as a `::before` pseudo-element fixed to the viewport at `opacity: 0.035`. Used on marketing/landing surfaces only — not in the logged-in app. It gives warmth without weight.

### Hairline Borders

Use `border-black/[0.07]` everywhere. Opacity-based borders adapt naturally to any surface tint without needing a separate border color per surface.

---

## Layout

### Navigation

- **Mobile**: Bottom tab bar (4 tabs), always visible
- **Desktop**: Side rail, collapsible

### Data Density

Logged-in views are dense by design. Users are logging food mid-meal — every interaction should complete in under 3 taps. Keep form fields short, confirmations instant, and never require a page navigation to log something.

### Marketing vs. App

The landing page (`/`) uses `.grain`, `.lift`, `.marquee-track`, and `font-display` headings freely. The logged-in app is calmer — `font-display` only appears in the wordmark.

---

## Accessibility

- Focus ring: `2px solid sky-600`, `outline-offset: 2px`, `border-radius: 2px` — always visible, never hidden
- All semantic accent colors meet AA contrast on white backgrounds
- No emoji in the UI — inline SVG icons only (`Icons.tsx`)
- `prefers-reduced-motion` collapses all animation durations to `0.01ms`
- `color-scheme: light` declared on `:root` — dark mode is not supported

---

## What Not To Do

- **Don't use accent colors decoratively.** Moss is not "a nice green." It means clean.
- **Don't use `toISOString()` for dates.** Always use `localDate()` from `lib/db.ts`.
- **Don't put plain numbers in `font-sans`.** Scores, calories, macros — always `font-mono tabular-nums`.
- **Don't add animation without a job.** State the job before writing the keyframe.
- **Don't reference badge `icon`/`color` fields from old DB rows.** They are legacy light-theme values — restyle at render time.
