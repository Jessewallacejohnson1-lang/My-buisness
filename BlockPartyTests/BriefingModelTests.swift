//
//  BriefingModelTests.swift
//  Block Party — the briefing's pure transforms.
//
//  The optimistic vote is the one place the Today tab edits data it did not
//  fetch, so it is the one place a mutation bug would show up as a poll
//  reporting a vote that never landed.
//

import XCTest
@testable import BlockParty

final class BriefingModelTests: XCTestCase {

    private func poll(counts: [Int] = [1, 2, 3, 4], myVote: Int? = nil) -> BriefingTouch {
        BriefingTouch(
            id: "t1", kind: .poll, prompt: "How do you take your sweet corn?",
            options: ["Butter and salt, done", "Butter, salt, pepper",
                      "Straight off the cob, dry", "Cut off, in a bowl"],
            body: nil, voteCounts: counts, totalVotes: counts.reduce(0, +), myVote: myVote
        )
    }

    // MARK: - applyingVote

    func testApplyingVoteIncrementsOnlyTheChosenOption() {
        let after = poll().applyingVote(2)
        XCTAssertEqual(after.voteCounts, [1, 2, 4, 4])
        XCTAssertEqual(after.totalVotes, 11)
        XCTAssertEqual(after.myVote, 2)
        XCTAssertTrue(after.hasVoted)
    }

    func testApplyingVoteDoesNotMutateTheOriginal() {
        let before = poll()
        _ = before.applyingVote(0)
        XCTAssertEqual(before.voteCounts, [1, 2, 3, 4])
        XCTAssertEqual(before.totalVotes, 10)
        XCTAssertNil(before.myVote)
    }

    func testApplyingVoteIsANoOpWhenAlreadyVoted() {
        let voted = poll(myVote: 1)
        let after = voted.applyingVote(3)
        XCTAssertEqual(after.myVote, 1, "a vote is final in v1")
        XCTAssertEqual(after.voteCounts, voted.voteCounts)
        XCTAssertEqual(after.totalVotes, voted.totalVotes)
    }

    func testApplyingVoteIsANoOpForAnOutOfRangeIndex() {
        let after = poll().applyingVote(9)
        XCTAssertNil(after.myVote)
        XCTAssertEqual(after.totalVotes, 10)
    }

    /// The contract invariant the RPC guarantees must survive the local edit too,
    /// or the bars stop summing to the total the moment someone votes.
    func testVoteCountsStillSumToTotalAfterVoting() {
        let after = poll().applyingVote(1)
        XCTAssertEqual(after.voteCounts.reduce(0, +), after.totalVotes)
    }

    func testShareReflectsTheOptimisticVote() {
        let after = poll(counts: [0, 0, 0, 0]).applyingVote(0)
        XCTAssertEqual(after.share(at: 0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(after.share(at: 1), 0.0, accuracy: 0.0001)
    }

    // MARK: - applying(touch:)

    func testApplyingTouchLeavesEveryOtherModuleIntact() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/briefing_sample.json")
        let original = try SupabaseCoding.decoder.decode(
            BriefingPayload.self, from: try Data(contentsOf: url)
        )
        let updated = original.applying(touch: poll(myVote: 0))

        XCTAssertEqual(updated.touch?.myVote, 0)
        XCTAssertEqual(updated.featured, original.featured)
        XCTAssertEqual(updated.almanac, original.almanac)
        XCTAssertEqual(updated.spotlight, original.spotlight)
        XCTAssertEqual(updated.caughtUp, original.caughtUp)
        XCTAssertEqual(updated.briefingDate, original.briefingDate)
        XCTAssertNil(original.touch?.myVote, "the original must be untouched")
    }

    // MARK: - Town date

    @MainActor
    func testTownTodayIsFormattedAndAnchoredToTheTown() {
        // 2026-08-06 04:30 UTC is still 2026-08-05 in Central. The briefing is
        // the town's day, not the device's.
        let justAfterUTCMidnight = Date(timeIntervalSince1970: 1_785_990_600)
        let s = BriefingModel.townToday(justAfterUTCMidnight)
        XCTAssertEqual(s.count, 10)
        XCTAssertEqual(s.prefix(2), "20")

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Town.timeZone
        let expected = cal.dateComponents([.year, .month, .day], from: justAfterUTCMidnight)
        XCTAssertEqual(s, String(format: "%04d-%02d-%02d",
                                 expected.year!, expected.month!, expected.day!))
    }
}
