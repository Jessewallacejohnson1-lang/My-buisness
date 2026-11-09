//
//  NewEventTests.swift
//  BlockPartyTests — New post, from the Town bar's + (BP app references/post-screen, town-feed 29), and
//  its Event chip, town-plus's New event (references/town-plus): what Post and Share send, how the
//  instant check's answer reads, and how the pill says it.
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

    // MARK: Filter (BP app town-feed 52)

    func testFilterSendsNothingUntilSomethingIsPicked() {
        let input = NewEventDraft().input(id: "abc", imageURL: nil)
        XCTAssertNil(input.forGender)
        XCTAssertNil(input.ages)
    }

    func testFilterSendsTheGenderAsOnboardingSavesItAndTheAgeAsTheCardSaysIt() {
        var draft = NewEventDraft()
        draft.gender = .female
        draft.ages = EventAges(youngest: 18, oldest: EventAges.top)
        let input = draft.input(id: "abc", imageURL: nil)
        XCTAssertEqual(input.forGender, "female")
        XCTAssertEqual(input.ages, "18+")
    }

    func testAnAgeRangeReadsInTheCardsShapes() {
        XCTAssertNil(EventAges().words, "all ages says nothing")
        XCTAssertEqual(EventAges(youngest: 21, oldest: EventAges.top).words, "21+")
        XCTAssertEqual(EventAges(youngest: 0, oldest: 12).words, "Ages 12 and under")
        XCTAssertEqual(EventAges(youngest: 6, oldest: 14).words, "Ages 6–14")
    }

    func testAnEndNeverPassesTheOtherOrTheSlidersEnds() {
        var ages = EventAges(youngest: 10, oldest: 20)
        ages.move(.youngest, to: 30)
        XCTAssertEqual(ages.youngest, 19)
        ages.move(.oldest, to: 5)
        XCTAssertEqual(ages.oldest, 20)
        ages.move(.youngest, to: -4)
        XCTAssertEqual(ages.youngest, 0)
        ages.move(.oldest, to: 200)
        XCTAssertEqual(ages.oldest, EventAges.top)
    }

    func testAFingerTakesTheEndItIsPastElseTheNearer() {
        let ages = EventAges(youngest: 10, oldest: 30)
        XCTAssertEqual(ages.end(nearest: 4), .youngest)
        XCTAssertEqual(ages.end(nearest: 50), .oldest)
        XCTAssertEqual(ages.end(nearest: 14), .youngest)
        XCTAssertEqual(ages.end(nearest: 26), .oldest)
        // Both ends at the far left: dragging right moves the oldest only once past it.
        XCTAssertEqual(EventAges(youngest: 0, oldest: 1).end(nearest: 0), .youngest)
    }

    func testTheFilterRowSumsUpThePicks() {
        XCTAssertNil(NewEventFilterCopy.summary(gender: nil, ages: EventAges()))
        XCTAssertEqual(NewEventFilterCopy.summary(gender: .female, ages: EventAges()), "Women")
        XCTAssertEqual(NewEventFilterCopy.summary(gender: .male, ages: EventAges(youngest: 21, oldest: EventAges.top)), "Men · 21+")
        XCTAssertEqual(NewEventFilterCopy.summary(gender: nil, ages: EventAges(youngest: 6, oldest: 14)), "Ages 6–14")
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

    // MARK: New post (town-feed 29)

    func testPostLightsUpWithWordsOrAPhoto() {
        var draft = NewPostDraft()
        XCTAssertFalse(draft.ready(photo: false))
        XCTAssertTrue(draft.ready(photo: true), "a photo alone")
        draft.words = "  \n "
        XCTAssertFalse(draft.ready(photo: false), "blank words")
        draft.words = "Sledding?"
        XCTAssertTrue(draft.ready(photo: false))
    }

    func testWordsAreBigWhileShortWithNoPhoto() {
        var draft = NewPostDraft()
        draft.words = String(repeating: "a", count: NewPostDraft.bigUntil)
        XCTAssertTrue(draft.big(photo: false))
        XCTAssertFalse(draft.big(photo: true), "a photo makes them small")
        draft.words += "a"
        XCTAssertFalse(draft.big(photo: false), "past 85 letters")
    }

    func testPostSendsTheTrimmedWordsPlaceAndTaggedFriends() {
        var draft = NewPostDraft()
        draft.words = "  Burger night \n"
        draft.place = " Sal's "
        draft.tagged = [Neighbor(userId: "u2", displayName: "Sam Lee", avatarUrl: nil, since: nil, relation: .friends,
                                 mutualFriends: 0)]
        XCTAssertEqual(draft.input(id: "p1", imageURL: "https://x/p1.jpg", aspect: 0.8),
                       NewPostInput(id: "p1", words: "Burger night", imageURL: "https://x/p1.jpg", aspect: 0.8,
                                    place: "Sal's", friendsOnly: false, tagged: ["u2"]))
        XCTAssertNil(draft.input(id: "p1", imageURL: nil, aspect: 0.8).aspect, "no photo, no shape")
        draft.friendsOnly = true
        draft.place = "  "
        let friends = draft.input(id: "p1", imageURL: nil, aspect: nil)
        XCTAssertTrue(friends.friendsOnly)
        XCTAssertNil(friends.place, "a blank Place is none")
        XCTAssertEqual(draft.line(name: "Jesse"), "Jesse is with Sam Lee.")
    }

    func testLongWordsAreCutAtTheChecksLimit() {
        var draft = NewPostDraft()
        draft.words = String(repeating: "a", count: 2500)
        XCTAssertEqual(draft.text.count, NewPostDraft.wordsLimit)
    }

    /// A photo is cut from its middle into Instagram's limits, 4:5 tall to 1.91:1 wide; one inside
    /// them keeps its shape.
    func testAPhotoIsCutIntoInstagramsLimits() {
        XCTAssertEqual(NewPostDraft.aspect(CGSize(width: 1000, height: 3000)), 0.8)
        XCTAssertEqual(NewPostDraft.aspect(CGSize(width: 4000, height: 1000)), 1.91)
        XCTAssertEqual(NewPostDraft.aspect(CGSize(width: 1200, height: 900)), 4.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(NewPostDraft.cropRect(CGSize(width: 1000, height: 3000)), CGRect(x: 0, y: 875, width: 1000, height: 1250))
        let wide = NewPostDraft.cropRect(CGSize(width: 4000, height: 1000))
        XCTAssertEqual(wide.width, 1910, accuracy: 1)
        XCTAssertEqual(wide.midX, 2000, accuracy: 1, "from the middle")
        XCTAssertEqual(wide.height, 1000)
        XCTAssertEqual(NewPostDraft.cropRect(CGSize(width: 1200, height: 900)), CGRect(x: 0, y: 0, width: 1200, height: 900))
    }

    /// The Event chip shares an Event with New post's words as its description.
    func testAnEventCarriesThePostsWordsAsItsDescription() {
        var draft = NewEventDraft(now: town("2026-11-01 15:00"))
        draft.name = "Sledding"
        draft.place = "Millstream Park"
        draft.about = "  Bring a sled "
        XCTAssertEqual(draft.input(id: "e1", imageURL: nil).description, "Bring a sled")
        draft.about = " "
        XCTAssertNil(draft.input(id: "e1", imageURL: nil).description)
    }
}
