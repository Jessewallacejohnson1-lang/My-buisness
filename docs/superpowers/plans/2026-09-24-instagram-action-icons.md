# Feed action row: Instagram's icons, in black

**Date:** 2026-09-24
**Surface:** `BlockParty/Features/Home/Feed/FeedEventCardActionRow.swift`. It is the only
file that changes. Both the event card (`FeedEventCard`) and the posting card
(`PostingCard`) draw this row.
**Reference:** Jesse's Instagram capture: heart 220K · comment 3,778 · repost 2,213 ·
send 7,187, with the bookmark alone on the right.
**Status:** built 2026-09-24. SF `.regular` weight kept: it matched the capture on screen, so `.medium` wasn't needed. The paper plane is SF's; the Lucide fallback wasn't needed.

## What Jesse asked for

- Copy the heart, comment, send and bookmark icons.
- **Leave out the repost icon.**
- Make them **black**, at the **same size** as the reference.

## Today vs. target

| | Today | Target |
|---|---|---|
| Heart | `heart`, 45% grey | `heart`, solid black. Liked stays red (`Hue.heart`), the same as Instagram |
| Comment | `bubble.right` (square-ish, tail on the right) | `message`: a round bubble with its tail at the lower left, like Instagram's |
| Share | `square.and.arrow.up` (iOS share box) | `paperplane`, Instagram's "send" |
| Bookmark | `bookmark`, 45% grey, trailing | `bookmark`, solid black, trailing (unchanged apart from the colour) |
| Counts | 13 pt, 45% grey | about 14 pt medium, solid black |
| Repost | not present | stays out |

Sizing stays where it is. `Metric` was already measured off an Instagram capture on
2026-09-20: 24 pt glyph, count 6 pt from its glyph, 16 pt between controls, 44 pt row.
The difference in the new capture is colour and glyph shape, not size.

## Steps

1. **Colour.** In `actionIcon`, change `Hue.ink.opacity(active ? 1 : 0.45)` to
   `Hue.ink`. In `countText`, change `Hue.ink.opacity(0.45)` to `Hue.ink`. Leave the
   `tint` override for the liked heart alone.
2. **Glyphs.** Comment: `"bubble.right"` becomes `"message"`. Share:
   `"square.and.arrow.up"` becomes `"paperplane"`. The accessibility label stays
   "Share", because the action is still the share sheet.
3. **Weight.** Instagram's stroke is a little heavier than SF's `.regular`. Try
   `.fontWeight(.medium)` on the glyph, compare the two side by side with the
   capture, and keep whichever matches better.
4. **Count text.** Change `.mono(13)` to `.sansMedium(14)` (it snaps to 15, like every
   SF helper). Keep `.monospacedDigit()` so the numbers don't shift when a like lands.
5. **Short counts**, like the capture's `220K`. Add one pure formatter:
   under 10,000 the number is written in full with a comma (`3,778`), from 10,000 up
   it's `12.4K`, from a million it's `1.2M`, with any trailing `.0` dropped (`220K`,
   not `220.0K`). Leave the VoiceOver label as the full number.
6. **Send count: none.** Nothing in the data counts shares (no `shareCount`
   anywhere), so the paper plane sits without a number. Adding one needs a backend
   column first, which is out of scope.
7. **Check.**
   - Unit test for the formatter (0, 999, 3778, 9999, 10000, 220000, 1_250_000),
     added to the already-registered `BlockPartyTests/FeedPolishTests.swift`.
   - Screenshot `-daily-feed-preview -daily-feed-state postings` (heart, comment
     and send with counts) and `-daily-feed-state events` (heart and send, with no
     comment on events). Put each next to Jesse's capture.
   - Light mode, default text size only (MEMORY.md, 2026-09-24).

## Fallback if SF's paper plane reads wrong

SF's `paperplane` is close to Instagram's send icon but not identical. Instagram's
has a notch cut into the back edge. If the side-by-side shows a difference Jesse
cares about, add Lucide's `send` as a template imageset in `Assets.xcassets/Lucide/`,
where the app already keeps Lucide icons. Swap only that one glyph and keep the other
three on SF, because the liked heart needs SF's `heart.fill`. Don't trace Instagram's
own artwork. The icon shapes are generic, but their exact drawings are Instagram's.

## Out of scope

- Repost, per Jesse.
- A share counter (see step 6).
- Motion. The heart pop and bookmark dip stay exactly as they are.
