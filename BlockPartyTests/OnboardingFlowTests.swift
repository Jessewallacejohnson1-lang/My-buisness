//
//  OnboardingFlowTests.swift
//  BlockPartyTests — the pure logic behind the 20-screen onboarding.
//
//  The flow itself is visual and has no test path (the bar there is "builds clean +
//  confirmed in the simulator via screenshots"). But four pieces of it are pure,
//  brand-critical logic of exactly the kind CLAUDE.md says to cover — and three of them
//  fail SILENTLY, which is what makes them worth testing:
//
//   • `BPFinaleScreen.line(forLevel:)` — the wrong closing line still looks perfectly
//     fine on screen. Nothing surfaces the mistake.
//   • `BPStep.progress` — an off-by-one leaves the bar slightly wrong on every screen.
//   • `BPAnswers` round-trip — a broken buffer silently loses twenty screens of answers
//     at the exact moment the user signs in.
//   • `BPOnboardingCompletion.landingTab` — sends the user to the wrong tab.
//

import XCTest
@testable import BlockParty

@MainActor
final class OnboardingFlowTests: XCTestCase {

    /// An isolated suite, wiped before each test.
    ///
    /// `UserDefaults.standard` is NOT usable here: the test host is the real app, whose
    /// container carries whatever the screenshot-seeding wrote (`hygge.onboarding.*`),
    /// and those are the very keys under test. The first run of this file failed on
    /// exactly that — reading a leftover "moving_here" from a screenshot session.
    private static let suiteName = "blockparty.tests.onboarding"
    private var store: UserDefaults!

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removePersistentDomain(forName: Self.suiteName)
        store = UserDefaults(suiteName: Self.suiteName)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: Self.suiteName)
        store = nil
        super.tearDown()
    }

    // MARK: - S20's closing line, keyed to S08's town_level

    func testFinaleLineForEachLevel() {
        XCTAssertEqual(BPFinaleScreen.line(forLevel: 1),
                       "New in town? Perfect. We'll show you around.")
        XCTAssertEqual(BPFinaleScreen.line(forLevel: 5),
                       "Alright, mayor — your town's waiting.")
        for mid in 2...4 {
            XCTAssertEqual(BPFinaleScreen.line(forLevel: mid),
                           "St. Joe's waiting — let's go.",
                           "level \(mid) should take the neutral line")
        }
    }

    /// A nil level is only reachable if S08 were somehow skipped. It must fall to the
    /// neutral line — never greet a stranger as the mayor.
    func testFinaleLineWithNoLevelIsNeutral() {
        XCTAssertEqual(BPFinaleScreen.line(forLevel: nil),
                       "St. Joe's waiting — let's go.")
        XCTAssertEqual(BPFinaleScreen.line(forLevel: 99),
                       "St. Joe's waiting — let's go.")
        XCTAssertEqual(BPFinaleScreen.line(forLevel: 0),
                       "St. Joe's waiting — let's go.")
    }

    // MARK: - Progress bar

    /// The bar debuts on S05 (`.connection`) and must be absent before it — including on
    /// the two talking screens, which DO have a back arrow.
    func testProgressAbsentBeforeConnection() {
        for step in [BPStep.splash, .welcome, .hello, .sixQuestions] {
            XCTAssertFalse(step.showsProgress, "\(step) must not show the bar")
            XCTAssertEqual(step.progress, 0)
        }
    }

    func testProgressRunsFromConnectionToFinale() {
        XCTAssertTrue(BPStep.connection.showsProgress)
        XCTAssertEqual(BPStep.finale.progress, 1.0, accuracy: 0.0001,
                       "the last screen must read as complete")
        // Strictly increasing across every bar-bearing step — an off-by-one or a
        // reordered case would break monotonicity here rather than in a screenshot.
        let bearing = BPStep.allCases.filter(\.showsProgress)
        for (a, b) in zip(bearing, bearing.dropFirst()) {
            XCTAssertLessThan(a.progress, b.progress, "\(a) → \(b) must advance")
        }
        XCTAssertGreaterThan(BPStep.connection.progress, 0)
    }

    func testBackArrowAbsentOnlyOnTheFirstTwoScreens() {
        XCTAssertFalse(BPStep.splash.showsBack)
        XCTAssertFalse(BPStep.welcome.showsBack)
        for step in BPStep.allCases where step.rawValue >= BPStep.hello.rawValue {
            XCTAssertTrue(step.showsBack, "\(step) should offer a way back")
        }
    }

    /// Every step maps to a reference frame, so the verification loop can always name
    /// what a screen is being diffed against.
    func testEveryStepHasAReferenceFrame() {
        for step in BPStep.allCases {
            XCTAssertTrue(step.refID.hasPrefix("S"), "\(step) has no ref frame")
        }
        XCTAssertEqual(BPStep.allCases.count, 17)
    }

    // MARK: - The answer buffer

    func testAnswersRoundTripThroughStorage() {
        let a = BPAnswers(defaults: store)

        a.connection = "moving_here"
        a.townLevel = 2
        a.motivations = ["find_things", "stay_in_loop"]
        a.notifyCadence = "few"
        a.foundingMember = true
        a.landingChoice = BPLandingScreen.week

        // A second instance reads the same persisted buffer — this is the path that runs
        // after the app is killed mid-flow and after sign-in.
        let reloaded = BPAnswers(defaults: store)
        XCTAssertEqual(reloaded.connection, "moving_here")
        XCTAssertEqual(reloaded.townLevel, 2)
        XCTAssertEqual(reloaded.motivations, ["find_things", "stay_in_loop"])
        XCTAssertEqual(reloaded.notifyCadence, "few")
        XCTAssertEqual(reloaded.foundingMember, true)
        XCTAssertEqual(reloaded.landingChoice, BPLandingScreen.week)
        XCTAssertTrue(reloaded.isComplete)
    }

    func testClearWipesEveryAnswer() {
        let a = BPAnswers(defaults: store)
        a.connection = "live_here"
        a.townLevel = 5
        a.motivations = ["other"]
        a.notifyCadence = "daily"
        a.foundingMember = false
        a.landingChoice = BPLandingScreen.map
        a.clear()

        let reloaded = BPAnswers(defaults: store)
        XCTAssertNil(reloaded.connection)
        XCTAssertNil(reloaded.townLevel)
        XCTAssertTrue(reloaded.motivations.isEmpty)
        XCTAssertNil(reloaded.notifyCadence)
        XCTAssertNil(reloaded.foundingMember)
        XCTAssertNil(reloaded.landingChoice)
        XCTAssertFalse(reloaded.isComplete)
    }

    /// `isComplete` gates whether `onboarded_at` gets stamped. A partially-answered
    /// buffer must NOT read as complete — stamping it would permanently skip the rest of
    /// onboarding for that user.
    func testPartialAnswersAreNotComplete() {
        let a = BPAnswers(defaults: store)

        XCTAssertFalse(a.isComplete, "an empty buffer is not complete")
        a.connection = "live_here"
        XCTAssertFalse(a.isComplete, "one answer is not complete")
        a.townLevel = 3
        a.motivations = ["meet_people"]
        a.notifyCadence = "weekly"
        a.foundingMember = true
        XCTAssertFalse(a.isComplete, "five of six is not complete")
        a.landingChoice = BPLandingScreen.map
        XCTAssertTrue(a.isComplete)
    }

    // MARK: - S19 routing

    func testLandingTabMapsToRealTabs() {
        let a = BPAnswers(defaults: store)

        XCTAssertNil(BPOnboardingCompletion.landingTab(a), "unanswered → no forced tab")

        a.landingChoice = BPLandingScreen.week
        XCTAssertEqual(BPOnboardingCompletion.landingTab(a), .home,
                       "\"This week in St. Joe\" lands on Today — there is no This-week tab")

        a.landingChoice = BPLandingScreen.map
        XCTAssertEqual(BPOnboardingCompletion.landingTab(a), .map)

        a.landingChoice = "something_removed_later"
        XCTAssertNil(BPOnboardingCompletion.landingTab(a),
                     "an unknown id must not crash or route somewhere arbitrary")
    }
}
