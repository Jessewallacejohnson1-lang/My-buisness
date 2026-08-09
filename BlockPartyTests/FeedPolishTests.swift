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
