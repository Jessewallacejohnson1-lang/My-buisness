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

    func testUnder13SymbolExists() {
        XCTAssertNotNil(UIImage(systemName: OnboardingTooYoung.symbol))
    }
}
