---
name: animation
description: "Router for all motion and animation work — GSAP across the board. Use whenever the user wants to animate anything: tweens, timelines, scroll-linked/scroll-triggered animation, parallax, pinning, React/Vue/Svelte animation, GSAP plugins (ScrollTrigger, ScrollSmoother, Flip, Draggable, SplitText, etc.), easing, sequencing, motion performance/jank, or GSAP utility helpers. Triggers: animate, animation, motion, GSAP, tween, timeline, scroll animation, parallax, pin, stagger, easing, micro-interaction, page transition."
---

# Animation (GSAP) — Router

All motion work for this project lives here. The sub-skills are the official GSAP
skills, split by topic. Read the matching sub-skill's `SKILL.md` for the real
guidance, then implement.

> **House rule (from `DESIGN.md`):** *Motion confirms, never decorates.* Animations
> answer "did that work?" — they don't draw attention to themselves. Keep it calm,
> warm, and subtle. Honor `prefers-reduced-motion`. No flashy/decorative motion.

## Pick the sub-skill

| If the task is about… | Read |
|---|---|
| Core API — `gsap.to/from/fromTo`, easing, duration, stagger, defaults, `matchMedia()`, reduced-motion | `animation/gsap-core/SKILL.md` |
| Sequencing & choreography — `gsap.timeline()`, position parameter, nesting, playback order | `animation/gsap-timeline/SKILL.md` |
| Scroll-linked motion — ScrollTrigger, scrub, pinning, parallax, triggers | `animation/gsap-scrolltrigger/SKILL.md` |
| Any GSAP plugin — ScrollToPlugin, ScrollSmoother, Flip, Draggable, Inertia, Observer, SplitText, ScrambleText, CustomEase/Wiggle/Bounce, GSDevTools | `animation/gsap-plugins/SKILL.md` |
| Animation in **React / Next.js** — `useGSAP`, refs, `gsap.context()`, cleanup | `animation/gsap-react/SKILL.md` |
| Animation in **Vue / Svelte / Nuxt / SvelteKit** — lifecycle, scoping, cleanup on unmount | `animation/gsap-frameworks/SKILL.md` |
| Performance — transforms over layout, avoiding jank, `will-change`, batching, 60fps | `animation/gsap-performance/SKILL.md` |
| Helper utilities — `gsap.utils` clamp, mapRange, normalize, interpolate, random, snap, toArray, wrap, pipe | `animation/gsap-utils/SKILL.md` |

## Typical combinations

- **Animate a React component** → `gsap-react` + `gsap-core` (+ `gsap-timeline` if sequenced).
- **Scroll storytelling / pinned section** → `gsap-scrolltrigger` + `gsap-plugins` + `gsap-performance`.
- **Smooth scrolling site** → `gsap-plugins` (ScrollSmoother) + `gsap-performance`.

This app is React Native / Expo on mobile and React on web — for in-app motion start with `gsap-react`.
