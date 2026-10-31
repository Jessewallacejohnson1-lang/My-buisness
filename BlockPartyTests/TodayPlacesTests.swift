//
//  TodayPlacesTests.swift
//  BlockPartyTests — where each of today's events sits on the map (`TodayPlaces`, BP app
//  map-reset): one bubble per real spot, the one on now in front, events with no spot off the
//  map, touching bubbles merged, and the day over only when every event is.
//

import CoreLocation
import XCTest
@testable import BlockParty

@MainActor
final class TodayPlacesTests: XCTestCase {

    private let day = "2026-10-30"
    private func at(_ hour: Double) -> Date { Town.midnight(day)!.addingTimeInterval(hour * 3600) }
    private func event(_ id: String, _ time: String? = "7 PM", end: Double? = nil) -> FeedCardItem {
        var card = FeedCardItem(id: id, title: id, dateChip: "", metaLine: "", image: .fallback, recurrence: nil,
                                goingCount: 0, goingAvatars: [], likeCount: 0, isLiked: false, isSaved: false, isJoined: false)
        card.eventDate = day
        card.startTime = time
        card.endAt = end.map(at)
        return card
    }
    private let obbink = CLLocationCoordinate2D(latitude: 45.568417, longitude: -94.317459)
    private let sals = CLLocationCoordinate2D(latitude: 45.5644264, longitude: -94.320549)

    /// Friday Oct 30 at 6:20 PM: two events at Benedicta (one on, one at 7:30) share a bubble with
    /// the one on now in front; Sal's raffle is on; the 11 AM jewelry party is over; the
    /// volleyball game has no spot.
    func testOneBubblePerSpotOnNowFirstEndedAndSpotlessOff() {
        let bac = CLLocationCoordinate2D(latitude: 45.5612, longitude: -94.3183)
        let places = TodayPlaces(
            events: [event("workshop", "7:30 PM", end: 20.5), event("raffle", "5 PM", end: 19),
                     event("reflection", "10 AM", end: 21), event("jewelry", "11 AM", end: 17),
                     event("volleyball", "7 PM")],
            spots: ["workshop": bac, "reflection": bac, "raffle": sals,
                    "jewelry": CLLocationCoordinate2D(latitude: 45.5647, longitude: -94.3201)])
        let bubbles = places.bubbles(now: at(18 + 20.0 / 60))
        XCTAssertEqual(bubbles.map { $0.events.map(\.id) }, [["reflection", "workshop"], ["raffle"]],
                       "soonest first, the one on now in front, the ended and the spotless off")
        XCTAssertEqual(bubbles.map(\.order), [0, 1])
        XCTAssertEqual(bubbles[0].event.id, "reflection")
    }

    /// Bubbles closer on screen than a bead merge into the first; the rest stay apart.
    func testTouchingBubblesMergeAndPageThroughAllTheirEvents() {
        let places = TodayPlaces(events: [event("bingo", "6 PM"), event("raffle", "5 PM", end: 19), event("lecture", "8 PM")],
                                 spots: ["bingo": obbink, "raffle": sals,
                                         "lecture": CLLocationCoordinate2D(latitude: 45.58, longitude: -94.39)])
        let now = at(18.5)
        let bubbles = places.bubbles(now: now)
        XCTAssertEqual(bubbles.map(\.event.id), ["raffle", "bingo", "lecture"])
        let merged = TodayPlaces.merge(bubbles, at: [CGPoint(x: 100, y: 100), CGPoint(x: 130, y: 110), CGPoint(x: 300, y: 500)],
                                       within: 46, now: now)
        XCTAssertEqual(merged.map { $0.events.map(\.id) }, [["raffle", "bingo"], ["lecture"]])
        XCTAssertEqual(merged[0].id, bubbles[0].id, "the merged bubble keeps the earliest one's spot")
        XCTAssertEqual(TodayPlaces.merge(bubbles, at: [CGPoint(x: 100, y: 100), CGPoint(x: 150, y: 100), CGPoint(x: 300, y: 500)],
                                         within: 46, now: now).count, 3, "46 pt apart still touches nothing")
    }

    /// "Nothing else today" waits for every event, spot or not: a day whose only event left has
    /// no spot isn't over.
    func testTheDayIsOverOnlyWhenEveryEventIs() {
        let places = TodayPlaces(events: [event("raffle", "5 PM", end: 19), event("volleyball", "7 PM")],
                                 spots: ["raffle": sals])
        XCTAssertFalse(places.dayIsOver(now: at(20)), "the volleyball game has no spot but isn't over")
        XCTAssertTrue(places.dayIsOver(now: at(21)))
        XCTAssertTrue(TodayPlaces.none.dayIsOver(now: at(9)), "a day with nothing says so too")
    }
}
