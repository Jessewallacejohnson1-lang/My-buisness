# Block Party — the mark

The logo (Sep 19, 2026) is the **wordmark lockup**: black `BlockParty.` on a yellow
field. `source-logo-1254.png` is the master, and every visible app mark derives from
those pixels.

It replaced the Aug 25 **wave figure** — a painted black figure with raised arms
inside three yellow broadcast arcs — which Jesse cut on 2026-09-19 ("remove that logo
with a person, totally delete it"). That master, the coral lowercase-"bp" render
before it, the retired `block-party-mark.svg`/`.json` construction files, and the dead
`MarkTemplate` / `LaunchWordmark` imagesets are all gone from the repo. Git history
has them if they are ever wanted back; nothing in the tree should reference them.

## Generated assets

Do not hand-edit — regenerate:

```
python3 scripts/brand/wordmark.py docs/brand/source-logo-1254.png
```

| asset | size | format |
|---|---|---|
| `Assets.xcassets/AppIcon.appiconset/AppIcon.png` | 1024² | RGB, full-bleed, **no alpha** |
| `Assets.xcassets/LaunchMark.imageset/LaunchMark.png` | 880² | RGB, the **36**/1024 inset crop |
| `Assets.xcassets/Wordmark.imageset/Wordmark.png` | 1051 × 216 | RGBA, the letterforms alone, **template-rendered** |

The script writes them into `docs/brand/`; move them into the asset catalog. It also
leaves `clean-<n>.png`, the de-noised master it resamples from — an intermediate, not
an asset.

Unlike the painted renders this art is **flat two-colour**, so every pixel is a
coverage blend between the field and the ink. The script resolves that coverage once
and writes all three assets from it: the icon as a yellow/ink blend, `Wordmark` as ink
with coverage in the alpha channel. That is why the header can now show the logo with
no tile behind it — an alpha export of the old painted art never existed.

The waitlist site's icons (`block-party-waitlist/`: `favicon.ico`, `favicon-32.png`,
`apple-touch-icon.png`, `bp-mark-192.webp`) are downsamples of the same `AppIcon.png`
— regenerate them together with the app assets. (That directory is not in this
worktree.)

## The two numbers that move

Both are printed by the script on every run, and both **degrade quietly** rather than
failing when stale — a wrong value mis-sizes marks instead of crashing.

| number | where | current |
|---|---|---|
| `BlockPartyMark.contentFraction` | `BlockParty/App/LoaderBlockPartyMark.swift` | **0.9014** — 1051 px of the 1166 px crop |
| `BlockPartyWordmark.aspect` | `BlockParty/Features/Components/BlockPartyWordmark.swift` | **4.8657** — 1051 × 216 |

`contentFraction` history: 0.8273 (Aug 7 confetti) → 0.8864 (Aug 8 flat vector) →
0.8614 (script-BP render) → 0.8591 (lowercase-bp render) → 0.9727 (wave figure) →
0.9014 (wordmark).

## Rules that still hold

- Export the icon **full-bleed**: no alpha. iOS applies its own squircle mask.
- The icon is brand **content**, like photography and the map basemap — and since
  2026-09-18 its yellow is also the app's **accent**: `#FCE804`, sampled from the
  master here, lives in `BlockPartyColor.swift` as `Hue.brandYellowHex`. Every UI
  yellow derives from it. Re-sample on every re-export; it was `#F2B800` under the
  wave figure.
- Use the exact mark on every live brand surface. Do not tint, trace, redraw, or
  substitute a typographic imitation. `Wordmark` is the one exception to "do not
  tint" — it is *exported* as a template precisely so it can take `Hue.ink`.
- **`BlockPartyMark` means the app icon** (field and all, squircle-clipped);
  **`BlockPartyWordmark` means the logo on our own page** (ink letterforms, no tile).
  Picking the wrong one is how a square of the wrong paper ends up on the page.
- `scripts/brand/*.swift` and the other scripts beside `wordmark.py` drove the retired
  bp tile pipeline. They are historical artifacts, **not** a current export path.
