//
//  CalendarSyncTests.swift
//  BlockPartyTests — your Going in your iPhone Calendar (BP app docs/plans/you-tab, ticket
//  05), through a stand-in for EventKit: added once on Going, removed on leaving, the
//  upcoming Going added when switched on, a refusal flipping back, and your own edits to
//  the calendar left alone.
//

import XCTest
@testable import BlockParty

/// The phone's calendar in memory. `delete` and `move` are the person, in Apple Calendar.
@MainActor
private final class FakeCalendar: PhoneCalendar {
    var allows = true
    var hasAccess = false
    var entries: [String: CalendarEntry] = [:]
    var asked = 0
    private var next = 0

    func requestAccess() async -> Bool {
        asked += 1
        hasAccess = allows
        return allows
    }
    func exists(_ ref: String) -> Bool { entries[ref] != nil }
    func find(_ entry: CalendarEntry) -> String? {
        entries.first { $0.value.title == entry.title && $0.value.starts == entry.starts }?.key
    }
    func add(_ entry: CalendarEntry) throws -> String {
        next += 1
        entries["ref\(next)"] = entry
        return "ref\(next)"
    }
    func update(_ ref: String, to entry: CalendarEntry) throws { entries[ref] = entry }
    func remove(_ ref: String) throws { entries[ref] = nil }

    var titles: [String] { entries.values.map(\.title).sorted() }
}

@MainActor
final class CalendarSyncTests: XCTestCase {
    private var phone: FakeCalendar!
    private var defaults: UserDefaults!
    private var account: String? = "me"
    /// What `get_my_going` answers; nil fails the read.
    private var rows: [UpcomingEvent]? = []

    override func setUp() {
        phone = FakeCalendar()
        defaults = UserDefaults(suiteName: "CalendarSyncTests-\(UUID().uuidString)")
        account = "me"
        rows = []
    }

    private func town(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Town.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    private func row(_ id: String, _ day: String, _ time: String? = "6 PM", allDay: Bool = false) -> UpcomingEvent {
        UpcomingEvent(id: id, title: id, eventDate: day, startTime: time, location: "Klinefelter Park",
                      goingCount: 1, createdAt: "", rsvpd: true, endAt: nil, isAllDay: allDay)
    }

    private func makeSync() -> CalendarSync {
        CalendarSync(calendar: phone, defaults: defaults, account: { [unowned self] in self.account },
                     read: { [unowned self] _, _ in
                         guard let rows = self.rows else { throw URLError(.notConnectedToInternet) }
                         return rows
                     })
    }

    private func sync(_ s: CalendarSync, tapped: [FeedCardItem] = [], isGoing: @escaping (FeedCardItem) -> Bool = { _ in true }) async {
        await s.sync(tapped: tapped, isGoing: isGoing, now: town("2026-10-14 12:00"))
    }

    /// Switched on, then the shell's sync that follows.
    private func on(_ s: CalendarSync) async {
        await s.turnOn()
        await sync(s)
    }

    /// Off until switched on; switching on asks iOS and adds every upcoming Going once.
    func testSwitchingOnAddsTheUpcomingGoingOnce() async {
        rows = [row("hike", "2026-10-15"), row("market", "2026-12-20")]
        let s = makeSync()
        XCTAssertFalse(s.isOn)
        await sync(s)
        XCTAssertEqual(phone.titles, [], "off syncs nothing")
        await s.turnOn()
        XCTAssertTrue(s.isOn)
        XCTAssertEqual(phone.asked, 1)
        await sync(s)
        await sync(s)
        XCTAssertEqual(phone.titles, ["hike", "market"])
        XCTAssertTrue(makeSync().isOn, "the switch is kept on the phone")
    }

    /// iOS says no: the switch flips back, shakes once, and says why; nothing is added.
    func testARefusalFlipsTheSwitchBack() async {
        rows = [row("hike", "2026-10-15")]
        phone.allows = false
        let s = makeSync()
        await s.turnOn()
        XCTAssertFalse(s.isOn)
        XCTAssertFalse(s.asking)
        XCTAssertTrue(s.refused)
        XCTAssertEqual(s.refusals, 1)
        XCTAssertEqual(phone.titles, [])
    }

    /// Going adds the Event; leaving takes it out.
    func testGoingAddsAndLeavingRemoves() async {
        rows = [row("hike", "2026-10-15")]
        let s = makeSync()
        await on(s)
        let card = FeedCardItem(row("ride", "2026-10-20"))
        await sync(s, tapped: [card])
        XCTAssertEqual(phone.titles, ["hike", "ride"])
        await sync(s, tapped: [card], isGoing: { $0.id != "ride" })
        XCTAssertEqual(phone.titles, ["hike"])
    }

    /// The Event's time changes: the entry moves. The person moves it themselves: it stays
    /// where they put it.
    func testATimeChangeMovesItButYourMoveStays() async {
        rows = [row("hike", "2026-10-15", "6 PM")]
        let s = makeSync()
        await on(s)
        let ref = phone.entries.first!.key
        phone.entries[ref]!.starts = town("2026-10-15 09:00")
        await sync(s)
        XCTAssertEqual(phone.entries[ref]?.starts, town("2026-10-15 09:00"), "your move stays")
        rows = [row("hike", "2026-10-15", "7 PM")]
        await sync(s)
        XCTAssertEqual(phone.entries[ref]?.starts, town("2026-10-15 19:00"), "the Event's own change moves it")
        XCTAssertEqual(phone.entries.count, 1)
    }

    /// An entry the person deletes stays deleted.
    func testYourDeleteStaysDeleted() async {
        rows = [row("hike", "2026-10-15")]
        let s = makeSync()
        await on(s)
        phone.entries = [:]
        await sync(s)
        XCTAssertEqual(phone.titles, [])
    }

    /// A failed read is not "nothing Going": the calendar stays as it is.
    func testAFailedReadChangesNothing() async {
        rows = [row("hike", "2026-10-15")]
        let s = makeSync()
        await on(s)
        rows = nil
        await sync(s)
        XCTAssertEqual(phone.titles, ["hike"])
    }

    /// A new account starts over and leaves the calendar alone (Jesse, 2026-10-12).
    func testANewAccountLeavesTheCalendarAlone() async {
        rows = [row("hike", "2026-10-15")]
        let s = makeSync()
        await on(s)
        account = "someone new"
        rows = []
        await sync(s)
        XCTAssertEqual(phone.titles, ["hike"])
    }

    /// The app deleted and put back: what's kept on the phone is gone, the entries aren't.
    /// Switching on again adopts them rather than adding them twice.
    func testPuttingTheAppBackAddsNothingTwice() async {
        rows = [row("hike", "2026-10-15")]
        await on(makeSync())
        defaults = UserDefaults(suiteName: "CalendarSyncTests-\(UUID().uuidString)")
        let again = makeSync()
        await on(again)
        XCTAssertEqual(phone.titles, ["hike"])
    }

    /// Over already: left in the calendar when it drops out of the read.
    func testAPastEntryIsLeftAlone() async {
        rows = [row("hike", "2026-10-15")]
        let s = makeSync()
        await on(s)
        rows = []
        await s.sync(tapped: [], isGoing: { _ in true }, now: town("2026-10-16 12:00"))
        XCTAssertEqual(phone.titles, ["hike"])
    }

    /// "After dark" and all-day Events go in as all-day entries on their day.
    func testUntimedEventsAreAllDay() async {
        rows = [row("dark", "2026-10-15", "after dark"), row("fair", "2026-10-16", "9 AM", allDay: true)]
        let s = makeSync()
        await on(s)
        XCTAssertEqual(phone.entries.values.map(\.allDay), [true, true])
        XCTAssertEqual(phone.entries.values.first { $0.title == "dark" }?.starts, town("2026-10-15 00:00"))
    }

    /// Access taken away in Settings: the switch goes off and says so; nothing is touched.
    func testAccessTakenAwayTurnsTheSwitchOff() async {
        rows = [row("hike", "2026-10-15")]
        let s = makeSync()
        await on(s)
        phone.hasAccess = false
        rows = []
        await sync(s)
        XCTAssertFalse(s.isOn)
        XCTAssertTrue(s.refused)
        XCTAssertEqual(phone.titles, ["hike"])
    }
}
