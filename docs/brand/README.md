# Block Party — the mark

The logo is the **script "BP" monogram**: the glossy 3-D render, coral on a near-black
tile. It ships **1:1 from the artwork** — `source-render-1254.png` is the master, and the
icon is those exact pixels. It is deliberately **not** redrawn, flattened, or re-coloured.

## The one thing you must not do

**Never ship the source frame directly as `AppIcon.png`.** The render is a rounded tile
floating on black — it has a black surround and its own corner rounding baked in, and an
iOS icon must be **full-bleed** because iOS applies its own squircle mask.

`scripts/brand/exact.swift` handles this: it crops to the tile **face** (the largest
centred square inside the tile bbox) and scales to 1024.

```bash
swift scripts/brand/tile.swift  docs/brand/source-render-1254.png     # find the tile bbox
swift scripts/brand/exact.swift docs/brand/source-render-1254.png OUT 92 97 1070 1065
swift scripts/brand/masksim.swift OUT/AppIcon.png /tmp/check.png 420  # ALWAYS check this
```

`masksim.swift` applies Apple's **0.2237** corner mask over a light ground — the one view
where a dark double-corner or a sliced-off bezel is obvious. For the current render, iOS's
mask radius (~239 px at icon scale) is **wider** than the render's baked rounding (~190 px),
so the mask cuts safely inside it and the lit bezel survives as a clean glassy edge. Re-check
this if the artwork is ever re-rendered — that clearance is a measured fact, not a guarantee.

## Generated assets

Do not hand-edit — regenerate.

| asset | size | format |
|---|---|---|
| `Assets.xcassets/AppIcon.appiconset/AppIcon.png` | 1024² | RGB, full-bleed, **no alpha** |
| `Assets.xcassets/LaunchMark.imageset/LaunchMark.png` | 880² | RGB, the 72/1024 inset crop |
| `Assets.xcassets/MarkTemplate.imageset/MarkTemplate.png` | 880² | RGBA, alpha = artwork coverage |

The template's alpha is scored on each pixel's *coral-ness* (red lead over blue) rather
than hard-thresholded, so the render's antialiased and beveled edges carry into the
template instead of clipping to a jagged silhouette.

## contentFraction

`BlockPartyMark.contentFraction` in `BlockParty/App/LoaderBlockPartyMark.swift` is the
lockup's extent as a fraction of the 880 `LaunchMark`. Callers size marks by
`side / contentFraction`, so **a stale value silently mis-sizes every loader mark** — it
degrades quietly instead of failing.

`exact.swift` prints the measured value on every run. It has moved every single time:

| icon | contentFraction |
|---|---|
| Aug 7 confetti render | 0.8273 |
| Aug 8 flat vector | 0.8864 |
| **Aug 8 exact render (current)** | **0.8614** — 758 px of 880 |

## The flat-vector alternate

`block-party-mark.svg` + `scripts/brand/export.py` build a **flat vector** version of the
same monogram — letterforms traced from this very render, with an optional striped party
hat (`HAT` in `export.py`). It is measurably sharper at 40 pt and is fully working.

**It is not what ships.** Jesse chose the exact render. Keep the vector in sync if the
mark changes, or delete it — just don't confuse the two when regenerating assets.

How the trace was made, if it is ever wanted: `mask.swift` thresholds the coral, keeps the
two largest components (B and P), morphologically **closes** r=3 to bridge the dark bevel
creases that split each stroke's highlight rim off its body, and fills interior holes under
3000 px so bevel slivers die while the real counter survives; `potrace` traces that bitmap;
`normalize.py` bakes potrace's flip transform and normalises to a 1000-unit box.

## Rules that still hold

- Export the icon **full-bleed**: no alpha. iOS applies the mask.
- The icon is brand **content**, like photography and the map basemap. It is the one place
  accent colour is allowed. The in-app world stays ink on paper.
- Whether a coral becomes the app's pending **UI accent token** is a separate, still-open
  decision. Shipping this icon does not decide it.
