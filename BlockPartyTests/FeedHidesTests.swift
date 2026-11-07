//
//  FeedHidesTests.swift
//  What you take out of the Town feed (`FeedHides`): Not interested, Mute and Report (tickets 21
//  and 22), their Undo, and the Muted list. That the list leaves hidden cards out is `TownFeed`'s,
//  tested in TownFeedEventsTests.
//

import XCTest
@testable import BlockParty

/// Keeps every choice it's told, answers a Mute with its host, and fails when told to.
@MainActor
final class FeedChooser {
    var told: [FeedChoice] = []
    var error: Error?
    var muted: [MutedHost] = []
    var delay: Duration?
    func choose(_ choice: FeedChoice) async throws -> String? {
        if let delay { try await Task.sleep(for: delay) }
        if let error { throw error }
        told.append(choice)
        if case .mute = choice { return "parks-key" }
        return nil
    }
}

@MainActor
final class FeedHidesTests: XCTestCase {

    private func newHides(_ chooser: FeedChooser) -> FeedHides {
        FeedHides(choose: chooser.choose, readMuted: { chooser.muted }, deletePost: { _ in })
    }

    /// Of cards a and b from Parks and c from the City, those not hidden.
    private func left(_ hides: FeedHides) -> [String] {
        [("a", "Parks"), ("b", "Parks"), ("c", "City of St. Joseph")]
            .filter { !hides.isHidden(id: $0.0, host: $0.1) }.map(\.0)
    }

    func testNotInterestedFoldsTheCardToItsUndoLineThenItGoesAndIsSent() async {
        let chooser = FeedChooser()
        let hides = newHides(chooser)
        await hides.hide(id: "a", host: "Parks", mute: false)
        XCTAssertEqual(chooser.told, [.notInterested("a")], "sent straight away")
        XCTAssertEqual(hides.undo, FeedHide(id: "a", hostName: "Parks", mute: false))
        XCTAssertEqual(left(hides), ["a", "b", "c"], "a stays in, drawn as its Undo line")
        hides.undoEnded("a")
        XCTAssertNil(hides.undo)
        XCTAssertEqual(left(hides), ["b", "c"])
    }

    func testUndoBringsTheCardBackAndTakesTheChoiceBack() async {
        let chooser = FeedChooser()
        let hides = newHides(chooser)
        await hides.hide(id: "a", host: "Parks", mute: false)
        await hides.undoHide()
        await hides.hide(id: "b", host: "Parks", mute: true)
        await hides.undoHide()
        XCTAssertEqual(chooser.told, [.notInterested("a"), .undoNotInterested("a"), .mute("b"), .unmute("parks-key")])
        XCTAssertNil(hides.undo)
        XCTAssertEqual(left(hides), ["a", "b", "c"])
    }

    // MARK: Report (ticket 22)

    func testReportSendsTheReasonThenTheCardFoldsAndUndoLiftsOnlyTheHide() async throws {
        let chooser = FeedChooser()
        let hides = newHides(chooser)
        try await hides.report(id: "a", .scam)
        XCTAssertEqual(chooser.told, [.report("a", .scam)])
        XCTAssertEqual(left(hides), ["a", "b", "c"], "nothing moves while the sheet is open")
        hides.hideReported(id: "a", host: "Parks")
        XCTAssertEqual(hides.undo, FeedHide(id: "a", hostName: "Parks", mute: false))
        await hides.undoHide()
        XCTAssertEqual(chooser.told, [.report("a", .scam), .undoNotInterested("a")], "the report stays sent")
        XCTAssertEqual(left(hides), ["a", "b", "c"])
    }

    func testAReportThatFailsThrowsAndHidesNothing() async {
        let chooser = FeedChooser()
        chooser.error = URLError(.notConnectedToInternet)
        let hides = newHides(chooser)
        do {
            try await hides.report(id: "a", .nudity)
            XCTFail("the sheet must hear it failed")
        } catch {}
        XCTAssertEqual(left(hides), ["a", "b", "c"])
        XCTAssertNil(hides.undo)
    }

    func testWrongPhotoOnlyWithASavedPhotoWrongInfoOnlyOnAFoundEventAndNeitherHides() {
        XCTAssertEqual(ReportReason.offered(photo: false, found: false).map(\.label),
                       ["Scam, fraud or spam", "Bullying or unwanted contact", "Violence, hate or exploitation",
                        "Nudity or sexual activity", "Selling or promoting restricted items",
                        "Suicide, self-injury or eating disorders"])
        XCTAssertEqual(ReportReason.offered(photo: true, found: true).prefix(2), [.wrongPhoto, .wrongInfo])
        XCTAssertEqual(ReportReason.allCases.filter { !$0.hides }, [.wrongPhoto, .wrongInfo])
    }

    // MARK: A slow or failing network

    /// A slow network: Undo tapped while the Mute is still on its way waits for it, so the server
    /// gets the Mute first and Undo knows which host to unmute.
    func testUndoWaitsForTheChoiceStillOnItsWay() async {
        let chooser = FeedChooser()
        let hides = newHides(chooser)
        chooser.delay = .milliseconds(200)
        let hiding = Task { await hides.hide(id: "a", host: "Parks", mute: true) }
        while hides.undo == nil { await Task.yield() }
        await hides.undoHide()
        await hiding.value
        XCTAssertEqual(chooser.told, [.mute("a"), .unmute("parks-key")])
        XCTAssertEqual(left(hides), ["a", "b", "c"])
    }

    func testAChoiceThatDoesntGoThroughBringsTheCardBack() async {
        let chooser = FeedChooser()
        chooser.error = URLError(.notConnectedToInternet)
        let hides = newHides(chooser)
        await hides.hide(id: "a", host: "Parks", mute: true)
        XCTAssertNil(hides.undo)
        XCTAssertEqual(left(hides), ["a", "b", "c"])
    }

    func testAFailedUnmuteKeepsTheRowAndCountsAFailure() async {
        let chooser = FeedChooser()
        chooser.muted = [MutedHost(host: "parks-key", name: "Parks")]
        let hides = newHides(chooser)
        await hides.refreshMuted()
        chooser.error = URLError(.notConnectedToInternet)
        let went = await hides.unmute(chooser.muted[0])
        XCTAssertFalse(went, "the feed doesn't read the host back")
        XCTAssertEqual(hides.muted, chooser.muted)
        XCTAssertEqual(hides.unmuteFailures["parks-key"], 1)
    }
}
