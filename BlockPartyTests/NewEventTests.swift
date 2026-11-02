//
//  NewEventTests.swift
//  BlockPartyTests — New event, from the Town bar's + (BP app references/town-plus): what Share
//  sends, how the instant check's answer reads, and how the pill says it.
//

import XCTest
@testable import BlockParty

@MainActor
final class NewEventTests: XCTestCase {
    /// "2026-11-01 15:00" in St. Joseph.
    private func town(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Town.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    func testItStartsTonightAtSevenOrTomorrowOnceThatsPast() {
        XCTAssertEqual(NewEventDraft.defaultWhen(now: town("2026-11-01 15:00")), town("2026-11-01 19:00"))
        XCTAssertEqual(NewEventDraft.defaultWhen(now: town("2026-11-01 19:30")), town("2026-11-02 19:00"))
    }

    func testTheTimeGoesOutOnTheTownsTwentyFourHourClock() {
        XCTAssertEqual(NewEventDraft.clock(town("2026-11-01 19:00")), "19:00")
        XCTAssertEqual(NewEventDraft.clock(town("2026-11-07 09:05")), "09:05")
    }

    func testShareSendsTheTrimmedNameAndPlaceOnTheTownsDay() {
        var draft = NewEventDraft(now: town("2026-11-01 15:00"))
        draft.name = "  Porch concert \n"
        draft.place = " Millstream Park "
        draft.when = town("2026-11-07 23:30")
        let input = draft.input(id: "abc", imageURL: "https://example.com/p.jpg")
        XCTAssertEqual(input.id, "abc")
        XCTAssertEqual(input.title, "Porch concert")
        XCTAssertEqual(input.location, "Millstream Park")
        XCTAssertEqual(input.eventDate, "2026-11-07")
        XCTAssertEqual(input.startTime, "23:30")
        XCTAssertEqual(input.imageUrl, "https://example.com/p.jpg")
        XCTAssertEqual(input.category, EventCategory.other.rawValue)
    }

    func testANameAndAPlaceAreBothNeeded() {
        var draft = NewEventDraft()
        XCTAssertFalse(draft.ready)
        draft.name = "Porch concert"
        XCTAssertFalse(draft.ready, "no place")
        draft.place = "   "
        XCTAssertFalse(draft.ready, "a blank place")
        draft.place = "Millstream Park"
        XCTAssertTrue(draft.ready)
    }

    func testLongWordsAreCut() {
        var draft = NewEventDraft()
        draft.name = String(repeating: "a", count: 300)
        draft.place = String(repeating: "b", count: 300)
        XCTAssertEqual(draft.title.count, NewEventDraft.nameLimit)
        XCTAssertEqual(draft.location.count, NewEventDraft.placeLimit)
    }

    func testPlaceListsParksAndPlacesToEatOrDrinkFirst() {
        let items = [
            SearchItem(id: "1", kind: .business, name: "Autobody 2000", keywords: ["car repair"]),
            SearchItem(id: "2", kind: .business, name: "Bad Habit Brewing", keywords: ["brewery"]),
            SearchItem(id: "3", kind: .park, name: "Millstream Park"),
            SearchItem(id: "4", kind: .restaurant, name: "Bello Cucina", keywords: ["italian restaurant"]),
            SearchItem(id: "5", kind: .business, name: "Barber Bros", keywords: ["barber shop"]),
            SearchItem(id: "6", kind: .coffee, name: "The Local Blend", keywords: ["coffee shop"]),
            SearchItem(id: "7", kind: .event, name: "Rocktoberfest"),
            SearchItem(id: "8", kind: .business, name: "Sal's", keywords: ["bar and grill"]),
        ]
        XCTAssertEqual(NewEventPlaces.ordered(items).map(\.name),
                       ["Bad Habit Brewing", "Bello Cucina", "Millstream Park", "Sal's", "The Local Blend",
                        "Autobody 2000", "Barber Bros"])
    }

    func testTheChecksAnswerReads() {
        XCTAssertEqual(CommunityAPI.check(ok: true, reason: ""), .live)
        XCTAssertEqual(CommunityAPI.check(ok: false, reason: "This reads like an ad."), .declined("This reads like an ad."))
        guard case .declined(let words) = CommunityAPI.check(ok: false, reason: "  ") else { return XCTFail("a no") }
        XCTAssertFalse(words.isEmpty, "a no without words still says something")
    }

    func testThePillSaysItAtOnceAndTheBellKeepsIt() {
        let photo = URL(string: "https://example.com/p.jpg")
        let live = HelloItem(what: .posted(.init(eventId: "e1", title: "Porch concert", photo: photo, live: true,
                                                 eventDate: "2026-11-30", startTime: "19:00", location: "Bad Habit Brewing")), at: Date())
        XCTAssertTrue(live.yours, "a tap's answer, outside the 3 a day")
        XCTAssertEqual(live.rank, 0)
        XCTAssertEqual(live.id, "posted:e1")
        XCTAssertEqual(live.message?.text, "Your event is live")
        // Its page opens from the pill even while it's more than two weeks out and not on Town yet.
        guard case .event(let card)? = live.message?.target else { return XCTFail("the pill opens its Event") }
        XCTAssertEqual(card.id, "e1")
        XCTAssertEqual(card.title, "Porch concert")
        XCTAssertEqual(card.eventDate, "2026-11-30")
        XCTAssertEqual(live.message?.logo, photo)
        XCTAssertEqual(live.row().words, "shared Porch concert.")

        let waiting = HelloItem(what: .posted(.init(eventId: "e2", title: "Porch concert", photo: nil, live: false,
                                                    eventDate: "2026-11-30", startTime: "19:00", location: "Bad Habit Brewing")), at: Date())
        XCTAssertEqual(waiting.message?.text, "Shared. It goes up once it's checked.")
        XCTAssertEqual(waiting.message?.target, .town)
        XCTAssertEqual(waiting.row().words, "shared Porch concert. It goes up once it's checked.")
        XCTAssertEqual(waiting.row().picture, .tick)
    }

    func testARetryCountsWhatAlreadyLandedAsSent() {
        XCTAssertTrue(SupabaseError(message: "duplicate key value violates unique constraint \"club_events_pkey\"", status: 409).alreadyThere)
        XCTAssertTrue(SupabaseError(message: "The resource already exists", status: 400).alreadyThere)
        XCTAssertFalse(SupabaseError(message: "new row violates row-level security policy", status: 403).alreadyThere)
        XCTAssertFalse(SupabaseError(message: "The server couldn't complete this request.", status: 0).alreadyThere)
    }

    func testAnotherAccountForgetsWhatThisOneShared() {
        let keep = UserDefaults(suiteName: "NewEventTests")!
        keep.removePersistentDomain(forName: "NewEventTests")
        let inbox = HelloInbox(keep: keep)
        inbox.add(.posted(.init(eventId: "e1", title: "Porch concert", photo: nil, live: true,
                                eventDate: "2026-11-30", startTime: "19:00", location: "Bad Habit Brewing")))
        XCTAssertEqual(inbox.next?.id, "posted:e1")
        inbox.forgetAccount()
        XCTAssertNil(inbox.next)
    }
}
