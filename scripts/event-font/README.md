# Event heading font

`BlockParty/Resources/Fonts/BPEventHeading-Regular.ttf` is not a licensed
typeface. It was built from `alphabet-sheet.png` — Jesse's own drawing of the
face — by tracing each glyph and assembling the outlines into a TTF. These
scripts are how, so the font can be rebuilt when the drawing changes rather
than being an unexplained binary in the repo.

## Rebuild

Needs `potrace` (`brew install potrace`) and `fonttools` (`pip install fonttools`).

```sh
cd scripts/event-font
WORK=/tmp/event-font-build
mkdir -p "$WORK/glyphs"

swift segment.swift alphabet-sheet.png "$WORK" > "$WORK/glyphs.tsv"
swift rasterize.swift alphabet-sheet.png "$WORK"
for f in "$WORK"/glyphs/*.pbm; do potrace -b svg --flat -a 1.0 -O 0.2 -t 2 -o "${f%.pbm}.svg" "$f"; done
EVENT_FONT_WORK="$WORK" python3 build.py

cp "$WORK/BPEventHeading-Regular.ttf" ../../BlockParty/Resources/Fonts/
```

## How it works

`segment.swift` finds the six glyph rows by horizontal ink profile, then splits
each row into glyphs by vertical ink profile, and prints one bounding box per
glyph. `rasterize.swift` cuts each box out of the sheet and upsamples it 6x
before thresholding — tracing the raw ~67px glyph directly gives visibly lumpy
curves, and the upsample is what buys the smooth outline. `build.py` maps each
traced outline onto the metrics measured from the sheet and writes the TTF.

## What the sheet does not contain

Accented characters, `%`, and `*`. A title containing one falls back to the
system face for that character alone, which looks like a mistake in the middle
of a word. The apostrophe and quote marks are NOT on the sheet either — those
are synthesised in `build.py` as bars at the measured stem width, because event
titles hit them constantly ("Salt's Cure"). Draw them properly on the sheet and
the synthesis goes away.

## Spacing

The sheet sets its glyphs far apart for legibility, so it cannot supply side
bearings. `SB` in `build.py` is a single uniform value, tuned so that a line set
in the font matches the width of the same line on the sheet's two sample rows
(1173px against 1175px at a 51px x-height). That is a global fit, not per-glyph
spacing: round letters carry slightly too much room next to straight ones.
Per-glyph side bearings and kerning pairs are the next thing worth doing, and
both want eyes on a screenshot rather than a rule here.
