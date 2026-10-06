//
//  ReviewQueueTests.swift
//  The admin Review queue's row formatting and its decline reasons (ADR-021).
//

import XCTest
@testable import BlockParty

final class ReviewQueueTests: XCTestCase {

    func testDateTileReadsTheEventDate() {
        let tile = ReviewRow.tile("2026-10-12")
        XCTAssertEqual(tile?.day, "12")
        XCTAssertEqual(tile?.month, Calendar.current.shortMonthSymbols[9].uppercased())
        XCTAssertNil(ReviewRow.tile(nil), "a trail has no date, so its tile shows a symbol")
        XCTAssertNil(ReviewRow.tile("2026-13-01"))
    }

    func testSubtitleIsWhenThenWho() {
        XCTAssertEqual(ReviewRow.subtitle(startTime: "6 PM", allDay: false, sourceName: "City of St. Joseph",
                                          location: "St. Joseph MN 56374"), "6 PM · City of St. Joseph")
        XCTAssertEqual(ReviewRow.subtitle(startTime: nil, allDay: true, sourceName: "City of St. Joseph",
                                          location: nil), "All day · City of St. Joseph")
        // A neighbour's post has no source: where it is stands in for who announced it.
        XCTAssertEqual(ReviewRow.subtitle(startTime: "7 PM", allDay: false, sourceName: nil,
                                          location: "Klinefelter Park"), "7 PM · Klinefelter Park")
        XCTAssertEqual(ReviewRow.subtitle(startTime: nil, allDay: false, sourceName: nil, location: nil), "")
    }

    /// The City's feeds once gave a relative path back to the feed; SFSafariViewController
    /// throws on anything but a web page, so such a link must not reach it.
    func testOnlyWebPagesOpen() {
        XCTAssertNotNil(ReviewRow.webURL("https://www.stjosephmn.gov/Calendar.aspx?EID=2447"))
        XCTAssertNil(ReviewRow.webURL("/common/modules/iCalendar/iCalendar.aspx?feed=calendar&catID=25"))
        XCTAssertNil(ReviewRow.webURL("mailto:clerk@stjosephmn.gov"))
        XCTAssertNil(ReviewRow.webURL(nil))
    }

    /// The database's check constraint accepts exactly these values.
    func testDeclineReasonsMatchTheDatabase() {
        XCTAssertEqual(DeclineReason.allCases.map(\.rawValue),
                       ["not_event", "wrong_when", "wrong_place", "wrong_title", "other"])
    }
}
