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

    func testStartsOnWelcomeAndWalksTheStepsWithDashesFromBirthday() {
        let store = OnboardingStore(defaults: defaults)
        XCTAssertEqual(store.step, .welcome)
        XCTAssertEqual(store.barIndex, 0)
        var indexes: [Int] = []
        for _ in 1..<OnboardingStep.allCases.count { store.next(); indexes.append(store.barIndex) }
        XCTAssertEqual(indexes, [0, 0, 1, 2, 3, 4, 5], "Name and Photo have no dashes (onboarding 55)")
        XCTAssertEqual(OnboardingStep.barTotal, 5, "Phone and Code wait for phone sign-in (onboarding 24); the dashes start at Birthday (55)")
        XCTAssertEqual(store.step, .contacts)
        XCTAssertFalse(store.finished)
        store.next()
        XCTAssertTrue(store.finished)
    }

    func testBackGoesToThePreviousStepAndStopsAtTheFirstQuestion() {
        let store = OnboardingStore(defaults: defaults)
        store.next(); store.next(); store.next()
        XCTAssertEqual(store.step, .birthday)
        store.back()
        XCTAssertEqual(store.step, .photo)
        XCTAssertFalse(store.forward)
        store.back()
        XCTAssertEqual(store.step, .profile)
        store.back()
        XCTAssertEqual(store.step, .profile, "the account is made before the name step: Back would make a second one")
    }

    func testRelaunchResumesOnTheSameStep() {
        let store = OnboardingStore(defaults: defaults)
        for _ in 0..<3 { store.next() }   // Welcome, Name, Photo
        XCTAssertEqual(OnboardingStore(defaults: defaults).step, .birthday)
    }

    func testFinishedStaysFinished() {
        let store = OnboardingStore(defaults: defaults)
        while store.step != .friends { store.next() }
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

    // MARK: Forgot password (onboarding 40)

    func testForgotPasswordStepsBackThroughItselfToLogIn() {
        let store = OnboardingStore(defaults: defaults)
        store.open(.logIn)
        store.open(.forgot)
        store.open(.code)
        store.accountBack()
        XCTAssertEqual(store.account, .forgot)
        XCTAssertFalse(store.forward, "back slides in from the left")
        store.accountBack()
        XCTAssertEqual(store.account, .logIn)
        store.accountBack()
        XCTAssertNil(store.account, "Log in goes back to the Welcome")
        XCTAssertEqual(OnboardingAccount.newPassword.back, .logIn)
    }

    func testBackingOutOfANewPasswordLandsOnLogInAfterTheSignOut() {
        let store = OnboardingStore(defaults: defaults)
        store.open(.logIn)
        store.open(.forgot)
        store.open(.code)
        store.open(.newPassword)
        store.accountBack()
        store.reset()   // RootView's, as the code's sign-in ends
        XCTAssertEqual(store.account, .logIn)
        XCTAssertEqual(store.step, .welcome)
        store.open(.create)
        store.reset()
        XCTAssertNil(store.account, "any other screen goes back to the Welcome")
    }

    func testTheServerStampWaitsForTheNewPassword() {
        let store = OnboardingStore(defaults: defaults)
        store.open(.newPassword)
        store.serverSaysFinished()
        XCTAssertFalse(store.finished, "the code's sign-in must not skip the new password")
        store.loggedIn(onboarded: true)
        XCTAssertTrue(store.finished, "its Log in goes in")
        XCTAssertNil(store.account)
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
        XCTAssertEqual(store.step, .profile)
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
        XCTAssertEqual(done.step, .profile, "an unfinished account picks up at the first question")
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

    // MARK: Profile as Clubhouse's two steps (onboarding 55; one step from 35 to 55)

    func testTheNameStepComesFirstThenThePhotoThenBirthday() {
        let store = OnboardingStore(defaults: defaults)
        store.next()
        XCTAssertEqual(store.step, .profile)
        XCTAssertEqual(store.step.question, "What Mom calls you", "Jesse's words")
        XCTAssertFalse(store.step.dashed)
        XCTAssertTrue(store.step.clubhouse)
        store.next()
        XCTAssertEqual(store.step, .photo)
        XCTAssertFalse(store.step.dashed)
        XCTAssertTrue(store.step.clubhouse)
        store.next()
        XCTAssertEqual(store.step, .birthday)
        XCTAssertEqual(store.barIndex, 1, "the dashes start at Birthday")
        XCTAssertFalse(store.step.clubhouse, "every step's pill again")
    }

    func testAFlowSavedOnTheOldNameStepResumesOnProfileWithWhatWasTyped() {
        defaults.set("name", forKey: "onboarding.step")
        defaults.set("Avery", forKey: "onboarding.firstName")
        defaults.set("Lund", forKey: "onboarding.lastName")
        let store = OnboardingStore(defaults: defaults)
        XCTAssertEqual(store.step, .profile)
        XCTAssertEqual(store.name, "Avery Lund")
        XCTAssertEqual(store.displayName, "Avery Lund")
    }

    func testAFlowSavedOnThePhotoStepResumesThereWithItsPhoto() {
        defaults.set("photo", forKey: "onboarding.step")
        defaults.set("Avery", forKey: "onboarding.firstName")
        defaults.set(Data([4, 2]), forKey: "onboarding.photo")
        let store = OnboardingStore(defaults: defaults)
        XCTAssertEqual(store.step, .photo, "the Photo step is back (onboarding 55)")
        XCTAssertEqual(store.name, "Avery")
        XCTAssertEqual(store.photo, Data([4, 2]))
    }

    func testProfileNeedsANameAndTheBioIsOptional() {
        let store = OnboardingStore(defaults: defaults)
        store.next()
        XCTAssertFalse(store.profileDone, "nothing typed")
        store.bio = "Coffee and lakes."
        store.photo = Data([1])
        XCTAssertFalse(store.profileDone, "a bio and a photo don't make a name")
        store.name = "   "
        XCTAssertFalse(store.profileDone, "spaces aren't a name")
        store.name = " Avery Lund "
        XCTAssertTrue(store.profileDone)
        XCTAssertEqual(store.displayName, "Avery Lund")
    }

    func testNameBioAndPhotoSurviveARelaunch() {
        let store = OnboardingStore(defaults: defaults)
        store.next()
        store.name = "Avery Lund"
        store.bio = "Coffee and lakes."
        store.photo = Data([1, 2, 3])
        let again = OnboardingStore(defaults: defaults)
        XCTAssertEqual(again.step, .profile)
        XCTAssertEqual(again.name, "Avery Lund")
        XCTAssertEqual(again.bio, "Coffee and lakes.")
        XCTAssertEqual(again.photo, Data([1, 2, 3]))
        XCTAssertTrue(again.answersPending)
    }

    func testAnswersSaveOnceAndWaitAfterAFailure() async {
        let store = OnboardingStore(defaults: defaults)
        var calls: [(String?, String?, Data?)] = []
        await store.saveAnswers { calls.append(($0, $1, $2)) }
        XCTAssertTrue(calls.isEmpty, "nothing answered, nothing sent")

        store.name = "Avery"
        store.bio = "  Coffee and lakes. "
        store.photo = Data([9])
        await store.saveAnswers { _, _, _ in throw URLError(.notConnectedToInternet) }
        XCTAssertTrue(OnboardingStore(defaults: defaults).answersPending, "a failed save keeps them waiting")

        await store.saveAnswers { calls.append(($0, $1, $2)) }
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.0, "Avery")
        XCTAssertEqual(calls.first?.1, "Coffee and lakes.")
        XCTAssertEqual(calls.first?.2, Data([9]))
        XCTAssertFalse(OnboardingStore(defaults: defaults).answersPending)

        await store.saveAnswers { calls.append(($0, $1, $2)) }
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
        async let first: Void = store.saveAnswers { _, _, _ in calls += 1; try await Task.sleep(for: .milliseconds(50)) }
        async let second: Void = store.saveAnswers { _, _, _ in calls += 1 }
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
        // It arrives as a step forward and Back leaves it as a step back (onboarding 47).
        XCTAssertTrue(store.forward)
        store.notTooYoung()
        XCTAssertFalse(store.tooYoung)
        XCTAssertFalse(store.forward)
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

    func testGenderSurvivesRelaunchAndGoesOnClose() {
        // Onboarding 31: the Birthday step's optional pick is kept on the phone as the birthday is.
        let store = onBirthday()
        store.gender = "female"
        XCTAssertEqual(OnboardingStore(defaults: defaults).gender, "female")
        store.gender = nil   // a second tap on the picked one
        XCTAssertNil(OnboardingStore(defaults: defaults).gender)
        store.gender = "male"
        store.reset()
        XCTAssertNil(store.gender)
        XCTAssertNil(OnboardingStore(defaults: defaults).gender)
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

    /// The places with a spot (`places.follow_spot`, onboarding 50) lead in that order whatever is picked; schools
    /// still lead for somebody who picked Schools; then what fits the picks, as before.
    func testPlacesWithASpotLeadFollowThree() {
        var last = poi("p9", "Sal's", "bar_and_grill")
        last.followSpot = FollowSpot(spot: 2, photo: nil)
        var first = poi("p8", "Flour & Flower", "bakery", entry: "flour")
        first.followSpot = FollowSpot(spot: 1, photo: URL(string: "https://x.co/b.webp"))
        let live = ["a", "b"].map { PlacePicture(url: URL(string: "https://x.co/\($0).webp")!, kind: .photo) }
        let all = FollowSuggestions.build(
            places: [poi("p1", "The Middy", "bar", entry: "middy"), last, first], photos: ["flour": live],
            schools: [LocalSchool(id: "apollo", uuid: "a1", name: "Apollo", schoolName: nil, logoUrl: nil)], pages: [],
            events: [UpcomingTags(interests: ["bars"], place: "middy")])
        XCTAssertEqual(FollowSuggestions.ordered(all, picked: ["bars"]).map(\.name),
                       ["Flour & Flower", "Sal's", "The Middy", "Apollo"])
        XCTAssertEqual(FollowSuggestions.ordered(all, picked: ["bars"], schoolsFirst: true).first?.name, "Apollo")
        XCTAssertEqual(all.first { $0.name == "Flour & Flower" }?.photo, live[1].url, "the one picked, not the cover")
        XCTAssertEqual(FollowSuggestions.photo(of: first, live: [live[0]]), live[0].url,
                       "taken down, it shows here no more: a place with no logo shows another")
        first.followSpot = FollowSpot(spot: 1)
        XCTAssertEqual(FollowSuggestions.photo(of: first, live: live), live[0].url, "no photo picked and no logo: its cover")
    }

    /// The line (community-value 04): a place that fits a pick stands at its `fit`, one with only a `fit` is in line
    /// for who picked it alone, and a page stands in it too.
    private func line(_ name: String, _ type: String = "storage", spot: Int?, fit: Int? = nil, group: String? = nil,
                      late: Bool = false) -> POI {
        var poi = poi(name, name, type)
        poi.followSpot = FollowSpot(spot: spot, fit: fit, group: group, late: late)
        return poi
    }

    private func order(_ places: [POI], pages: [TownPageRow] = [], picked: [String] = [], under18: Bool = false) -> [String] {
        FollowSuggestions.ordered(FollowSuggestions.build(places: places, schools: [], pages: pages, events: []),
                                  picked: picked, under18: under18).map(\.name)
    }

    func testAPickLiftsAPlaceToItsFit() {
        let places = [line("A", spot: 1, fit: 1), line("B", spot: 4, fit: 2), line("Cafe", "coffee_shop", spot: 6, fit: 3),
                      line("D", "coffee_shop", spot: nil, fit: 7), line("C", spot: 8, fit: 5), poi("e", "E", "coffee_shop")]
        let city = TownPageRow(id: "c", slug: "city", name: "City", kind: "City government", sourceName: nil, picture: nil,
                               pictureKind: nil, followSpot: FollowSpot(spot: 9, fit: 2))
        XCTAssertEqual(order(places, pages: [city]), ["A", "B", "Cafe", "C", "City", "D", "E"])
        XCTAssertEqual(order(places, pages: [city], picked: ["coffee"]), ["A", "Cafe", "B", "D", "C", "City", "E"],
                       "D joins the line at its fit; E, in no line, stays after it")
        XCTAssertEqual(order(places, pages: [city], picked: ["town_meetings"]).prefix(3), ["A", "City", "B"])
    }

    func testTheFirstTwelveHoldTheMixAndFiveFood() {
        var places = (1...9).map { (n: Int) in line("Food \(n)", spot: n, fit: n, group: "food") }
        places += (10...20).map { (n: Int) in line("Other \(n)", spot: n, fit: n) }
        places += [line("Late", spot: 21, fit: 21, group: "learn", late: true), line("Shelf", spot: 22, fit: 22, group: "help"),
                   line("Park", spot: 23, fit: 23, group: "outdoors"), line("Shop", spot: 24, fit: 24, group: "shop"),
                   line("Library", spot: 25, fit: 25, group: "learn")]
        let names = order(places)
        XCTAssertEqual(Array(names.prefix(12)), (1...5).map { "Food \($0)" } + (10...12).map { "Other \($0)" }
                       + ["Shelf", "Park", "Shop", "Library"])
        XCTAssertEqual(Array(names[12..<14]), ["Food 6", "Food 7"], "what was passed over leads what follows")
        XCTAssertEqual(Set(names).count, places.count, "nobody is hidden")
        // A group with only a late place can't be had, and a line of fewer than 12 shows all it has.
        XCTAssertEqual(order([line("Late", spot: 1, fit: 1, group: "learn", late: true), line("A", spot: 2, fit: 2, group: "food")]),
                       ["A", "Late"])
        // Schools lead, then the mix.
        let school = LocalSchool(id: "kennedy", uuid: "k1", name: "Kennedy", schoolName: nil, logoUrl: nil)
        let all = FollowSuggestions.build(places: places, schools: [school], pages: [], events: [])
        XCTAssertEqual(FollowSuggestions.ordered(all, picked: [], schoolsFirst: true).map(\.name), ["Kennedy"] + names)
    }

    func testUnder18NoBarIsInTheFirstTwentyFour() {
        let places = [line("Grill", "bar_and_grill", spot: 1, fit: 1), line("Brewery", "brewery", spot: 2, fit: 2), line("Bar", "bar", spot: 4, fit: 3)]
            + (5...34).map { (n: Int) in line("P\(n)", spot: n, fit: n) }
        XCTAssertEqual(order(places).prefix(3), ["Grill", "Brewery", "Bar"])
        let teen = order(places, picked: ["bars"], under18: true)
        XCTAssertEqual(teen.first, "Grill", "a bar and grill stays")
        XCTAssertEqual(Array(teen[22...26]), ["P26", "P27", "Brewery", "Bar", "P28"])
        XCTAssertEqual(teen.count, places.count)
        // Following the grill pulls up no bar.
        let all = FollowSuggestions.build(places: places, schools: [], pages: [], events: [])
        let grid = FollowSuggestions.ordered(all, picked: [], under18: true), grill = grid[0].target
        XCTAssertEqual(FollowSuggestions.pull(grid, after: grill, follows: [grill], under18: true).moved, [])
        XCTAssertEqual(FollowSuggestions.pull(grid, after: grill, follows: [grill]).moved.count, 2)
    }

    func testAnAdultsOnlyPlaceIsNotInOnboarding() throws {
        let adult = try Supabase.decode(Data(#"""
        {"id": "p", "name": "The Middy", "lat": 0, "lon": 0, "family": "food", "primary_type": "bar", "types": [], "adults_only": true}
        """#.utf8), as: POI.self)
        XCTAssertEqual(order([adult, poi("q", "Blend", "coffee_shop")]), ["Blend"])
    }

    func testUnder18IsReadFromTheBirthday() {
        let store = OnboardingStore(defaults: defaults)
        XCTAssertFalse(store.under18)
        store.birthday = Calendar.current.date(byAdding: .year, value: -15, to: .now)
        XCTAssertTrue(store.under18)
        store.birthday = Calendar.current.date(byAdding: .year, value: -30, to: .now)
        XCTAssertFalse(store.under18)
    }

    /// An odd `follow_spot` can't fail the read of every place: it is in no line.
    func testAnOddSpotNeverFailsTheRead() throws {
        let read = { (json: String) in try JSONDecoder().decode(FollowSpot.self, from: Data(json.utf8)) }
        XCTAssertEqual(try read(#"{"spot": 4, "photo": "https://x.co/a.webp"}"#).spot, 4)
        let full = try read(#"{"spot": 4, "fit": 2, "group": "food", "late": true, "photo": null}"#)
        XCTAssertEqual(full, FollowSpot(spot: 4, fit: 2, group: "food", late: true))
        XCTAssertEqual(try read(#"{"fit": 9}"#), FollowSpot(spot: nil, fit: 9))
        for odd in ["{}", #"{"photo": ""}"#, #"{"spot": 1.5}"#, "[]", "7"] { XCTAssertNil(try read(odd).spot, odd) }
    }

    /// A place with no logo shows its saved photo; one with a logo keeps the logo unless its spot names a photo.
    func testAPlaceWithNoLogoShowsItsPhoto() {
        let photo = PlacePicture(url: URL(string: "https://x.co/p.webp")!, kind: .photo)
        let bare = poi("p1", "Ball Park", "park", entry: "park")
        let logo = POI(id: "p2", placeId: nil, name: "Krewe", lat: 0, lon: 0, family: .food, primaryType: "restaurant",
                       types: [], address: nil, logoUrl: "https://x.co/l.png", entryId: "krewe")
        let all = FollowSuggestions.build(places: [bare, logo], photos: ["park": [photo], "krewe": [photo]],
                                          schools: [], pages: [], events: [])
        XCTAssertEqual(all.first { $0.name == "Ball Park" }?.photo, photo.url)
        XCTAssertNil(all.first { $0.name == "Krewe" }?.photo)
    }

    /// Kennedy is a place and a school: one tile, the school's, which follows both and keeps the place's spot.
    func testASchoolThatIsAPlaceTooIsOneTile() {
        var place = poi("p1", "Kennedy Community School", "school")
        place.followSpot = FollowSpot(spot: 3, photo: nil)
        let all = FollowSuggestions.build(
            places: [place, poi("p2", "St Joseph Meat Market Inc", "butcher_shop")],
            schools: [LocalSchool(id: "kennedy", uuid: "k1", name: "Kennedy", schoolName: "Kennedy Community School", logoUrl: nil)],
            pages: [], events: [UpcomingTags(interests: [], teams: ["kennedy"])])
        XCTAssertEqual(all.map(\.name).sorted(), ["Kennedy Community School", "St Joseph Meat Market"])
        let school = all.first { $0.isSchool }
        XCTAssertEqual(school?.target, .init(type: .team, id: "k1"))
        XCTAssertEqual(school?.twin, .init(type: .place, id: "p1"))
        XCTAssertEqual(school?.line?.spot, 3)
    }

    /// A tile that follows two things counts once toward the 3.
    func testAFollowedTileCountsOnceThoughItFollowsTwo() {
        let school = FollowSuggestion(target: .init(type: .team, id: "k1"), name: "Kennedy", kind: nil, picture: nil,
                                      twin: .init(type: .place, id: "p1"))
        let cafe = FollowSuggestion(target: .init(type: .place, id: "p2"), name: "Blend", kind: nil, picture: nil)
        let store = OnboardingStore(defaults: defaults)
        store.toggleFollow(school.target, with: school.twin)
        store.toggleFollow(cafe.target)
        XCTAssertEqual(store.follows.count, 3)
        XCTAssertEqual(FollowSuggestions.followed([school, cafe], store.follows), 2)
        store.toggleFollow(school.target, with: school.twin)
        XCTAssertEqual(store.follows, [cafe.target])
        store.toggleFollow(school.twin!)
        store.toggleFollow(school.target, with: school.twin)
        XCTAssertEqual(store.follows.count, 3, "its place, already followed, isn't followed twice")
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

    func testPickingSchoolsIsKeptAndGoesWithTheFlow() {
        let store = OnboardingStore(defaults: defaults)
        XCTAssertFalse(store.schoolsPicked)
        store.schoolsPicked = true
        XCTAssertTrue(OnboardingStore(defaults: defaults).schoolsPicked, "a relaunch resumes on it")
        store.reset()
        XCTAssertFalse(OnboardingStore(defaults: defaults).schoolsPicked)
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
        store.name = "Avery"
        store.toggleRequest("maya")
        var sent: [String] = []
        await store.sendRequests { sent.append($0) }
        XCTAssertEqual(sent, [], "not before the flow is done")
        store.finish()
        await store.sendRequests { sent.append($0) }
        XCTAssertEqual(sent, [], "not before the name is on the account")
        await store.saveAnswers { _, _, _ in }
        await store.sendRequests { sent.append($0) }
        XCTAssertEqual(sent, ["maya"])
        XCTAssertEqual(store.requests, [])
    }

    func testNoSignalKeepsTheRequestsAndARefusalDropsThem() async {
        let store = OnboardingStore(defaults: defaults)
        store.name = "Avery"
        store.toggleRequest("maya")
        store.toggleRequest("sam")
        store.finish()
        await store.saveAnswers { _, _, _ in }
        await store.sendRequests { _ in throw URLError(.notConnectedToInternet) }
        XCTAssertEqual(OnboardingStore(defaults: defaults).requests, ["maya", "sam"], "kept for the next launch")
        await store.sendRequests { id in
            if id == "maya" { throw SupabaseError(message: "friend_limit", status: 400) }
        }
        XCTAssertEqual(store.requests, [], "the server answered both: one refused, one sent")
    }

    // MARK: Contacts' one button (onboarding 37, mock v8)

    /// On Contacts with Profile's name typed, as a real flow gets there.
    private func onContacts() -> OnboardingStore {
        let store = OnboardingStore(defaults: defaults)
        store.name = "Avery"
        while store.step != .contacts { store.next() }
        return store
    }

    func testTheButtonCountsWhoIsTicked() {
        let store = onContacts()
        XCTAssertEqual(store.contactsButton, "Next")
        store.toggleRequest("maya")
        XCTAssertEqual(store.contactsButton, "Add 1 friend")
        store.toggleRequest("sam")
        XCTAssertEqual(store.contactsButton, "Add 2 friends")
        store.toggleRequest("maya")
        XCTAssertEqual(store.contactsButton, "Add 1 friend")
    }

    func testTickingTwoAndPressingTheButtonSendsTwoAndMovesOn() async {
        let store = onContacts()
        store.toggleRequest("maya")
        store.toggleRequest("sam")
        store.next()
        XCTAssertTrue(store.finished, "the button moves on: Contacts is the last step")
        await store.saveAnswers { _, _, _ in }
        var sent: [String] = []
        await store.sendRequests { sent.append($0) }
        XCTAssertEqual(sent, ["maya", "sam"])
    }

    func testNoneTickedMovesOnWithNoneSent() async {
        let store = onContacts()
        store.next()
        XCTAssertTrue(store.finished)
        await store.saveAnswers { _, _, _ in }
        var sent: [String] = []
        await store.sendRequests { sent.append($0) }
        XCTAssertEqual(sent, [])
    }

    /// Ticked on Contacts, back to Find your friends, then Not now: none go (onboarding 37's review).
    func testNotNowSendsNoneOfTheTickedRequests() async {
        let store = onContacts()
        store.toggleRequest("maya")
        store.toggleRequest("sam")
        store.back()
        XCTAssertEqual(store.step, .friends)
        store.skipFriends()
        XCTAssertTrue(store.finished)
        await store.saveAnswers { _, _, _ in }
        var sent: [String] = []
        await store.sendRequests { sent.append($0) }
        XCTAssertEqual(sent, [])
        XCTAssertEqual(OnboardingStore(defaults: defaults).requests, [], "none wait for a relaunch either")
    }

    /// Refused on Apple's contacts prompt: the flow ends there, as Not now, with nobody sent; allowed
    /// goes on to Contacts. An answer landing once off Find your friends moves nothing.
    func testContactsRefusedEndsTheFlowAndAllowedGoesOnToContacts() async {
        let refused = onContacts()
        refused.toggleRequest("maya")
        refused.back()
        refused.answeredContacts(allowed: false)
        XCTAssertTrue(refused.finished)
        XCTAssertTrue(refused.finishedHere, "the Done island's")
        XCTAssertEqual(refused.requests, [])

        defaults.removePersistentDomain(forName: "OnboardingStoreTests")
        let allowed = onContacts()
        allowed.back()
        allowed.answeredContacts(allowed: true)
        XCTAssertEqual(allowed.step, .contacts)
        allowed.answeredContacts(allowed: false)
        XCTAssertEqual(allowed.step, .contacts, "a second tap's answer doesn't end the flow")
        XCTAssertFalse(allowed.finished)
    }

    func testTooYoungForgetsTheRequests() {
        let store = OnboardingStore(defaults: defaults)
        store.toggleRequest("maya")
        store.reset()
        XCTAssertEqual(OnboardingStore(defaults: defaults).requests, [])
    }
}
