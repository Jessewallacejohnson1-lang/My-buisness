//
//  YouCalendarTests.swift
//  BlockPartyTests — the You tab's three weeks (BP app docs/plans/you-tab, ticket 01): which
//  days the Calendar shows, which of the neighbour's Going falls on each, what the Agenda
//  card says, and the model keeping its list through a failed read. You's Liked list
//  (ticket 04's Saved until inside-cards 16) runs on the same rules.
//

import XCTest
@testable import BlockParty

@MainActor
final class YouCalendarTests: XCTestCase {
    private var calendar: Calendar { YouCalendar.calendar }

    /// A Town wall-clock moment, "2026-10-14 12:00".
    private func town(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Town.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    private func row(_ id: String, _ day: String, _ time: String?, title: String? = nil,
                     endAt: Date? = nil, allDay: Bool = false, at place: String? = "Klinefelter Park") -> UpcomingEvent {
        UpcomingEvent(id: id, title: title ?? id, eventDate: day, startTime: time, location: place,
                      goingCount: 1, createdAt: "", rsvpd: true, endAt: endAt, isAllDay: allDay)
    }

    // MARK: The days

    /// Three weeks from the Sunday of this week, in the Town, whatever day it is.
    func testThreeWeeksFromThisSunday() {
        let days = YouCalendar.days(from: YouCalendar.firstDay(of: town("2026-10-14 12:00")))
        XCTAssertEqual(days.count, 21)
        XCTAssertEqual(days.first.map(Town.day), "2026-10-11")
        XCTAssertEqual(days.last.map(Town.day), "2026-10-31")
        XCTAssertEqual(YouCalendar.firstDay(of: town("2026-10-11 00:00")), town("2026-10-11 00:00"))
        XCTAssertEqual(YouCalendar.firstDay(of: town("2026-10-17 23:59")), town("2026-10-11 00:00"))
    }

    /// Across a month end and the Sunday the clocks go back (Nov 1), every day is one
    /// Town midnight, none doubled or skipped.
    func testDaysStayMidnightsAcrossTheClockChange() {
        let days = YouCalendar.days(from: YouCalendar.firstDay(of: town("2026-10-31 18:00")))
        XCTAssertEqual(days.map(Town.day).first, "2026-10-25")
        XCTAssertEqual(days.map(Town.day).last, "2026-11-14")
        XCTAssertEqual(Set(days.map(Town.day)).count, 21)
        for day in days {
            XCTAssertEqual(calendar.dateComponents([.hour, .minute], from: day), DateComponents(hour: 0, minute: 0))
        }
    }

    /// Sunday first even when the phone's week starts Monday: the Town calendar is its own.
    func testSundayFirstWhateverThePhoneSays() {
        XCTAssertEqual(YouCalendar.calendar.firstWeekday, 1)
        XCTAssertEqual(YouCalendar.calendar.component(.weekday, from: YouCalendar.firstDay(of: town("2026-10-12 09:00"))), 1)
    }

    // MARK: An Event's times

    /// A time the parser reads starts then and ends two hours on, or at its end.
    func testATimedEventStartsAndEndsInTheTown() {
        let event = YouCalendar.event(from: row("a", "2026-10-14", "7 PM"))!
        XCTAssertEqual(event.starts, town("2026-10-14 19:00"))
        XCTAssertEqual(event.ends, town("2026-10-14 21:00"))
        XCTAssertTrue(event.timed)
        let ended = YouCalendar.event(from: row("b", "2026-10-14", "7 PM", endAt: town("2026-10-14 22:30")))!
        XCTAssertEqual(ended.ends, town("2026-10-14 22:30"))
    }

    /// "After dark" and all-day Events run the whole day and show the organizer's words.
    func testUntimedEventsRunAllDay() {
        let dark = YouCalendar.event(from: row("a", "2026-10-14", "after dark"))!
        XCTAssertFalse(dark.timed)
        XCTAssertEqual(dark.starts, town("2026-10-14 00:00"))
        XCTAssertEqual(dark.ends, town("2026-10-15 00:00"))
        XCTAssertEqual(dark.startTime(now: town("2026-10-14 20:00")), "after dark")
        let allDay = YouCalendar.event(from: row("b", "2026-10-14", "9 AM", allDay: true))!
        XCTAssertFalse(allDay.timed)
        XCTAssertEqual(allDay.startTime(now: town("2026-10-14 10:00")), "All day")
        XCTAssertNil(YouCalendar.event(from: row("c", "someday", "9 AM")))
    }

    /// The Agenda card's and Liked's square photo is the Town card's pick (`FeedCardItem.image`):
    /// an Event whose only photo is its place's (`place_picture`, `image_url` null) shows that
    /// photo, not the grey square. Its own photo still comes first; a logo has no photo.
    func testTheAgendaPhotoIsTheTownCardsPick() {
        let hall = URL(string: "https://example.com/place-photos/hall.jpg")!
        var placeOnly = row("dogs", "2026-10-31", "1 PM", title: "Annual Dog Costume Contest")
        placeOnly.placePicture = PlacePicture(url: hall, kind: .photo)
        let event = YouCalendar.event(from: placeOnly)!
        XCTAssertEqual(event.photo, hall)
        XCTAssertEqual(event.photo, event.item.image.url, "the Town card's photo")

        var both = placeOnly
        both.imageUrl = "https://example.com/own.jpg"
        XCTAssertEqual(YouCalendar.event(from: both)!.photo?.absoluteString, "https://example.com/own.jpg")

        var logo = placeOnly
        logo.placePicture = PlacePicture(url: hall, kind: .logo)
        XCTAssertNil(YouCalendar.event(from: logo)!.photo)
        XCTAssertNil(YouCalendar.event(from: row("none", "2026-10-31", "1 PM", at: nil))!.photo)
    }

    /// The card says "Now" only while the Event is on; on an earlier day, or once it's
    /// over, it says when it started.
    func testTheCardSaysNowOnlyWhileItsOn() {
        let event = YouCalendar.event(from: row("a", "2026-10-13", "7 PM"))!
        func plain(_ text: String) -> String { text.replacingOccurrences(of: "\u{202F}", with: " ") }
        XCTAssertEqual(plain(event.startTime(now: town("2026-10-13 18:00"))), "7 PM")
        XCTAssertEqual(event.startTime(now: town("2026-10-13 19:30")), "Now")
        XCTAssertEqual(plain(event.startTime(now: town("2026-10-14 12:00"))), "7 PM")
    }

    // MARK: The Going on the Calendar

    /// The read's Going, soonest first then by title, on the right days.
    func testGoingSortsByStartThenTitleAndFallsOnItsDay() {
        let first = YouCalendar.firstDay(of: town("2026-10-14 12:00"))
        let read = [row("late", "2026-10-14", "7 PM"), row("zumba", "2026-10-14", "8 AM", title: "Zumba"),
                    row("book", "2026-10-14", "8 AM", title: "Book club"), row("sun", "2026-10-11", "10 AM")]
            .compactMap(YouCalendar.event(from:))
        let going = YouCalendar.going(read: read, tapped: [], isGoing: { _ in true }, first: first)
        XCTAssertEqual(going.map(\.id), ["sun", "book", "zumba", "late"])
        XCTAssertEqual(YouCalendar.on(town("2026-10-14 00:00"), going).map(\.id), ["book", "zumba", "late"])
        XCTAssertEqual(YouCalendar.on(town("2026-10-12 00:00"), going).map(\.id), [])
    }

    /// On one day, the timed Events come first, soonest first; "after dark" and all-day
    /// ones after them.
    func testUntimedEventsComeAfterTheDaysTimedOnes() {
        let first = YouCalendar.firstDay(of: town("2026-10-14 12:00"))
        let read = [row("dark", "2026-10-14", "after dark"), row("coffee", "2026-10-14", "8 AM"),
                    row("fair", "2026-10-14", nil, allDay: true), row("next", "2026-10-15", "7 AM")]
            .compactMap(YouCalendar.event(from:))
        let going = YouCalendar.going(read: read, tapped: [], isGoing: { _ in true }, first: first)
        XCTAssertEqual(going.map(\.id), ["coffee", "dark", "fair", "next"])
        XCTAssertEqual(YouCalendar.byDay(going)[town("2026-10-14 00:00")]?.map(\.id), ["coffee", "dark", "fair"])
    }

    /// A Join on a card shows before the read brings it back; one outside the three weeks
    /// doesn't; the read's copy wins when both have it.
    func testAJoinOnACardShowsAtOnce() {
        let first = YouCalendar.firstDay(of: town("2026-10-14 12:00"))
        let card = FeedCardItem(row("joined", "2026-10-20", "6 PM", title: "From the card"))
        let far = FeedCardItem(row("far", "2026-11-20", "6 PM"))
        let both = FeedCardItem(row("both", "2026-10-16", "6 PM", title: "Card's copy"))
        let read = [YouCalendar.event(from: row("both", "2026-10-16", "6 PM", title: "Read's copy"))!]
        let going = YouCalendar.going(read: read, tapped: [card, far, both], isGoing: { _ in true }, first: first)
        XCTAssertEqual(going.map(\.id), ["both", "joined"])
        XCTAssertEqual(going.first?.item.title, "Read's copy")
    }

    /// Leaving takes an Event off; a Join that turns back never shows.
    func testOnlyWhatsStillGoingShows() {
        let first = YouCalendar.firstDay(of: town("2026-10-14 12:00"))
        let read = [row("left", "2026-10-15", "6 PM"), row("kept", "2026-10-15", "7 PM")].compactMap(YouCalendar.event(from:))
        let turnedBack = FeedCardItem(row("turned-back", "2026-10-16", "6 PM"))
        let going = YouCalendar.going(read: read, tapped: [turnedBack],
                                      isGoing: { $0.id == "kept" }, first: first)
        XCTAssertEqual(going.map(\.id), ["kept"])
    }

    /// Going through a real Real-life actions: a Join on a card shows, leaving it hides it,
    /// a failed Join that turns back never shows.
    func testRealLifeActionsDriveWhatShows() async throws {
        let first = YouCalendar.firstDay(of: town("2026-10-14 12:00"))
        let actions = RealLifeActions(signedIn: true, needsAccount: false, hold: .milliseconds(1), flip: .milliseconds(1),
                                      setGoing: { id, _ in if id == "refused" { throw SupabaseError(message: "no", status: 403) } },
                                      setHeart: { _, _ in })
        var card = FeedCardItem(row("card", "2026-10-20", "6 PM"))
        card.isJoined = false
        var refused = FeedCardItem(row("refused", "2026-10-21", "6 PM"))
        refused.isJoined = false
        func shown() -> [String] {
            YouCalendar.going(read: [], tapped: Array(actions.goingTapped.values),
                              isGoing: { actions.going($0).isGoing }, first: first).map(\.id)
        }
        actions.toggleGoing(card)
        XCTAssertEqual(shown(), ["card"])
        actions.toggleGoing(card)
        XCTAssertEqual(shown(), [])
        actions.toggleGoing(refused)
        XCTAssertEqual(shown(), ["refused"])
        try await waitWhile(shown() != [])
        XCTAssertEqual(shown(), [])
    }

    // MARK: Liked (ticket 04's Saved, inside-cards 16)

    private func liked(_ id: String, _ day: String, _ time: String?, endAt: Date? = nil) -> UpcomingEvent {
        var event = row(id, day, time, endAt: endAt)
        event.rsvpd = false
        event.hearted = true
        event.heartCount = 1
        return event
    }

    /// Liked lists the read's hearts and this session's, each once, soonest first: this
    /// morning's that's over drops off, a festival from before today still running stays,
    /// one unhearted since the read goes, and next year's stays.
    func testLikedShowsWhatsStillHeartedAndNotOver() {
        let now = town("2026-10-14 12:00")
        let read = [liked("morning", "2026-10-14", "8 AM"),
                    liked("festival", "2026-10-10", "10 AM", endAt: town("2026-10-15 22:00")),
                    liked("tonight", "2026-10-14", "7 PM"),
                    liked("unhearted", "2026-10-16", "6 PM"),
                    liked("next-year", "2027-10-14", "6 PM")].compactMap(YouCalendar.event(from:))
        var card = FeedCardItem(row("card", "2026-10-20", "6 PM"))
        card.isLiked = true
        let list = YouCalendar.liked(read: read, tapped: [card], isLiked: { $0.isLiked && $0.id != "unhearted" }, now: now)
        XCTAssertEqual(list.map(\.id), ["festival", "tonight", "card", "next-year"])
    }

    /// Through a real Real-life actions: a read row the Town feed never read stays hearted, a
    /// heart on a card or a double tap on its photo shows at once, unhearting hides either, a
    /// heart that turns back never shows, and a new account starts with none of this session's.
    func testRealLifeActionsDriveLiked() async throws {
        let now = town("2026-10-14 12:00")
        var fail = false
        let actions = RealLifeActions(signedIn: true, needsAccount: false, hold: .milliseconds(1), flip: .milliseconds(1),
                                      setGoing: { _, _ in },
                                      setHeart: { _, _ in if fail { throw SupabaseError(message: "no", status: 403) } })
        let read = [liked("read", "2026-10-15", "6 PM")].compactMap(YouCalendar.event(from:))
        let card = FeedCardItem(row("card", "2026-10-20", "6 PM"))
        let photo = FeedCardItem(row("photo", "2026-10-21", "6 PM"))
        func shown() -> [String] {
            YouCalendar.liked(read: read, tapped: Array(actions.likedTapped.values),
                              isLiked: { actions.heart($0).isHearted }, now: now).map(\.id)
        }
        XCTAssertEqual(shown(), ["read"])
        actions.toggleHeart(card)
        XCTAssertEqual(shown(), ["read", "card"])
        actions.heartOn(photo)
        XCTAssertEqual(shown(), ["read", "card", "photo"], "a double tap on a photo counts")
        actions.toggleHeart(read[0].item)
        XCTAssertEqual(shown(), ["card", "photo"])
        try await Task.sleep(for: .milliseconds(50))
        actions.toggleHeart(card)
        actions.toggleHeart(photo)
        XCTAssertEqual(shown(), [])
        try await Task.sleep(for: .milliseconds(50))
        fail = true
        actions.toggleHeart(card)
        XCTAssertEqual(shown(), ["card"])
        // Wait on the turn back itself, not a fixed time: GitHub's runner once outlasted 200 ms
        // (2026-10-22, 0e8da6c).
        let deadline = ContinuousClock.now + .seconds(5)
        while shown() != [], ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(shown(), [])
        actions.accountChanged(signedIn: true)
        XCTAssertTrue(actions.likedTapped.isEmpty)
    }

    /// `get_my_likes`' rows decode hearted as their card says, Going only where it says so, and
    /// their cards carry the heart.
    func testTheLikedReadsRowsDecode() throws {
        let json = """
        [{"card":{"id":"e1","title":"Fall market","event_date":"2026-10-24","start_time":"8 AM",
         "location":"Centennial Park","image_url":null,"category":"food","club_name":null,
         "source_name":"City of St. Joseph","end_at":null,"all_day":false,"created_at":"2026-10-01T12:00:00+00:00",
         "going_count":4,"going":false,"heart_count":2,"hearted":true}},
         {"card":{"id":"e2","title":"Ride","event_date":"2026-10-25","start_time":"6 PM",
         "location":null,"image_url":null,"category":null,"club_name":"Bike club","source_name":null,
         "end_at":null,"all_day":false,"created_at":"2026-10-01T12:00:00+00:00","going_count":1,
         "going":true,"heart_count":1,"hearted":true}}]
        """
        let rows = try CommunityAPI.myGoingRows(from: Data(json.utf8))
        XCTAssertEqual(rows.map(\.rsvpd), [false, true])
        XCTAssertEqual(rows.map(\.heartCount), [2, 1])
        XCTAssertTrue(rows.allSatisfy(\.hearted))
        XCTAssertTrue(rows.compactMap(YouCalendar.event(from:)).allSatisfy(\.item.isLiked))
    }

    // MARK: Liked's stories (inside-cards 22)

    /// `get_my_likes` sends an Event as its card and a story as the Town feed's News row, after the Events; each
    /// lands on its own side, and a story's row reads as the feed's does.
    func testTheLikedReadSendsStoriesBesideTheEvents() throws {
        let json = """
        [{"card":{"id":"e1","title":"Fall market","event_date":"2026-10-24","start_time":"8 AM",
         "location":null,"image_url":null,"category":null,"club_name":null,"source_name":"City of St. Joseph",
         "end_at":null,"all_day":false,"created_at":"2026-10-01T12:00:00+00:00","going_count":4,"going":false,
         "heart_count":2,"hearted":true},"news":null},
         {"card":null,"news":{"id":"n1","title":"Flight Friday","image_url":null,"source_name":"The Wandering Cow",
         "created_at":"2026-10-08T14:00:00+00:00","leaves_at":"2026-10-15T14:00:00+00:00","place_picture":null,
         "description":"Four scoops for $5 on Fridays.","kind":"news","source_url":"https://www.instagram.com/p/x/",
         "poster":null,"heart_count":2,"hearted":true}}]
        """
        let (events, news) = try CommunityAPI.myLikesRows(from: Data(json.utf8))
        XCTAssertEqual(events.map(\.id), ["e1"])
        XCTAssertEqual(news.map(\.id), ["n1"])
        XCTAssertEqual([news[0].place, news[0].headline, news[0].words], ["The Wandering Cow", "Flight Friday",
                                                                         "Four scoops for $5 on Fridays."])
        XCTAssertEqual([news[0].hearted ? 1 : 0, news[0].heartCount], [1, 2])
        XCTAssertEqual(news[0].leavesAt, ISO8601DateFormatter().date(from: "2026-10-15T14:00:00Z"))
        XCTAssertEqual(try CommunityAPI.myLikesRows(from: Data("[]".utf8)).news, [])
    }

    /// One story that doesn't read (no `leaves_at`, a title that isn't words) is left out of Liked, never the read:
    /// the Events and the other stories still come (inside-cards 22, review).
    func testABadStoryLeavesLikedReadable() throws {
        let story = { (id: String, extra: String) in """
        {"card":null,"news":{"id":"\(id)","source_name":"The Wandering Cow","created_at":"2026-10-08T14:00:00+00:00",
         "place_picture":null,"description":"Four scoops.","kind":"news","source_url":"https://www.instagram.com/p/\(id)/",
         "poster":null,"heart_count":1,"hearted":true\(extra)}}
        """ }
        let json = "[" + [
            ##"{"card":{"id":"e1","title":"Fall market","event_date":"2026-10-24","start_time":null,"location":null,"##
                + ##""image_url":null,"category":null,"club_name":null,"source_name":null,"end_at":null,"all_day":false,"##
                + ##""created_at":"2026-10-01T12:00:00+00:00","going_count":0,"going":false},"news":null}"##,
            story("good", ##","title":"Flight Friday","leaves_at":"2026-10-15T14:00:00+00:00""##),
            story("no-leave", ##","title":"Flight Friday""##),
            story("bad-title", ##","title":12,"leaves_at":"2026-10-15T14:00:00+00:00""##),
        ].joined(separator: ",") + "]"
        let (events, news) = try CommunityAPI.myLikesRows(from: Data(json.utf8))
        XCTAssertEqual(events.map(\.id), ["e1"])
        XCTAssertEqual(news.map(\.id), ["good"])
    }

    private func story(_ id: String, published: String, leaves: String, hearted: Bool = true) -> TownNews {
        TownNews(id: id, place: "The Wandering Cow", words: id, post: URL(string: "https://www.instagram.com/p/\(id)/")!,
                 leavesAt: town(leaves), published: town(published), title: id, hearted: hearted, heartCount: 1)
    }

    /// Liked's stories: the read's and this session's hearts, each once, newest first; one the Town feed has let
    /// go, or unhearted since, leaves.
    func testLikedStoriesStayUntilTheyLeaveTheFeed() {
        let now = town("2026-10-14 12:00")
        let read = [story("cow", published: "2026-10-13 09:00", leaves: "2026-10-20 09:00"),
                    story("gone", published: "2026-10-07 09:00", leaves: "2026-10-14 09:00"),
                    story("unhearted", published: "2026-10-13 10:00", leaves: "2026-10-20 10:00")]
        let tapped = [story("peony", published: "2026-10-14 08:00", leaves: "2026-10-21 08:00"),
                      story("cow", published: "2026-10-13 09:00", leaves: "2026-10-20 09:00")]
        let list = YouCalendar.likedNews(read: read, tapped: tapped, isLiked: { $0.id != "unhearted" }, now: now)
        XCTAssertEqual(list.map(\.id), ["peony", "cow"])
        XCTAssertEqual(YouCalendar.likedNews(read: read, tapped: [], isLiked: { _ in true },
                                             now: town("2026-10-20 09:30")).map(\.id), ["unhearted"],
                       "the cow's story left with its feed time")
    }

    /// Through a real Real-life actions: a story hearted on its card shows in Liked at once and leaves when
    /// unhearted; a read's story stays hearted as the read says; a new account starts with none.
    func testRealLifeActionsDriveLikedStories() async throws {
        let now = town("2026-10-14 12:00")
        var written: [String] = []
        let actions = RealLifeActions(signedIn: true, needsAccount: false, hold: .milliseconds(1), flip: .milliseconds(1),
                                      setGoing: { _, _ in }, setHeart: { id, _ in written.append("event \(id)") },
                                      setNewsHeart: { id, on in written.append("news \(id) \(on)") })
        let read = [story("cow", published: "2026-10-13 09:00", leaves: "2026-10-20 09:00")]
        let peony = story("peony", published: "2026-10-14 08:00", leaves: "2026-10-21 08:00", hearted: false)
        actions.read(news: read)
        func shown() -> [String] {
            YouCalendar.likedNews(read: read, tapped: Array(actions.likedNews.values),
                                  isLiked: { actions.heart($0).isHearted }, now: now).map(\.id)
        }
        XCTAssertEqual(shown(), ["cow"])
        actions.toggleHeart(peony)
        XCTAssertEqual(shown(), ["peony", "cow"], "in Liked at once")
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(written, ["news peony true"], "written as a story's, never an Event's")
        actions.toggleHeart(read[0])
        XCTAssertEqual(shown(), ["peony"])
        actions.accountChanged(signedIn: true)
        XCTAssertTrue(actions.likedNews.isEmpty)
    }

    // MARK: Swiping the Agenda (ticket 12)

    /// The pages are the days with plans, past ones this week too, plus today and the day picked
    /// even when empty; every other empty day is skipped.
    func testTheAgendaPagesSkipEmptyDaysButKeepTodayAndThePickedDay() {
        let now = town("2026-10-22 09:00")
        let first = YouCalendar.firstDay(of: now)
        let days = YouCalendar.days(from: first)
        let today = town("2026-10-22 00:00")
        let going = YouCalendar.going(read: [row("mon", "2026-10-19", "6 PM"), row("fri", "2026-10-23", "7 PM"),
                                             row("fri2", "2026-10-23", "8 PM"), row("tue", "2026-10-27", "7 PM")]
            .compactMap(YouCalendar.event(from:)), tapped: [], isGoing: { _ in true }, first: first)
        XCTAssertEqual(YouCalendar.pages(going, days: days, today: today, day: today).map(Town.day),
                       ["2026-10-19", "2026-10-22", "2026-10-23", "2026-10-27"])
        XCTAssertEqual(YouCalendar.pages(going, days: days, today: today, day: town("2026-10-29 00:00")).map(Town.day),
                       ["2026-10-19", "2026-10-22", "2026-10-23", "2026-10-27", "2026-10-29"])
    }

    // MARK: The next plan (ticket 11)

    /// An empty today points to the first plan still to come, in the Calendar's order, and its
    /// card says how far off it is beside the date, never "Tomorrow" twice. Another day picked,
    /// a today with a plan (even one that's over) and nothing ahead in the three weeks show the
    /// line alone.
    func testAnEmptyTodayPointsToTheNextPlan() {
        let now = town("2026-10-21 12:00")
        let first = YouCalendar.firstDay(of: now)
        let today = town("2026-10-21 00:00")
        func going(_ rows: [UpcomingEvent]) -> [DailyEvent] {
            YouCalendar.going(read: rows.compactMap(YouCalendar.event(from:)), tapped: [],
                              isGoing: { _ in true }, first: first)
        }
        let plans = going([row("past", "2026-10-19", "7 PM"), row("fri", "2026-10-23", "7:30 PM"),
                           row("thu", "2026-10-22", "8 AM"), row("sat", "2026-10-24", "9 AM")])
        let next = YouCalendar.next(plans, day: today, now: now)
        XCTAssertEqual(next?.id, "thu")
        XCTAssertEqual(next?.startsLabel(now: now), "Tomorrow")
        XCTAssertEqual(FeedWhenLine(eventDate: "2026-10-22", startTime: "8 AM", now: now,
                                    relative: false)?.text, "Thu, Oct 22 · 8 AM")
        XCTAssertEqual(YouCalendar.next(going([row("fri", "2026-10-23", "7:30 PM")]), day: today, now: now)?
            .startsLabel(now: now), "In 2 days")

        XCTAssertNil(YouCalendar.next(plans, day: town("2026-10-22 00:00"), now: now))
        XCTAssertNil(YouCalendar.next(going([row("morning", "2026-10-21", "8 AM"), row("fri", "2026-10-23", "7:30 PM")]),
                                      day: today, now: now))
        XCTAssertNil(YouCalendar.next(going([row("past", "2026-10-19", "7 PM"), row("far", "2026-11-10", "7 PM")]),
                                      day: today, now: now))
    }

    // MARK: The model

    /// The first read fills the list; a failed one after it keeps the list and says so;
    /// a failed first read leaves no list, so the page shows its retry.
    func testTheModelKeepsItsListThroughAFailedRead() async {
        var fail = false
        var asked: [String] = []
        let model = YouModel(read: { from, to in
            asked = [from, to]
            if fail { throw URLError(.notConnectedToInternet) }
            return [self.row("a", "2026-10-14", "7 PM")]
        })
        await model.refresh(now: town("2026-10-14 12:00"))
        XCTAssertEqual(asked, ["2026-10-11", "2026-10-31"])
        XCTAssertEqual(model.going?.map(\.id), ["a"])
        XCTAssertFalse(model.failed)
        fail = true
        await model.refresh(now: town("2026-10-14 12:00"))
        XCTAssertEqual(model.going?.map(\.id), ["a"])
        XCTAssertTrue(model.failed)

        let fresh = YouModel(read: { _, _ in throw URLError(.notConnectedToInternet) })
        await fresh.refresh(now: town("2026-10-14 12:00"))
        XCTAssertNil(fresh.going)
        XCTAssertTrue(fresh.failed)
    }

    /// A new account starts from no list.
    func testANewAccountSeesNoneOfTheLast() async {
        let model = YouModel(read: { _, _ in [self.row("a", "2026-10-14", "7 PM")] })
        await model.refresh(now: town("2026-10-14 12:00"))
        model.accountChanged()
        XCTAssertNil(model.going)
    }

    // MARK: Groups (ticket 09)

    private func group(_ id: String, joined: Bool = false) -> TownGroup {
        var group = TownGroup(id: id, name: id)
        group.joined = joined
        return group
    }

    /// The row is the read's groups the neighbour is in, in its order: a Join group anywhere
    /// adds one at once and leaving takes it off, without a read.
    func testAJoinOrLeaveChangesGroupsAtOnce() {
        let actions = RealLifeActions(signedIn: true, needsAccount: false, hold: .milliseconds(1), flip: .milliseconds(1),
                                      setGoing: { _, _ in }, setHeart: { _, _ in })
        let read = [group("legion", joined: true), group("lions"), group("yarnovers", joined: true)]
        actions.read(read)
        func shown() -> [String] { read.filter { actions.member($0).isMember }.map(\.id) }
        XCTAssertEqual(shown(), ["legion", "yarnovers"])
        actions.toggleMember(read[1])
        XCTAssertEqual(shown(), ["legion", "lions", "yarnovers"])
        actions.toggleMember(read[0])
        XCTAssertEqual(shown(), ["lions", "yarnovers"])
    }

    /// The groups read fills the list and a failed one keeps it, but hands back nothing, so an
    /// old list never overwrites who's in what; a new account starts from none.
    func testTheModelKeepsItsGroupsThroughAFailedRead() async {
        var fail = false
        let model = YouModel(read: { _, _ in [] }, groups: {
            if fail { throw URLError(.notConnectedToInternet) }
            return [self.group("legion", joined: true)]
        })
        let fresh = await model.refreshGroups()
        XCTAssertEqual(fresh?.map(\.id), ["legion"])
        XCTAssertEqual(model.groups?.map(\.id), ["legion"])
        fail = true
        let failed = await model.refreshGroups()
        XCTAssertNil(failed)
        XCTAssertEqual(model.groups?.map(\.id), ["legion"])
        model.accountChanged()
        XCTAssertNil(model.groups)
    }

    #if DEBUG
    /// The samples sit in the three weeks around today, today busy, and their photos are bundled.
    func testSamplesFallInTheThreeWeeks() {
        let now = town("2026-10-14 12:00")
        let first = YouCalendar.firstDay(of: now)
        let events = YouCalendar.samples(now: now).compactMap(YouCalendar.event(from:))
        XCTAssertTrue(events.allSatisfy { $0.starts >= first && $0.starts <= YouCalendar.lastDay(from: first).addingTimeInterval(86_400) })
        XCTAssertEqual(YouCalendar.on(town("2026-10-14 00:00"), events).count, 2)
        XCTAssertEqual(events.filter { $0.photo == nil }.count, 1)
    }
    #endif

    /// Only the 1st of a month the three weeks run into says its month (ticket 10).
    func testTheFirstOfANewMonthSaysItsMonth() {
        let days = YouCalendar.days(from: YouCalendar.firstDay(of: town("2026-10-21 12:00")))
        let said = days.compactMap { day in YouCalendar.month(on: day, first: days.first).map { "\(Town.day(day)) \($0)" } }
        XCTAssertEqual(said, ["2026-11-01 NOV"])
        // Three weeks that start on the 1st need no month on it.
        let november = YouCalendar.days(from: YouCalendar.firstDay(of: town("2026-11-03 12:00")))
        XCTAssertEqual(november.compactMap { YouCalendar.month(on: $0, first: november.first) }, [])
    }

    /// VoiceOver reads a day as its date and how many plans it has.
    func testVoiceOverReadsTheDayAndItsPlans() {
        XCTAssertEqual(YouPage.spoken(town("2026-10-13 00:00"), plans: 2), "Tuesday, October 13, 2 plans")
        XCTAssertEqual(YouPage.spoken(town("2026-10-13 00:00"), plans: 0), "Tuesday, October 13, nothing planned")
        XCTAssertEqual(YouPage.spoken(town("2026-10-13 00:00"), plans: 1, today: true), "Today, Tuesday, October 13, 1 plan")
    }

    /// `get_my_going`'s rows decode into Going Events, an all-day one and a club's included.
    func testTheReadsRowsDecode() throws {
        let json = """
        [{"card":{"id":"e1","title":"Fall market","event_date":"2026-10-24","start_time":"8 AM",
         "location":"Centennial Park","image_url":null,"category":"food","club_name":null,
         "source_name":"City of St. Joseph","end_at":"2026-10-24T17:00:00+00:00","all_day":false,
         "created_at":"2026-10-01T12:00:00+00:00","going_count":4,"going":true}},
         {"card":{"id":"e2","title":"Ride","event_date":"2026-10-25","start_time":null,
         "location":null,"image_url":null,"category":null,"club_name":"Bike club","source_name":null,
         "end_at":null,"all_day":true,"created_at":"2026-10-01T12:00:00+00:00","going_count":1,
         "going":true}}]
        """
        let rows = try CommunityAPI.myGoingRows(from: Data(json.utf8))
        XCTAssertEqual(rows.map(\.id), ["e1", "e2"])
        XCTAssertTrue(rows.allSatisfy(\.rsvpd))
        XCTAssertEqual(rows[0].goingCount, 4)
        XCTAssertEqual(rows[0].category, .food)
        XCTAssertEqual(rows[0].endAt, town("2026-10-24 12:00"))
        XCTAssertEqual(rows[1].clubName, "Bike club")
        XCTAssertTrue(rows[1].isAllDay)
    }

    /// The Going read's Event card (BP app codebase-health-2 01 and 03): a full one carries everything the
    /// Town card and the Event page show, its found link under About included; a bare one reads with empties;
    /// one that doesn't decode is left out, never the read; one not Going says so.
    func testTheGoingReadsEventCardDecodesFullAndBare() throws {
        let json = """
        [{"card":{"id":"e1","title":"SJU Football vs Concordia","event_date":"2026-11-05","start_time":"1 PM",
            "location":"Clemens Field","image_url":"https://x/flyer.jpg","category":"sports",
            "club_name":"Johnnie Football Boosters","source_name":"SJU Athletics",
            "end_at":"2026-11-05T21:00:00+00:00","all_day":false,"created_at":"2026-10-01T12:00:00.123456+00:00",
            "going_count":2,"going":true,"cancelled":true,
            "place_picture":{"url":"https://x/field.webp","kind":"photo","credit":null,"site":"https://csbsju.edu/",
                             "w":1200,"h":800,"more":[]},
            "host_picture":{"url":"https://x/sju-logo.webp","kind":"logo","hue":null},
            "description":"Homecoming against the Cobbers.","what":"Football game",
            "source_url":"https://gojohnnies.com/sports/football/schedule",
            "game":{"sport":"Football","occasion":"Homecoming","final":null,"live":null,"plays":null,
                    "teams":[{"name":"Saint John's","short":"SJU","logo":"https://x/sju.png","color":null,
                              "id":"7d1f6c1e-0000-4000-8000-000000000001","local":true,"colors":null,"nickname":null},
                             {"name":"Concordia","short":"Concordia","logo":null,"color":null,
                              "id":"7d1f6c1e-0000-4000-8000-000000000002","local":false,"colors":null,"nickname":null}]},
            "friends_going":[{"name":"Anna","photo":"https://x/anna.jpg"}]}},
         {"card":{"id":"e2","title":"Porch jam","event_date":"2026-11-05","start_time":null,"location":null,
            "image_url":null,"category":null,"club_name":null,"source_name":null,"end_at":null,"all_day":false,
            "created_at":"2026-10-01T12:00:00+00:00","going_count":1,"going":true,"cancelled":false,
            "place_picture":null,"host_picture":null,"description":null,"what":null,"source_url":null,"game":null,
            "friends_going":[]}},
         {"card":{"title":"Quiz night","source_url":"https://x/quiz"}},
         {"card":{"id":"e4","title":"Fall market","event_date":"2026-11-07","going_count":4,"going":false,
            "created_at":"2026-10-01T12:00:00+00:00"}}]
        """
        let rows = try CommunityAPI.myGoingRows(from: Data(json.utf8))
        let full = rows[0]
        XCTAssertEqual(full.imageUrl, "https://x/flyer.jpg")
        XCTAssertEqual(full.clubName, "Johnnie Football Boosters")
        XCTAssertEqual(full.endAt, DateHelpers.timestamp("2026-11-05T21:00:00+00:00"))
        XCTAssertTrue(full.rsvpd)
        XCTAssertTrue(full.cancelled)
        XCTAssertEqual(full.placePicture?.url, URL(string: "https://x/field.webp"))
        XCTAssertEqual(full.hostPicture?.kind, .logo)
        XCTAssertEqual(full.game?.teams.map(\.short), ["SJU", "Concordia"])
        XCTAssertEqual(full.game?.occasion, "Homecoming")
        XCTAssertEqual(full.friendsGoing.map(\.name), ["Anna"])
        let page = FeedCardItem(full)
        XCTAssertEqual(page.sourceURL, URL(string: "https://gojohnnies.com/sports/football/schedule"),
                       "the Event page opened from You has its found link")
        XCTAssertEqual(page.description, "Homecoming against the Cobbers.")
        XCTAssertEqual(page.what, "Football game")

        let bare = rows[1]
        XCTAssertEqual([bare.id, bare.title, bare.eventDate], ["e2", "Porch jam", "2026-11-05"])
        XCTAssertTrue(bare.rsvpd)
        XCTAssertEqual(bare.goingCount, 1)
        XCTAssertNil(bare.startTime)
        XCTAssertEqual(bare.category, .other)
        XCTAssertNil(bare.endAt)
        XCTAssertNil(bare.placePicture)
        XCTAssertNil(bare.hostPicture)
        XCTAssertNil(bare.game)
        XCTAssertNil(bare.sourceURL)
        XCTAssertTrue(bare.friendsGoing.isEmpty)
        XCTAssertFalse(bare.cancelled)

        XCTAssertEqual(rows.map(\.id), ["e1", "e2", "e4"], "e3's card doesn't decode: left out, never the read")
        XCTAssertFalse(rows[2].rsvpd, "a card that says not Going is not Going")
    }

    // MARK: Friends going with you (ticket 07)

    /// The read's friends Going ride the Agenda card, first name and photo, newest first.
    func testTheReadsFriendsGoingRideTheCard() throws {
        let json = """
        [{"card":{"id":"e1","title":"Quiz night","event_date":"2026-10-24","start_time":"7 PM",
         "location":null,"image_url":null,"category":null,"club_name":null,"source_name":"City of St. Joseph",
         "end_at":null,"all_day":false,"created_at":"2026-10-01T12:00:00+00:00","going_count":3,
         "friends_going":[{"name":"Anna","photo":"https://x/anna.jpg"},{"name":"Ben",
         "photo":null}],"going":true}}]
        """
        let row = try XCTUnwrap(CommunityAPI.myGoingRows(from: Data(json.utf8)).first)
        let card = try XCTUnwrap(YouCalendar.event(from: row)).item
        XCTAssertEqual(card.friendsGoing.map(\.name), ["Anna", "Ben"])
        XCTAssertEqual(card.friendsGoing.map(\.photo), [URL(string: "https://x/anna.jpg"), nil])
    }

    /// VoiceOver reads the friends after the time (words page `agenda-friends-vo`), then what an
    /// open card adds; a card with none reads as before.
    func testVoiceOverReadsTheFriendsWithTheCard() {
        XCTAssertEqual(AgendaCards.spoken(title: "Trivia Night", when: "7 PM", friends: ["Anna", "Ben"], more: ""),
                       "Trivia Night, 7 PM, Anna and Ben are going")
        XCTAssertEqual(AgendaCards.spoken(title: "Trivia Night", when: "7 PM", friends: [],
                                          more: "Until 9 PM, Bad Habit Brewing"),
                       "Trivia Night, 7 PM, Until 9 PM, Bad Habit Brewing")
    }

    // MARK: The first name (the hello pill, onboarding's Done)

    func testTheFirstNameIsTheNamesFirstWord() {
        XCTAssertEqual(YouPage.firstName("Jesse Johnson"), "Jesse")
        XCTAssertEqual(YouPage.firstName("  Mary Ann\n"), "Mary")
        XCTAssertEqual(YouPage.firstName("Jesse"), "Jesse")
        // No saved name: none.
        XCTAssertNil(YouPage.firstName(nil))
        XCTAssertNil(YouPage.firstName(""))
        XCTAssertNil(YouPage.firstName("   "))
    }

    // MARK: Profile (BP app references/profile-remake)

    /// "24 friends · 1 group · 9 going": a zero or an unknown is left out, never said.
    func testProfileCountsLeaveOutZerosAndUnknowns() {
        let words = { (parts: [(number: Int, word: String)]) in parts.map { "\($0.number) \($0.word)" } }
        XCTAssertEqual(words(ProfileFace.counts(friends: 24, groups: 1, going: 9)), ["24 friends", "1 group", "9 going"])
        XCTAssertEqual(words(ProfileFace.counts(friends: 1, groups: 0, going: nil)), ["1 friend"])
        XCTAssertEqual(words(ProfileFace.counts(friends: nil, groups: 3, going: 0)), ["3 groups"])
        XCTAssertTrue(ProfileFace.counts(friends: 0, groups: 0, going: nil).isEmpty)
    }

    /// Your next plans: only those not over, three at most, in the Calendar's order, and how many.
    func testProfileNextPlansSkipWhatIsOver() {
        let now = town("2026-10-14 20:00")
        let events = [row("over", "2026-10-14", "9 AM", endAt: town("2026-10-14 11:00")),
                      row("on", "2026-10-14", "7 PM", endAt: town("2026-10-14 22:00")),
                      row("b", "2026-10-15", "9 AM"), row("c", "2026-10-16", "9 AM"), row("d", "2026-10-17", "9 AM")]
            .compactMap(YouCalendar.event(from:))
        let plans = ProfileFace.nextPlans(events, now: now)
        XCTAssertEqual(plans.rows.map(\.id), ["on", "b", "c"])
        XCTAssertEqual(plans.count, 4)
        XCTAssertTrue(ProfileFace.nextPlans([], now: now).rows.isEmpty)
    }

    /// A Going row's line: the Group page's day, then the card's time; an all-day one says so.
    func testProfileGoingLine() {
        let now = town("2026-10-14 08:00")
        let timed = YouCalendar.event(from: row("a", "2026-10-31", "9 AM"))!
        // The clock's space is the formatter's narrow one ("9\u{202F}AM").
        XCTAssertEqual(ProfileFace.goingLine(timed, now: now), "Sat, Oct 31 · \(Town.clock(timed.starts))")
        XCTAssertTrue(ProfileFace.goingLine(timed, now: now).hasPrefix("Sat, Oct 31 · 9"))
        let allDay = YouCalendar.event(from: row("b", "2026-11-01", nil, allDay: true))!
        XCTAssertEqual(ProfileFace.goingLine(allDay, now: now), "Sun, Nov 1 · All day")
    }

    /// A neighbour's friends you share sit in the counts line, after their friends.
    func testProfileCountsCarryMutualFriends() {
        let words = ProfileFace.counts(friends: 31, mutual: 2, groups: 0, going: nil).map { "\($0.number) \($0.word)" }
        XCTAssertEqual(words, ["31 friends", "2 mutual"])
    }

    /// A bio is cut as the database counts it, one per Unicode scalar, never mid-emoji.
    func testBioIsCountedAndCutTheDatabasesWay() {
        let family = "👨‍👩‍👧"     // one letter to Swift, five scalars to Postgres
        XCTAssertEqual(ProfileModel.bioLength(family), 5)
        let long = String(repeating: "a", count: 147) + family
        XCTAssertEqual(ProfileModel.clampBio(long), String(repeating: "a", count: 147))
        XCTAssertEqual(ProfileModel.clampBio("Hi " + family), "Hi " + family)
    }
}
