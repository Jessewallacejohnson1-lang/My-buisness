---
name: match-design
description: >-
  Iteratively reproduce a reference design in the running app until it is
  visually indistinguishable from the reference. Use this WHENEVER the user
  shares a screenshot, mockup, Figma frame, or photo of a UI and wants the app
  to "look like this," "match this design," "make it pixel-perfect," "clone this
  screen," or "keep going until it's exact" — even if they don't say the word
  "match." Drives a closed loop: build → run → screenshot → diff against the
  reference → fix the biggest gaps → repeat, including animations and other live
  graphics. Trigger on any reference image handed over as a visual target.
---

# Match a reference design

Your job is to make a screen in the running app look like a reference image the
user gave you, and to keep going — implement, screenshot, compare, refine — until
the two are visually indistinguishable. You close your own loop; you do not stop
after one pass and ask "is this close enough?" unless you're genuinely blocked.

## What "100% match" actually means

Pixel-for-pixel identity is usually neither achievable nor what the user wants —
fonts hint differently across renderers, you may not have the original's exact
images/icons, and anti-aliasing varies. So the real target is: **at the same
viewport size, a person flipping between the reference and your screenshot can't
tell which is which.** Layout, spacing, proportions, color, type, and motion all
read the same.

State your allowances out loud once, early (e.g. "I'm substituting system fonts
for the proprietary one and using placeholder images at the right dimensions"),
so the user can correct them. Then chase everything else to the end. Don't let a
legitimate allowance become an excuse to leave real gaps unfixed.

## The loop

1. **Read the reference like a spec — before writing any code.** Look hard and
   write down what you see: overall layout and grid, every section top-to-bottom,
   spacing rhythm, exact colors (sample hex from the image, don't guess), type
   (family feel, sizes, weights, tracking, line-height), corner radii, borders,
   shadows, imagery/icons, and any visible interactive or animated state. If the
   project has a design system, map what you see onto its existing tokens instead
   of inventing new values — a match that fights the codebase isn't done.

2. **Implement** the screen against that spec.

3. **Run the app and screenshot it at the reference's viewport.** Match the
   width — comparing a 390px reference to a 1440px screenshot is meaningless. Use
   the project's preview/browser tooling to navigate to the screen and capture it.
   Never ask the user to screenshot it for you; capture it yourself.

4. **Diff systematically, in this order** (fix structural problems before cosmetic
   ones — a misaligned column matters more than a 1px radius, and fixing layout
   often moves everything else anyway):
   - **Structure** — is every element present, in the right place, right order?
   - **Spacing & size** — gaps, padding, element dimensions, proportions.
   - **Color** — backgrounds, text, borders, accents (compare sampled hex).
   - **Typography** — size, weight, tracking, line-height, alignment.
   - **Assets** — images, icons, logos: right content, crop, and dimensions.
   - **State** — hover, active, selected, empty, loading, error if visible.
   - **Motion** — see the animation section below.

   Write the discrepancies as a short list, worst-first.

5. **Fix the top discrepancies**, re-run, re-screenshot, re-diff. Each pass should
   visibly shrink the list. If a pass doesn't, you're guessing — go back to the
   image and measure instead of nudging values blindly.

6. **Stop when the list is empty** (only your stated allowances remain). Show the
   reference and your final screenshot side by side and name what you matched and
   any allowance you took.

## Comparing well

- **Overlay or side-by-side, same scale.** Put them next to each other at equal
  width. If your tooling can produce a difference image or let you toggle between
  the two, use it — the human eye catches misalignment far better in a flip than
  in two static images viewed apart.
- **Measure, don't vibe.** When something's off, pull real numbers — sample the
  reference's pixel colors, measure gaps in image pixels, count the grid. Guessed
  values cause the loop to oscillate instead of converge.
- **One source of truth.** The reference is the spec. If it conflicts with a habit
  or a default, the reference wins — unless it also conflicts with the project's
  design system, in which case surface the tension to the user rather than
  silently picking one.
- **Match the content, not the capture artifacts.** Your screenshot may include a
  framework dev overlay, browser chrome, a scrollbar, or a focus ring; the
  reference may include a phone status bar, a browser toolbar, or a cursor. None
  of those are the design. Ignore them — don't burn rounds trying to reproduce a
  Next.js dev badge or a macOS scrollbar.
- **A compressed screenshot lies about exact values.** Screenshots are great for
  layout, structure, and "does this read the same," but JPEG compression and scaling
  make them unreliable for an exact hex color or a 1px size. When a color or size
  needs to be precise, read the computed style with an inspector rather than trusting
  the pixels in the image.

## Animations and live graphics

A single screenshot cannot capture motion, so a static diff will silently miss it.
When the reference implies movement (a loading shimmer, a transition, a parallax,
a live chart, a video, an animated illustration):

- **Identify the motion spec**: what triggers it, what properties change, the
  duration, the easing curve, whether it loops, and any stagger between elements.
  If the reference is itself a video or GIF, study it frame by frame.
- **Verify with frames, not a snapshot.** Capture several screenshots across the
  animation's timeline (or record a short clip if the tooling supports it) and
  compare the sequence — start, mid, end — against the reference's sequence.
- **Match feel, then numbers.** Easing and timing carry most of the perceived
  quality; a linear 1s where the reference eases over 300ms reads wrong even with
  identical keyframes. Tune duration and curve until the motion feels the same.
- **Respect the project's motion rules.** If the codebase has conventions (reduced-
  motion handling, a stated purpose for animation, shared keyframe classes), honor
  them — a matched animation that breaks accessibility or house style isn't done.

## Pitfalls that stall the loop

- Comparing at the wrong viewport width — fix this first, it invalidates every
  other comparison.
- Polishing a 1px detail while a whole section is structurally wrong — always
  worst-first.
- Inventing new colors/spacing/components when the project already has tokens for
  them — the match should look native to the codebase.
- Declaring victory from memory instead of from a fresh screenshot. The loop ends
  on observed evidence, not on belief that the last edit worked.
- Treating a static screenshot as proof for an animated element.
