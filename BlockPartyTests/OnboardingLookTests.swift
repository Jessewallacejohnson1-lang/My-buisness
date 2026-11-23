//
//  OnboardingLookTests.swift
//  Block Party — Luma's look (BP app onboarding 34): every question names the SF Symbol drawn in its
//  grey circle. A misspelt name draws nothing and fails nowhere else, so each is checked against iOS.
//  The Big art look's cake (onboarding 43) has to be sharp at its 124 pt.
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

    func testUnder13SymbolExists() {
        XCTAssertNotNil(UIImage(systemName: OnboardingTooYoung.symbol))
    }

    /// The Welcome's two photos (onboarding 54): both in the app, the coin picks either, and the
    /// screenshot flag beats the coin.
    func testWelcomePhotoTakesTurns() {
        let photos = OnboardingWelcome.photos
        for name in [photos.dogs, photos.millstream] {
            XCTAssertNotNil(UIImage(named: name), "\(name) is not in the app")
        }
        XCTAssertEqual(OnboardingWelcome.pickPhoto(flag: nil, coin: true), photos.dogs)
        XCTAssertEqual(OnboardingWelcome.pickPhoto(flag: nil, coin: false), photos.millstream)
        XCTAssertEqual(OnboardingWelcome.pickPhoto(flag: "millstream", coin: true), photos.millstream)
        XCTAssertEqual(OnboardingWelcome.pickPhoto(flag: "dogs", coin: false), photos.dogs)
    }
}
