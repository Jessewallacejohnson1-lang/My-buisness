//
//  OnboardingLookTests.swift
//  Block Party — Luma's look (BP app onboarding 34): every question names the SF Symbol drawn in its
//  grey circle. A misspelt name draws nothing and fails nowhere else, so each is checked against iOS.
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

    /// Birthday's icon is Jesse's cake, not a symbol (onboarding 36): the asset has to be in the app.
    func testBirthdayCakeIsInTheApp() {
        XCTAssertNotNil(UIImage(named: OnboardingHeading.cakeImage))
    }

    func testUnder13SymbolExists() {
        XCTAssertNotNil(UIImage(systemName: OnboardingTooYoung.symbol))
    }
}
