# Skills — grouped by job

Design skills are organized into **category routers**. Each top-level folder has a
`SKILL.md` that explains when to use it and routes to the right nested sub-skill.
Start at the router that matches the job; don't go hunting through sub-folders.

| Router | Use it when you want to… | Contains |
|--------|--------------------------|----------|
| **`animation/`** | Animate anything — motion, tweens, scroll effects, transitions | `gsap-core`, `gsap-timeline`, `gsap-scrolltrigger`, `gsap-plugins`, `gsap-react`, `gsap-frameworks`, `gsap-performance`, `gsap-utils` |
| **`ui-layout/`** | Design, lay out, or build a screen / component (web + mobile) | `frontend-design`, `ui-ux-pro-max`, `ui-styling`, `mobile-app-ui-design`, `match-design` |
| **`brand-visual/`** | Brand voice, design tokens, banners, presentations | `brand`, `design-system`, `banner-design`, `slides` |
| **`design/`** | Generate brand assets — logos, corporate-identity programs, icons, social photos | built-in AI generators (`scripts/` + `references/`); routes to `brand-visual/` for voice & tokens |

`.impeccable/` is a helper (live polish/critique loop), not a category.

## Quick routing

- "Design / reorganize / lay out my app screen" → **`ui-layout`**
- "Add an animation / make it move / scroll effect" → **`animation`**
- "Set up our colors/tokens / write the brand voice / make a banner / build a deck" → **`brand-visual`**
- "Make me a logo / icon set / social graphic / full brand identity package" → **`design`**

## How discovery works (why it's grouped this way)

Claude Code discovers a skill from the `SKILL.md` at the top of each folder. The
four routers sit one level deep, so they're found directly. The individual
skills live one level further in (e.g. `animation/gsap-core/SKILL.md`) and are
reached *through* their router — the router's `SKILL.md` names the exact path to
open. This keeps the top level clean and grouped while every skill stays reachable.

> Reorg note (June 2026): skills used to sit flat at the top level (as symlinks
> into `design/`). They're now grouped into the routers above, with a single
> canonical copy of each — no more duplication. See `../TOOLKIT.md` §1 for the
> full design workflow and `../../DESIGN.md` for the Hygge design system.
