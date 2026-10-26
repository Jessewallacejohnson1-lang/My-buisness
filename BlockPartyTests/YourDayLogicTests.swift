//
//  YourDayLogicTests.swift
//  Block PartyTests — the town-time rules left from Your Day: the free-text time
//  parse, the town-day parse and the realtime relevance filter. The rail, day sheet
//  and completion tests went with that code on 2026-10-25 (GUTTING-LEDGER.md).
//

import Foundation
import XCTest
@testable import BlockParty

final class YourDayLogicTests: XCTestCase {

    // MARK: - Realtime relevance

    /// A fixed May instant, safely away from any DST boundary, so ±day math
    /// lands on the expected town dates.
    private static let realtimeNow = Date(timeIntervalSince1970: 2_000_000_000)

    @MainActor
    private func change(
        _ kind: RealtimeClient.Change.Kind,
        new: RealtimeClient.Change.Row? = nil,
        old: RealtimeClient.Change.Row? = nil
    ) -> RealtimeClient.Change {
        RealtimeClient.Change(kind: kind, new: new, old: old)
    }

    @MainActor
    private func row(
        id: String = "e1", date: String?, kind: String? = "event"
    ) -> RealtimeClient.Change.Row {
        RealtimeClient.Change.Row(
            id: id, eventDate: date, startTime: nil, status: "approved",
            kind: kind, title: nil, location: nil
        )
    }

    @MainActor
    func testInsertRelevanceMatchesTheCandidateWindow() {
        let now = Self.realtimeNow
        let today = Town.day(now)
        let withinLookback = Town.day(now.addingTimeInterval(-3 * 86_400))
        let tomorrow = Town.day(now.addingTimeInterval(86_400))
        let beyondLookback = Town.day(
            now.addingTimeInterval(-Double(CommunityAPI.dayLookbackDays + 1) * 86_400)
        )

        func relevant(_ c: RealtimeClient.Change) -> Bool {
            YourDayLogic.changeIsRelevant(c, shownIDs: [], now: now)
        }

        XCTAssertTrue(relevant(change(.insert, new: row(date: today))))
        // A multi-day row dated within the lookback can still overlap today.
        XCTAssertTrue(relevant(change(.insert, new: row(date: withinLookback))))
        XCTAssertFalse(relevant(change(.insert, new: row(date: tomorrow))))
        XCTAssertFalse(relevant(change(.insert, new: row(date: beyondLookback))))
        XCTAssertFalse(relevant(change(.insert, new: row(date: today, kind: "trail"))))
        XCTAssertFalse(relevant(change(.insert, new: row(date: nil))))
    }

    @MainActor
    func testUpdateIsRelevantWhenItTouchesTheWindowOrAShownItem() {
        let now = Self.realtimeNow
        let tomorrow = Town.day(now.addingTimeInterval(86_400))

        // An edit that moves a shown event OFF today must still re-sync,
        // matched by id — the new row itself no longer touches the window.
        XCTAssertTrue(YourDayLogic.changeIsRelevant(
            change(.update, new: row(id: "shown", date: tomorrow)),
            shownIDs: ["shown"], now: now
        ))
        XCTAssertFalse(YourDayLogic.changeIsRelevant(
            change(.update, new: row(id: "other", date: tomorrow)),
            shownIDs: ["shown"], now: now
        ))
        // The approval UPDATE of a pending event counts — status is not checked.
        XCTAssertTrue(YourDayLogic.changeIsRelevant(
            change(.update, new: row(id: "new", date: Town.day(now))),
            shownIDs: [], now: now
        ))
    }

    @MainActor
    func testDeleteMatchesByShownIdOnly() {
        let now = Self.realtimeNow
        // A DELETE's old_record carries only the primary key.
        XCTAssertTrue(YourDayLogic.changeIsRelevant(
            change(.delete, old: row(id: "shown", date: nil, kind: nil)),
            shownIDs: ["shown"], now: now
        ))
        XCTAssertFalse(YourDayLogic.changeIsRelevant(
            change(.delete, old: row(id: "gone-long-ago", date: nil, kind: nil)),
            shownIDs: ["shown"], now: now
        ))
        XCTAssertFalse(YourDayLogic.changeIsRelevant(
            change(.delete),
            shownIDs: ["shown"], now: now
        ))
    }
}
