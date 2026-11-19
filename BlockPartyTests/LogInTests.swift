//
//  LogInTests.swift
//  BlockPartyTests — Log in and Create account (BP app onboarding 27): what the screens say when
//  the server says no, matched on GoTrue's code or the status and never its English, and when
//  the Next bar lets you on, Forgot password's steps included (onboarding 40).
//

import XCTest
@testable import BlockParty

final class LogInTests: XCTestCase {
    private func refused(_ code: String?, status: Int = 400) -> Error {
        SupabaseError(message: "Server English", status: status, code: code)
    }

    func testEachRefusalHasItsOwnLine() {
        XCTAssertEqual(AuthStore.line(for: refused("invalid_credentials")), AuthStore.Words.wrong)
        XCTAssertEqual(AuthStore.line(for: refused("user_already_exists", status: 422)), AuthStore.Words.taken)
        XCTAssertEqual(AuthStore.line(for: refused("email_exists", status: 422)), AuthStore.Words.taken)
        XCTAssertEqual(AuthStore.line(for: refused("weak_password", status: 422)), AuthStore.Words.short)
        XCTAssertEqual(AuthStore.line(for: refused("email_address_invalid")), AuthStore.Words.badEmail)
        XCTAssertEqual(AuthStore.line(for: refused("over_request_rate_limit", status: 429)), AuthStore.Words.tooMany)
        XCTAssertEqual(AuthStore.line(for: refused(nil, status: 429)), AuthStore.Words.tooMany)
    }

    func testNoAnswerSaysCheckYourConnection() {
        XCTAssertEqual(AuthStore.line(for: URLError(.notConnectedToInternet)), AuthStore.Words.offline)
        XCTAssertEqual(AuthStore.line(for: refused(nil, status: 503)), AuthStore.Words.offline)
    }

    func testAnythingElseGetsTheFallbackNeverTheServersWords() {
        let line = AuthStore.line(for: refused("something_new"))
        XCTAssertEqual(line, AuthStore.Words.other)
        XCTAssertFalse(line.contains("Server English"))
    }

    @MainActor
    func testNextWaitsForAnEmailAndSixCharacters() {
        let form = AccountForm()
        XCTAssertFalse(form.canSubmit(.logIn))
        form.email = "avery@example"
        form.password = "joetown"
        XCTAssertFalse(form.canSubmit(.logIn), "no dot after the @")
        form.email = " avery@example.com "
        XCTAssertTrue(form.canSubmit(.logIn), "spaces around it are trimmed")
        form.password = "joe"
        XCTAssertFalse(form.canSubmit(.create), "under 6 characters")
    }

    // MARK: Forgot password (onboarding 40)

    @MainActor
    func testEachForgotPasswordStepWaitsForItsOwnAnswer() {
        let form = AccountForm()
        form.email = "avery@example.com"
        XCTAssertTrue(form.canSubmit(.forgot), "the email alone sends the code")
        XCTAssertFalse(form.canSubmit(.code))
        form.code = "48291"
        XCTAssertFalse(form.canSubmit(.code), "5 digits")
        form.code = "482913"
        XCTAssertTrue(form.canSubmit(.code))
        form.password = "joe"
        XCTAssertFalse(form.canSubmit(.newPassword), "under 6 characters")
        form.password = "joetown"
        XCTAssertTrue(form.canSubmit(.newPassword))
    }

    func testAWrongCodeAndTheOldPasswordHaveTheirOwnLines() {
        XCTAssertEqual(AuthStore.line(for: refused("otp_expired", status: 403)), AuthStore.Words.badCode)
        XCTAssertEqual(AuthStore.line(for: refused("same_password", status: 422)), AuthStore.Words.samePassword)
        XCTAssertEqual(AuthStore.line(for: refused("over_email_send_rate_limit", status: 429)), AuthStore.Words.tooMany)
    }
}
