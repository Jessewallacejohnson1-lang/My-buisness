# Body font

`BlockParty/Resources/Fonts/BPBody-*.ttf` (Regular, Medium, SemiBold, Bold) is
not a licensed typeface. It is traced from `font-sheet.png`, the reference Jesse
picked for the app's body text (an approximation of Airbnb Cereal, which Airbnb
doesn't license). Every `sans` and `mono` helper in `BlockPartyFont.swift` uses it.

## Rebuild

Needs `potrace` (`brew install potrace`) and `uv`, which fetches the Python packages for the run.

```sh
uv run --with fonttools --with pillow --with numpy python scripts/body-font/build.py /tmp/body-font
cp /tmp/body-font/BPBody-*.ttf BlockParty/Resources/Fonts/
```

## How it works

`build.py` finds each glyph on the sheet by its ink, upsamples it 8x, thresholds
and traces it. The sheet has one weight; Medium, SemiBold and Bold are the same
raster grown by 4, 9 and 14 upsampled pixels before tracing, then fitted back to
the regular glyph's height so x-height and cap height don't move.

Spacing: a side whose ink runs most of the glyph's height (a stem) gets 58 units,
a bowl 28. That sets lines about 3% wider than the sheet's sample rows, which
read too tight once set small. Kerning pairs are the next thing worth doing.

Digits are proportional; `tnum` (what `.monospacedDigit()` asks for) swaps in
tabular ones. Vertical metrics copy SF Pro's line height (950 / 240 units), so
screens keep their spacing.

## What the sheet does not contain

Accented letters and a straight double quote. `build.py` makes them from the
sheet's own marks: the Western European letters (à through ÿ, À through Ý, ç, ñ)
from ` ^ ~ ° , and i's dot, and " from two straight singles. Anything else
(ø, ß, Polish or Czech letters) falls back to the system face for that letter
alone. Draw them on the sheet and add a band to `BANDS`.
