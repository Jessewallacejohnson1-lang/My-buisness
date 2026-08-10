//
//  FeedPolishTests.swift
//  BlockPartyTests — the Today feed's Reduce Motion contract, its "no placeholder
//  values" product rule, the almanac readings line, and the event-detail route.
//
//  These are the parts of the polish pass that are decidable without a screenshot.
//  Layout and feel are verified in the simulator; the rules below are verified here
//  so they cannot regress silently.
//

import XCTest
@testable import BlockParty

final class FeedMotionTests: XCTestCase {

    // MARK: Reduce Motion degrades EVERY feed animation to a cross-fade

    func testReduceMotionTurnsEveryFeedAnimationIntoACrossFade() {
        let specs: [(name: String, spec: FeedMotion.Spec)] = [
            ("news expand", FeedMotion.newsExpandSpec(reduceMotion: true)),
            ("quiet press", FeedMotion.quietPressSpec(reduceMotion: true)),
            ("plus press", FeedMarkPress.spec(reduceMotion: true)),
        ]

        for entry in specs {
            XCTAssertFalse(entry.spec.usesSpring, "\(entry.name) must not spring")
            XCTAssertFalse(entry.spec.usesScale, "\(entry.name) must not scale")
            XCTAssertFalse(entry.spec.usesOffset, "\(entry.name) must not move")
            XCTAssertTrue(entry.spec.isCrossFade, "\(entry.name) must be a cross-fade")
            XCTAssertEqual(entry.spec.duration, FeedMotion.crossFade)
        }
    }

    func testFullMotionKeepsTheSignatureExpandSpringy() {
        let spec = FeedMotion.newsExpandSpec(reduceMotion: false)

        XCTAssertTrue(spec.usesSpring)
        XCTAssertTrue(spec.usesOffset, "The body rises as it fades in")
        XCTAssertFalse(spec.usesScale, "The card grows; it does not zoom")
        XCTAssertEqual(spec.duration, FeedMotion.expandResponse)
        XCTAssertFalse(spec.isCrossFade)
    }

    func testReduceMotionExpandIsAPlainTimedFade() {
        XCTAssertEqual(
            FeedMotion.newsExpand(reduceMotion: true),
            .easeInOut(duration: FeedMotion.crossFade)
        )
        XCTAssertNotEqual(
            FeedMotion.newsExpand(reduceMotion: false),
            FeedMotion.newsExpand(reduceMotion: true)
        )
    }

    func testReduceMotionRemovesEveryPressScaleAndSubstitutesAFade() {
        XCTAssertEqual(FeedMotion.pressScale(isPressed: true, reduceMotion: true), 1)
        XCTAssertEqual(FeedMotion.pressScale(isPressed: false, reduceMotion: true), 1)
        XCTAssertEqual(FeedMarkPress.scale(isPressed: true, reduceMotion: true), 1)

        XCTAssertLessThan(
            FeedMotion.pressOpacity(isPressed: true, reduceMotion: true),
            1,
            "Reduce Motion carries the press with a value dip instead"
        )
        XCTAssertEqual(FeedMotion.pressOpacity(isPressed: true, reduceMotion: false), 1)
    }

    func testFeedPressStaysQuietWhileThePlusStaysEmphatic() {
        let quiet = FeedMotion.pressScale(isPressed: true, reduceMotion: false)
        let plus = FeedMarkPress.scale(isPressed: true, reduceMotion: false)

        XCTAssertEqual(quiet, FeedMotion.quietPress)
        XCTAssertGreaterThan(quiet, 0.97, "A whole card must barely move")
        XCTAssertLessThan(plus, quiet, "Only the + press is allowed to be felt")
    }
}

final class FeedPlaceholderRuleTests: XCTestCase {

    // MARK: Never render a placeholder value

    func testMissingLocationProducesNoTextRatherThanLocationTBD() {
        XCTAssertNil(YourDayLogic.placeText(for: event(location: nil)))
        XCTAssertNil(YourDayLogic.placeText(for: event(location: "")))
        XCTAssertNil(YourDayLogic.placeText(for: event(location: "   ")))
        XCTAssertEqual(
            YourDayLogic.placeText(for: event(location: "  Millstream Park ")),
            "Millstream Park"
        )
    }

    func testMissingStartTimeProducesNoTextRatherThanTimeTBD() {
        XCTAssertNil(YourDayLogic.startTimeText(for: event(time: nil)))
        XCTAssertNil(YourDayLogic.startTimeText(for: event(time: "  ")))
        XCTAssertEqual(YourDayLogic.startTimeText(for: event(time: "7:00 PM")), "7:00 PM")
        XCTAssertEqual(
            YourDayLogic.startTimeText(for: event(time: "after dark")),
            "after dark",
            "The organizer's own words are real data and survive"
        )
    }

    func testUnparseableDateLeaksNoRawRowValue() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        XCTAssertNil(YourDayLogic.dayText(for: event(date: "not-a-date"), now: now))
        XCTAssertNil(YourDayLogic.dayText(for: event(date: ""), now: now))
    }

    func testScheduleDropsTheMissingHalfInsteadOfPrintingAPlaceholder() {
        XCTAssertEqual(YourDayLogic.joined(day: "Today", time: "7:00 PM"), "Today, 7:00 PM")
        XCTAssertEqual(YourDayLogic.joined(day: "Today", time: nil), "Today")
        XCTAssertEqual(YourDayLogic.joined(day: nil, time: "7:00 PM"), "7:00 PM")
        XCTAssertNil(YourDayLogic.joined(day: nil, time: nil))

        let timeless = YourDayLogic.schedulePresentation(
            for: event(date: "2033-05-18", time: nil),
            now: Date(timeIntervalSince1970: 2_000_000_000)
        )
        XCTAssertFalse(timeless.dateAndTime.contains("TBD"))
        XCTAssertFalse(timeless.dateAndTime.hasSuffix(", "))
    }

    func testZeroGoingCountStillRendersNothing() {
        XCTAssertNil(YourDayLogic.goingLabel(for: 0))
        XCTAssertEqual(YourDayLogic.goingLabel(for: 3), "3 going")
    }

    private func event(
        date: String = "2033-05-18",
        time: String? = "7:00 PM",
        location: String? = "Downtown"
    ) -> UpcomingEvent {
        UpcomingEvent(
            id: "event-1",
            title: "Neighborhood walk",
            eventDate: date,
            startTime: time,
            location: location,
            goingCount: 0,
            createdAt: "2033-05-01T12:00:00Z"
        )
    }
}

@MainActor
final class FeedRouteAndCopyTests: XCTestCase {

    // MARK: The event detail route

    func testEventRouteCarriesItsOwnEventAndStaysDistinct() {
        let walk = FeedRoute.event(sampleEvent(id: "walk"))
        let supper = FeedRoute.event(sampleEvent(id: "supper"))

        XCTAssertNotEqual(walk, supper)
        XCTAssertEqual(walk, FeedRoute.event(sampleEvent(id: "walk")))
        XCTAssertEqual(walk.id, walk)
        XCTAssertNotEqual(walk, .feedDiscovery)
    }

    // MARK: Error copy

    func testEveryFeedErrorTitleIsCalmSentenceCaseHouseVoice() {
        let titles = [
            FeedStateCopy.almanacUnavailable,
            FeedStateCopy.yourDayUnavailable,
            FeedStateCopy.townNotesUnavailable,
        ]

        for title in titles {
            XCTAssertFalse(title.contains("!"), "No exclamation marks: \(title)")
            XCTAssertFalse(title.lowercased().contains("error"), "No error codes: \(title)")
            XCTAssertFalse(title.lowercased().contains("failed"), "Plain verbs: \(title)")
            XCTAssertTrue(title.hasSuffix("."), "One finished sentence: \(title)")
            let first = try? XCTUnwrap(title.first)
            XCTAssertEqual(String(first ?? " "), String(first ?? " ").uppercased())
        }

        XCTAssertEqual(FeedStateCopy.retryAction, "Try again")
        XCTAssertEqual(FeedStateCopy.retryMessage, "Check your connection and try again.")
    }

    // MARK: The almanac's readings line (the weather moved off the greeting)

    func testReadingsLineCarriesTheWeatherAlongsideTheSunTimes() throws {
        let line = try XCTUnwrap(
            Almanac.readingsLine(for: weather(sunrise: sunTime(hour: 6), sunset: sunTime(hour: 20)))
        )

        XCTAssertTrue(line.hasPrefix("Clear, 70°"), line)
        XCTAssertTrue(line.contains("· sunrise "), line)
        XCTAssertTrue(line.contains("· sunset "), line)
    }

    func testReadingsLinePrintsOnlyTheFieldsThatArrived() throws {
        let partial = try XCTUnwrap(
            Almanac.readingsLine(for: weather(sunrise: sunTime(hour: 6), sunset: nil))
        )

        XCTAssertTrue(partial.contains("sunrise"))
        XCTAssertFalse(partial.contains("sunset"))
        XCTAssertNil(
            Almanac.readingsLine(for: nil),
            "No reading at all is the error state's job, not a line saying 'unavailable'"
        )
    }

    func testMastheadBlockSkipsAnAbsentReadingWithoutLeavingABlankLine() {
        let withoutReadings = String(
            Almanac.mastheadBlock(
                readingsLine: nil,
                civicLine: nil,
                suggestion: "Take the long way home."
            ).characters
        )

        XCTAssertEqual(withoutReadings, "Take the long way home.")

        let full = String(
            Almanac.mastheadBlock(
                readingsLine: "Clear, 70°",
                civicLine: "Recycling week — bins out Wednesday night",
                suggestion: "Take the long way home."
            ).characters
        )
        XCTAssertEqual(
            full,
            "Clear, 70°\nRecycling week — bins out Wednesday night\nTake the long way home."
        )
    }

    private func sampleEvent(id: String) -> UpcomingEvent {
        UpcomingEvent(
            id: id,
            title: "Neighborhood walk",
            eventDate: "2033-05-18",
            startTime: "7:00 PM",
            location: "Downtown",
            goingCount: 2,
            createdAt: "2033-05-01T12:00:00Z"
        )
    }

    private func sunTime(hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2033
        components.month = 5
        components.day = 18
        components.hour = hour
        components.minute = 11
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = WeatherService.townTZ
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    private func weather(sunrise: Date?, sunset: Date?) -> Weather {
        Weather(
            tempF: 70,
            feelsLikeF: 70,
            highF: 78,
            lowF: 60,
            label: "Clear",
            state: .clearDay,
            windGustMph: nil,
            precipProbNext2h: nil,
            precipPeakTime: nil,
            aqi: nil,
            sunrise: sunrise,
            sunset: sunset
        )
    }
}

@MainActor
final class TownNotesFailureStateTests: XCTestCase {
    private struct LoaderFailure: Error {}

    func testAFailedStoriesReadEntersTheSharedErrorState() async {
        let module = TownNotesModule(
            storiesLoader: { _, _ in throw LoaderFailure() },
            sweepLoader: { _, _ in nil }
        )

        await module.load(
            FeedModuleContext(
                auth: AuthStore(),
                briefing: BriefingModel(),
                displayName: "Jesse",
                navigate: { _ in }
            )
        )

        XCTAssertEqual(module.phase, .failed)
        XCTAssertTrue(module.stories.isEmpty)
        XCTAssertNil(module.sweepLine)
    }
}

// MARK: - The day schedule sheet
//
// The sheet's rules are almost entirely about ABSENCE: which stat columns get
// dropped, when the now line is not drawn, when the gutter says nothing. Those are
// exactly the things a screenshot of a happy fixture will not catch, so they are
// pinned here.

final class DayScheduleLogicTests: XCTestCase {

    /// 2026-08-10, 09:23 America/Chicago — the fixtures' Monday morning.
    private var now: Date { DayScheduleTestClock.morning }

    // MARK: Stat columns — suppression is the common path

    func testUpcomingDropsDistanceBecauseThereIsNoDistanceSource() {
        let item = DayScheduleTestClock.item(startingAt: 18 * 60 + 30, going: 12)
        let stats = DayScheduleLogic.stats(for: item, state: .upcoming, now: now)

        XCTAssertEqual(stats.map(\.label), ["STARTS", "GOING"])
        XCTAssertFalse(stats.contains { $0.label == "DISTANCE" },
                       "Events carry no coordinates, so DISTANCE can never be real")
    }

    func testUpcomingWithNobodyGoingRendersOneColumn() {
        let item = DayScheduleTestClock.item(startingAt: 17 * 60 + 30, going: 0)
        let stats = DayScheduleLogic.stats(for: item, state: .upcoming, now: now)

        XCTAssertEqual(stats.map(\.label), ["STARTS"],
                       "A zero going-count is a fact about our database, not the town")
    }

    func testInProgressWithoutAnEndRendersGoingAlone() {
        let item = DayScheduleTestClock.item(startingAt: 9 * 60, going: 4)
        let stats = DayScheduleLogic.stats(for: item, state: .inProgress, now: now)

        XCTAssertEqual(stats.map(\.label), ["GOING"],
                       "ENDS IN needs club_events.end_at, which does not exist yet")
    }

    func testInProgressWithNoEndAndNobodyGoingRendersNoStatRowAtAll() {
        let item = DayScheduleTestClock.item(startingAt: 8 * 60 + 30, going: 0)

        XCTAssertTrue(DayScheduleLogic.stats(for: item, state: .inProgress, now: now).isEmpty,
                      "Zero columns means the caller drops the divider too")
    }

    func testCompletedShowsWhenItHappenedAndWhoWentButNotADuration() {
        let item = DayScheduleTestClock.item(startingAt: 7 * 60, going: 6)
        let stats = DayScheduleLogic.stats(for: item, state: .completed, now: now)

        XCTAssertEqual(stats.map(\.label), ["WENT", "GOING"])
        XCTAssertEqual(stats.first?.value, "7:00 AM")
    }

    /// The suppression is data-driven, not a hardcoded "never". When `end_at`
    /// lands, the two duration columns appear with no other change.
    func testAStatedEndBringsBackEndsInAndDuration() {
        let start = DayScheduleTestClock.instant(minutes: 9 * 60)
        let item = DayScheduleTestClock.item(
            startingAt: 9 * 60,
            going: 4,
            end: start.addingTimeInterval(90 * 60)
        )

        XCTAssertEqual(
            DayScheduleLogic.stats(for: item, state: .inProgress, now: now).map(\.label),
            ["ENDS IN", "GOING"]
        )
        XCTAssertEqual(
            DayScheduleLogic.stats(for: item, state: .completed, now: now).map(\.label),
            ["WENT", "DURATION", "GOING"]
        )
        XCTAssertEqual(DayScheduleLogic.duration(item), "1.5 hr")
    }

    func testNoStatValueIsEverAPlaceholder() {
        let items = [
            DayScheduleTestClock.item(startingAt: 7 * 60, going: 0),
            DayScheduleTestClock.item(startingAt: 9 * 60, going: 4),
            DayScheduleTestClock.item(startingAt: 18 * 60, going: 12),
            DayScheduleTestClock.item(startingAt: 0, going: 0, isAllDay: true),
        ]
        let placeholders = ["—", "-", "--", "TBD", "0", "n/a", "N/A", ""]

        for item in items {
            for state in [DayRowState.upcoming, .inProgress, .completed] {
                for stat in DayScheduleLogic.stats(for: item, state: state, now: now) {
                    XCTAssertFalse(placeholders.contains(stat.value),
                                   "\(stat.label) rendered the placeholder '\(stat.value)'")
                }
            }
        }
    }

    // MARK: The gutter

    func testGutterSplitsAClockTimeOffItsMeridiem() {
        let time = DayScheduleLogic.gutterTime(
            for: DayScheduleTestClock.item(startingAt: 18 * 60 + 30, going: 0)
        )

        XCTAssertEqual(time?.value, "6:30")
        XCTAssertEqual(time?.meridiem, "PM")
        XCTAssertEqual(time?.spoken, "6:30 PM")
    }

    func testGutterNamesTheShapeOfAnAllDayOrOngoingItem() {
        let allDay = DayScheduleTestClock.item(startingAt: 0, going: 0, isAllDay: true)
        let ongoing = DayScheduleTestClock.item(startingAt: 10 * 60, going: 0, isMultiDay: true)

        XCTAssertEqual(DayScheduleLogic.gutterTime(for: allDay)?.value, "all day")
        XCTAssertNil(DayScheduleLogic.gutterTime(for: allDay)?.meridiem)
        XCTAssertEqual(DayScheduleLogic.gutterTime(for: ongoing)?.value, "ongoing")
    }

    /// An unparseable start time is parked at 11:59 PM so it sorts last. That is a
    /// sort key, not a fact, and the gutter must not print it.
    func testGutterSaysNothingWhenTheOrganiserNeverGaveATime() {
        let item = DayScheduleTestClock.item(
            startingAt: 23 * 60 + 59,
            going: 0,
            eyebrow: "Today"
        )

        XCTAssertNil(DayScheduleLogic.gutterTime(for: item))
        XCTAssertNil(DayScheduleLogic.went(item), "and WENT cannot invent one either")
    }

    // MARK: The now line

    func testNowLineIsHiddenBeforeTheDayHasStarted() {
        let evening = [DayScheduleTestClock.item(startingAt: 18 * 60, going: 0)]

        XCTAssertFalse(DayScheduleLogic.showsNowLine(items: evening, now: now))
        XCTAssertNil(DayScheduleLogic.nowLineIndex(items: evening, now: now))
    }

    func testNowLineIsHiddenOnceEverythingHasEnded() {
        let dawn = [DayScheduleTestClock.item(startingAt: 5 * 60, going: 0)]

        XCTAssertFalse(DayScheduleLogic.showsNowLine(items: dawn, now: now),
                       "5 AM plus the assumed two hours is over by 9:23")
    }

    func testNowLineSitsAfterEverythingThatHasAlreadyStarted() {
        let day = [
            DayScheduleTestClock.item(startingAt: 7 * 60, going: 0),
            DayScheduleTestClock.item(startingAt: 9 * 60, going: 0),
            DayScheduleTestClock.item(startingAt: 17 * 60 + 30, going: 0),
        ]

        XCTAssertTrue(DayScheduleLogic.showsNowLine(items: day, now: now))
        XCTAssertEqual(DayScheduleLogic.nowLineIndex(items: day, now: now), 2)
    }

    func testAnEmptyDayHasNoSpanAndNoNowLine() {
        XCTAssertNil(DayScheduleLogic.span(of: []))
        XCTAssertFalse(DayScheduleLogic.showsNowLine(items: [], now: now))
    }

    // MARK: Copy

    func testHeaderCountsThingsRatherThanAnnouncingAZero() {
        XCTAssertEqual(DayScheduleLogic.headerCount(0), "Nothing today")
        XCTAssertEqual(DayScheduleLogic.headerCount(1), "1 thing today")
        XCTAssertEqual(DayScheduleLogic.headerCount(3), "3 things today")
    }

    func testHeaderDateAndNowLabelReadInTownTime() {
        XCTAssertEqual(DayScheduleLogic.headerDate(now), "Monday, August 10")
        XCTAssertEqual(DayScheduleLogic.nowLabel(now), "now 9:23")
        XCTAssertEqual(DayScheduleLogic.nowSpoken(now), "Now, 9:23 AM")
    }

    /// Every live row is `.other`, so printing the category label would put
    /// "Other · somewhere" under every title in the app.
    @MainActor
    func testSubtitleDropsTheUncategorisedFallback() {
        let uncategorised = DayScheduleTestClock.item(
            startingAt: 9 * 60,
            going: 0,
            category: .other
        )
        let categorised = DayScheduleTestClock.item(
            startingAt: 9 * 60,
            going: 0,
            category: .food
        )

        XCTAssertEqual(DayScheduleLogic.subtitle(for: uncategorised), "Local Blend")
        XCTAssertEqual(DayScheduleLogic.subtitle(for: categorised), "Food & drink · Local Blend")
    }
}

// MARK: - Presenting the day in-hierarchy
//
// The day sheet stopped being a `.sheet` so the rail-card → timeline-row morph
// could run at all (a namespace does not cross a presentation boundary). The cost
// is that drag-to-dismiss, the resting detent and the open anchor are now ours.
// The gesture itself cannot be automated in this setup; its ARITHMETIC can, and
// that is where every judgement call actually lives.

final class DayScheduleDragTests: XCTestCase {

    // MARK: The translation curve

    func testDownwardDragFollowsTheFingerExactly() {
        for pull in [1.0, 40.0, 120.0, 400.0] as [CGFloat] {
            XCTAssertEqual(
                DayScheduleDrag.translation(for: pull),
                pull,
                "A downward drag is going somewhere; it must not be damped"
            )
        }
    }

    func testUpwardDragIsRubberBandedAndBounded() {
        let small = DayScheduleDrag.translation(for: -20)
        let large = DayScheduleDrag.translation(for: -400)

        XCTAssertGreaterThan(small, -20, "An upward pull must give less than it is asked")
        XCTAssertLessThan(small, 0, "…but it must still give something")
        XCTAssertGreaterThan(
            large,
            -DayScheduleDrag.rubberBandLimit,
            "However hard it is pulled, the card never passes the rubber-band limit"
        )
        XCTAssertLessThan(large, small, "Further pull still yields further travel")
    }

    func testReduceMotionRemovesTheRubberBandEntirely() {
        XCTAssertEqual(
            DayScheduleDrag.translation(for: -200, rubberBands: false),
            0,
            "The spec asks for no rubber banding; a stiff top edge is that, honestly"
        )
        XCTAssertEqual(
            DayScheduleDrag.translation(for: 200, rubberBands: false),
            200,
            "Dismissal is a function, not motion — the downward drag still works"
        )
    }

    // MARK: The dismissal verdict

    func testASlowShortDragDoesNotDismiss() {
        XCTAssertFalse(
            DayScheduleDrag.dismisses(translation: 60, velocity: 0, viewportHeight: 812)
        )
    }

    func testALongDragDismissesWithNoVelocityAtAll() {
        XCTAssertTrue(
            DayScheduleDrag.dismisses(translation: 400, velocity: 0, viewportHeight: 812)
        )
    }

    func testAFastFlickDismissesFromShortOfTheDistanceThreshold() {
        let translation: CGFloat = 60
        let height: CGFloat = 812

        XCTAssertFalse(
            DayScheduleDrag.dismisses(translation: translation, velocity: 0, viewportHeight: height),
            "Sanity: this distance alone is not enough"
        )
        XCTAssertTrue(
            DayScheduleDrag.dismisses(
                translation: translation,
                velocity: 2000,
                viewportHeight: height
            ),
            "…but thrown at 2000pt/s it is going, and distance-only would have kept it"
        )
    }

    func testAnUpwardFlingNeverDismisses() {
        XCTAssertFalse(
            DayScheduleDrag.dismisses(translation: 30, velocity: -3000, viewportHeight: 812)
        )
    }

    func testTheThresholdScalesWithTheViewportButNeverBelowItsFloor() {
        let tall = DayScheduleDrag.dismissDistance(viewportHeight: 1000)
        let short = DayScheduleDrag.dismissDistance(viewportHeight: 200)

        XCTAssertEqual(tall, 220, accuracy: 0.001)
        XCTAssertEqual(
            short,
            DayScheduleDrag.minimumDismissDistance,
            "A small viewport falls back to the floor rather than a hair trigger"
        )
    }
}

final class DayScheduleAnchorTests: XCTestCase {

    func testATappedRailCardAnchorsOnItsOwnRow() {
        XCTAssertEqual(DayScheduleAnchor.item("evt-1").itemID, "evt-1")
    }

    /// §3: the add tile opens the day on the bottom CTA, not on a row — so it must
    /// NOT name an item to scroll to.
    func testTheAddTileAnchorNamesNoRow() {
        XCTAssertNil(DayScheduleAnchor.callToAction.itemID)
        XCTAssertNil(DayScheduleAnchor.top.itemID)
    }

    func testTheFixtureMapsEveryDebugStateToAnAnchor() {
        func anchor(_ state: String) -> DayScheduleAnchor {
            DayScheduleFixture.fromArguments(["-day-sheet-state", state]).anchor
        }

        XCTAssertEqual(anchor("upcoming"), .item("fixture-trivia"))
        XCTAssertEqual(anchor("inprogress"), .item("fixture-story"))
        XCTAssertEqual(anchor("completed"), .item("fixture-walk"))
        XCTAssertEqual(anchor("cta"), .callToAction)
        XCTAssertEqual(anchor("empty"), .top)
        XCTAssertEqual(DayScheduleFixture.fromArguments([]).anchor, .top)
    }
}

@MainActor
final class DaySchedulePresentationTests: XCTestCase {

    func testItStartsClosed() {
        XCTAssertFalse(DaySchedulePresentation().isOpen)
    }

    func testOpeningCarriesTheDayAndTheAnchor() {
        let presentation = DaySchedulePresentation()
        let day = [DayScheduleTestClock.item(startingAt: 9 * 60, going: 2)]

        presentation.open(
            DayScheduleRequest(
                items: day,
                anchor: .item(day[0].id),
                dates: FixedDateProvider(DayScheduleTestClock.morning)
            )
        )

        XCTAssertTrue(presentation.isOpen)
        XCTAssertEqual(presentation.request?.items.map(\.id), day.map(\.id))
        XCTAssertEqual(presentation.request?.anchor, .item(day[0].id))
    }

    /// Re-opening on a different card while open re-anchors rather than stacking a
    /// second presentation — the failure a `.sheet` used to prevent for us.
    func testOpeningAgainReplacesTheRequest() {
        let presentation = DaySchedulePresentation()
        let dates = FixedDateProvider(DayScheduleTestClock.morning)

        presentation.open(DayScheduleRequest(items: [], anchor: .item("a"), dates: dates))
        presentation.open(DayScheduleRequest(items: [], anchor: .item("b"), dates: dates))

        XCTAssertEqual(presentation.request?.anchor, .item("b"))
    }

    func testClosingEmptiesTheRequest() {
        let presentation = DaySchedulePresentation()
        presentation.open(
            DayScheduleRequest(
                items: [],
                anchor: .top,
                dates: FixedDateProvider(DayScheduleTestClock.morning)
            )
        )

        presentation.close()

        XCTAssertFalse(presentation.isOpen)
        XCTAssertNil(presentation.request)
    }
}

final class DayScheduleMorphContractTests: XCTestCase {

    /// The rail card and the timeline row must spell the matched ids IDENTICALLY or
    /// the morph silently does not pair. Both sides now call these two functions,
    /// which is the only reason that cannot drift.
    func testTheMatchedIdsAreUniquePerItemAndPerRole() {
        XCTAssertEqual(DayScheduleSheet.accentID("evt-1"), "dayitem-accent-evt-1")
        XCTAssertEqual(DayScheduleSheet.titleID("evt-1"), "dayitem-title-evt-1")
        XCTAssertNotEqual(DayScheduleSheet.accentID("evt-1"), DayScheduleSheet.titleID("evt-1"))
        XCTAssertNotEqual(DayScheduleSheet.accentID("evt-1"), DayScheduleSheet.accentID("evt-2"))
    }

    /// Reduce Motion gets the 0.2s cross-fade and nothing springy.
    func testReduceMotionMotionIsAShortCrossFade() {
        XCTAssertEqual(DayScheduleMotion.reduced, .easeInOut(duration: 0.2))
        XCTAssertNotEqual(DayScheduleMotion.open, DayScheduleMotion.reduced)
    }

    /// The hand-built detent lands where the system `.large` one did — measured off
    /// a screenshot of the old `.sheet` presentation at 62pt, which is the iPhone
    /// 17's top safe-area inset, so the host adds nothing to it.
    func testTheRestingDetentAddsNothingToTheTopSafeArea() {
        XCTAssertEqual(DayScheduleMetrics.restingTopInset, 0)
        XCTAssertEqual(DayScheduleMetrics.sheetCornerRadius, 20)
    }

    /// The close button's 44pt target is carved out of the drag strip, or the two
    /// compete for the same touch and the × stops working.
    func testTheDragStripLeavesTheCloseButtonAlone() {
        XCTAssertGreaterThanOrEqual(
            DayScheduleMetrics.dragHandleLeading,
            44,
            "The 44pt close target must be outside the grab area"
        )
    }
}

/// Fixed-clock helpers. Everything is built for 2026-08-10 in town time so a test
/// never depends on when it runs.
private enum DayScheduleTestClock {
    static var morning: Date { instant(minutes: 9 * 60 + 23) }

    static func instant(minutes: Int) -> Date {
        var components = DateComponents()
        components.calendar = Town.calendar
        components.timeZone = Town.timeZone
        components.year = 2026
        components.month = 8
        components.day = 10
        components.hour = minutes / 60
        components.minute = minutes % 60
        return Town.calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    static func item(
        startingAt minutes: Int,
        going: Int,
        end: Date? = nil,
        isAllDay: Bool = false,
        isMultiDay: Bool = false,
        category: EventCategory = .other,
        eyebrow: String? = nil
    ) -> DayItem {
        let start = instant(minutes: minutes)
        let event = UpcomingEvent(
            id: "test-\(minutes)-\(going)",
            title: "Patio trivia at Local Blend",
            eventDate: Town.day(start),
            startTime: nil,
            location: "Local Blend",
            goingCount: going,
            createdAt: "test",
            rsvpd: true,
            category: category,
            endAt: end,
            isAllDay: isAllDay
        )

        return DayItem(
            id: event.id,
            title: event.title,
            source: .committed,
            start: start,
            end: end,
            isAllDay: isAllDay,
            isMultiDay: isMultiDay,
            isComplete: false,
            eyebrow: eyebrow ?? resolvedEyebrow(
                start: start,
                isAllDay: isAllDay,
                isMultiDay: isMultiDay
            ),
            location: event.location,
            goingCount: going,
            event: event
        )
    }

    private static func resolvedEyebrow(
        start: Date,
        isAllDay: Bool,
        isMultiDay: Bool
    ) -> String {
        if isAllDay { return "Today · all day" }
        if isMultiDay { return "Today · ongoing" }

        let formatter = DateFormatter()
        formatter.calendar = Town.calendar
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = Town.timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: start)
    }
}
