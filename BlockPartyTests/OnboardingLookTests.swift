//
//  OnboardingLookTests.swift
//  Block Party — Luma's look (BP app onboarding 34): every question names the SF Symbol drawn in its
//  grey circle. A misspelt name draws nothing and fails nowhere else, so each is checked against iOS.
//  The Big art look (onboarding 43) arrives a step at a time: which steps wear its colour is checked here.
//

import UIKit
import XCTest
@testable import BlockParty

final class OnboardingLookTests: XCTestCase {

    func testEveryQuestionStepsSymbolExists() {
        for step in OnboardingStep.allCases where step != .welcome {
            XCTAssertNotNil(UIImage(systemName: step.symbol), "\(step): no SF Symbol \(step.symbol)")
        }
    }

    func testLogInAndCreateAccountSymbolsExist() {
        for way in [OnboardingAccount.create, .logIn] {
            XCTAssertNotNil(UIImage(systemName: way.symbol), "\(way): no SF Symbol \(way.symbol)")
        }
    }

    /// Birthday's art is Jesse's cake, not a symbol (onboarding 36, 43): the asset has to be in the app, and
    /// sharp at the Big art look's 124 pt on a 3x screen.
    func testBirthdayCakeIsInTheApp() throws {
        let cake = try XCTUnwrap(UIImage(named: OnboardingBirthdayField.cakeImage))
        XCTAssertGreaterThanOrEqual(cake.size.height * cake.scale, BigArt.art * 3)
    }

    /// Profile and Birthday wear the Big art look (Jesse, 2026-11-19: the other steps change in tickets of
    /// their own); a step with no colour keeps Luma's grey canvas and icon circle.
    func testOnlyProfileAndBirthdayWearBigArtYet() {
        XCTAssertEqual(OnboardingStep.allCases.filter { $0.tint != nil }, [.profile, .birthday])
    }

    func testUnder13SymbolExists() {
        XCTAssertNotNil(UIImage(systemName: OnboardingTooYoung.symbol))
    }
}
