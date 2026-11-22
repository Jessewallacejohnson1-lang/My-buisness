//
//  GroupCalendarTests.swift
//  BlockPartyTests — the Group page's Calendar (BP app docs/plans/start-a-group, ticket 05): which days of the month
//  grid have Events and get-togethers, which months the arrows step through, the day picked first and its list, and
//  what Add when you meet sends.
//

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
}
