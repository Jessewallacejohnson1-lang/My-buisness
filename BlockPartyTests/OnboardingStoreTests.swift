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

    func testStartsOnWelcomeAndWalksTheNineBarSteps() {
        let store = OnboardingStore(defaults: defaults)
        XCTAssertEqual(store.step, .welcome)
        XCTAssertEqual(store.barIndex, 0)
        var indexes: [Int] = []
        for _ in 0..<OnboardingStep.barTotal { store.next(); indexes.append(store.barIndex) }
        XCTAssertEqual(indexes, Array(1...9))
        XCTAssertEqual(store.step, .contacts)
        XCTAssertFalse(store.finished)
        store.next()
        XCTAssertTrue(store.finished)
    }

    func testBackGoesToThePreviousStepAndStopsAtWelcome() {
        let store = OnboardingStore(defaults: defaults)
        store.next(); store.next()
        XCTAssertEqual(store.step, .code)
        store.back()
        XCTAssertEqual(store.step, .phone)
        XCTAssertFalse(store.forward)
        store.back(); store.back()
        XCTAssertEqual(store.step, .welcome)
    }

    func testRelaunchResumesOnTheSameStep() {
        let store = OnboardingStore(defaults: defaults)
        for _ in 0..<4 { store.next() }
        XCTAssertEqual(OnboardingStore(defaults: defaults).step, .photo)
    }

    func testFinishedStaysFinished() {
        let store = OnboardingStore(defaults: defaults)
        for _ in 0..<8 { store.next() }
        XCTAssertEqual(store.step, .friends)
        store.skipFriends()
        XCTAssertTrue(OnboardingStore(defaults: defaults).finished)
    }

    func testServerStampOnlyCountsOnTheWelcome() {
        let midway = OnboardingStore(defaults: defaults)
        midway.next()
        midway.serverSaysFinished()
        XCTAssertFalse(midway.finished, "a late read must not pull someone out halfway")
        midway.back()
        midway.serverSaysFinished()
        XCTAssertTrue(midway.finished)
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
}
