---
name: brand-visual
description: "Router for brand identity and visual assets — brand voice/messaging, design tokens, banners, and presentations. Use whenever the user works on the brand (tone of voice, style guide, messaging, brand consistency/compliance), defines or edits design tokens (colors, spacing, type scales, CSS variables, component specs), creates banners/social/ad/hero/print graphics, or builds slide decks and presentations. Triggers: brand voice, style guide, messaging, brand assets, design tokens, color/spacing/type scale, CSS variables, banner, social graphic, ad creative, hero image, pitch deck, presentation, slides. For app logos / full corporate-identity generation, see the design router."
---

# Brand & Visual Identity — Router

Brand voice, design tokens, banners, and presentations route from here. Read the
matching sub-skill's `SKILL.md`, then produce the asset.

> **House rule (from `DESIGN.md`):** Hygge = calm, warm, neighborly. Tokens are the
> source of truth — surfaces are warm linen, ink is charcoal, accents (sky/moss/
> honey/clay) are semantic only. Keep brand voice non-corporate. The token values
> in `DESIGN.md` and `app/globals.css` are canonical; don't invent new hues.

## Pick the sub-skill

| If the task is about… | Read |
|---|---|
| Brand voice, messaging frameworks, tone, style guides, asset management, brand consistency/compliance | `brand-visual/brand/SKILL.md` |
| Design tokens & system — three-layer tokens (primitive→semantic→component), CSS variables, spacing/type scales, component specs | `brand-visual/design-system/SKILL.md` |
| Banners — social, ads, website hero, creative assets, print (multi-platform sizes, AI visuals) | `brand-visual/banner-design/SKILL.md` |
| Presentations — strategic HTML decks with Chart.js, token-driven layouts, copywriting formulas | `brand-visual/slides/SKILL.md` |

## Notes

- `brand` and `design-system` share scripts (e.g. `sync-brand-to-tokens.cjs` calls
  `design-system`'s token generator) — keep them in sync when brand colors change.
- For **logo generation, corporate-identity programs (CIP), icon sets, or
  AI social photos**, use the top-level `design` router — it owns those built-in
  generators and routes back here for brand/tokens.
