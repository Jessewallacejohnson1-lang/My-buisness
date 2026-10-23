import XCTest
@testable import BlockParty

/// The rules behind the map's today bubbles (TodayBubbles.swift): when an event counts
/// down, is on, or has ended; how the countdown reads; how much ring is left; which event
/// a place's bubble shows; and how far the squishy drag can pull.
@MainActor
final class TodayBubblesTests: XCTestCase {
    private func ev(_ id: String, _ start: String?) -> TimelineEvent {
        TimelineEvent(id: id, title: id, startTime: start, location: nil, clubName: nil, fromJoinedClub: false)
    }
    private let sevenPM = 19 * 3600

    func testPhaseCountsDownThenIsOnForTwoHoursThenEnds() {
        XCTAssertEqual(TodayBubbleRules.phase(startTime: "7 PM", now: sevenPM - 600), .upcoming(secondsLeft: 600))
        XCTAssertEqual(TodayBubbleRules.phase(startTime: "7 PM", now: sevenPM), .live)
        XCTAssertEqual(TodayBubbleRules.phase(startTime: "7 PM", now: sevenPM + 2 * 3600), .live)
        XCTAssertEqual(TodayBubbleRules.phase(startTime: "7 PM", now: sevenPM + 2 * 3600 + 60), .ended)
        XCTAssertEqual(TodayBubbleRules.phase(startTime: nil, now: sevenPM), .untimed)
        XCTAssertEqual(TodayBubbleRules.phase(startTime: "All day", now: sevenPM), .untimed)
    }

    func testCountdownReadsHoursThenMinutesAndSeconds() {
        XCTAssertEqual(TodayBubbleRules.countdown(5 * 3600 + 3 * 60 + 59), "5h 03m")
        XCTAssertEqual(TodayBubbleRules.countdown(3600), "1h 00m")
        XCTAssertEqual(TodayBubbleRules.countdown(3599), "59:59")
        XCTAssertEqual(TodayBubbleRules.countdown(485), "8:05")
        XCTAssertEqual(TodayBubbleRules.countdown(-3), "0:00")
    }

    func testVoiceOverSaysTheCountdownInWords() {
        XCTAssertEqual(TodayBubbleRules.spokenCountdown(37 * 60 + 30), "37 minutes")
        XCTAssertEqual(TodayBubbleRules.spokenCountdown(3600 + 23 * 60), "1 hour 23 minutes")
        XCTAssertEqual(TodayBubbleRules.spokenCountdown(2 * 3600 + 30), "2 hours")
        XCTAssertEqual(TodayBubbleRules.spokenCountdown(61), "1 minute")
        XCTAssertEqual(TodayBubbleRules.spokenCountdown(20), "under a minute")
    }

    func testRingOnlyInTheLastHourAndEmptiesToTheStart() {
        XCTAssertNil(TodayBubbleRules.ringLeft(3601))
        XCTAssertEqual(TodayBubbleRules.ringLeft(3600), 1)
        XCTAssertEqual(TodayBubbleRules.ringLeft(1800)!, 0.5, accuracy: 0.0001)
        XCTAssertEqual(TodayBubbleRules.ringLeft(0), 0)
    }

    func testLeadPrefersOnNowThenNextToStartAndDropsEnded() {
        let morning = ev("morning", "9 AM"), on = ev("on", "6 PM"), next = ev("next", "8 PM"), later = ev("later", "9 PM")
        XCTAssertEqual(TodayBubbleRules.lead([later, next, on, morning], now: sevenPM)?.id, "on")
        XCTAssertEqual(TodayBubbleRules.lead([later, next, morning], now: sevenPM)?.id, "next")
        XCTAssertNil(TodayBubbleRules.lead([morning], now: sevenPM))
        XCTAssertEqual(TodayBubbleRules.lead([morning, ev("allday", nil)], now: sevenPM)?.id, "allday")
    }

    func testDragFollowsThenResistsAndStretchIsCapped() {
        XCTAssertEqual(TodayBubbleRules.rubber(0), 0)
        XCTAssertLessThan(TodayBubbleRules.rubber(10), 10)
        XCTAssertLessThan(TodayBubbleRules.rubber(1000), 23)            // a 40 pt drag moves it about 11 pt
        XCTAssertEqual(TodayBubbleRules.rubber(100), 16.22, accuracy: 0.05)
        XCTAssertEqual(TodayBubbleRules.rubber(-40), -TodayBubbleRules.rubber(40), accuracy: 0.0001)
        XCTAssertEqual(TodayBubbleRules.stretch(distance: 11, speed: 0), 0.1, accuracy: 0.0001)
        XCTAssertEqual(TodayBubbleRules.stretch(distance: 12, speed: 4000), 0.13)
    }

    func testClemensLibraryEventsLandAtSaintBens() {
        XCTAssertNotNil(KnownVenues.coordinate(for: "Clemens Library"))
        XCTAssertTrue(MapSpots.all.first { $0.id == "saintbens" }!.keywords.contains("clemens"))
    }
}
