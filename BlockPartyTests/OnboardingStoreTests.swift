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
}
