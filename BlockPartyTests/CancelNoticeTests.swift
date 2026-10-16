//
//  CancelNoticeTests.swift
//  BlockPartyTests — an Event called off (BP app docs/plans/watch-every-place, ticket 12):
//  the reads say so, the people Going are told once, it leaves the You tab, and back on its
//  schedule it is an Event like any other again.
//

import XCTest
@testable import BlockParty

@MainActor
final class CancelNoticeTests: XCTestCase {
    private var keep: UserDefaults!
    /// Before every sample Event: Thursday 2026-10-15, noon in the Town.
    private let now = DateHelpers.timestamp("2026-10-15T17:00:00Z")!

    override func setUp() {
        super.setUp()
        keep = UserDefaults(suiteName: "CancelNoticeTests")
        keep.removePersistentDomain(forName: "CancelNoticeTests")
    }

    private func event(_ id: String, cancelled: Bool, day: String = "2026-10-20",
                       time: String? = "7 PM") -> UpcomingEvent {
        UpcomingEvent(id: id, title: id, eventDate: day, startTime: time, location: "ROCORI High School",
                      goingCount: 1, createdAt: "", rsvpd: true, cancelled: cancelled)
    }

    // MARK: The reads

    func testTheReadsSayWhichAreCalledOffAndOlderRowsAreOn() throws {
        let feed = """
        [{"id":"e1","title":"Sartell Volleyball vs ROCORI","event_date":"2026-10-20","start_time":"7 PM",
          "location":null,"image_url":null,"category":null,"club_name":null,"source_name":"ROCORI High School",
          "end_at":null,"all_day":false,"created_at":"2026-10-06T16:08:20+00:00","going_count":0,
          "rsvpd":false,"recurrence":null,"leaves_at":"2026-10-21T02:00:00+00:00","cancelled":true},
         {"id":"e2","title":"Bake sale","event_date":"2026-10-21","start_time":null,
          "location":null,"image_url":null,"category":null,"club_name":null,"source_name":"City of St. Joseph",
          "end_at":null,"all_day":false,"created_at":"2026-10-06T16:08:20+00:00","going_count":0,
          "rsvpd":false,"recurrence":null,"leaves_at":"2026-10-22T05:00:00+00:00"}]
        """
        let rows = try CommunityAPI.townFeedRows(from: Data(feed.utf8))
        XCTAssertEqual(rows.map(\.event.cancelled), [true, false], "a kept list from before says nothing: on")
        XCTAssertEqual(rows.map { TownFeed.entry($0).card.cancelled }, [true, false])

        let going = """
        [{"id":"e1","title":"Sartell Volleyball vs ROCORI","event_date":"2026-10-20","start_time":"7 PM",
          "location":null,"image_url":null,"category":null,"club_name":null,"source_name":"ROCORI High School",
          "end_at":null,"all_day":false,"created_at":"2026-10-06T16:08:20+00:00","going_count":1,"cancelled":true}]
        """
        XCTAssertEqual(try CommunityAPI.myGoingRows(from: Data(going.utf8)).map(\.cancelled), [true])
    }

    // MARK: The You tab

    /// Jesse, 2026-10-15: a called-off Event leaves the Agenda and the Calendar (and Saved);
    /// back on its schedule, it comes back.
    func testCalledOffLeavesTheYouTabAndComesBackWhenOn() {
        let first = YouCalendar.firstDay(of: DateHelpers.timestamp("2026-10-20T17:00:00Z")!)
        func going(_ events: [UpcomingEvent]) -> [String] {
            YouCalendar.going(read: events.compactMap(YouCalendar.event(from:)), tapped: [],
                              isGoing: { _ in true }, first: first).map(\.id)
        }
        func saved(_ events: [UpcomingEvent]) -> [String] {
            YouCalendar.saved(read: events.compactMap(YouCalendar.event(from:)), tapped: [],
                              isSaved: { _ in true }, now: first).map(\.id)
        }
        let off = [event("game", cancelled: true), event("trivia", cancelled: false, day: "2026-10-21")]
        XCTAssertEqual(going(off), ["trivia"])
        XCTAssertEqual(saved(off), ["trivia"])
        let on = [event("game", cancelled: false), event("trivia", cancelled: false, day: "2026-10-21")]
        XCTAssertEqual(going(on), ["game", "trivia"])
        XCTAssertFalse(FeedCardItem(on[0]).cancelled, "back on its schedule: no tag, no grey")
    }

    // MARK: The alert

    func testToldOnceAndOnlyAfterOK() async {
        let rows = [event("game", cancelled: true), event("trivia", cancelled: false)]
        let notice = CancelNotice(read: { rows }, keep: keep)
        await notice.check(now: now)
        XCTAssertEqual(notice.showing.map(\.id), ["game"], "only the called-off one")

        // Opened again before OK (a sheet was up, the app was closed): still to tell.
        let again = CancelNotice(read: { rows }, keep: keep)
        await again.check(now: now)
        XCTAssertEqual(again.showing.map(\.id), ["game"])

        again.ok()
        XCTAssertTrue(again.showing.isEmpty)
        XCTAssertEqual(again.said.map(\.id), ["game"], "the fading alert keeps its words")
        await again.check(now: now)
        let later = CancelNotice(read: { rows }, keep: keep)
        await later.check(now: now)
        XCTAssertTrue(again.showing.isEmpty && later.showing.isEmpty, "told for good")
    }

    /// A school's schedule that drops a game, brings it back and drops it again tells no one
    /// twice: once per Event.
    func testCalledOffAgainIsNotToldTwice() async {
        var rows = [event("game", cancelled: true)]
        let notice = CancelNotice(read: { rows }, keep: keep)
        await notice.check(now: now)
        notice.ok()
        rows = [event("game", cancelled: false)]
        await notice.check(now: now)
        rows = [event("game", cancelled: true)]
        await notice.check(now: now)
        XCTAssertTrue(notice.showing.isEmpty)
    }

    func testAFailedReadTellsNothingAndAShownAlertStays() async {
        let failing = CancelNotice(read: { throw URLError(.notConnectedToInternet) }, keep: keep)
        await failing.check(now: now)
        XCTAssertTrue(failing.showing.isEmpty)

        var rows = [event("game", cancelled: true)]
        let notice = CancelNotice(read: { rows }, keep: keep)
        await notice.check(now: now)
        rows = [event("game", cancelled: true), event("hike", cancelled: true)]
        await notice.check(now: now)
        XCTAssertEqual(notice.showing.map(\.id), ["game"], "the alert up isn't swapped under the finger")

        // Left untold (it may have been behind a sheet): the next open asks again, with both.
        notice.away()
        await notice.check(now: now)
        XCTAssertEqual(notice.showing.map(\.id), ["game", "hike"])
    }

    /// One already over by the time the app opens isn't worth an alert.
    func testAnEventAlreadyOverIsNotTold() {
        let over = event("coffee", cancelled: true, day: "2026-10-15", time: "8 AM")
        let later = event("game", cancelled: true)
        XCTAssertEqual(CancelNotice.toTell([over, later], told: [], now: now).map(\.id), ["game"])
    }

    func testTheAlertNamesEachEventWithItsWhen() {
        let one = CancelNotice.toTell([event("Sartell Volleyball vs ROCORI", cancelled: true)], told: [], now: now)
        XCTAssertEqual(one.count, 1)
        XCTAssertEqual(CancelNotice.title(one), "Event canceled")
        let message = CancelNotice.message(one)
        XCTAssertTrue(message.hasPrefix("Sartell Volleyball vs ROCORI, "), message)
        XCTAssertTrue(message.hasSuffix("7\u{00A0}PM"), message)
        XCTAssertFalse(message.dropFirst("Sartell Volleyball vs ROCORI, ".count).contains(" "),
                       "the when stays on one line")

        let two = CancelNotice.toTell([event("game", cancelled: true), event("hike", cancelled: true, time: nil)],
                                      told: [], now: now)
        XCTAssertEqual(CancelNotice.title(two), "2 events canceled")
        XCTAssertEqual(CancelNotice.message(two).split(separator: "\n").count, 2)
    }
}
