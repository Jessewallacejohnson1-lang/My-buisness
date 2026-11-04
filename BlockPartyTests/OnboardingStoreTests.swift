//
//  OnboardingStoreTests.swift
//  BlockPartyTests — onboarding's place in the flow (BP app onboarding 16): the steps' order,
//  resuming on relaunch, finishing for good, and the server's stamp only taken on the Welcome.
//

import XCTest
@testable import BlockParty

@MainActor
final class OnboardingStoreTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "OnboardingStoreTests")!
        defaults.removePersistentDomain(forName: "OnboardingStoreTests")
    }

    func testStartsOnWelcomeAndWalksTheSevenBarSteps() {
        let store = OnboardingStore(defaults: defaults)
        XCTAssertEqual(store.step, .welcome)
        XCTAssertEqual(store.barIndex, 0)
        var indexes: [Int] = []
        for _ in 0..<OnboardingStep.barTotal { store.next(); indexes.append(store.barIndex) }
        XCTAssertEqual(indexes, Array(1...7))
        XCTAssertEqual(OnboardingStep.barTotal, 7, "Phone and Code wait for phone sign-in (onboarding 24)")
        XCTAssertEqual(store.step, .contacts)
        XCTAssertFalse(store.finished)
        store.next()
        XCTAssertTrue(store.finished)
    }

    func testBackGoesToThePreviousStepAndStopsAtTheFirstQuestion() {
        let store = OnboardingStore(defaults: defaults)
        store.next(); store.next()
        XCTAssertEqual(store.step, .photo)
        store.back()
        XCTAssertEqual(store.step, .name)
        XCTAssertFalse(store.forward)
        store.back()
        XCTAssertEqual(store.step, .name, "the account is made before Name: Back would make a second one")
    }

    func testRelaunchResumesOnTheSameStep() {
        let store = OnboardingStore(defaults: defaults)
        for _ in 0..<2 { store.next() }
        XCTAssertEqual(OnboardingStore(defaults: defaults).step, .photo)
    }

    func testFinishedStaysFinished() {
        let store = OnboardingStore(defaults: defaults)
        for _ in 0..<6 { store.next() }
        XCTAssertEqual(store.step, .friends)
        store.skipFriends()
        XCTAssertTrue(store.finishedHere, "finished through the flow: the Done island's")
        let again = OnboardingStore(defaults: defaults)
        XCTAssertTrue(again.finished)
        XCTAssertFalse(again.finishedHere, "a relaunch has no Done to show")
    }

    func testAnInstallThatOpenedTheTabsBeforeIsAlreadyIn() {
        // Onboarding 24 switched the flow on: a phone that had the app before never gets it.
        XCTAssertFalse(OnboardingStore(defaults: defaults).finished, "a new install starts the flow")
        defaults.set(Date().timeIntervalSince1970, forKey: HelloDrop.lastSeenKey)
        let old = OnboardingStore(defaults: defaults)
        XCTAssertTrue(old.finished)
        XCTAssertTrue(old.arrivedBefore, "nothing of theirs to stamp")
        old.finish()
        XCTAssertFalse(OnboardingStore(defaults: defaults).arrivedBefore, "finished through the flow once: not an old install")
    }

    func testServerStampOnlyCountsOnTheWelcome() {
        let midway = OnboardingStore(defaults: defaults)
        midway.next()
        midway.serverSaysFinished()
        XCTAssertFalse(midway.finished, "a late read must not pull someone out halfway")
        midway.reset()
        midway.serverSaysFinished()
        XCTAssertTrue(midway.finished)
        XCTAssertFalse(midway.finishedHere, "the server's stamp gets no Done island")
    }

    // MARK: Log in and Create account (onboarding 27)

    func testCreateAccountGoesOnToTheFirstQuestion() {
        let store = OnboardingStore(defaults: defaults)
        store.open(.create)
        XCTAssertEqual(store.account, .create)
        XCTAssertEqual(store.step, .welcome, "a relaunch opens on the Welcome")
        store.open(nil)
        XCTAssertNil(store.account, "Back goes to the Welcome")
        store.open(.create)
        store.created()
        XCTAssertNil(store.account)
        XCTAssertEqual(store.step, .name)
    }

    func testLogInGoesStraightInOnlyWhenOnboardingWasFinished() {
        let done = OnboardingStore(defaults: defaults)
        done.open(.logIn)
        done.loggedIn(onboarded: true)
        XCTAssertTrue(done.finished)
        XCTAssertFalse(done.finishedHere, "no Done island for an account that finished before")
        done.reset()
        done.open(.logIn)
        done.loggedIn(onboarded: false)
        XCTAssertFalse(done.finished)
        XCTAssertEqual(done.step, .name, "an unfinished account picks up at the first question")
    }

    func testSignedOutTheNextAccountStartsFromTheWelcome() {
        // The tabs were open: the hello pill's last look is kept.
        defaults.set(Date().timeIntervalSince1970, forKey: HelloDrop.lastSeenKey)
        let store = OnboardingStore(defaults: defaults)
        store.finish()
        store.reset()
        XCTAssertFalse(store.finished)
        XCTAssertFalse(store.welcoming, "no Done island left over for the next account")
        XCTAssertEqual(store.step, .welcome)
        let next = OnboardingStore(defaults: defaults)
        XCTAssertFalse(next.finished, "not taken for an install from before onboarding")
        XCTAssertFalse(next.arrivedBefore)
    }

    // MARK: Name and photo (ticket 18)

    func testNameNeedsAFirstNameAndJoinsTheLastOne() {
        let store = OnboardingStore(defaults: defaults)
        XCTAssertNil(store.displayName)
        store.lastName = "Lund"
        store.firstName = "   "
        XCTAssertNil(store.displayName, "spaces or a last name alone don't make a name")
        store.firstName = " Avery "
        XCTAssertEqual(store.displayName, "Avery Lund")
        store.lastName = ""
        XCTAssertEqual(store.displayName, "Avery")
    }

    func testNameAndPhotoSurviveARelaunch() {
        let store = OnboardingStore(defaults: defaults)
        store.firstName = "Avery"
        store.lastName = "Lund"
        store.photo = Data([1, 2, 3])
        let again = OnboardingStore(defaults: defaults)
        XCTAssertEqual(again.displayName, "Avery Lund")
        XCTAssertEqual(again.photo, Data([1, 2, 3]))
        XCTAssertTrue(again.answersPending)
    }

    func testAnswersSaveOnceAndWaitAfterAFailure() async {
        let store = OnboardingStore(defaults: defaults)
        var calls: [(String?, Data?)] = []
        await store.saveAnswers { calls.append(($0, $1)) }
        XCTAssertTrue(calls.isEmpty, "nothing answered, nothing sent")

        store.firstName = "Avery"
        store.photo = Data([9])
        await store.saveAnswers { _, _ in throw URLError(.notConnectedToInternet) }
        XCTAssertTrue(OnboardingStore(defaults: defaults).answersPending, "a failed save keeps them waiting")

        await store.saveAnswers { calls.append(($0, $1)) }
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.0, "Avery")
        XCTAssertEqual(calls.first?.1, Data([9]))
        XCTAssertFalse(OnboardingStore(defaults: defaults).answersPending)

        await store.saveAnswers { calls.append(($0, $1)) }
        XCTAssertEqual(calls.count, 1, "saved answers aren't sent again")
    }

    func testInterestPicksWaitToBeSaved() {
        let store = OnboardingStore(defaults: defaults)
        XCTAssertFalse(store.answersPending)
        store.interests = ["coffee", "campus", "faith"]
        let again = OnboardingStore(defaults: defaults)
        XCTAssertTrue(again.answersPending, "picks wait for the account")
        XCTAssertEqual(again.interests, ["coffee", "campus", "faith"], "a relaunch resumes on them")
        XCTAssertEqual(Interests.get(defaults), [], "Your profile takes them when the flow is done")
    }

    /// A flow begun before the picks had a key of their own kept them in the phone's copy.
    func testPicksFromBeforeTheUpdateComeBack() {
        defaults.set(["coffee"], forKey: Interests.interestsKey)
        XCTAssertEqual(OnboardingStore(defaults: defaults).interests, ["coffee"])
    }

    func testTwoSavesAtOnceSendOnce() async {
        let store = OnboardingStore(defaults: defaults)
        store.photo = Data([7])
        var calls = 0
        async let first: Void = store.saveAnswers { _, _ in calls += 1; try await Task.sleep(for: .milliseconds(50)) }
        async let second: Void = store.saveAnswers { _, _ in calls += 1 }
        _ = await (first, second)
        XCTAssertEqual(calls, 1)
    }

    // Ticket 19: the birthday and under 13.

    private func day(_ s: String) -> Date { try! OnboardingAge.day.parse(s) }

    func testAgeCountsWholeYearsInTownTime() {
        XCTAssertEqual(OnboardingAge.years(from: day("2012-10-25"), to: day("2025-10-24")), 12)
        XCTAssertEqual(OnboardingAge.years(from: day("2012-10-25"), to: day("2025-10-25")), 13)
        XCTAssertEqual(OnboardingAge.years(from: day("2012-02-29"), to: day("2025-03-01")), 13)
        XCTAssertEqual(OnboardingAge.years(from: day("2026-10-25"), to: day("2026-10-25")), 0)
    }

    private func onBirthday() -> OnboardingStore {
        let store = OnboardingStore(defaults: defaults)
        while store.step != .birthday { store.next() }
        return store
    }

    func testUnder13StaysOnTheBirthdayWithComeBackUp() {
        let store = onBirthday()
        store.birthday = day("2013-10-26")
        store.next(now: day("2026-10-25"))
        XCTAssertEqual(store.step, .birthday)
        XCTAssertTrue(store.tooYoung)
        store.notTooYoung()
        XCTAssertFalse(store.tooYoung)
    }

    func testThirteenTodayGoesOnToInterests() {
        let store = onBirthday()
        store.birthday = day("2013-10-25")
        store.next(now: day("2026-10-25"))
        XCTAssertEqual(store.step, .interests)
        XCTAssertFalse(store.tooYoung)
    }

    func testBirthdaySurvivesRelaunch() {
        let store = onBirthday()
        store.birthday = day("2001-10-24")
        let again = OnboardingStore(defaults: defaults)
        XCTAssertEqual(again.birthday.map { OnboardingAge.day.format($0) }, "2001-10-24")
        XCTAssertEqual(again.step, .birthday)
    }

    func testCloseClearsEverythingTheDeviceKeptAndStartsOver() {
        let store = onBirthday()
        store.interests = ["coffee", "campus", "faith"]   // picked, then back to the birthday
        store.birthday = day("2015-01-01")
        defaults.set("Avery", forKey: "onboarding.name")   // another step's answer
        defaults.set("keep", forKey: "other.setting")
        store.next(now: day("2026-10-25"))
        store.reset()
        XCTAssertEqual(store.step, .welcome)
        XCTAssertNil(store.birthday)
        XCTAssertEqual(store.interests, [])
        XCTAssertFalse(store.answersPending)
        XCTAssertFalse(store.tooYoung)
        XCTAssertTrue(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("onboarding.") }.isEmpty)
        XCTAssertEqual(defaults.string(forKey: "other.setting"), "keep")
        let again = OnboardingStore(defaults: defaults)
        XCTAssertEqual(again.step, .welcome)
        XCTAssertNil(again.birthday)
        XCTAssertEqual(again.interests, [], "a kid's picks don't stay behind")
    }

    // MARK: Follow 3 (onboarding 22)

    private func poi(_ id: String, _ name: String, _ type: String, entry: String? = nil) -> POI {
        POI(id: id, placeId: nil, name: name, lat: 0, lon: 0, family: .business, primaryType: type, types: [],
            address: nil, logoUrl: nil, entryId: entry)
    }

    private var town: [FollowSuggestion] {
        FollowSuggestions.build(
            places: [poi("p1", "The Local Blend", "coffee_shop"), poi("p2", "The Middy", "bar", entry: "middy"),
                     poi("p3", "Bad Habit", "brewery"), poi("p4", "Coborn's", "grocery_store"),
                     poi("p5", "Little Saints", "day_care_center")],
            schools: [LocalSchool(id: "kennedy", uuid: "k1", name: "Kennedy", schoolName: nil, logoUrl: nil)],
            pages: [TownPageRow(id: "c1", slug: "city", name: "City", kind: "City government", sourceName: "City",
                                picture: nil, pictureKind: nil)],
            events: [UpcomingTags(interests: ["games"], place: "middy"), UpcomingTags(interests: ["games"], place: "middy"),
                     UpcomingTags(interests: ["watch_sports"], teams: ["kennedy"]),
                     UpcomingTags(interests: ["live_music"], teams: ["kennedy"]),
                     UpcomingTags(interests: ["town_meetings"], source: "City")])
    }

    func testFollowThreeShowsWhatFitsThePickedInterestsFirstBusiestFirst() {
        let names = { (picked: [String]) in FollowSuggestions.ordered(self.town, picked: picked).map(\.name) }
        XCTAssertEqual(names(["coffee"]).first, "The Local Blend")
        XCTAssertEqual(Array(names(["bars"]).prefix(2)), ["The Middy", "Bad Habit"], "busiest first within what fits")
        // A place's Events add what its kind doesn't say: trivia makes The Middy a Games place.
        XCTAssertEqual(names(["games"]).first, "The Middy")
        // A school's concert doesn't make it a Live music place, so what fits comes first though
        // the school is busier (onboarding 28).
        XCTAssertEqual(names(["live_music", "coffee"]).first, "The Local Blend")
        XCTAssertEqual(FollowSuggestions.ordered(town, picked: ["coffee"], schoolsFirst: true).first?.name, "Kennedy",
                       "schools lead for somebody who opened Schools")
        XCTAssertEqual(names(["town_meetings"]).first, "City")
        // Popular first (onboarding 26): whatever fits, busiest first, then A to Z.
        XCTAssertEqual(Array(names(["coffee", "families_kids", "bars"]).prefix(4)),
                       ["The Middy", "Bad Habit", "Little Saints", "The Local Blend"])
        XCTAssertEqual(names(["coffee"])[1], "Kennedy", "then the rest, busiest first")
        XCTAssertNotEqual(names(["coffee"]), names(["bars"]))
    }

    func testSchoolsLeadFollowThreeOnlyForWhoOpenedSchools() {
        let all = FollowSuggestions.build(
            places: [poi("z", "Zed's", "bar", entry: "zed")],
            schools: [LocalSchool(id: "kennedy", uuid: "k1", name: "Kennedy", schoolName: nil, logoUrl: nil)],
            pages: [],
            events: [UpcomingTags(interests: [], place: "zed"), UpcomingTags(interests: [], place: "zed"),
                     UpcomingTags(interests: [], teams: ["kennedy"])])
        XCTAssertEqual(FollowSuggestions.ordered(all, picked: ["bars"]).map(\.name), ["Zed's", "Kennedy"])
        XCTAssertEqual(FollowSuggestions.ordered(all, picked: ["bars"], schoolsFirst: true).map(\.name),
                       ["Kennedy", "Zed's"], "ahead of what fits, though it's quieter")
    }

    func testSchoolsShowEachKindInTheTownsOrderUnderItsShortNames() {
        let all = FollowSuggestions.build(
            places: [poi("p1", "Sartell Cafe", "cafe")],
            schools: [LocalSchool(id: "sartell", uuid: "s", name: "Sartell", schoolName: "Sartell High School", logoUrl: nil),
                      LocalSchool(id: "apollo", uuid: "a", name: "Apollo", schoolName: "Apollo High School", logoUrl: nil),
                      LocalSchool(id: "cathedral", uuid: "c", name: "Cathedral", schoolName: "Cathedral High School", logoUrl: nil),
                      LocalSchool(id: "apollo-cathedral", uuid: "x", name: "Apollo-Cathedral", schoolName: nil, logoUrl: nil),
                      LocalSchool(id: "saint-johns", uuid: "j", name: "Saint John's", schoolName: "Saint John's University", logoUrl: nil)],
            pages: [TownPageRow(id: "p", slug: "csbsju-campus-events", name: "CSB SJU Campus Events", kind: "College",
                                sourceName: "CSB SJU Campus Events", picture: nil, pictureKind: nil),
                    TownPageRow(id: "j", slug: "st-joseph-catholic", name: "St. Joseph Catholic School", kind: "School",
                                sourceName: "St. Joseph Catholic School", picture: nil, pictureKind: nil)],
            events: [UpcomingTags(interests: ["live_music"], source: "St. Joseph Catholic School")])
        let names = { (id: String) in
            FollowSuggestions.tiles(Town.schoolTypes.first { $0.id == id }!, in: all).map(\.name)
        }
        // Apollo before Cathedral before Sartell whatever the read's order; no row live, no tile.
        XCTAssertEqual(names("high"), ["Apollo", "Cathedral", "Sartell"])
        XCTAssertEqual(names("middle"), ["St. Joseph Catholic", "Cathedral", "Sartell"])
        XCTAssertEqual(names("college"), ["Saint John's", "Campus Events"])
        // A school two kinds show counts once; the co-op no kind names is never a tile.
        XCTAssertEqual(FollowSuggestions.schoolTargets(in: all).count, 6)
        // A school page is a school: no pick fits it, and Follow 3 pulls it up with the others.
        let page = all.first { $0.key == "st-joseph-catholic" }!
        XCTAssertTrue(page.isSchool)
        XCTAssertTrue(page.interests.isEmpty)
        XCTAssertEqual(page.events, 1)
        XCTAssertEqual(FollowSuggestions.collegeTargets(in: all).count, 2)
    }

    func testOpeningSchoolsIsKeptAndGoesWithTheFlow() {
        let store = OnboardingStore(defaults: defaults)
        XCTAssertFalse(store.schoolsOpened)
        store.schoolsOpened = true
        XCTAssertTrue(OnboardingStore(defaults: defaults).schoolsOpened, "a relaunch resumes on it")
        store.reset()
        XCTAssertFalse(OnboardingStore(defaults: defaults).schoolsOpened)
    }

    func testFollowThreeShowsEveryPlaceAndSearchesEverything() {
        XCTAssertEqual(FollowSuggestions.ordered(town, picked: ["coffee"]).count, 7, "every place, school and page")
        XCTAssertEqual(FollowSuggestions.search(town, "brew").map(\.name), ["Bad Habit"])
        XCTAssertEqual(FollowSuggestions.search(town, "school").map(\.name), ["Kennedy"], "kinds are searched too")
        XCTAssertTrue(FollowSuggestions.search(town, "zzz").isEmpty)
        // A page's logo shows bare, as a place's; a photo stays a photo.
        let pages = FollowSuggestions.build(places: [], schools: [], pages: [
            TownPageRow(id: "c1", slug: "city", name: "City", kind: "City government", sourceName: nil,
                        picture: "https://example.com/logo.png", pictureKind: "logo"),
            TownPageRow(id: "c2", slug: "campus", name: "Campus", kind: "College", sourceName: nil,
                        picture: "https://example.com/photo.webp", pictureKind: "photo")], events: [])
        XCTAssertEqual(pages.map { $0.logo?.url.absoluteString }, ["https://example.com/logo.png", nil])
    }

    func testFollowingAPlacePullsPlacesOfItsKindUpToRightAfterIt() {
        let grid = FollowSuggestions.build(
            places: [poi("c1", "Local Blend", "coffee_shop"), poi("r1", "Krewe", "cajun_restaurant"), poi("b1", "Middy", "bar"),
                     // The two rows in sight under its row.
                     poi("k1", "Flour", "bakery"), poi("c0", "Brew Near", "coffee_shop"), poi("r2", "Kay's", "restaurant"),
                     poi("v1", "Vet", "veterinary_care"), poi("c2", "Brew Two", "coffee_shop"), poi("g1", "Gym", "gym"),
                     // Further down.
                     poi("c3", "Brew Three", "coffee_shop"), poi("k2", "Bakery Two", "bakery"),
                     poi("c5", "Brew Five", "coffee_shop", entry: "five"), poi("c6", "Brew Six", "coffee_shop")],
            schools: [LocalSchool(id: "sju", uuid: "s1", name: "SJU", schoolName: nil, logoUrl: nil),
                      LocalSchool(id: "csb", uuid: "s2", name: "CSB", schoolName: nil, logoUrl: nil)],
            pages: [], events: [UpcomingTags(interests: [], place: "five")])
        let names = { (order: [FollowSuggestion]) in order.map(\.name) }
        let id = { (name: String) in grid.first { $0.name == name }!.target }

        // From below what's in sight: coffee shops first (two in common), the busiest first; 3 at most.
        let (once, moved) = FollowSuggestions.pull(grid, after: id("Local Blend"), follows: [id("Local Blend")])
        XCTAssertEqual(Array(names(once).prefix(4)), ["Local Blend", "Brew Five", "Brew Three", "Brew Six"])
        XCTAssertEqual(moved, [id("Brew Five"), id("Brew Three"), id("Brew Six")])
        XCTAssertEqual(names(once)[4...11], ["Krewe", "Middy", "Flour", "Brew Near", "Kay's", "Vet", "Brew Two", "Gym"],
                       "what was in sight keeps its order, Brew Two too")
        XCTAssertEqual(Set(names(once)), Set(names(grid)), "pulled, never added or lost")

        // Places above it and followed ones stay put; one in common still counts once two run out.
        let (twice, again) = FollowSuggestions.pull(once, after: id("Brew Three"), follows: [id("Local Blend"), id("Brew Three"), id("Brew Two")])
        XCTAssertEqual(names(twice)[1], "Brew Five")
        XCTAssertEqual(again, [id("Bakery Two")], "Brew Two is followed: it stays")
        XCTAssertEqual(names(twice)[3], "Bakery Two")

        // Nothing of its kind further down: nothing moves.
        XCTAssertTrue(FollowSuggestions.pull(grid, after: id("Vet"), follows: [id("Vet")]).moved.isEmpty)
        XCTAssertTrue(FollowSuggestions.pull(grid, after: id("SJU"), follows: [id("SJU")]).moved.isEmpty, "CSB is in sight")
    }

    func testFollowsWaitOnThePhoneUntilTheFlowIsDoneAndAreTakenOnce() {
        let store = OnboardingStore(defaults: defaults)
        let a = FollowTarget(type: .place, id: "p1"), b = FollowTarget(type: .team, id: "k1")
        store.toggleFollow(a); store.toggleFollow(b); store.toggleFollow(a)
        XCTAssertEqual(store.follows, [b])
        XCTAssertEqual(OnboardingStore(defaults: defaults).follows, [b], "kept over a relaunch")
        XCTAssertEqual(OnboardingStore.takeFollows(defaults), [], "nothing goes up mid-flow")
        store.finish()
        XCTAssertEqual(OnboardingStore.takeFollows(defaults), [b])
        XCTAssertEqual(OnboardingStore.takeFollows(defaults), [], "taken once")
    }

    // MARK: Find friends (ticket 23)

    func testRequestsToggleAndOutliveARelaunch() {
        let store = OnboardingStore(defaults: defaults)
        store.toggleRequest("sam")
        store.toggleRequest("maya")
        store.toggleRequest("sam")
        XCTAssertEqual(store.requests, ["maya"])
        XCTAssertEqual(OnboardingStore(defaults: defaults).requests, ["maya"])
    }

    func testRequestsWaitForTheFinishAndTheSavedName() async {
        let store = OnboardingStore(defaults: defaults)
        store.firstName = "Avery"
        store.toggleRequest("maya")
        var sent: [String] = []
        await store.sendRequests { sent.append($0) }
        XCTAssertEqual(sent, [], "not before the flow is done")
        store.finish()
        await store.sendRequests { sent.append($0) }
        XCTAssertEqual(sent, [], "not before the name is on the account")
        await store.saveAnswers { _, _ in }
        await store.sendRequests { sent.append($0) }
        XCTAssertEqual(sent, ["maya"])
        XCTAssertEqual(store.requests, [])
    }

    func testNoSignalKeepsTheRequestsAndARefusalDropsThem() async {
        let store = OnboardingStore(defaults: defaults)
        store.firstName = "Avery"
        store.toggleRequest("maya")
        store.toggleRequest("sam")
        store.finish()
        await store.saveAnswers { _, _ in }
        await store.sendRequests { _ in throw URLError(.notConnectedToInternet) }
        XCTAssertEqual(OnboardingStore(defaults: defaults).requests, ["maya", "sam"], "kept for the next launch")
        await store.sendRequests { id in
            if id == "maya" { throw SupabaseError(message: "friend_limit", status: 400) }
        }
        XCTAssertEqual(store.requests, [], "the server answered both: one refused, one sent")
    }

    func testTooYoungForgetsTheRequests() {
        let store = OnboardingStore(defaults: defaults)
        store.toggleRequest("maya")
        store.reset()
        XCTAssertEqual(OnboardingStore(defaults: defaults).requests, [])
    }
}
