# Almanac daily write — design

**Date:** 2026-07-13
**Feature:** A "Coffee and Claude"-style time-of-day greeting at the top of the Daily
Almanac, and — on the **first open of the day** — the card *writes itself* in front of
the neighbor (greeting types out, then the read follows).

## Intent

Two parts, in Jesse's words: a small charming line at the top of the Almanac (the vibe
of the little text Claude shows up top), and "underneath that, all the text gets written
right in front of them" on the first open of the day.

- **Part 1 — the greeting:** a warm **time-of-day** hello (morning / afternoon /
  evening), Claude-inspired, mostly warm-by-name with a few playful ones. Drawn from a
  curated pool (180 generated → 158 kept after culling the outlandish ones).
- **Part 2 — the write:** the first open of each local day plays a reveal — the greeting
  **types char-by-char** (soft coral caret, terminal feel), then the read-of-the-day
  **writes word-by-word** underneath. Every later open that day renders it instantly.

## Decisions (approved)

1. **Greeting voice:** time-of-day, warm-by-name + a sprinkle of fun. Deterministic per
   (local day + part-of-day) so it's stable all day and rolls over tomorrow; weighted
   ~80% warm. `{name}` substituted at runtime; a name-less line is used when we have no
   name.
2. **Reveal:** greeting types (char-by-char, coral block caret ▌), then the read writes
   (word-by-word). ~2s total. Only `transform`/content animate.
3. **Masthead de-dupe (①):** drop "Hi {name}" from the masthead (keep wordmark + date);
   the Almanac greeting now carries the personal hello.
4. **Reduce Motion (②):** skip the typewriter entirely — render the finished card
   instantly (matches ShareCenter / CornerDrawer).
5. **Pull-to-refresh (③):** re-springs the sections (existing) but does **not** re-type;
   only a genuine new-day first-open writes.

## Architecture

- **`Features/Home/DailyGreeting.swift`** — the pool (warm/fun per slot) + slot logic
  (town clock) + deterministic daily pick (stable djb2 hash of `localDate|PART`, since
  `String.hashValue` is per-launch random) + `{name}` resolution (name-less pool when no
  name).
- **`Features/Components/TypewriterText.swift`** — a reusable reveal primitive. Unveils a
  growing prefix of an `AttributedString` by `.character` or `.word`, over a reserved
  final layout (full string at opacity 0 underneath → no reflow, no rewrapping), with an
  optional caret. Three states: `.hidden` (reserve, show nothing), `.writing` (play),
  `.shown` (render whole). Driven by a `.task(id: state)` so it plays when a stage flips.
- **`Features/Home/AlmanacSection.swift`** —
  - `AlmanacReveal` gate: UserDefaults `hygge.almanac.lastWrittenDay` vs
    `DateHelpers.localDate()`.
  - Eyebrow becomes coffee glyph (`cup.and.saucer.fill`) + the slot word.
  - Greeting hero (char write) → read block (word write) as a two-stage chain
    (`activeStage`: 0 greeting, 1 read, `Int.max` = static). Seeded in `init` from the
    gate so the first frame is already correct (no flash of the finished card).
  - The read is **snapshotted** (`frozenRead`) the instant the greeting finishes, so an
    AI-line upgrade arriving mid-write can't re-wrap under the cursor; a later upgrade
    lands on the next (static) open.
  - `Almanac.readBlock(_:)` assembles hero + detail + optional pointer into one
    attributed block so the word-write flows across all lines while keeping per-run fonts.
- **`Masthead.swift` / `HomeView.swift`** — masthead drops the name; `AlmanacSection`
  gains `name` (threaded from `HomeModel` so a profile edit keeps it in sync).

## Timing (Emil framework — a rare, first-open delight)

- Greeting: `perUnit 0.032`, `startDelay 0.5` (clears the card's spring), coral caret.
- Read: `perUnit 0.045`, `startDelay 0.1`, `lineSpacing 5`.
- Reduce Motion → `.shown` (no character animation). Reveal is content-only (no per-frame
  transform/opacity churn); the full string reserves height so nothing reflows.

## Verification

- Builds clean (0 warnings).
- DEBUG `-almanac-write` forces the write regardless of the day-stamp (and bypasses
  Reduce Motion) so it can be captured headlessly; confirmed in the simulator that the
  greeting types (coffee + slot eyebrow, coral caret) then the read writes, and the
  masthead no longer double-greets.
