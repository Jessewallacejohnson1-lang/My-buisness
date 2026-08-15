//
//  PinDetailCopyTests.swift
//  BlockPartyTests — the pin-detail sheet's status-card copy (PinDetailCopy),
//  map polish Phase 3.
//
//  Pure string logic: the status word, the real-data-only happenings sentence,
//  the live/quiet status sentence, the secondary street line, and the round-2
//  quiet-collapse rule (isQuiet + quietSentence — the compact card). The visual
//  sheet (pills, dim, drag-dismiss) is verified by simulator screenshots.
//

import XCTest
@testable import BlockParty

final class PinDetailCopyTests: XCTestCase {

    // MARK: Status word

    func testStatusWordIsQuietWithNothingToday() {
        XCTAssertEqual(PinDetailCopy.statusWord(isLive: false, todayCount: 0), "Quiet today")
    }

    func testStatusWordAnticipatesEventsLaterToday() {
        XCTAssertEqual(PinDetailCopy.statusWord(isLive: false, todayCount: 2), "Later today")
    }

    func testStatusWordLiveWinsOverEverything() {
        XCTAssertEqual(PinDetailCopy.statusWord(isLive: true, todayCount: 0), "Happening now")
        XCTAssertEqual(PinDetailCopy.statusWord(isLive: true, todayCount: 3), "Happening now")
    }

    // MARK: Happenings sentence (real data only)

    func testHappeningsSentenceOmittedAtZero() {
        XCTAssertNil(PinDetailCopy.happeningsSentence(todayCount: 0))
    }

    func testHappeningsSentenceSingular() {
        XCTAssertEqual(PinDetailCopy.happeningsSentence(todayCount: 1),
                       "One event here today.")
    }

    func testHappeningsSentenceSpellsSmallCounts() {
        XCTAssertEqual(PinDetailCopy.happeningsSentence(todayCount: 3),
                       "Three events here today.")
    }

    func testHappeningsSentenceFallsBackToNumeralsPastNine() {
        XCTAssertEqual(PinDetailCopy.happeningsSentence(todayCount: 12),
                       "12 events here today.")
    }

    // MARK: Status sentence

    func testStatusSentenceQuiet() {
        XCTAssertEqual(PinDetailCopy.statusSentence(isLive: false, liveTitle: nil),
                       "Nothing happening yet today.")
    }

    func testStatusSentenceNamesTheLiveEvent() {
        XCTAssertEqual(PinDetailCopy.statusSentence(isLive: true, liveTitle: "Farmers Market"),
                       "Farmers Market is happening right now.")
    }

    func testStatusSentenceLiveWithoutATitleStaysGeneric() {
        // A DEBUG-forced live state has no resolvable event — never invent one.
        XCTAssertEqual(PinDetailCopy.statusSentence(isLive: true, liveTitle: nil),
                       "Something is happening here right now.")
        XCTAssertEqual(PinDetailCopy.statusSentence(isLive: true, liveTitle: ""),
                       "Something is happening here right now.")
    }

    func testStatusRowLabel() {
        XCTAssertEqual(PinDetailCopy.statusRowLabel(isLive: true), "Live now")
        XCTAssertEqual(PinDetailCopy.statusRowLabel(isLive: false), "Right now")
    }

    // MARK: Quiet compact card (round 2 — rows render only on real signal)

    func testQuietWithNoEventsAndNotLive() {
        XCTAssertTrue(PinDetailCopy.isQuiet(isLive: false, todayCount: 0))
    }

    func testNotQuietWithEventsToday() {
        XCTAssertFalse(PinDetailCopy.isQuiet(isLive: false, todayCount: 1))
        XCTAssertFalse(PinDetailCopy.isQuiet(isLive: false, todayCount: 5))
    }

    func testNotQuietWhileLiveEvenWithZeroResolvedEvents() {
        // A DEBUG-forced live state resolves no event — live still wins over quiet.
        XCTAssertFalse(PinDetailCopy.isQuiet(isLive: true, todayCount: 0))
    }

    func testQuietSentenceIsTheStatusWordInSentenceForm() {
        XCTAssertEqual(PinDetailCopy.quietSentence, "Quiet today.")
        XCTAssertEqual(PinDetailCopy.quietSentence,
                       PinDetailCopy.statusWord(isLive: false, todayCount: 0) + ".")
    }

    // MARK: Secondary line (street from real address data, else the town)

    func testSecondaryLineTakesTheStreetFromAnAddress() {
        XCTAssertEqual(
            PinDetailCopy.secondaryLine(address: "19 W Minnesota St, St Joseph, MN 56374"),
            "19 W Minnesota St")
    }

    func testSecondaryLineFallsBackToTheTown() {
        XCTAssertEqual(PinDetailCopy.secondaryLine(address: nil), "Saint Joseph")
        XCTAssertEqual(PinDetailCopy.secondaryLine(address: ""), "Saint Joseph")
        XCTAssertEqual(PinDetailCopy.secondaryLine(address: "   "), "Saint Joseph")
    }

    func testSecondaryLineWithoutCommasUsesTheWholeAddress() {
        XCTAssertEqual(PinDetailCopy.secondaryLine(address: "College Ave N"),
                       "College Ave N")
    }

    // MARK: Brand voice — complete sentences, no exclamation points

    func testEverySentenceIsACompleteSentenceWithoutExclamation() {
        // Arrange — every sentence the card can produce.
        let sentences: [String] = [
            PinDetailCopy.happeningsSentence(todayCount: 1)!,
            PinDetailCopy.happeningsSentence(todayCount: 5)!,
            PinDetailCopy.statusSentence(isLive: false, liveTitle: nil),
            PinDetailCopy.statusSentence(isLive: true, liveTitle: "Trivia Night"),
            PinDetailCopy.statusSentence(isLive: true, liveTitle: nil),
            PinDetailCopy.quietSentence,
        ]

        // Assert
        for sentence in sentences {
            XCTAssertTrue(sentence.hasSuffix("."), "Not a sentence: \(sentence)")
            XCTAssertFalse(sentence.contains("!"), "Exclamation point: \(sentence)")
            XCTAssertTrue(sentence.first?.isUppercase == true, "No capital: \(sentence)")
        }
    }
}
