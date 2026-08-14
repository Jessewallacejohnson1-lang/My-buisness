//
//  MapFilterChipsTests.swift
//  BlockPartyTests — the map filter chips' semantics (MapFilter) and the map
//  sheet's counted sentences (MapSheetCopy), map polish Phase 4.
//
//  Pure logic: which spots/POIs each chip includes — notably Events (the same
//  today/live resolution the pins use, passed in as a fact) and Saved (both
//  catalogs) — plus the sentence forms of the copy voice audit. The visual row
//  (glass chips, ink selection, cluster recount) is verified by screenshots.
//

import XCTest
@testable import BlockParty

final class MapFilterChipsTests: XCTestCase {

    // MARK: Chip titles + DEBUG flag mapping

    func testChipTitles() {
        XCTAssertEqual(MapFilter.allCases.map(\.title),
                       ["All", "Food", "Parks", "Events", "Saved"])
    }

    func testRawValuesMatchTheLaunchArgumentSpellings() {
        // `-map-filter <chip>` parses via the raw value — keep them lowercase words.
        XCTAssertEqual(MapFilter(rawValue: "food"), .food)
        XCTAssertEqual(MapFilter(rawValue: "parks"), .parks)
        XCTAssertEqual(MapFilter(rawValue: "events"), .events)
        XCTAssertEqual(MapFilter(rawValue: "saved"), .saved)
        XCTAssertEqual(MapFilter(rawValue: "all"), .all)
        XCTAssertNil(MapFilter(rawValue: "everything"))
    }

    // MARK: All

    func testAllIncludesEverySpotAndPOI() {
        for category: SpotCategory in [.park, .trail, .downtown, .coffee, .college, .chapel] {
            XCTAssertTrue(MapFilter.all.includesSpot(category: category,
                                                     hasEventToday: false,
                                                     isSaved: false))
        }
        XCTAssertTrue(MapFilter.all.includesPOI(family: .food, isSaved: false))
        XCTAssertTrue(MapFilter.all.includesPOI(family: .business, isSaved: false))
    }

    // MARK: Food

    func testFoodIncludesFoodPOIsAndCoffeeSpotsOnly() {
        XCTAssertTrue(MapFilter.food.includesPOI(family: .food, isSaved: false))
        XCTAssertFalse(MapFilter.food.includesPOI(family: .business, isSaved: false))
        XCTAssertTrue(MapFilter.food.includesSpot(category: .coffee,
                                                  hasEventToday: true, isSaved: true))
        XCTAssertFalse(MapFilter.food.includesSpot(category: .park,
                                                   hasEventToday: true, isSaved: true))
        XCTAssertFalse(MapFilter.food.includesSpot(category: .downtown,
                                                   hasEventToday: false, isSaved: false))
    }

    // MARK: Parks

    func testParksIncludesParkAndTrailSpotsOnly() {
        XCTAssertTrue(MapFilter.parks.includesSpot(category: .park,
                                                   hasEventToday: false, isSaved: false))
        XCTAssertTrue(MapFilter.parks.includesSpot(category: .trail,
                                                   hasEventToday: false, isSaved: false))
        XCTAssertFalse(MapFilter.parks.includesSpot(category: .downtown,
                                                    hasEventToday: true, isSaved: true))
        XCTAssertFalse(MapFilter.parks.includesSpot(category: .college,
                                                    hasEventToday: false, isSaved: false))
    }

    func testParksNeverIncludesPOIs() {
        // The POI catalog ships only the food/business families — no park POIs exist.
        XCTAssertFalse(MapFilter.parks.includesPOI(family: .food, isSaved: true))
        XCTAssertFalse(MapFilter.parks.includesPOI(family: .business, isSaved: true))
    }

    // MARK: Events — the same resolution the pins use

    func testEventsIncludesOnlySpotsThatResolveAnEventToday() {
        XCTAssertTrue(MapFilter.events.includesSpot(category: .downtown,
                                                    hasEventToday: true, isSaved: false))
        XCTAssertFalse(MapFilter.events.includesSpot(category: .downtown,
                                                     hasEventToday: false, isSaved: true))
        // Category is irrelevant — a park with a happening today qualifies.
        XCTAssertTrue(MapFilter.events.includesSpot(category: .park,
                                                    hasEventToday: true, isSaved: false))
    }

    func testEventsNeverIncludesPOIs() {
        // Events resolve to curated pins only (SJMapView.spot(for:)).
        XCTAssertFalse(MapFilter.events.includesPOI(family: .food, isSaved: true))
        XCTAssertFalse(MapFilter.events.includesPOI(family: .business, isSaved: true))
    }

    // MARK: Saved — both catalogs

    func testSavedIncludesSavedSpotsAndSavedPOIs() {
        XCTAssertTrue(MapFilter.saved.includesSpot(category: .chapel,
                                                   hasEventToday: false, isSaved: true))
        XCTAssertFalse(MapFilter.saved.includesSpot(category: .chapel,
                                                    hasEventToday: true, isSaved: false))
        XCTAssertTrue(MapFilter.saved.includesPOI(family: .business, isSaved: true))
        XCTAssertFalse(MapFilter.saved.includesPOI(family: .food, isSaved: false))
    }

    // MARK: MapSheetCopy — the counted sentences

    func testTodayCountSentenceSpellsOneAndKeepsNumerals() {
        XCTAssertEqual(MapSheetCopy.todayCountSentence(1), "One thing happening today.")
        XCTAssertEqual(MapSheetCopy.todayCountSentence(6), "6 things happening today.")
    }

    func testNowCountSentence() {
        XCTAssertEqual(MapSheetCopy.nowCountSentence(1), "One thing happening now.")
        XCTAssertEqual(MapSheetCopy.nowCountSentence(3), "3 things happening now.")
    }

    func testPullUpSentenceAgreesWithItsCount() {
        XCTAssertEqual(MapSheetCopy.pullUpSentence(1), "Pull up to see it.")
        XCTAssertEqual(MapSheetCopy.pullUpSentence(4), "Pull up to see them.")
    }

    func testPlacesCountSentence() {
        XCTAssertEqual(MapSheetCopy.placesCountSentence(1), "One place in town.")
        XCTAssertEqual(MapSheetCopy.placesCountSentence(6), "6 places in town.")
    }

    func testEveryCountedSentenceIsACompleteSentenceWithoutExclamation() {
        let sentences = [
            MapSheetCopy.todayCountSentence(1), MapSheetCopy.todayCountSentence(6),
            MapSheetCopy.nowCountSentence(1), MapSheetCopy.nowCountSentence(2),
            MapSheetCopy.pullUpSentence(1), MapSheetCopy.pullUpSentence(5),
            MapSheetCopy.placesCountSentence(1), MapSheetCopy.placesCountSentence(6),
        ]
        for sentence in sentences {
            XCTAssertTrue(sentence.hasSuffix("."), "Not a sentence: \(sentence)")
            XCTAssertFalse(sentence.contains("!"), "Exclamation point: \(sentence)")
            // The spec keeps the numeral past one ("6 things happening today."),
            // so a sentence may open with a digit instead of a capital.
            let first = sentence.first
            XCTAssertTrue(first?.isUppercase == true || first?.isNumber == true,
                          "No capital or numeral: \(sentence)")
        }
    }
}
