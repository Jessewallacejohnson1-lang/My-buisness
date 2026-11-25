//
//  GroupCalendarTests.swift
//  BlockPartyTests — the Group page's Calendar (BP app docs/plans/start-a-group, ticket 05): which days of the month
//  grid have Events and get-togethers, which months the arrows step through, the day picked first and its list, and
//  what Add when you meet sends.
//

import SwiftUI
import XCTest
@testable import BlockParty

@MainActor
final class GroupCalendarTests: XCTestCase {
    private func day(_ text: String) -> Date { Town.midnight(text)! }

    private func card(_ title: String, _ day: String, _ time: String?) -> FeedCardItem {
        var card = FeedCardItem(id: title, title: title, dateChip: "", metaLine: "", image: .fallback, recurrence: nil,
                                goingCount: 0, goingAvatars: [], likeCount: 0, isLiked: false, isJoined: false)
        card.eventDate = day
        card.startTime = time
        return card
    }

    private var sewing: TownGroup {
        var group = TownGroup(id: "sewing", name: "Joetown Sewing Circle",
                              photos: [PlacePicture(url: URL(string: "https://example.com/yarn.jpg")!, kind: .photo)])
        group.location = "Resurrection Lutheran"
        return group
    }

    private let tuesdays = [TownGroup.Meeting(what: "Get-together", day: "2026-11-24", time: "18:30"),
                            TownGroup.Meeting(what: "Get-together", day: "2026-12-01", time: "18:30"),
                            TownGroup.Meeting(what: "Get-together", day: "2027-01-05", time: "18:30")]

    /// The grid lights each day with an Event or a get-together; a get-together wears the Group's own photo, as the
    /// mock's Tuesday does, and an Event on a get-together's day takes its place (it is that get-together, with a
    /// page of its own: rsvp-and-groups 10).
    func testGridDaysWithEventsAndGetTogethers() {
        let plans = GroupCalendar.plans(sewing, meetings: tuesdays,
                                        events: [card("Holiday quilt swap", "2026-11-28", "10 AM"),
                                                 card("Christmas sewing night", "2026-12-01", "6:30 PM")])
        let byDay = YouCalendar.byDay(plans)
        XCTAssertEqual(Set(byDay.keys), [day("2026-11-24"), day("2026-11-28"), day("2026-12-01"), day("2027-01-05")])
        XCTAssertEqual(byDay[day("2026-12-01")]?.map(\.item.title), ["Christmas sewing night"], "the Event takes the day")
        let tuesday = byDay[day("2026-11-24")]?.first
        XCTAssertEqual(tuesday?.item.title, "Get-together")
        XCTAssertEqual(tuesday?.group?.id, "sewing")
        XCTAssertEqual(tuesday?.photo?.absoluteString, "https://example.com/yarn.jpg", "the day circle shows the Group's photo")
        XCTAssertEqual(tuesday.flatMap(YouCalendar.place), "Resurrection Lutheran")
        XCTAssertEqual(plans.map(\.item.title).first, "Get-together", "in the Calendar's order")
    }

    /// The day's list: its Events and get-togethers, timed first by time, then the untimed.
    func testDayList() {
        let plans = GroupCalendar.plans(sewing, meetings: [.init(what: "Get-together", day: "2026-11-28", time: "18:30")],
                                        events: [card("Holiday quilt swap", "2026-11-28", "10 AM"),
                                                 card("Open sewing", "2026-11-29", nil)])
        // The quilt swap is that day's Event, so the get-together goes: one row a day as Coming up had.
        XCTAssertEqual(YouCalendar.byDay(plans)[day("2026-11-28")]?.map(\.item.title), ["Holiday quilt swap"])
        let two = GroupCalendar.plans(sewing, meetings: [], events: [card("Evening", "2026-12-06", "7 PM"),
                                                                     card("Morning", "2026-12-06", "8 AM")])
        XCTAssertEqual(YouCalendar.byDay(two)[day("2026-12-06")]?.map(\.item.title), ["Morning", "Evening"])
    }

    /// ‹ › step through this month and each later one with a plan; nothing planned still shows this month.
    func testMonths() {
        let plans = GroupCalendar.plans(sewing, meetings: tuesdays, events: [])
        XCTAssertEqual(GroupCalendar.months(plans, today: day("2026-11-22")),
                       [day("2026-11-01"), day("2026-12-01"), day("2027-01-01")])
        XCTAssertEqual(GroupCalendar.months([], today: day("2026-11-22")), [day("2026-11-01")])
        XCTAssertEqual(GroupCalendar.months(plans, today: day("2026-12-10")), [day("2026-12-01"), day("2027-01-01")],
                       "a month gone by isn't stepped back to")
    }

    /// Opened, the next day with a plan is picked, today included; nothing ahead picks none.
    func testFirstDay() {
        let plans = GroupCalendar.plans(sewing, meetings: tuesdays, events: [])
        XCTAssertEqual(GroupCalendar.first(plans, today: day("2026-11-22")), day("2026-11-24"))
        XCTAssertEqual(GroupCalendar.first(plans, today: day("2026-11-24")), day("2026-11-24"))
        XCTAssertNil(GroupCalendar.first(plans, today: day("2027-02-01")))
    }

    /// Add when you meet: the picks as `set_group_meets` takes them.
    func testMeetsDraft() {
        var draft = GroupMeetsDraft()
        XCTAssertFalse(draft.ready, "a day first")
        draft.days = ["thu", "tue"]
        XCTAssertTrue(draft.ready)
        XCTAssertEqual(draft.sentDays, ["tue", "thu"], "in the week's order")
        XCTAssertNil(draft.weeks, "every week")
        draft.often = .firstAndThird
        XCTAssertEqual(draft.weeks, [1, 3])
        draft.often = .monthly
        draft.week = 3
        XCTAssertEqual(draft.weeks, [3])
        draft.time = Town.gregorian.date(bySettingHour: 18, minute: 30, second: 0, of: day("2026-11-22"))!
        XCTAssertEqual(draft.clock, "18:30")
        XCTAssertNil(draft.sentPlace)
        draft.place = "  Resurrection Lutheran "
        XCTAssertEqual(draft.sentPlace, "Resurrection Lutheran")
    }

    /// Edit when you meet opens on what the Group already says, and Save with no days clears it.
    func testMeetsDraftOpensOnTheGroupsTimes() {
        let rule = GroupMeetsDraft.Rule(days: ["thu", "tue"], weeks: [1, 3], time: "18:30")
        var draft = GroupMeetsDraft(rule, place: "Resurrection Lutheran")
        XCTAssertEqual(draft.sentDays, ["tue", "thu"])
        XCTAssertEqual(draft.often, .firstAndThird)
        XCTAssertEqual(draft.clock, "18:30")
        XCTAssertEqual(draft.sentPlace, "Resurrection Lutheran")
        XCTAssertTrue(draft.ready)
        XCTAssertEqual(draft.savedPlace, "Resurrection Lutheran")
        draft.days = []
        XCTAssertNil(draft.savedPlace, "and their Place, on the page as the server has it")
        XCTAssertTrue(draft.ready, "no days clears the times it had")
        XCTAssertEqual(draft.sentDays, [], "and sends no days")

        let monthly = GroupMeetsDraft(.init(days: ["mon"], weeks: [2], time: nil), place: nil)
        XCTAssertEqual(monthly.often, .monthly)
        XCTAssertEqual(monthly.week, 2)
        XCTAssertEqual(GroupMeetsDraft(.init(days: ["sat"], weeks: nil, time: "09:05"), place: nil).often, .weekly)
        XCTAssertEqual(GroupMeetsDraft(.init(days: ["sat"], weeks: nil, time: "09:05"), place: nil).clock, "09:05")

        let none = GroupMeetsDraft(nil, place: nil)
        XCTAssertFalse(none.ready, "nothing to clear: a day first")
    }

    /// The checks' answer on a new Place (start-a-group 08): saved with the when line, or held with the reason.
    func testTheChecksAnswerOnAPlace() throws {
        func answer(_ json: String) throws -> GroupMeetsDraft.Answer { try .from(Data(json.utf8)) }
        XCTAssertEqual(try answer(#"{"ok": true, "reason": "", "schedule": "Tuesdays at 6:30 PM"}"#), .saved("Tuesdays at 6:30 PM"))
        XCTAssertEqual(try answer(#"{"ok": false, "reason": "Please leave out the phone number."}"#),
                       .held("Please leave out the phone number."))
        XCTAssertEqual(try answer(#"{"ok": false}"#), .held(""))
        XCTAssertThrowsError(try answer("null"))
    }

    /// `get_group_calendar` as the page reads it: the get-togethers, whether you add, the Group's rule for Edit when you
    /// meet, and the Events its Admin may take off.
    func testCalendarRead() throws {
        let json = """
        {"meetings": [{"what": "Get-together", "day": "2026-11-24", "time": "18:30"}, {"day": 5}],
         "adds": true, "meets": [{"what": "Get-together", "days": ["tue"], "weeks": [1, 3], "time": "18:30"}],
         "takes_off": ["e1", "e2"]}
        """
        let read = try GroupCalendar.Read.from(Data(json.utf8))
        XCTAssertEqual(read.meetings.map(\.day), ["2026-11-24"], "a meeting that doesn't decode is left out")
        XCTAssertTrue(read.adds)
        XCTAssertEqual(read.rule, GroupMeetsDraft.Rule(days: ["tue"], weeks: [1, 3], time: "18:30"))
        XCTAssertEqual(read.takesOff, ["e1", "e2"])

        let member = try GroupCalendar.Read.from(Data(#"{"meetings": [], "adds": false, "meets": null}"#.utf8))
        XCTAssertNil(member.rule)
        XCTAssertEqual(member.takesOff, [], "only the Admin takes Events off")
    }

    /// A Group page inside Start a group's sheet opens an Event on the sheet's own stack, and no host's page.
    func testAGroupPageInASheetOpensOnTheSheetsOwnStack() {
        var path = NavigationPath()
        let opener = HostOpener.inSheet { path.append($0) }
        opener.push(card("Holiday quilt swap", "2026-11-28", "10 AM"))
        XCTAssertEqual(path.count, 1)
        XCTAssertNil(opener.group("sewing"))
    }

    /// New event from a Group page says so, not New post.
    func testNewEventFromAGroupIsTitledNewEvent() {
        XCTAssertEqual(NewPostCopy.title(editing: false, group: true), "New event")
        XCTAssertEqual(NewPostCopy.title(editing: false, group: false), "New post")
        XCTAssertEqual(NewPostCopy.title(editing: true, group: false), PostEditCopy.title)
    }
}
