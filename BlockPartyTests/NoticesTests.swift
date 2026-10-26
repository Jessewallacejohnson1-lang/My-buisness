//
//  NoticesTests.swift
//  BlockPartyTests — an Event called off (BP app docs/plans/watch-every-place, ticket 12): the
//  reads say so, it leaves the You tab, and back on its schedule it is an Event like any other
//  again. Called off or moved, it goes into the bell's Notifications (school-activities 04): the
//  dot once per change, the words, the sections.
//

import XCTest
@testable import BlockParty

@MainActor
final class NoticesTests: XCTestCase {
    private var keep: UserDefaults!
    /// Before every sample Event: Thursday 2026-10-15, noon in the Town.
    private let now = DateHelpers.timestamp("2026-10-15T17:00:00Z")!

    override func setUp() {
        super.setUp()
        keep = UserDefaults(suiteName: "NoticesTests")
        keep.removePersistentDomain(forName: "NoticesTests")
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
        XCTAssertEqual(rows.map { TownFeed.card($0).cancelled }, [true, false])

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

    // MARK: Notifications

    private func notice(_ id: String, moved: Notice.Was? = nil, followed: String? = nil, day: String = "2026-10-20",
                        time: String? = "7 PM", place: String = "ROCORI High School", game: Game? = nil,
                        hoursAgo: Double = 2) -> Notice {
        var event = UpcomingEvent(id: id, title: id, eventDate: day, startTime: time, location: place,
                              goingCount: 1, createdAt: "", cancelled: moved == nil)
        event.game = game
        return Notice(event: event, changedAt: now - hoursAgo * 3600, movedFrom: moved, followed: followed,
                      followedLogo: nil)
    }

    private func game(_ teams: [String]) -> Game {
        let list = teams.map { #"{"name":"\#($0)","short":"\#($0)"}"# }.joined(separator: ",")
        return try! JSONDecoder().decode(Game.self, from: Data(#"{"sport":"Volleyball","teams":[\#(list)]}"#.utf8))
    }

    func testTheReadSaysWhatChanged() throws {
        let rows = """
        [{"id":"e1","title":"Kennedy Volleyball vs Sartell","event_date":"2026-10-20","start_time":"7 PM",
          "location":"Kennedy","image_url":null,"category":null,"club_name":null,"source_name":"Bound",
          "end_at":null,"all_day":false,"created_at":"2026-10-06T16:08:20+00:00","going_count":0,"going":false,
          "cancelled":false,"place_picture":null,"game":{"sport":"Volleyball","teams":[{"name":"Kennedy"},{"name":"Sartell"}]},
          "changed_at":"2026-10-15T15:00:00.123+00:00","moved_from":{"event_date":"2026-10-20","start_time":"6 PM","location":"Kennedy"},
          "followed":"Kennedy Volleyball","followed_logo":"https://x/k.png"},
         {"id":"e2","title":"Bake sale","event_date":"2026-10-21","start_time":null,"location":null,"image_url":null,
          "category":null,"club_name":null,"source_name":"City","end_at":null,"all_day":false,
          "created_at":"2026-10-06T16:08:20+00:00","going_count":3,"going":true,"cancelled":true,"place_picture":null,
          "game":{"oops":1},"changed_at":"2026-10-14T15:00:00+00:00","moved_from":null,"followed":null,"followed_logo":null}]
        """
        let notices = try CommunityAPI.changeRows(from: Data(rows.utf8))
        XCTAssertEqual(notices.count, 2, "a game that doesn't read costs nothing")
        XCTAssertEqual(notices[0].movedFrom?.startTime, "6 PM")
        XCTAssertEqual(notices[0].event.game?.teams.map(\.short), ["Kennedy", "Sartell"])
        XCTAssertEqual(notices[0].picture, URL(string: "https://x/k.png"))
        XCTAssertTrue(notices[1].cancelled)
        XCTAssertTrue(notices[1].event.rsvpd)
        XCTAssertNil(notices[1].event.game)
    }

    /// Jesse's words (2026-10-26): "Kennedy Volleyball · Tonight's game vs Sartell moved to 7 PM".
    func testTheWords() {
        let tonight = notice("g", moved: .init(eventDate: "2026-10-15", startTime: "6 PM", location: "Kennedy"),
                             followed: "Kennedy Volleyball", day: "2026-10-15", place: "Kennedy",
                             game: game(["Kennedy", "Sartell"]))
        XCTAssertEqual(tonight.name, "Kennedy Volleyball")
        XCTAssertEqual(tonight.words(now: now), "Tonight's game vs Sartell moved to 7 PM.")

        let place = notice("p", moved: .init(eventDate: "2026-10-17", startTime: "7 PM", location: "Kennedy"),
                           followed: "Kennedy Volleyball", day: "2026-10-17", place: "Sartell High School",
                           game: game(["Kennedy", "Sartell"]))
        XCTAssertEqual(place.words(now: now), "Saturday's game vs Sartell moved to Sartell High School.")

        let concert = notice("Fall Concert", followed: "Apollo Choir", day: "2026-10-16")
        XCTAssertEqual(concert.words(now: now), "Tomorrow's Fall Concert is canceled.")

        let going = notice("Music in Millstream Park",
                           moved: .init(eventDate: "2026-10-19", startTime: "6 PM", location: "Millstream Park"),
                           day: "2026-10-31", place: "Millstream Park")
        XCTAssertEqual(going.name, "Music in Millstream Park")
        XCTAssertEqual(going.words(now: now), "moved to Sat, Oct 31 · 7 PM.")

        let far = notice("Fall Concert", followed: "Apollo Choir", day: "2026-11-07")
        XCTAssertEqual(far.words(now: now), "The Nov 7 Fall Concert is canceled.")
    }

    func testTheDotOncePerChange() async {
        var rows = [notice("game")]
        let notices = Notices(read: { rows }, keep: keep)
        XCTAssertFalse(notices.dot, "nothing read yet")
        await notices.refresh(now: now)
        XCTAssertTrue(notices.dot)
        notices.opened()
        XCTAssertFalse(notices.dot)

        // Read again on another open: still seen, on this phone for good.
        let again = Notices(read: { rows }, keep: keep)
        await again.refresh(now: now)
        XCTAssertFalse(again.dot)

        // Moved, then moved again: each move is news.
        let first = notice("hike", moved: .init(eventDate: "2026-10-20", startTime: "6 PM", location: nil), hoursAgo: 3)
        rows = [notice("game"), first]
        await again.refresh(now: now)
        XCTAssertTrue(again.dot)
        again.opened()
        rows = [notice("game"), notice("hike", moved: .init(eventDate: "2026-10-20", startTime: "6 PM", location: nil),
                                       hoursAgo: 1)]
        await again.refresh(now: now)
        XCTAssertTrue(again.dot, "a second move")
    }

    /// An Event ticket 12's alert already told is seen: no dot for old news after the update.
    func testOneTheOldAlertToldIsSeen() async {
        keep.set(["game"], forKey: Notices.seenKey)
        let notices = Notices(read: { [self] in [notice("game")] }, keep: keep)
        await notices.refresh(now: now)
        XCTAssertFalse(notices.dot)
    }

    func testAFailedReadKeepsWhatItHadAndOneOverLeaves() async {
        var fail = false
        let over = notice("coffee", day: "2026-10-15", time: "8 AM")
        let notices = Notices(read: { [self] in
            if fail { throw URLError(.notConnectedToInternet) }
            return [over, notice("game")]
        }, keep: keep)
        fail = true
        await notices.refresh(now: now)
        XCTAssertTrue(notices.failed, "nothing read: the page says so")
        fail = false
        await notices.refresh(now: now)
        XCTAssertFalse(notices.failed)
        XCTAssertEqual(notices.list?.map(\.event.id), ["game"], "one already over isn't news")
        fail = true
        await notices.refresh(now: now)
        XCTAssertEqual(notices.list?.map(\.event.id), ["game"])
        XCTAssertFalse(notices.failed, "what it had still shows")
    }

    func testInstagramsSections() {
        let list = [notice("a", hoursAgo: 1), notice("b", hoursAgo: 20), notice("c", hoursAgo: 72),
                    notice("d", hoursAgo: 24 * 20)]
        let sections = Notices.sections(list, now: now)
        XCTAssertEqual(sections.map(\.title), ["Today", "Yesterday", "Last 7 days", "Earlier"])
        XCTAssertEqual(sections.map { $0.notices.map(\.event.id) }, [["a"], ["b"], ["c"], ["d"]])
    }
}
