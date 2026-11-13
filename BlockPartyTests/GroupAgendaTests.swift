//
//  GroupAgendaTests.swift
//  BlockPartyTests — Group get-togethers on your Agenda (BP app docs/plans/rsvp-and-groups, ticket 09):
//  what the toast's Add, a green Add and the long press each put on or take off, what's kept on the
//  phone, and which get-togethers the Calendar and Coming up show.
//

import XCTest
@testable import BlockParty

@MainActor
final class GroupAgendaTests: XCTestCase {
    /// A Town wall-clock moment, "2026-11-13 12:00".
    private func town(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Town.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    private func defaults() -> UserDefaults {
        let name = "GroupAgendaTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private let legion = TownGroup(id: "legion", name: "American Legion Post 328", meetings: [
        .init(what: "500 cards", day: "2026-11-18", time: "13:30"),
        .init(what: "Bingo", day: "2026-11-23", time: "18:30"),
        .init(what: "Membership meeting", day: "2026-12-29", time: "19:00"),
    ])
    private let runners = TownGroup(id: "runners", name: "St. Cloud River Runners", meetings: [
        .init(what: "Breakfast Run", day: "2026-11-13", time: "06:00"),
        .init(what: "Coffee Run", day: "2026-11-15", time: "07:30"),
        .init(what: "Away Run", day: "2026-11-16", time: "07:30", away: true),
    ])

    // MARK: The choices

    /// A green Add puts one on, its Added takes it off; the toast's Add puts the whole Group on, and a
    /// long press takes one of those off while the rest stay.
    func testAddsAndTakesOff() {
        let agenda = GroupAgenda(defaults: defaults(), clock: { self.town("2026-11-13 12:00") })
        let cards = legion.meetings[0], bingo = legion.meetings[1]
        XCTAssertEqual(agenda.state(legion, cards), .off)
        agenda.toggle(legion, cards)
        XCTAssertEqual(agenda.state(legion, cards), .one)
        XCTAssertEqual(agenda.state(legion, bingo), .off)
        agenda.toggle(legion, cards)
        XCTAssertEqual(agenda.state(legion, cards), .off)

        agenda.addGroup(legion)
        XCTAssertEqual(agenda.state(legion, cards), .group)
        XCTAssertEqual(agenda.state(legion, bingo), .group)
        agenda.remove(legion, cards)
        XCTAssertEqual(agenda.state(legion, cards), .off)
        XCTAssertEqual(agenda.state(legion, bingo), .group)
        // Its green Add puts it back with its Group.
        agenda.toggle(legion, cards)
        XCTAssertEqual(agenda.state(legion, cards), .group)
    }

    /// The toast asks only for a Group with a get-together still to come here, and a join starts
    /// the Group over.
    func testAJoinAsksOnlyWithSomethingAhead() {
        let agenda = GroupAgenda(defaults: defaults(), clock: { self.town("2026-11-13 12:00") })
        agenda.addGroup(legion)
        agenda.joined(legion, now: town("2026-11-13 12:00"))
        XCTAssertEqual(agenda.asking?.id, "legion")
        XCTAssertEqual(agenda.state(legion, legion.meetings[0]), .off)

        agenda.asking = nil
        let away = TownGroup(id: "away", name: "Away", meetings: [.init(what: "Run", day: "2026-11-20", time: "08:00", away: true)])
        agenda.joined(away, now: town("2026-11-13 12:00"))
        XCTAssertNil(agenda.asking)
        agenda.joined(legion, now: town("2027-01-01 12:00"))
        XCTAssertNil(agenda.asking, "everything is over")
    }

    /// Kept on the phone for the next launch; another account starts empty.
    func testKeptOnThePhoneUntilAnotherAccount() {
        let store = defaults()
        let agenda = GroupAgenda(defaults: store, clock: { self.town("2026-11-13 12:00") })
        agenda.addGroup(legion)
        agenda.toggle(runners, runners.meetings[1])
        let again = GroupAgenda(defaults: store, clock: { self.town("2026-11-13 12:00") })
        XCTAssertEqual(again.state(legion, legion.meetings[1]), .group)
        XCTAssertEqual(again.state(runners, runners.meetings[1]), .one)
        again.clear()
        XCTAssertEqual(GroupAgenda(defaults: store, clock: { self.town("2026-11-13 12:00") }).state(legion, legion.meetings[1]), .off)
    }

    /// A get-together's choice goes once its day is over, so what's kept stays short.
    func testWhatsOverIsForgotten() {
        let store = defaults()
        var now = town("2026-11-13 12:00")
        let agenda = GroupAgenda(defaults: store, clock: { now })
        agenda.toggle(legion, legion.meetings[0])
        now = town("2026-11-19 09:00")
        agenda.toggle(legion, legion.meetings[1])
        XCTAssertEqual(agenda.state(legion, legion.meetings[0]), .off)
        XCTAssertEqual(agenda.state(legion, legion.meetings[1]), .one)
    }

    // MARK: What You shows

    /// The Calendar's: only those on, inside the three weeks, never an away one, each a card that
    /// knows its Group.
    func testTheCalendarShowsWhatsOnInsideTheThreeWeeks() {
        let first = YouCalendar.firstDay(of: town("2026-11-13 12:00"))
        let plans = YouCalendar.groupPlans([legion, runners], state: { _, _ in .group }, first: first)
        XCTAssertEqual(plans.map(\.item.title), ["500 cards", "Bingo", "Breakfast Run", "Coffee Run"])
        XCTAssertEqual(plans.first?.group?.id, "legion")
        XCTAssertEqual(plans.first?.starts, town("2026-11-18 13:30"))
        XCTAssertTrue(YouCalendar.groupPlans([legion], state: { _, _ in .off }, first: first).isEmpty)

        let going = YouCalendar.withGroups([], plans)
        XCTAssertEqual(going.map(\.item.title), ["Breakfast Run", "Coffee Run", "500 cards", "Bingo"])
    }

    /// Coming up: the next three still to come that aren't on with their Group, soonest first; one
    /// added by itself stays, to show Added.
    func testComingUpLeavesOutWhatsOnWithItsGroup() {
        let now = town("2026-11-13 12:00")
        let state: (TownGroup, TownGroup.Meeting) -> GroupAgenda.State = { group, meeting in
            group.id == "runners" ? .group : meeting.what == "Bingo" ? .one : .off
        }
        let rows = YouCalendar.comingUp([legion, runners], state: state, now: now)
        XCTAssertEqual(rows.map(\.item.title), ["500 cards", "Bingo", "Membership meeting"])
        let all = YouCalendar.comingUp([runners], state: { _, _ in .off }, now: now)
        XCTAssertEqual(all.map(\.item.title), ["Coffee Run"], "this morning's run is over, the away one never shows")
    }

    /// A get-together with no time runs its whole day; its row says whose it is.
    func testAnUntimedGetTogether() throws {
        let meeting = TownGroup.Meeting(what: "Meeting", day: "2026-12-14")
        let event = try XCTUnwrap(YouCalendar.event(legion, meeting))
        XCTAssertFalse(event.timed)
        XCTAssertTrue(YouCalendar.stillToCome(meeting, now: town("2026-12-14 20:00")))
        XCTAssertEqual(YouComingUp.line(legion.meetings[0], group: legion), "Wed 1:30 PM · American Legion Post 328")
    }
}
