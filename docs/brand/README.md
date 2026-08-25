# Block Party — the mark

The logo (Aug 25, 2026) is the **wave figure**: a painted black figure with raised
arms inside three concentric yellow broadcast arcs, on warm paper. It ships **1:1
from the artwork** — `source-logo-1024.png` is the lossless master, and every
visible app mark derives from those exact pixels. It is deliberately **not**
redrawn, flattened, or re-coloured; the brushstroke texture is the point.

The Aug 12 coral lowercase-"bp" tile render (`source-render-1254.png`) is retired.
Its tile-crop pipeline (`scripts/brand/tile.swift` + `exact.swift` + `masksim.swift`)
does not apply to the new art, which is already full-bleed with no baked tile.

## Generated assets

Do not hand-edit — regenerate from the master.

| asset | size | format |
|---|---|---|
| `Assets.xcassets/AppIcon.appiconset/AppIcon.png` | 1024² | RGB, full-bleed, **no alpha** — the master, re-encoded opaque |
| `Assets.xcassets/LaunchMark.imageset/LaunchMark.png` | 880² | RGB, the **36**/1024 inset crop (72 would clip the art — its top edge sits 40 px from the frame) |
| `Assets.xcassets/MarkTemplate.imageset/MarkTemplate.png` | 880² | **STALE** — still the retired coral bp silhouette. No code references it; regenerate or delete when a tinted rendering is actually needed |

The waitlist site's icons (`block-party-waitlist/`: `favicon.ico`, `favicon-32.png`,
`apple-touch-icon.png`, `bp-mark-192.webp`) are downsamples of the same
`AppIcon.png` — regenerate them together with the app assets.

## contentFraction

`BlockPartyMark.contentFraction` in `BlockParty/App/LoaderBlockPartyMark.swift` is the
artwork's extent as a fraction of the `LaunchMark` crop. Callers size marks by
`side / contentFraction`, so **a stale value silently mis-sizes every loader mark** — it
degrades quietly instead of failing.

It has moved on every re-export:

| icon | contentFraction |
|---|---|
| Aug 7 confetti render | 0.8273 |
| Aug 8 flat vector | 0.8864 |
| Aug 8 script-BP exact render | 0.8614 |
| Aug 12 lowercase-bp exact render | 0.8591 — 756 px of 880 |
| **Aug 25 wave-figure logo (current)** | **0.9727** — 926 px of the 952 px crop |

## Retired construction material

`block-party-mark.svg`, `block-party-mark.json`, `scripts/brand/*` and
`source-render-1254.png` describe the retired bp designs. They remain only as
historical artifacts and are **not** a current alternate, fallback, or export path.

## Rules that still hold

- Export the icon **full-bleed**: no alpha. iOS applies its own squircle mask.
- The icon is brand **content**, like photography and the map basemap. Its own
  yellow is allowed wherever the canonical mark appears; it does not change
  `Hue.accent`.
- Use the exact full-colour mark on every live brand surface. Do not tint, trace,
  redraw, or substitute a flat-vector interpretation.
- Whether the mark's yellow becomes the app's **UI accent token** is a separate,
  still-open decision. Shipping this icon does not decide it.
