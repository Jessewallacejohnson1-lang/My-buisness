//
//  YouCalendarTests.swift
//  BlockPartyTests — the You tab's three weeks (BP app docs/plans/you-tab, ticket 01): which
//  days the Calendar shows, which of the neighbour's Going falls on each, what the Agenda
//  card says, and the model keeping its list through a failed read. Profile's Saved list
//  (ticket 04) runs on the same rules.
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
        var fail = false
        let actions = RealLifeActions(signedIn: true, needsAccount: false, hold: .milliseconds(1), flip: .milliseconds(1),
                                      setGoing: { _, _ in if fail { throw SupabaseError(message: "no", status: 403) } },
                                      setHeart: { _, _ in }, setSave: { _, _ in }, knownEvents: { _ in [] })
        var card = FeedCardItem(row("card", "2026-10-20", "6 PM"))
        card.isJoined = false
        func shown() -> [String] {
            YouCalendar.going(read: [], tapped: Array(actions.goingTapped.values),
                              isGoing: { actions.going($0).isGoing }, first: first).map(\.id)
        }
        actions.toggleGoing(card)
        XCTAssertEqual(shown(), ["card"])
        actions.toggleGoing(card)
        XCTAssertEqual(shown(), [])
        try await Task.sleep(for: .milliseconds(50))
        fail = true
        actions.toggleGoing(card)
        XCTAssertEqual(shown(), ["card"])
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(shown(), [])
    }

    // MARK: Saved (ticket 04)

    private func saved(_ id: String, _ day: String, _ time: String?, endAt: Date? = nil) -> UpcomingEvent {
        var event = row(id, day, time, endAt: endAt)
        event.rsvpd = false
        event.saved = true
        return event
    }

    /// Saved lists the read's saves and this session's, each once, soonest first: this
    /// morning's that's over drops off, a festival from before today still running stays,
    /// one unsaved since the read goes, and next year's stays.
    func testSavedShowsWhatsStillSavedAndNotOver() {
        let now = town("2026-10-14 12:00")
        let read = [saved("morning", "2026-10-14", "8 AM"),
                    saved("festival", "2026-10-10", "10 AM", endAt: town("2026-10-15 22:00")),
                    saved("tonight", "2026-10-14", "7 PM"),
                    saved("unsaved", "2026-10-16", "6 PM"),
                    saved("next-year", "2027-10-14", "6 PM")].compactMap(YouCalendar.event(from:))
        var card = FeedCardItem(row("card", "2026-10-20", "6 PM"))
        card.isSaved = true
        let list = YouCalendar.saved(read: read, tapped: [card], isSaved: { $0.isSaved && $0.id != "unsaved" }, now: now)
        XCTAssertEqual(list.map(\.id), ["festival", "tonight", "card", "next-year"])
    }

    /// Through a real Real-life actions: a read row the Town feed never read stays saved, a
    /// save on a card shows at once, unsaving hides either, a save that turns back never
    /// shows, and a new account starts with none of this session's.
    func testRealLifeActionsDriveSaved() async throws {
        let now = town("2026-10-14 12:00")
        var fail = false
        let actions = RealLifeActions(signedIn: true, needsAccount: false, hold: .milliseconds(1), flip: .milliseconds(1),
                                      setGoing: { _, _ in }, setHeart: { _, _ in },
                                      setSave: { _, _ in if fail { throw SupabaseError(message: "no", status: 403) } },
                                      knownEvents: { _ in [] })
        let read = [saved("read", "2026-10-15", "6 PM")].compactMap(YouCalendar.event(from:))
        let card = FeedCardItem(row("card", "2026-10-20", "6 PM"))
        func shown() -> [String] {
            YouCalendar.saved(read: read, tapped: Array(actions.savedTapped.values),
                              isSaved: { actions.saved($0) }, now: now).map(\.id)
        }
        XCTAssertEqual(shown(), ["read"])
        actions.toggleSave(card)
        XCTAssertEqual(shown(), ["read", "card"])
        actions.toggleSave(read[0].item)
        XCTAssertEqual(shown(), ["card"])
        try await Task.sleep(for: .milliseconds(50))
        actions.toggleSave(card)
        XCTAssertEqual(shown(), [])
        try await Task.sleep(for: .milliseconds(50))
        fail = true
        actions.toggleSave(card)
        XCTAssertEqual(shown(), ["card"])
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(shown(), [])
        actions.accountChanged(signedIn: true)
        XCTAssertTrue(actions.savedTapped.isEmpty)
    }

    /// `get_my_saves`' rows decode saved, Going only where the row says so, and their cards
    /// carry the bookmark.
    func testTheSavedReadsRowsDecode() throws {
        let json = """
        [{"id":"e1","title":"Fall market","event_date":"2026-10-24","start_time":"8 AM",
          "location":"Centennial Park","image_url":null,"category":"food","club_name":null,
          "source_name":"City of St. Joseph","end_at":null,"all_day":false,
          "created_at":"2026-10-01T12:00:00+00:00","going_count":4,"going":false},
         {"id":"e2","title":"Ride","event_date":"2026-10-25","start_time":"6 PM","location":null,
          "image_url":null,"category":null,"club_name":"Bike club","source_name":null,"end_at":null,
          "all_day":false,"created_at":"2026-10-01T12:00:00+00:00","going_count":1,"going":true}]
        """
        let rows = try CommunityAPI.myGoingRows(from: Data(json.utf8), saved: true)
        XCTAssertEqual(rows.map(\.rsvpd), [false, true])
        XCTAssertTrue(rows.allSatisfy(\.saved))
        XCTAssertTrue(rows.compactMap(YouCalendar.event(from:)).allSatisfy(\.item.isSaved))
    }

    // MARK: The Places row (ticket 03)

    /// Each place once with its next Event there, one not over yet, soonest first: past
    /// days and this morning's finished Event drop off, today's all-day one stays; the
    /// same typed name in another case, spacing or apostrophe is the same place; an Event
    /// with no place is left out.
    func testPlacesShowEachPlacesNextEventSoonestFirst() {
        let now = town("2026-10-14 12:00")
        let first = YouCalendar.firstDay(of: now)
        let read = [row("past", "2026-10-13", "6 PM", at: "Bad Habit Brewing"),
                    row("tonight", "2026-10-14", "7 PM", at: "Saint Ben's"),
                    row("morning", "2026-10-14", "8 AM", at: "The Local Blend"),
                    row("fair", "2026-10-14", nil, allDay: true, at: "Centennial Park"),
                    row("again", "2026-10-16", "6 PM", at: " saint  ben’s "),
                    row("nowhere", "2026-10-17", "6 PM", at: nil),
                    row("blank", "2026-10-17", "7 PM", at: "  "),
                    row("blend", "2026-10-19", "8 AM", at: "The Local Blend"),
                    row("later", "2026-10-20", "6 PM", at: "Bad Habit Brewing")]
            .compactMap(YouCalendar.event(from:))
        let going = YouCalendar.going(read: read, tapped: [], isGoing: { _ in true }, first: first)
        XCTAssertEqual(YouCalendar.places(going, now: now).map(\.id), ["tonight", "fair", "blend", "later"])
    }

    /// A Join adds its place; leaving the sooner Event at a place moves the place to the
    /// next one there, and leaving the last takes the place off.
    func testAJoinOrLeaveChangesPlaces() {
        let now = town("2026-10-14 12:00")
        let first = YouCalendar.firstDay(of: now)
        let read = [row("soon", "2026-10-15", "6 PM", at: "Klinefelter Park"),
                    row("next", "2026-10-22", "6 PM", at: "Klinefelter Park")]
            .compactMap(YouCalendar.event(from:))
        let joined = FeedCardItem(row("joined", "2026-10-16", "7 PM", at: "Saint Ben's"))
        func places(going ids: Set<String>) -> [String] {
            YouCalendar.places(YouCalendar.going(read: read, tapped: [joined], isGoing: { ids.contains($0.id) },
                                                 first: first), now: now).map(\.id)
        }
        XCTAssertEqual(places(going: ["soon", "next"]), ["soon"])
        XCTAssertEqual(places(going: ["soon", "next", "joined"]), ["soon", "joined"])
        XCTAssertEqual(places(going: ["next", "joined"]), ["joined", "next"])
        XCTAssertEqual(places(going: ["joined"]), ["joined"])
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
                                      setGoing: { _, _ in }, setHeart: { _, _ in }, setSave: { _, _ in },
                                      knownEvents: { _ in [] })
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

    /// VoiceOver reads a day as its date and how many plans it has.
    func testVoiceOverReadsTheDayAndItsPlans() {
        XCTAssertEqual(YouPage.spoken(town("2026-10-13 00:00"), plans: 2), "Tuesday, October 13, 2 plans")
        XCTAssertEqual(YouPage.spoken(town("2026-10-13 00:00"), plans: 0), "Tuesday, October 13, nothing planned")
        XCTAssertEqual(YouPage.spoken(town("2026-10-13 00:00"), plans: 1, today: true), "Today, Tuesday, October 13, 1 plan")
    }

    /// `get_my_going`'s rows decode into Going Events, an all-day one and a club's included.
    func testTheReadsRowsDecode() throws {
        let json = """
        [{"id":"e1","title":"Fall market","event_date":"2026-10-24","start_time":"8 AM",
          "location":"Centennial Park","image_url":null,"category":"food","club_name":null,
          "source_name":"City of St. Joseph","end_at":"2026-10-24T17:00:00+00:00","all_day":false,
          "created_at":"2026-10-01T12:00:00+00:00","going_count":4},
         {"id":"e2","title":"Ride","event_date":"2026-10-25","start_time":null,"location":null,
          "image_url":null,"category":null,"club_name":"Bike club","source_name":null,"end_at":null,
          "all_day":true,"created_at":"2026-10-01T12:00:00+00:00","going_count":1}]
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

    // MARK: The name pill

    func testThePillShowsTheFirstNameOnly() {
        XCTAssertEqual(YouPage.firstName("Jesse Johnson"), "Jesse")
        XCTAssertEqual(YouPage.firstName("  Mary Ann\n"), "Mary")
        XCTAssertEqual(YouPage.firstName("Jesse"), "Jesse")
        // No saved name: no pill, just the photo.
        XCTAssertNil(YouPage.firstName(nil))
        XCTAssertNil(YouPage.firstName(""))
        XCTAssertNil(YouPage.firstName("   "))
    }
}
