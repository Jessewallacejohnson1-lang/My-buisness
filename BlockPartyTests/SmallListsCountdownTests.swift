//
//  SmallListsCountdownTests.swift
//  BlockPartyTests — the small lists count down as the Town card does (BP app happening-now 07): the Block
//  Party tab's cards and Following rows, You's Agenda, Search's part of the day row and its Event rows, the Event
//  calendar and a Profile's Going rows all say "In 20 min" 20 minutes before a real happening, then "Now".
//

import XCTest
@testable import BlockParty

@MainActor
final class SmallListsCountdownTests: XCTestCase {
    /// A Town wall-clock moment on Nov 15, 2026: `at(18, 40)` is 6:40 PM in St. Joseph.
    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        var parts = DateComponents(year: 2026, month: 11, day: 15, hour: hour, minute: minute)
        parts.timeZone = Town.timeZone
        return Town.gregorian.date(from: parts)!
    }

    /// Music in Millstream Park at 7 PM: a real happening unless `liveKind` says otherwise.
    private func card(_ title: String = "Music in Millstream Park", time: String = "7 PM", liveKind: Bool = true,
                      part: EventPart? = nil) -> FeedCardItem {
        var item = FeedCardItem(id: title, title: title, dateChip: "", metaLine: "",
                                image: .eventPhoto(URL(string: "https://x/\(title.count).webp")!), recurrence: nil,
                                goingCount: 0, goingAvatars: [], likeCount: 0, isLiked: false, isJoined: false,
                                eventDate: "2026-11-15", startTime: time)
        item.liveKind = liveKind
        item.part = part
        return item
    }

    private func event(_ item: FeedCardItem) -> DailyEvent { YouCalendar.event(from: item)! }

    private func plain(_ text: String?) -> String? { text?.replacingOccurrences(of: "\u{202F}", with: " ") }

    /// The words every small list reads (`DailyEvent.startTime`): the Block Party tab's cards (Friends are going and
    /// For you today, on the Friends tab too), the Event calendar's rows and the Agenda.
    func testTheSmallListsTimeCountsDown() {
        let music = event(card())
        XCTAssertEqual(plain(music.startTime(now: at(17, 59))), "7 PM", "61 minutes off: the clock")
        XCTAssertEqual(music.startTime(now: at(18)), "In 60 min")
        XCTAssertEqual(music.startTime(now: at(18, 40)), "In 20 min")
        XCTAssertEqual(music.startTime(now: at(18, 59)), "In 1 min")
        XCTAssertEqual(music.startTime(now: at(19)), "Now", "the start minute")
        XCTAssertNil(music.dayLine(now: at(18, 40)), "today's card says the countdown, not a day")
    }

    /// A sale, an open house or a meeting keeps its time, as on the Town card; so does an untimed Event.
    func testOnlyARealHappeningCountsDown() {
        XCTAssertEqual(plain(event(card(liveKind: false)).startTime(now: at(18, 40))), "7 PM")
        XCTAssertEqual(event(card(time: "after dark")).startTime(now: at(18, 40)), "after dark")
    }

    /// A long Event's part counts down on its Town card ("Artist talk in 20 min"), never on a small list
    /// (Jesse at 07's Check-in 1): the exhibit keeps its own time there.
    func testAPartNeverCountsDownOnASmallList() {
        let talk = EventPart(title: "Artist talk", start: at(19), end: at(20))
        let exhibit = card("Drawings exhibition", time: "10 AM", liveKind: false, part: talk)
        XCTAssertEqual(exhibit.countdown(at: at(18, 40))?.text, "Artist talk in 20 min", "the Town card's")
        XCTAssertEqual(plain(event(exhibit).startTime(now: at(18, 40))), "10 AM")
    }

    /// Following's rows: "St. Joseph Parks & Rec Music in Millstream Park. In 20 min".
    func testFollowingCountsDown() {
        let row = DailyFollowing(id: "f", name: "St. Joseph Parks & Rec", what: "Music in Millstream Park.",
                                 event: event(card()))
        XCTAssertEqual(row.time(now: at(18, 40)), "In 20 min")
    }

    /// You's Agenda and Liked: the countdown, spoken "Starts in 20 minutes", in place of "Tonight · 7 PM" too.
    func testTheAgendaCountsDown() {
        let music = event(card())
        let today = AgendaCards.when(music, now: at(18, 40), withDay: false, pill: nil)
        XCTAssertEqual(today.text, "In 20 min")
        XCTAssertEqual(today.spoken, "Starts in 20 minutes")
        XCTAssertEqual(AgendaCards.when(music, now: at(18, 40), withDay: true, pill: nil).text, "In 20 min", "Liked")
        XCTAssertEqual(AgendaCards.when(music, now: at(19), withDay: true, pill: nil).text, "Now")
        XCTAssertEqual(plain(AgendaCards.when(music, now: at(12), withDay: true, pill: nil).text), "Tonight · 7 PM")
        XCTAssertNotEqual(AgendaCards.when(music, now: at(18, 40), withDay: true, pill: "Soon").text, "In 20 min",
                          "beside the next plan's pill, which already says how far off")
    }

    /// Search's part of the day row, and its Event rows, worked out at the minute they're drawn.
    func testSearchCountsDown() {
        let defaults = UserDefaults(suiteName: "SmallListsCountdownTests")!
        defaults.removePersistentDomain(forName: "SmallListsCountdownTests")
        let model = SearchModel(supabase: Supabase(auth: FakeTokenProvider(), send: FakeServer().send), defaults: defaults)
        model.show(events: [card()], now: at(12))
        XCTAssertEqual(model.happening(at: at(18, 40)).first?.sub, "In 20 min")
        XCTAssertEqual(model.happening(at: at(19)).first?.sub, "Now")
        let row = model.row(.event).first
        XCTAssertEqual(plain(row?.line(at(12))), "7 PM")
        XCTAssertEqual(row?.line(at(18, 40)), "In 20 min", "the row loaded at noon still counts down")
        XCTAssertEqual(row?.line(at(19)), "Now")
    }

    /// A neighbour's Profile, its Coming up rows: "Sun, Nov 15 · In 20 min".
    func testAProfilesGoingRowCountsDown() {
        XCTAssertEqual(ProfileFace.goingLine(event(card()), now: at(18, 40)), "Sun, Nov 15 · In 20 min")
    }
}
