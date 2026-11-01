//
//  ProfileSaveProblemTests.swift
//  BlockPartyTests — Edit profile's failed-save line: a signed-out session gets its own words,
//  anything else keeps the connection line.
//

import XCTest
@testable import BlockParty

@MainActor
final class ProfileSaveProblemTests: XCTestCase {
    /// The app's own no-session error, thrown before anything is sent.
    func testNoSessionIsSignedOut() {
        let error = SupabaseError(message: "Your session ended. Sign in and try again.", status: 401)
        XCTAssertEqual(ProfileModel.SaveProblem.of(error), .signedOut)
        XCTAssertEqual(ProfileModel.SaveProblem.of(error).line, "Couldn't save. Log in and try again.")
    }

    /// The server refusing the token is the session too.
    func testServer401IsSignedOut() {
        XCTAssertEqual(ProfileModel.SaveProblem.of(SupabaseError(message: "JWT expired", status: 401)), .signedOut)
    }

    /// No signal, the server down, or its no: the connection line, as before.
    func testOtherFailuresKeepTheConnectionLine() {
        for error: Error in [URLError(.notConnectedToInternet), SupabaseError(message: "down", status: 503),
                             SupabaseError(message: "no", status: 403), SupabaseError(message: "none", status: nil)] {
            XCTAssertEqual(ProfileModel.SaveProblem.of(error), .other, "\(error)")
        }
        XCTAssertEqual(ProfileModel.SaveProblem.other.line,
                       "Couldn't save your profile. Check your connection and try again.")
    }
}
