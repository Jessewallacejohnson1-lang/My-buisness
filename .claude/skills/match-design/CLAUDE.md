# Matching a reference design (Hygge)

When I hand you a screenshot, mockup, Figma frame, or photo of a UI and ask you
to make the app "look like this," "match this," "make it pixel-perfect," "clone
this screen," or "keep going until it's exact" — treat the image as a spec and
drive a closed loop until the running app is visually indistinguishable from it.
Don't stop after one implement pass to ask "close enough?" — close your own loop.
This applies even when I don't say the word "match."

## What "100%" means here

Pixel-for-pixel identity isn't the goal and usually isn't achievable — web fonts
hint differently, I may not have the original's exact images/icons, anti-aliasing
varies. The target is: **at the same viewport, flipping between the reference and
your screenshot, you can't tell which is which.** Layout, spacing, proportion,
color, type, and motion all read the same.

State any allowance once, early ("substituting system font for the proprietary
one," "placeholder image at the right dimensions"), so I can correct it — then
chase everything else to the end.

## The loop

1. **Read the reference as a spec before writing code.** Write down: layout/grid,
   every section top-to-bottom, spacing rhythm, sampled colors, type (size, weight,
   tracking, line-height), radii, borders, shadows, imagery/icons, and any visible
   interactive or animated state.
2. **Map onto the Hygge design system — don't invent values.** Surfaces are
   `paper*` linen; text is `ink`/`ink-2`/`ink-3`; accents have one job each
   (`moss` = positive/primary/selected/completed, `sky` = brand/focus, `honey` =
   warmth, `clay` = warning) — never decorative. Every number (dates, counts,
   prices) is `font-mono` with `tabular-nums`. Borders are `border-black/[0.07]`.
   A match that hardcodes hexes the tokens already cover, or uses an accent
   decoratively, isn't done. Full reference: `DESIGN.md` and `app/globals.css`.
3. **Run the app and screenshot at the reference's viewport.** This app is
   mobile-first — match the width (commonly ~390px); comparing a 390px reference
   to a 1280px screenshot is meaningless. Use the preview tools
   (`preview_start` → `preview_resize` → navigate via `preview_eval` →
   `preview_screenshot`); see `.claude/TOOLKIT.md`. Capture it yourself — never
   ask me to screenshot it.
4. **Diff worst-first, in this order** (structural problems dwarf cosmetic ones,
   and fixing layout usually moves everything else):
   - **Structure** — every element present, right place, right order?
   - **Spacing & size** — gaps, padding, dimensions, proportion.
   - **Color** — surfaces, text, borders, accents (against the right tokens).
   - **Typography** — Spectral for display/headings, Schibsted for UI, Geist Mono
     for numbers; size, weight, tracking, line-height, alignment.
   - **Assets** — images/icons (inline `<svg>` only, never emoji): content, crop, size.
   - **State** — selected, today, past/dimmed, hover, empty, loading, error if shown.
   - **Motion** — see below.
   Write the gaps as a short list, worst-first.
5. **Fix the top items, reload, re-screenshot, re-diff.** Each pass should shrink
   the list. If it doesn't, you're guessing — go back to the image and measure.
6. **Stop when the list is empty** (only stated allowances remain). Show the
   reference and your final screenshot side by side and name what you matched.

## Comparing well

- **Same scale, side by side.** Equal width. A flip catches misalignment the eye
  misses across two static images.
- **Match content, not capture artifacts.** Ignore the Next.js dev overlay, browser
  chrome, scrollbars, a phone status bar in the reference, cursors. None are the
  design — don't burn rounds reproducing them.
- **Screenshots lie about exact values.** They're reliable for layout and "does it
  read the same," not for an exact hex or a 1px size — JPEG compression and scaling
  distort both. When a color or size must be precise, read the computed style with
  `preview_inspect`, don't trust the pixels.
- **Measure, don't vibe.** Sample the reference's colors, measure gaps in pixels,
  count the grid. Guessed values make the loop oscillate instead of converge.

## Animations and live graphics

A single screenshot can't see motion, so a static diff silently misses it. When the
reference implies movement (shimmer, transition, parallax, a live count, a video,
an animated illustration):

- **Pin the motion spec**: trigger, which properties change, duration, easing,
  whether it loops, stagger between elements. If the reference is a video/GIF,
  study it frame by frame.
- **Verify with frames, not a snapshot** — capture start/mid/end across the
  timeline (or record a clip) and compare the sequence.
- **Match feel, then numbers** — easing and timing carry the quality; a linear 1s
  where the reference eases over 300ms reads wrong even with identical keyframes.
- **Honor the house rules.** Motion confirms, never decorates — every animation
  answers "did that work?" and has a stated job. Respect `prefers-reduced-motion`
  (all durations collapse to `0.01ms`); reuse the existing classes in `globals.css`
  (`.rise`, `.sheet-up`, `.press`, `.pop`, etc.) rather than inventing new ones.
  A matched animation that breaks reduced-motion or house style isn't done.

## Clears the on-brand bar

A pixel-match still fails if it imports a corporate-app feel. Keep it calm, warm,
neighborly, hyper-local. No badges/streaks/feeds/follower-counts, no notification
spam, no fake/seeded counts — real numbers only. If the reference itself pushes
something off-brand, match the layout but flag the tension rather than silently
shipping it.

## Pitfalls that stall the loop

- Wrong viewport width — fix first; it invalidates every other comparison.
- Polishing a 1px radius while a section is structurally wrong — always worst-first.
- Inventing hexes/spacing/components the tokens already cover — the match should
  look native to the codebase.
- Rendering numbers in `font-sans`, or using `toISOString()` for dates instead of
  `localDate()` from `lib/db.ts`.
- Declaring victory from memory instead of a fresh screenshot — the loop ends on
  observed evidence, not belief the last edit worked.
- Treating a static screenshot as proof for an animated element.
