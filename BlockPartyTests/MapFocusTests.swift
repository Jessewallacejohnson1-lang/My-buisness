//
//  MapFocusTests.swift
//  BlockPartyTests — the map's one owner of the open card and the camera (`MapFocus`, BP app
//  codebase-health 23): open then close lands level where the map is, recenter closes the card
//  in its one fly home, and a second bubble's card lifts that bubble with no move in between.
//  Pure values: no map is drawn.
//

import CoreLocation
import XCTest
@testable import BlockParty

@MainActor
final class MapFocusTests: XCTestCase {

    private let obbink = CLLocationCoordinate2D(latitude: 45.568417, longitude: -94.317459)
    private let sals = CLLocationCoordinate2D(latitude: 45.5644264, longitude: -94.320549)
    /// The camera where the map was left, zoomed in past the opening view.
    private let here = MapFocus.Camera(center: CLLocationCoordinate2D(latitude: 45.566, longitude: -94.319), zoom: 15.2)
    /// An iPhone 17 Pro's width: the card's photo is (402 − 40) × 198.6 / 352.7 tall.
    private let width: CGFloat = 402

    private func bubble(_ id: String, at spot: CLLocationCoordinate2D) -> TodayBubble {
        let card = FeedCardItem(id: id, title: id, dateChip: "", metaLine: "", image: .fallback, recurrence: nil,
                                goingCount: 0, goingAvatars: [], likeCount: 0, isLiked: false, isSaved: false,
                                isJoined: false)
        return TodayBubble(id: "\(spot.latitude),\(spot.longitude)", coordinate: spot, events: [card])
    }

    func testOpeningLiftsTheBubbleAboveTheCardAtTodaysZoom() {
        var focus = MapFocus()
        let benedicta = bubble("reflection", at: obbink)
        focus.page = 2

        let move = focus.open(benedicta, from: here, mapWidth: width)

        XCTAssertEqual(focus.selectedID, benedicta.id)
        XCTAssertEqual(focus.page, 0, "a card opens on its first page")
        XCTAssertEqual(move.center.latitude, obbink.latitude)
        XCTAssertEqual(move.center.longitude, obbink.longitude)
        XCTAssertEqual(move.zoom, 15.2, "opening keeps the zoom")
        XCTAssertNil(move.bearing, "opening keeps the turn")
        XCTAssertNil(move.pitch, "opening keeps the tilt")
        XCTAssertEqual(move.lift, (402 - 40) * 198.6 / 352.7 + 110 + 55, accuracy: 0.001)
        XCTAssertEqual(move.glide, .settle)
    }

    func testOpenThenCloseLandsOnTheLevelCamera() {
        var focus = MapFocus()
        _ = focus.open(bubble("reflection", at: obbink), from: here, mapWidth: width)
        // The open move landed: the map now reports the lifted bubble at the centre.
        let lifted = MapFocus.Camera(center: obbink, zoom: here.zoom)

        let move = focus.close(from: lifted)

        XCTAssertNil(focus.selectedID)
        XCTAssertEqual(move, MapFocus.Move(center: obbink, zoom: 15.2, bearing: nil, pitch: nil, lift: 0, glide: .settle),
                       "closing settles where the map is, with no lift left shoving it up")
    }

    func testHomeThenCloseMakesNoStrayMove() {
        var focus = MapFocus()
        _ = focus.open(bubble("reflection", at: obbink), from: here, mapWidth: width)

        let home = focus.home()

        XCTAssertNil(focus.selectedID, "recenter closes the card")
        XCTAssertEqual(home, MapFocus.Move(center: MapSpots.center, zoom: SJMapView.openZoom, bearing: nil, pitch: nil,
                                           lift: 0, glide: .home))
        // A tap on the map mid-fly: no card is up, so nothing pulls the camera back.
        XCTAssertNil(focus.close(from: here), "a close after home would fight the fly home")
    }

    func testATownSpotToAnotherBubbleDoesNotFightTheLift() {
        var focus = MapFocus()
        let benedicta = bubble("reflection", at: obbink)
        let salsBar = bubble("raffle", at: sals)
        let first = focus.open(benedicta, from: here, mapWidth: width)

        // The second tap goes straight to the second bubble: one move, lifted the same,
        // and no close in between to drop the map level first.
        let second = focus.open(salsBar, from: MapFocus.Camera(center: obbink, zoom: here.zoom), mapWidth: width)

        XCTAssertEqual(focus.selectedID, salsBar.id)
        XCTAssertEqual(second.center.latitude, sals.latitude)
        XCTAssertEqual(second.center.longitude, sals.longitude)
        XCTAssertEqual(second.lift, first.lift)
        XCTAssertEqual(second.glide, .settle)
    }

    func testAMergedBubbleKeepsTheCardWithoutAMove() {
        var focus = MapFocus()
        _ = focus.open(bubble("reflection", at: obbink), from: here, mapWidth: width)
        focus.page = 1
        let merged = bubble("reflection", at: sals)

        focus.follow(merged)

        XCTAssertEqual(focus.selectedID, merged.id)
        XCTAssertEqual(focus.page, 1, "the card stays on the page it was on")
    }

    func testTheCompassLevelsInPlaceAndLeavesTheCard() {
        var focus = MapFocus()
        let benedicta = bubble("reflection", at: obbink)
        _ = focus.open(benedicta, from: here, mapWidth: width)

        let move = focus.level(from: here)

        XCTAssertEqual(focus.selectedID, benedicta.id)
        XCTAssertEqual(move, MapFocus.Move(center: here.center, zoom: 15.2, bearing: 0, pitch: 0, lift: 0, glide: .level))
    }
}
