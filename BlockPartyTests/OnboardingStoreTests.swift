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

    func testBackGoesToThePreviousStepAndStopsAtWelcome() {
        let store = OnboardingStore(defaults: defaults)
        store.next(); store.next()
        XCTAssertEqual(store.step, .photo)
        store.back()
        XCTAssertEqual(store.step, .name)
        XCTAssertFalse(store.forward)
        store.back(); store.back()
        XCTAssertEqual(store.step, .welcome)
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
        midway.back()
        midway.serverSaysFinished()
        XCTAssertTrue(midway.finished)
        XCTAssertFalse(midway.finishedHere, "the server's stamp gets no Done island")
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
        let saved = Interests.get()
        defer { Interests.set(saved) }
        let store = OnboardingStore(defaults: defaults)
        XCTAssertFalse(store.answersPending)
        store.interests = ["coffee", "campus", "faith"]
        XCTAssertTrue(OnboardingStore(defaults: defaults).answersPending, "picks wait for the account")
        XCTAssertEqual(Interests.get(), ["coffee", "campus", "faith"], "every screen reads them at once")
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
        let saved = Interests.get()
        defer { Interests.set(saved) }
        let store = onBirthday()
        store.interests = ["coffee", "campus", "faith"]   // picked, then back to the birthday
        store.birthday = day("2015-01-01")
        defaults.set("Avery", forKey: "onboarding.name")   // another step's answer
        defaults.set("keep", forKey: "other.setting")
        store.next(now: day("2026-10-25"))
        store.leaveTooYoung()
        XCTAssertEqual(store.step, .welcome)
        XCTAssertNil(store.birthday)
        XCTAssertEqual(store.interests, [])
        XCTAssertEqual(Interests.get(), [], "a kid's picks don't stay behind")
        XCTAssertFalse(store.answersPending)
        XCTAssertFalse(store.tooYoung)
        XCTAssertTrue(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("onboarding.") }.isEmpty)
        XCTAssertEqual(defaults.string(forKey: "other.setting"), "keep")
        let again = OnboardingStore(defaults: defaults)
        XCTAssertEqual(again.step, .welcome)
        XCTAssertNil(again.birthday)
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

    func testFollowThreeShowsWhatFitsThePickedInterestsFirst() {
        let names = { (picked: [String]) in FollowSuggestions.ordered(self.town, picked: picked).map(\.name) }
        XCTAssertEqual(names(["coffee"]).first, "The Local Blend")
        XCTAssertEqual(Array(names(["bars"]).prefix(2)), ["The Middy", "Bad Habit"], "busiest first within an interest")
        // A place's Events add what its kind doesn't say: trivia makes The Middy a Games place.
        XCTAssertEqual(names(["games"]).first, "The Middy")
        XCTAssertEqual(names(["live_music"]).first, "Kennedy")
        XCTAssertEqual(names(["town_meetings"]).first, "City")
        // Picks take turns, in the order picked, so each shows near the top.
        XCTAssertEqual(Array(names(["coffee", "families_kids", "bars"]).prefix(3)),
                       ["The Local Blend", "Little Saints", "The Middy"])
        XCTAssertNotEqual(names(["coffee"]), names(["bars"]))
    }

    func testFollowThreeFillsToEightAndSearchesEverything() {
        XCTAssertEqual(FollowSuggestions.ordered(town, picked: ["coffee"]).count, 7, "all 7 when the town has fewer than 8")
        XCTAssertEqual(FollowSuggestions.search(town, "brew").map(\.name), ["Bad Habit"])
        XCTAssertEqual(FollowSuggestions.search(town, "school").map(\.name), ["Kennedy"], "kinds are searched too")
        XCTAssertTrue(FollowSuggestions.search(town, "zzz").isEmpty)
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
        store.leaveTooYoung()
        XCTAssertEqual(OnboardingStore(defaults: defaults).requests, [])
    }
}
