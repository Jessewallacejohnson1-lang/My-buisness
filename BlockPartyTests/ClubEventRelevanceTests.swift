//
//  ClubEventRelevanceTests.swift
//  BlockPartyTests — the one realtime "does this change matter" rule (`ClubEventRelevance`,
//  codebase-health 13): the map's today, and a window of days as a feed would pass.
//

import Foundation
import XCTest
@testable import BlockParty

@MainActor
final class ClubEventRelevanceTests: XCTestCase {

    /// A fixed May instant, safely away from any DST boundary, so ±day math
    /// lands on the expected town dates.
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private var today: String { Town.day(now) }
    private func day(_ offset: Int) -> String { Town.day(now.addingTimeInterval(Double(offset) * 86_400)) }

    private func change(_ kind: RealtimeClient.Change.Kind, new: RealtimeClient.Change.Row? = nil,
                        old: RealtimeClient.Change.Row? = nil) -> RealtimeClient.Change {
        RealtimeClient.Change(kind: kind, new: new, old: old)
    }

    private func row(id: String = "e1", date: String?, kind: String? = "event") -> RealtimeClient.Change.Row {
        RealtimeClient.Change.Row(id: id, eventDate: date, startTime: nil, status: "approved",
                                  kind: kind, title: nil, location: nil)
    }

    /// The map passes today alone: tomorrow's or last week's rows don't make it read again.
    func testTheMapsTodayOnly() {
        func matters(_ c: RealtimeClient.Change, shown: Set<String> = []) -> Bool {
            ClubEventRelevance.matters(c, shownIDs: shown, days: today...today)
        }
        XCTAssertTrue(matters(change(.insert, new: row(date: today))))
        XCTAssertFalse(matters(change(.insert, new: row(date: day(1)))))
        XCTAssertFalse(matters(change(.insert, new: row(date: day(-3)))))
        XCTAssertFalse(matters(change(.insert, new: row(date: today, kind: "trail"))), "trails never map")
        XCTAssertTrue(matters(change(.update, new: row(id: "on-map", date: day(1))), shown: ["on-map"]),
                      "moved off today, still re-read")
    }

    func testInsertMatchesTheWindow() {
        let window = day(-CommunityAPI.dayLookbackDays)...today
        func matters(_ c: RealtimeClient.Change) -> Bool {
            ClubEventRelevance.matters(c, shownIDs: [], days: window)
        }
        XCTAssertTrue(matters(change(.insert, new: row(date: today))))
        // A multi-day row dated within the lookback can still overlap today.
        XCTAssertTrue(matters(change(.insert, new: row(date: day(-3)))))
        XCTAssertFalse(matters(change(.insert, new: row(date: day(1)))))
        XCTAssertFalse(matters(change(.insert, new: row(date: day(-CommunityAPI.dayLookbackDays - 1)))))
        XCTAssertFalse(matters(change(.insert, new: row(date: today, kind: "trail"))))
        XCTAssertFalse(matters(change(.insert, new: row(date: nil))))
    }

    func testUpdateMattersWhenItTouchesTheDaysOrAShownItem() {
        let days = today...today
        // An edit that moves a shown event OFF today must still re-sync,
        // matched by id — the new row itself no longer touches the window.
        XCTAssertTrue(ClubEventRelevance.matters(change(.update, new: row(id: "shown", date: day(1))),
                                                 shownIDs: ["shown"], days: days))
        XCTAssertFalse(ClubEventRelevance.matters(change(.update, new: row(id: "other", date: day(1))),
                                                  shownIDs: ["shown"], days: days))
        // The approval UPDATE of a pending event counts — status is not checked.
        XCTAssertTrue(ClubEventRelevance.matters(change(.update, new: row(id: "new", date: today)),
                                                 shownIDs: [], days: days))
    }

    func testDeleteMatchesByShownIdOnly() {
        let days = today...today
        // A DELETE's old_record carries only the primary key.
        XCTAssertTrue(ClubEventRelevance.matters(change(.delete, old: row(id: "shown", date: nil, kind: nil)),
                                                 shownIDs: ["shown"], days: days))
        XCTAssertFalse(ClubEventRelevance.matters(change(.delete, old: row(id: "gone", date: nil, kind: nil)),
                                                  shownIDs: ["shown"], days: days))
        XCTAssertFalse(ClubEventRelevance.matters(change(.delete), shownIDs: ["shown"], days: days))
    }
}
