//
//  SupabaseAnswerTests.swift
//  BlockPartyTests — what a failed call means, the one rule the Town feed and Going, Heart,
//  Save and Follow share (`SupabaseHTTP.noAnswer`, codebase-health 11).
//

import XCTest
@testable import BlockParty

@MainActor
final class SupabaseAnswerTests: XCTestCase {

    func testNoAnswerTriesAgainAndAServersNoDoesNot() {
        let table: [(Error, Bool, String)] = [
            (URLError(.notConnectedToInternet), true, "offline"),
            (URLError(.timedOut), true, "timed out"),
            (SupabaseError(message: "", status: 0), true, "no HTTP answer"),
            (SupabaseError(message: "", status: 401), true, "expired token, refreshed and sent again"),
            (SupabaseError(message: "", status: 408), true, "request timeout"),
            (SupabaseError(message: "", status: 429), true, "too many requests"),
            (SupabaseError(message: "", status: 500), true, "server error"),
            (SupabaseError(message: "", status: 503), true, "server down"),
            (SupabaseError(message: "", status: 400), false, "bad request"),
            (SupabaseError(message: "", status: 403), false, "row security says no"),
            (SupabaseError(message: "", status: 404), false, "not found"),
            (SupabaseError(message: "", status: 409), false, "conflict"),
            (SupabaseError(message: "", status: nil), false, "no status"),
            (CocoaError(.coderReadCorrupt), false, "a reply we couldn't read"),
        ]
        for (error, expected, why) in table {
            XCTAssertEqual(SupabaseHTTP.noAnswer(error), expected, why)
        }
    }
}
