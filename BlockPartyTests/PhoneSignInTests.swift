//
//  PhoneSignInTests.swift
//  BlockPartyTests — phone sign-in (BP app onboarding 17, 44, 45): what counts as a number, what the two steps do
//  with the server's answers, and what is asked of GoTrue. No test here talks to the live server or keeps a session.
//

import UIKit
import XCTest
@testable import BlockParty

@MainActor
final class PhoneSignInTests: XCTestCase {

    // MARK: A number

    func testANumberIsItsTenDigitsHoweverItWasTyped() {
        for typed in ["3205550142", "320 555 0142", "(320) 555-0142", "+1 320-555-0142", "1 320 555 0142"] {
            XCTAssertEqual(PhoneNumber.digits(typed), "3205550142", typed)
        }
        XCTAssertEqual(PhoneNumber.digits("32055501429999"), "3205550142", "no more than ten")
        XCTAssertEqual(PhoneNumber.digits("1205"), "1205", "still typing: the 1 may be the number's own")
        XCTAssertEqual(PhoneNumber.sent("3205550142"), "+13205550142")
    }

    func testDigitsAreSpacedAsHinges() {
        XCTAssertEqual(PhoneNumber.spaced(""), "")
        XCTAssertEqual(PhoneNumber.spaced("320"), "320")
        XCTAssertEqual(PhoneNumber.spaced("3205"), "320 5")
        XCTAssertEqual(PhoneNumber.spaced("3205550142"), "320 555 0142")
    }

    /// The server scrambles the account's number without its plus; a friend's contact card is scrambled on their
    /// phone. The two have to be one code, or a checked number finds nobody.
    func testASentNumberMakesTheSameContactsCodeAsACard() {
        XCTAssertEqual(ContactCodes.phone(PhoneNumber.sent("3205550142")), ContactCodes.phone("(320) 555-0142"))
    }

    func testLogInsBoxTellsAPhoneNumberFromAnEmail() {
        for number in ["3205550142", " (320) 555-0142 ", "+1 320 555 0142"] {
            XCTAssertTrue(PhoneNumber.looksLike(number), number)
        }
        for not in ["", "320555014", "32055501421", "3205550142@vtext.com", "avery@example.com", "+49 151 5550142"] {
            XCTAssertFalse(PhoneNumber.looksLike(not), not)
        }
    }

    /// Two countries, so a bad day costs $10.58 (Jesse, 2026-11-23).
    func testTextsGoToTheUnitedStatesAndCanada() {
        XCTAssertEqual(PhoneCountry.allCases.map(\.name), ["United States", "Canada"])
    }

    /// Off until texts work: today's Welcome, Log in and Settings (Jesse's yes, 2026-11-23).
    func testPhoneSignInIsOffAsShipped() {
        XCTAssertFalse(PhoneSignIn.isOn)
        let form = AccountForm()
        form.email = "3205550142"
        XCTAssertFalse(form.canSubmit(.logIn), "Log in takes an email alone")
        XCTAssertEqual(OnboardingAccount.logIn.symbol, "envelope")
    }

    // MARK: The two steps

    private final class Server {
        var sent: [String] = []
        var checks: [String] = []
        var signOuts = 0
        var refusal: String?
        var answer = AuthStore.CodeAnswer.right
        /// Holds the answer back until the test lets it go.
        var gate: CheckedContinuation<Void, Never>?
        var slow = false

        func wait() async { if slow { await withCheckedContinuation { gate = $0 } } }
        func letGo() { gate?.resume(); gate = nil }
    }

    private func form(_ server: Server, changing: Bool = false, texted: String? = nil, current: String? = nil) -> PhoneForm {
        PhoneForm(changing: changing, texted: texted, current: current, calls: .init(
            send: { server.sent.append($0); await server.wait(); return server.refusal },
            verify: { code, phone in
                server.checks.append("\(code) \(phone)")
                await server.wait()
                return server.answer
            },
            signOut: { server.signOuts += 1 }))
    }

    func testContinueWaitsForTenDigitsThenTextsAndOpensTheCode() async {
        let server = Server(), form = form(server)
        form.digits = "320555014"
        XCTAssertFalse(form.canSend)
        XCTAssertNil(form.send())
        XCTAssertEqual(server.sent, [])
        form.digits = "3205550142"
        await form.send()?.value
        XCTAssertEqual(server.sent, ["+13205550142"])
        XCTAssertEqual(form.stage, .code)
        XCTAssertFalse(form.busy)
    }

    func testARefusedTextStaysOnTheNumberWithALineUntilYouType() async {
        let server = Server(), form = form(server)
        server.refusal = AuthStore.Words.offline
        form.digits = "3205550142"
        await form.send()?.value
        XCTAssertEqual(form.stage, .number)
        XCTAssertEqual(form.line, AuthStore.Words.offline)
        XCTAssertEqual(form.refusals, 1)
        XCTAssertFalse(form.busy)
        form.digits = "320555014"
        XCTAssertNil(form.line)
    }

    func testThePencilKeepsTheNumberAndContinueTextsAgainOnlyAfterTheWait() async {
        let server = Server(), form = form(server)
        form.digits = "3205550142"
        await form.send()?.value
        form.code = "482"
        form.editNumber()
        XCTAssertEqual(form.stage, .number)
        XCTAssertEqual(form.digits, "3205550142")
        XCTAssertFalse(form.forward, "slides in from the left")
        XCTAssertNil(form.send(), "the code just sent still works")
        XCTAssertEqual(form.stage, .code)
        XCTAssertEqual(server.sent.count, 1)
        form.editNumber()
        await form.send(now: Date().addingTimeInterval(PhoneForm.resendWait + 1))?.value
        XCTAssertEqual(server.sent.count, 2, "a new code")
        form.editNumber()
        form.digits = "3205550143"
        await form.send()?.value
        XCTAssertEqual(server.sent.last, "+13205550143", "another number needs no wait")
    }

    func testAWrongCodeSaysSoAndEmptiesAndTypingClearsTheLine() async {
        let server = Server(), form = form(server, texted: "3205550142")
        server.answer = .wrong
        form.code = "111111"
        await form.verify { XCTFail("nothing comes after a wrong code"); return nil }?.value
        XCTAssertEqual(form.code, "")
        XCTAssertEqual(form.wrongs, 1)
        XCTAssertEqual(form.line, "That code didn't work. Try again.", "still there once the boxes are empty")
        XCTAssertFalse(form.busy)
        form.code = "4"
        XCTAssertNil(form.line)
    }

    func testNoSignalKeepsTheDigits() async {
        let server = Server(), form = form(server, texted: "3205550142")
        server.answer = .refused(AuthStore.Words.offline)
        form.code = "482913"
        await form.verify { nil }?.value
        XCTAssertEqual(form.code, "482913")
        XCTAssertEqual(form.wrongs, 0)
        XCTAssertEqual(form.line, AuthStore.Words.offline)
    }

    func testTheRightCodeGoesOnOnce() async {
        let server = Server(), form = form(server, texted: "3205550142")
        form.code = "482913"
        var went = 0
        await form.verify { went += 1; return nil }?.value
        XCTAssertEqual(server.checks, ["482913 +13205550142"])
        XCTAssertEqual(went, 1)
    }

    func testARetryAfterTheRightCodeChecksNoCodeAgain() async {
        let server = Server(), form = form(server, texted: "3205550142")
        form.code = "482913"
        await form.verify { AuthStore.Words.offline }?.value
        XCTAssertTrue(form.checked)
        XCTAssertEqual(form.line, AuthStore.Words.offline)
        form.editNumber()
        XCTAssertEqual(form.stage, .code, "the code is spent: no going back to the number")
        await form.verify { nil }?.value
        XCTAssertEqual(server.checks.count, 1)
    }

    func testTheXAfterARightCodeThatWentNowhereSignsOut() async {
        let server = Server(), form = form(server, texted: "3205550142")
        form.code = "482913"
        await form.verify { AuthStore.Words.offline }?.value
        form.close()
        for _ in 0..<50 where server.signOuts == 0 { await Task.yield() }
        XCTAssertEqual(server.signOuts, 1)
    }

    func testLeavingALateVerifyFreesTheScreenAndItsAnswerSignsNobodyIn() async {
        let server = Server(), form = form(server, texted: "3205550142")
        server.slow = true
        form.code = "482913"
        let out = form.verify { XCTFail("the screen was left"); return nil }
        for _ in 0..<50 where server.gate == nil { await Task.yield() }
        XCTAssertTrue(form.busy)
        form.editNumber()
        XCTAssertFalse(form.busy, "no spinner to be trapped on")
        XCTAssertEqual(form.stage, .number)
        server.letGo()
        await out?.value
        XCTAssertEqual(server.signOuts, 1, "its sign-in is undone")
        XCTAssertNil(form.line)
    }

    func testAChangeCantBeToTheNumberYouHave() async {
        let server = Server(), form = form(server, changing: true, current: "13205550142")
        form.digits = "3205550142"
        XCTAssertNil(form.send())
        XCTAssertEqual(server.sent, [])
        XCTAssertEqual(form.line, AuthStore.Words.samePhone)
    }

    func testClosingAChangeNeverSignsOut() async {
        let server = Server(), form = form(server, changing: true, texted: "3205550142")
        form.code = "482913"
        await form.verify { AuthStore.Words.offline }?.value
        form.close()
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(server.signOuts, 0)
    }

    // MARK: What GoTrue is asked

    private final class GoTrue {
        var asked: [(method: String, path: String, body: [String: String])] = []
        var status = 200
        var answer = "{}"
        var before: () -> Void = {}

        var send: Supabase.Send {
            Supabase.Send { request in
                let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] } ?? [:]
                self.asked.append((request.httpMethod ?? "", request.url!.lastPathComponent, body))
                self.before()
                return (Data(self.answer.utf8), HTTPURLResponse(url: request.url!, statusCode: self.status, httpVersion: nil, headerFields: nil)!)
            }
        }
    }

    private func session(_ id: String, phone: String = "13205550142") -> String {
        #"{"access_token":"a","refresh_token":"r","expires_at":4000000000,"user":{"id":"\#(id)","email":"","phone":"\#(phone)"}}"#
    }

    private func signedIn(_ id: String, phone: String) throws -> Session {
        try JSONDecoder().decode(Session.self, from: Data(session(id, phone: phone).utf8))
    }

    func testACodeIsAskedForTheSameWayForAnyNumber() async {
        let server = GoTrue(), auth = AuthStore(send: server.send)
        let refused = await auth.sendCode(to: "+13205550142")
        XCTAssertNil(refused)
        XCTAssertEqual(server.asked.map(\.path), ["otp"])
        XCTAssertEqual(server.asked.first?.body, ["phone": "+13205550142"], "nothing says whether the number is known")
    }

    func testTheRightCodeSignsInWithItsNumber() async {
        let server = GoTrue(), auth = AuthStore(send: server.send)
        server.answer = session("u1")
        let answer = await auth.verifyCode("482913", for: "+13205550142")
        XCTAssertEqual(answer, .right)
        XCTAssertEqual(server.asked.first?.body, ["type": "sms", "phone": "+13205550142", "token": "482913"])
        XCTAssertTrue(auth.hasAccount)
        XCTAssertEqual(auth.phone, "13205550142")
    }

    func testAWrongOrLateCodeIsWrongAndSignsNobodyIn() async {
        let server = GoTrue(), auth = AuthStore(send: server.send)
        server.status = 403
        server.answer = #"{"error_code":"otp_expired","msg":"Token has expired or is invalid"}"#
        let answer = await auth.verifyCode("111111", for: "+13205550142")
        XCTAssertEqual(answer, .wrong)
        XCTAssertFalse(auth.hasAccount)
    }

    func testACheckLeftWhileItWasOutSignsNobodyIn() async {
        let server = GoTrue(), auth = AuthStore(send: server.send)
        server.answer = session("u1")
        var out: Task<AuthStore.CodeAnswer, Never>?
        server.before = { out?.cancel() }
        out = Task { await auth.verifyCode("482913", for: "+13205550142") }
        _ = await out?.value
        XCTAssertFalse(auth.hasAccount)
    }

    func testAChangeKeepsTheOldNumberUntilItsCode() async throws {
        let server = GoTrue(), auth = AuthStore(send: server.send, session: try signedIn("u1", phone: "13205550142"))
        let refused = await auth.sendChangeCode(to: "+13205550199")
        XCTAssertNil(refused)
        XCTAssertEqual(server.asked.map(\.method), ["PUT"])
        XCTAssertEqual(server.asked.map(\.path), ["user"])
        XCTAssertEqual(auth.phone, "13205550142", "the old one still")
        server.answer = session("u1", phone: "13205550199")
        let answer = await auth.verifyChangeCode("482913", for: "+13205550199")
        XCTAssertEqual(answer, .right)
        XCTAssertEqual(server.asked.last?.body["type"], "phone_change")
        XCTAssertEqual(auth.phone, "13205550199")
    }

    func testAChangeAnsweredForAnotherAccountIsThrownAway() async throws {
        let server = GoTrue(), auth = AuthStore(send: server.send, session: try signedIn("u1", phone: "13205550142"))
        server.answer = session("u2", phone: "13205550199")
        let answer = await auth.verifyChangeCode("482913", for: "+13205550199")
        XCTAssertEqual(answer, .refused(AuthStore.Words.other))
        XCTAssertEqual(auth.userId, "u1")
        XCTAssertEqual(auth.phone, "13205550142")
    }

    /// Under 13's Close on a phone account: the server's delete, then out of it, even when the delete didn't go through.
    func testUnder13sCloseDeletesAPhoneAccountAndSignsOutEitherWay() async throws {
        for status in [200, 503] {
            let server = GoTrue(), auth = AuthStore(send: server.send, session: try signedIn("u1", phone: "13205550142"))
            server.status = status
            await auth.deleteAccount()
            XCTAssertEqual(server.asked.map(\.path), ["delete_my_account", "logout"], "\(status)")
            XCTAssertFalse(auth.hasAccount, "\(status)")
        }
    }

    func testEachRefusalHasItsOwnLine() {
        func refused(_ code: String, _ status: Int) -> Error { SupabaseError(message: "Server English", status: status, code: code) }
        XCTAssertEqual(AuthStore.phoneLine(for: refused("validation_failed", 400)), AuthStore.Words.badPhone)
        XCTAssertEqual(AuthStore.phoneLine(for: refused("sms_send_failed", 422)), AuthStore.Words.badPhone)
        XCTAssertEqual(AuthStore.phoneLine(for: refused("phone_exists", 422)), AuthStore.Words.phoneTaken)
        XCTAssertEqual(AuthStore.phoneLine(for: refused("over_sms_send_rate_limit", 429)), AuthStore.Words.tooMany)
        XCTAssertEqual(AuthStore.phoneLine(for: refused("phone_provider_disabled", 400)), AuthStore.Words.other)
        XCTAssertEqual(AuthStore.phoneLine(for: URLError(.timedOut)), AuthStore.Words.offline)
        XCTAssertEqual(AuthStore.line(for: refused("validation_failed", 400)), AuthStore.Words.badEmail, "an email's stays its own")
    }

    func testASessionKeptBeforePhoneSignInStillReads() throws {
        let kept = #"{"access_token":"a","refresh_token":"r","expires_at":4000000000,"user":{"id":"u1","email":"sam@example.com"}}"#
        XCTAssertNil(try JSONDecoder().decode(Session.self, from: Data(kept.utf8)).user.phone)
    }
}
