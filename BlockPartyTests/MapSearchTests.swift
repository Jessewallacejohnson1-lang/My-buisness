//
//  MapSearchTests.swift
//  BlockPartyTests — the map search's pure matcher (MapSearch) and the shared
//  distance formatter (MapDistance), map polish Phase 2.
//
//  Everything here is deterministic and offline: hand-built spots/POIs/events,
//  no network, no MapModel. The view-layer behavior (spring expansion, keyboard,
//  fly-and-open) is verified by simulator screenshots, not here.
//

import XCTest
import CoreLocation
@testable import BlockParty

@MainActor
final class MapSearchTests: XCTestCase {

    // MARK: Fixtures

    private func spot(_ id: String, _ name: String) -> Spot {
        Spot(id: id, name: name, category: .park,
             coordinate: .init(latitude: 45.56, longitude: -94.31),
             keywords: [id], blurb: nil)
    }

    private func poi(_ name: String, primaryType: String? = nil,
                     family: PlaceFamily = .food) -> POI {
        POI(id: name.lowercased(), placeId: nil, name: name,
            lat: 45.561, lon: -94.312, family: family,
            primaryType: primaryType, types: [], address: nil, logoUrl: nil)
    }

    private func event(_ title: String, location: String? = nil,
                       category: EventCategory = .other) -> TimelineEvent {
        TimelineEvent(id: title, title: title, startTime: nil, location: location,
                      goingCount: 0, rsvpd: false, clubName: nil,
                      fromJoinedClub: false, details: nil, category: category)
    }

    private func results(_ query: String,
                         spots: [Spot] = [],
                         pois: [POI] = [],
                         events: [TimelineEvent] = [],
                         spotFor: (TimelineEvent) -> Spot? = { _ in nil }) -> [MapSearchResult] {
        MapSearch.results(query: query, spots: spots, pois: pois,
                          events: events, spotFor: spotFor)
    }

    // MARK: Matcher

    func testEmptyOrWhitespaceQueryReturnsNothing() {
        // Arrange
        let spots = [spot("millstream", "Millstream Park")]

        // Act + Assert
        XCTAssertTrue(results("", spots: spots).isEmpty)
        XCTAssertTrue(results("   ", spots: spots).isEmpty)
    }

    func testMatchingIsCaseAndDiacriticInsensitive() {
        // Arrange
        let pois = [poi("Café Renée")]

        // Act
        let lowercasePlain = results("cafe renee", pois: pois)
        let uppercaseAccented = results("CAFÉ", pois: pois)

        // Assert
        XCTAssertEqual(lowercasePlain.map(\.name), ["Café Renée"])
        XCTAssertEqual(uppercaseAccented.map(\.name), ["Café Renée"])
    }

    func testNamePrefixRanksBeforeSubstring() {
        // Arrange — catalogue order deliberately puts the substring match first.
        let spots = [
            spot("mill", "Mill Creek Park"),      // "creek" is a substring
            spot("creekside", "Creekside Cafe"),  // "creek" is the name's prefix
        ]

        // Act
        let matches = results("creek", spots: spots)

        // Assert — prefix match lists first despite catalogue order.
        XCTAssertEqual(matches.map(\.name), ["Creekside Cafe", "Mill Creek Park"])
    }

    func testCategoryMatchesListAfterNameMatches() {
        // Arrange — "coffee" is in one name, and in another POI's primaryType.
        let pois = [
            poi("Local Blend", primaryType: "coffee_shop"),
            poi("Coffee Corner", primaryType: "cafe"),
        ]

        // Act
        let matches = results("coffee", pois: pois)

        // Assert — the name match outranks the category (primaryType) match.
        XCTAssertEqual(matches.map(\.name), ["Coffee Corner", "Local Blend"])
    }

    func testEventResolvesToItsSpotPin() {
        // Arrange
        let millstream = spot("millstream", "Millstream Park")
        let concert = event("Millstream Concert", location: "Millstream Park")

        // Act
        let matches = results("concert", events: [concert], spotFor: { _ in millstream })

        // Assert — the row flies to the SPOT's pin and carries it for the commit.
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].coordinate?.latitude, millstream.coordinate.latitude)
        guard case .event(_, let pin) = matches[0].target else {
            return XCTFail("expected an event target")
        }
        XCTAssertEqual(pin?.id, "millstream")
    }

    func testEventWithNoPinHasNoCoordinate() {
        // Arrange
        let potluck = event("Neighborhood Potluck", location: "A backyard")

        // Act
        let matches = results("potluck", events: [potluck], spotFor: { _ in nil })

        // Assert — no invented coordinate; the commit path flies home instead.
        XCTAssertEqual(matches.count, 1)
        XCTAssertNil(matches[0].coordinate)
    }

    func testEventGetsItsEventGlyph() {
        // Arrange
        let hike = event("Group Hike", category: .outdoors)

        // Act
        let matches = results("hike", events: [hike])

        // Assert
        XCTAssertEqual(matches.map(\.glyph), [EventCategory.outdoors.glyph])
    }

    // MARK: Empty-state copy

    func testEmptySentenceNamesTheTownAndStaysCalm() {
        // Act
        let sentence = MapSearch.emptySentence(town: "Saint Joseph")

        // Assert — a complete sentence in the brand voice, no exclamation.
        XCTAssertEqual(sentence, "Nothing in Saint Joseph matches that yet.")
        XCTAssertFalse(sentence.contains("!"))
        XCTAssertTrue(sentence.hasSuffix("."))
    }

    // MARK: Distance formatter (extracted from MapPlaceDetail.distanceLabel)

    func testDistanceFormatterMatchesTheDetailMorphStyle() {
        // Assert — under 30 m is noise; feet round to 50s; miles to a tenth.
        XCTAssertNil(MapDistance.label(meters: 20))
        XCTAssertEqual(MapDistance.label(meters: 100), "350 ft")
        XCTAssertEqual(MapDistance.label(meters: 45), "150 ft")
        XCTAssertEqual(MapDistance.label(meters: 5_000), "3.1 mi")
        XCTAssertEqual(MapDistance.label(meters: 32_187), "20 mi")
    }
}
