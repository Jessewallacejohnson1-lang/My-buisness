# Hygge Design System

> Named for *hygge* (Danish, pron. "hoo-guh"): coziness, warmth, togetherness. Warm linen surfaces, charcoal ink, color reserved for meaning only.

---

## Philosophy

Hygge's UI does one thing: get out of the way so neighbors can find each other. The design is calm, minimal, and warm — never busy, never corporate. Color is semantic, not decorative. Every hue carries a specific meaning and should never be used outside it.

The three rules:
1. **Warm-white first.** The default surface is linen paper. Tints and cards lift from it.
2. **Color means something.** Moss = positive / primary action. Sky = brand. Honey = warmth/energy. Clay = warning. Never use a hue just to fill space.
3. **Motion confirms, never decorates.** Animations answer "did that work?" — not draw attention to themselves.

---

## Color

Tokens are defined in `app/globals.css` via Tailwind v4 `@theme`. Values below are the source of truth.

### Surfaces — warm linen & sand

| Token | Value | Use |
|---|---|---|
| `paper` / `paper-50` | `#fbfaf5` | App canvas, cards, raised sections |
| `paper-100` | `#f5f1e8` | Inputs, wells |
| `paper-200` | `#eae4d4` | Dividers |
| `paper-300` | `#e1dbc9` | Marketing canvas *(LOCKED — Beige Sand)* |

All borders use `border-black/[0.07]` (opacity-based) so they stay proportional across tints.

### Text — charcoal family

| Token | Value | Use |
|---|---|---|
| `ink` | `#2a2a28` | Primary text, display headings |
| `ink-2` | `#5e5d56` | Secondary text, labels |
| `ink-3` | `#8a887e` | Tertiary text, placeholders, metadata |

### Semantic Accents

Each hue has one job. Never swap them.

#### Sky — Brand identity *(LOCKED: `#6b7b84`, Slate Blue-Grey)*
Calm slate blue-grey. Wordmark accents and focus rings.

| Token | Value |
|---|---|
| `sky-400` | `#a6b1b6` |
| `sky-500` | `#87959c` |
| `sky-600` | `#6b7b84` *(brand)* |
| `sky-700` | `#55636b` |
| `sky-800` | `#3e4d54` |

#### Moss — Positive / Primary action *(LOCKED: `#2d4530`, Dark Pine)*
Deep pine green. Primary buttons, RSVP'd / completed states, positive confirmations.

| Token | Value |
|---|---|
| `moss-400` | `#4f7053` |
| `moss-500` / `moss-600` | `#3c5a40` |
| `moss-700` | `#2d4530` *(primary CTA, hover)* |
| `moss-800` | `#1f3022` |

#### Honey — Warmth / Energy
Warm ochre. Used sparingly for energy/highlight accents.

| Token | Value |
|---|---|
| `honey-600` | `#b07d2b` |
| `honey-700` | `#8a5f1c` |

#### Clay — Warning / Error
Terracotta. Error messages and destructive affordances only.

| Token | Value |
|---|---|
| `clay-700` | `#b0573a` |
| `clay-800` | `#8c4329` |

---

## Typography

Three font roles, each with a strict purpose. Never swap them.

| Role | Font | Token | Use |
|---|---|---|---|
| Display | Spectral | `font-display` | Wordmark, H1s, marketing hero text |
| UI | Schibsted Grotesk | `font-sans` | All interface labels, body copy, buttons |
| Data | Geist Mono | `font-mono` | Every number — dates, counts, prices — always with `tabular-nums` |

Fonts are loaded via `next/font/google` in `app/layout.tsx` and exposed as the `--font-*` CSS variables the `@theme` block points at.

The mono rule is strict: if a value is a number — a going-count, a date, the `$2` price — it's `font-mono tabular-nums`. This prevents layout shift and gives data a consistent feel.

---

## Components

### Reveal

`IntersectionObserver`-based scroll entrance. Wraps any content; adds `.reveal-pending` on mount, swaps to `.reveal-in` when the element enters the viewport. Respects `prefers-reduced-motion`. Used on the marketing landing.

> The `/community` app builds its UI inline (no shared component library yet) using the tokens and motion classes below. Icons are inline `<svg>` defined where they're used — there is no shared icon module, and no emoji.

---

## Motion

Every animation has a job. If you can't state the job in one sentence, remove the animation.

| Class | Job | Curve |
|---|---|---|
| `.rise` | Cards enter — stagger with inline `animationDelay` | `cubic-bezier(0.22, 1, 0.36, 1)` 0.55s |
| `.sheet-up` | Bottom sheet slides over backdrop (calendar day view) | `cubic-bezier(0.22, 1, 0.36, 1)` 0.32s |
| `.fade-in` | Generic opacity entrance | `ease-out` 0.25s |
| `.press` | Tactile dip on tap — every tappable element | `cubic-bezier(0.22, 1, 0.36, 1)` 0.12s |
| `.pop` | Checkmarks / confirmations | Spring `cubic-bezier(0.34, 1.56, 0.64, 1)` 0.34s |
| `.bounce-in` | Completion / celebratory banners | Spring `cubic-bezier(0.34, 1.56, 0.64, 1)` 0.42s |
| `.lift` | Marketing cards rise on hover | `cubic-bezier(0.22, 1, 0.36, 1)` 0.35s |

All animations are disabled under `prefers-reduced-motion`. The `.rise` class additionally resets to `opacity: 1` so content stays visible without animating.

---

## Texture

### Paper Grain

The `.grain` class applies a subtle SVG noise texture as a fixed `::before` overlay at low opacity. Used on the marketing landing only — not in the `/community` app. It gives warmth without weight.

### Hairline Borders

Use `border-black/[0.07]` everywhere. Opacity-based borders adapt naturally to any surface tint without needing a separate border color per surface.

---

## Layout

### The app (`/community`)

A single mobile-first column (max-width ~480px, centered) with a fixed bottom tab bar of four tabs: **Timeline · Calendar · Add · Quest**. Tab icons are inline SVG; the active tab is shown by ink color + weight, never a decorative accent.

### Marketing vs. app

The landing page (`/`) uses `.grain`, `.lift`, and `font-display` headings freely, and is server-rendered. The `/community` app is calmer — `font-display` appears only in the header wordmark.

---

## Accessibility

- Focus rings use the `sky` brand color and stay visible — never hidden.
- All text colors meet AA contrast on the linen surfaces.
- No emoji in the UI — inline SVG icons only.
- `prefers-reduced-motion` collapses all animation durations to `0.01ms`.
- `color-scheme: light` declared on `:root` — dark mode is not supported.

---

## What Not To Do

- **Don't use accent colors decoratively.** Moss means positive/primary action, not "a nice green."
- **Don't use `toISOString()` for dates.** Always use `localDate()` from `lib/db.ts` — dates are user-timezone so an evening event stays on today.
- **Don't put plain numbers in `font-sans`.** Counts, dates, prices — always `font-mono tabular-nums`.
- **Don't add animation without a job.** State the job before writing the keyframe.
- **Don't show fake counts.** Real numbers only — never seed or inflate "X going" / "X completed."
