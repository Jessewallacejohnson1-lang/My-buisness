# Event card: date and time under the title

**Date:** 2026-09-24
**Surface:** Town feed event card, `BlockParty/Features/Home/Feed/FeedEventCard.swift`
**Status:** built 2026-09-24. How the build differs from the steps below:
- `metaLine` is unchanged. The card reads the new computed `FeedCardItem.whenLine` /
  `whereLine` instead, so fixtures, sharing and `FeedPipelineSelfCheck` didn't need to change.
- The tests went into the already-registered `BlockPartyTests/FeedPolishTests.swift`
  (`FeedWhenLineTests`) rather than a new file, so `project.pbxproj` wasn't touched.
- Added after measuring: the photo goes square at accessibility text sizes, because at AX5
  the title, when and where lines outgrew the 3:2 frame.

## Goal

When an event happens should be the second thing you read on the card, right after
its name. Put the date and time on their own line directly under the title, set so
they read as part of the headline block and not as small print.

## Current state (after banner removal)

The title sits over the photograph at the bottom-left, followed by one 13 pt meta line.
The date now rides at the front of that line as a stopgap:

```
Farmers Market
Fri Jul 24 · Weekly · 7:00 PM · Millstream Park
```

Problems:
- Date, recurrence, time and place all share one weight and size, so the "when"
  gets lost in the list.
- The line truncates at one line (non-accessibility sizes). A long venue can push
  the time off the end.
- `dateChip` is an uppercase string (`"FRI JUL 24"`) built for the banner, and
  `.capitalized` is a patch on top of it.

## Target layout

```
Farmers Market                       <- title, eventDisplay(28), white
Today · 7 PM                         <- WHEN line, sansSemibold(15), white
Weekly · Millstream Park             <- WHERE line, sans(13), white 85%
```

Rules:
1. **The when line** holds the date and start time, joined with ` · `.
   - Date is relative when close: `Today`, `Tonight` (today with a start at or after
     5 PM, replacing both words), `Tomorrow`. Otherwise `Fri, Jul 24`. For dates more
     than six months out, add the year.
   - Time is normalised to the app's short form: `7 PM`, `7:30 PM`, `Noon`. If
     it can't be parsed, show the raw string rather than dropping it.
   - Missing time: just the date. Missing date: just the time. Missing both: no line.
2. **The where line** holds recurrence and location, which is today's
   `metaSummary` minus the date. It keeps the existing accessibility-size behaviour
   (unbounded lines at AX sizes, one line otherwise).
3. Spacing: 4 pt between title and when line (the VStack already uses 4), 2 pt
   between when line and where line. This makes the when line hug the title so the
   two read as one unit.
4. No colour accent and no chip. The yellow went away because it competed with the
   photo. Weight and brightness do the job instead. The photo scrim
   (`FeedCardPhotoScrim`) and `.feedCardPhotoTypeShadow()` already cover legibility.
   Check contrast on the lightest photo in the fixtures.
5. Accessibility: the when line gets a spoken label with the full date
   ("Friday, July 24, at 7 PM"). Relative words are spoken as shown ("Today at 7 PM").
6. Dynamic Type: the when line wraps at AX sizes like the where line. It is never
   truncated, because the time is the part people need.

## Implementation steps

1. **Formatter (pure, testable).** Add `static func whenLine(eventDate: String?,
   startTime: String?, now: Date = .now) -> (text: String, spoken: String)?` in
   `FeedCardMapping.swift` next to `dateChip(from:)`.
   - Parse `eventDate` (`yyyy-MM-dd`) the same way `dateChip` does. Pull the shared
     parsing into one private helper instead of copying it.
   - Parse time with the existing `DateHelpers.minutesOf(_:)`
     (`Backend/DateHelpers.swift`). It already handles free text such as `"7am"`,
     `"10 AM"` and `"noon"`. Don't write a second parser.
   - Store the result on `FeedCardItem` as `whenLine: String` and `whenSpoken:
     String`, built in `init(from:recurrence:goingPreview:)`.
2. **Card.** In `FeedEventCard.imageCopy`, insert the when line between the title
   and the meta text. Change `metaSummary` back to `[recurrence, metaLine]` minus the
   time (see step 3) and remove the stopgap `dateChip.capitalized`.
3. **Stop printing the time twice.** `metaLine` is currently `time · location`. Build
   it from location only (the where line), since the when line now owns the time.
   `shareTime` parses `metaLine` as a fallback, so switch it to read `startTime`
   directly. Every mapped item already sets `startTime`.
4. **`dateChip` consumers.** `DailyFeedColumn.share` and `FeedCardGallery` pass
   `dateChip` to `InviteCard` / `ShareCenter` as `dateLabel`. Leave that path alone
   in this change, because the invite card has its own layout. Once the card stops
   using `dateChip`, check whether anything else still needs the uppercase form.
   If nothing does, switch sharing to the new date string and delete `dateChip`.
5. **Fixtures.** Update `FeedCardGallery` and `DailyFixtures` samples so they cover
   today, tonight, tomorrow, a far date, a missing time, and a long venue name.
6. **Check.** Add one test file, `BlockPartyTests/FeedWhenLineTests.swift`, covering
   the formatter with a fixed `now`: Today / Tonight / Tomorrow / weekday date / year
   rollover / unparseable time / nil fields. Register it in the test target's
   **Sources build phase**, not only as a file reference (Task 5 registration guard).
   Update the assert in `FeedPipelineSelfCheck.swift:73` if `dateChip` changes.
7. **Verify in the simulator.** Screenshot the Town feed at default size, AX3 and
   AX5, in light and dark, on the gallery (`FeedCardGallery`) and on live data.
   Confirm the when line never truncates and passes contrast on the lightest photo.

## Out of scope

- Postings (edge-to-edge cards). They carry no event date.
- The invite/share card layout.
- End times and multi-day ranges. The feed has no end-time field today. Add a range
  (`7–9 PM`) once the data has one.

## Design references

- `swiftui-design` skill and `DESIGN.md`: yellow is for small accents only, which is
  why the banner went and why the when line gets no colour.
- Apple News lead cards: the headline, then a bolder byline/time, then the rest.
