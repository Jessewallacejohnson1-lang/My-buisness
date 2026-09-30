//
//  DailyPageTests.swift
//  BlockPartyTests — the Daily tab's date line turns over at the Town's midnight, not
//  the phone's: Daily is "today in the Town" wherever the neighbour happens to be.
//

import XCTest
@testable import BlockParty

final class DailyPageTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    /// 04:30 UTC on Oct 1 is 11:30 PM on Sept 30 in St. Joseph (CDT, UTC−5).
    func testDateLineIsStillTheTownsDayBeforeMidnight() {
        let lateEvening = Date(timeIntervalSince1970: 1_790_829_000) // 2026-10-01 04:30 UTC
        XCTAssertEqual(DailyDateLine.label(for: lateEvening, locale: english), "WEDNESDAY, SEPTEMBER 30")
    }

    /// One hour later it is 12:30 AM on Oct 1 in town: the line has turned over.
    func testDateLineTurnsOverAtTheTownsMidnight() {
        let justAfter = Date(timeIntervalSince1970: 1_790_832_600) // 2026-10-01 05:30 UTC
        XCTAssertEqual(DailyDateLine.label(for: justAfter, locale: english), "THURSDAY, OCTOBER 1")
    }

    /// A release build has no Spotlight until the read exists, so Daily keeps its
    /// placeholder instead of an invented story; DEBUG shows the sample.
    func testSpotlightIsTheSampleOnlyInDebug() {
        #if DEBUG
        XCTAssertEqual(DailySpotlight.today, DailySpotlight.sample)
        XCTAssertEqual(DailySpotlight.sample.photos.count, 2, "both sample photos are bundled")
        #else
        XCTAssertNil(DailySpotlight.today)
        #endif
    }
}
