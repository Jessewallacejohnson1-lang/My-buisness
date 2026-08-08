# Block Party — the mark

The logo is the **script "BP" monogram**, in one accent hue on an ink tile. As of
Aug 8 2026 it is **vector**, not a render: `block-party-mark.svg` is the source of
truth, and every shipped raster is generated from it.

|  | value | note |
|---|---|---|
| tile | `#111111` | brand `ink` — the icon is an ink tile |
| accent | `#FA5A34` | the letterforms |
| lockup | 0.762 of the 1024 icon | 780 × 659, centred |

## Why it changed

The Aug 7 icon was a 3-D render: glossy bevels, scattered confetti, coral-orange **and**
purple, plus a striped party hat. It read beautifully at 1024 and turned to noise at
40 pt — the size that actually appears on a home screen.

The letterforms are **unchanged**: they are traced from the shipped art, not redrawn, so
the monogram is pixel-faithful to the one Jesse picked. Removed everything that was only
legible when large:

- confetti (it was carrying the tile, and it dissolved first)
- the gloss/bevel (flattened to one flat fill)
- the purple (one accent hue now)
- the baked edge sheen and corner rounding (the export is full-bleed; iOS masks it)
- **the party hat** — Jesse's call, Aug 8. The bare monogram is the strongest read at
  small sizes because nothing competes with the letterforms.

The hat is still fully implemented in `scripts/brand/build.py` and is one flag away
(`HAT = True` in `export.py`) if it is ever wanted back — striped cone, wrapped bands,
rounded brim, pompom, and the knockout gap that separates it from the B.

## Files

| file | what |
|---|---|
| `block-party-mark.svg` | **source of truth**, 1024 viewBox, flat fills only |
| `block-party-mark.json` | palette, layout knobs, and the measured `contentFraction` |

Generated assets (do not hand-edit — regenerate):

| asset | size | format |
|---|---|---|
| `Assets.xcassets/AppIcon.appiconset/AppIcon.png` | 1024² | RGB, full-bleed, **no alpha** |
| `Assets.xcassets/LaunchMark.imageset/LaunchMark.png` | 880² | RGB, the 72/1024 inset crop |
| `Assets.xcassets/MarkTemplate.imageset/MarkTemplate.png` | 880² | RGBA, alpha = artwork coverage |

## Regenerating

```bash
python3 scripts/brand/export.py          # -> scripts/brand/build/, then copy into Assets.xcassets
```

It prints the re-measured **`contentFraction`**, which lives in
`BlockParty/App/LoaderBlockPartyMark.swift` and **must be updated whenever the icon is
re-exported** — a stale value silently mis-sizes every loader mark.

It is currently **0.8864** (780 px of the 880 `LaunchMark`), up from the render-era
0.8273 because dropping the confetti let the lockup grow into the tile it used to share.
Note `letters_w = 781`, not a round number: that is chosen precisely so the lockup lands
on 780 px and the constant stays exactly 0.8864 across the hat/no-hat change, so removing
the hat needed **no Swift edit at all**.

To change the mark's scale, edit `FINAL` / `PALETTE` in `scripts/brand/export.py`. If you
re-enable the hat or alter its geometry, run `python3 scripts/brand/fit.py` first to
recalibrate the auto-centring constants.

## How the letterforms were made

They are **traced**, so the script BP is pixel-faithful to the mark Jesse picked:

1. `mask.swift` thresholds the coral out of the source render, keeps the two largest
   components (B and P), morphologically **closes** r=3 to bridge the dark bevel creases
   that split the highlight rim off each stroke, then fills interior holes under 3000 px
   so bevel slivers die and the real counter survives.
2. `potrace` traces that clean bitmap to beziers.
3. `normalize.py` bakes potrace's flip transform, drops trace specks, and normalises the
   result into a 1000-unit box → `bp-lockup.d`.

`build.py` then places that path on the tile and auto-centres it.

## Rules that still hold

- Export the icon **full-bleed**: no rounded corners, no shadow, no alpha. iOS masks it.
- The icon is brand **content**, like photography and the map basemap. It is the one
  place accent colour is allowed. The in-app world stays ink on paper.
- Whether `#FA5A34` also becomes the app's pending **UI accent token** is a separate,
  still-open decision. Shipping this icon does not decide it.
