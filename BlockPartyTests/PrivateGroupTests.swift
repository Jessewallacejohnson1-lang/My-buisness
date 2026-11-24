//
//  PrivateGroupTests.swift
//  BlockPartyTests — private Groups (BP app docs/plans/start-a-group, ticket 03): who meets the locked page, its
//  lock line, Groups to join's line, the read of the new columns, and Ask flipping at once and turning back.
//

import XCTest
@testable import BlockParty

@MainActor
final class PrivateGroupTests: XCTestCase {

    private func group(private isPrivate: Bool = true, invitedBy: String? = nil, requests: Int? = nil) -> TownGroup {
        var g = TownGroup(id: "g", name: "Thursday Bible Study", memberCount: 12)
        g.isPrivate = isPrivate
        g.invitedBy = invitedBy
        g.requests = requests
        return g
    }

    func testOnlyAStrangerMeetsTheLockedPage() {
        XCTAssertTrue(GroupAsks.locked(group(), member: false))
        XCTAssertFalse(GroupAsks.locked(group(), member: true), "a member sees it all")
        XCTAssertFalse(GroupAsks.locked(group(invitedBy: "Sam"), member: false), "invited: Join, no asking")
        XCTAssertFalse(GroupAsks.locked(group(requests: 0), member: false), "its Admin")
        XCTAssertFalse(GroupAsks.locked(group(private: false), member: false), "a public Group")
    }

    /// A Group you can't walk back into asks before you leave (start-a-group 09), and says what coming back takes.
    func testLeavingAsksOnlyWhereYouCantWalkBackIn() {
        XCTAssertNil(GroupAsks.leaveWarning(group(private: false)), "a public Group leaves at once")
        XCTAssertFalse(GroupAsks.asksToLeave(group(private: false)))
        XCTAssertEqual(GroupAsks.leaveWarning(group()), "To come back, you'll have to ask to join again.")
        var waiting = group(private: false)
        waiting.status = "pending"
        XCTAssertEqual(GroupAsks.leaveWarning(waiting), "To come back, you'll need a new invite.")
        waiting.isPrivate = true
        XCTAssertEqual(GroupAsks.leaveWarning(waiting), "To come back, you'll need a new invite.", "waiting comes first: no one can ask yet")
        XCTAssertTrue(GroupAsks.asksToLeave(group(private: false, requests: 0)), "its Admin hands over or closes first")
        var turnedDown = group(private: false, requests: 0)
        turnedDown.status = "rejected"
        XCTAssertFalse(GroupAsks.asksToLeave(turnedDown), "a turned-down Group has no Admin")
    }

    func testTheLockLineAndTheRowSayPrivate() {
        XCTAssertEqual(GroupPage.privateLine(12), "Private group · 12 members")
        XCTAssertEqual(GroupPage.privateLine(0), "Private group")
        XCTAssertEqual(GroupJoinRow.line(group(), members: 12, now: Date()), "Private · 12 members")
        XCTAssertEqual(GroupJoinRow.line(group(private: false), members: 12, now: Date()), "12 members")
    }

    func testAGroupReadsPrivateAskedAndRequests() throws {
        let json = """
        [{"id": "a", "name": "A", "private": true, "asked": true},
         {"id": "b", "name": "B", "private": true, "requests": 2},
         {"id": "c", "name": "C"}]
        """
        let groups: [TownGroup] = try Supabase.decode(Data(json.utf8))
        XCTAssertEqual(groups.map(\.isPrivate), [true, true, false])
        XCTAssertEqual(groups.map(\.asked), [true, false, false])
        XCTAssertEqual(groups.map(\.requests), [nil, 2, nil])
    }

    func testAskFlipsAtOnceAndTurnsBackWhenRefused() async {
        let asks = GroupAsks()
        var sent: [Bool] = []
        asks.send = { _, on in sent.append(on) }
        await asks.toggle(group())
        XCTAssertTrue(asks.isAsked(group()))
        await asks.toggle(group())
        XCTAssertFalse(asks.isAsked(group()), "a second tap takes it back")
        XCTAssertEqual(sent, [true, false])

        asks.send = { _, _ in throw URLError(.notConnectedToInternet) }
        await asks.toggle(group())
        XCTAssertFalse(asks.isAsked(group()), "refused: back as it was")
        XCTAssertEqual(asks.failures["g"], 1, "and it shakes")

        var asked = group()
        asked.asked = true
        asks.read([asked])
        XCTAssertTrue(asks.isAsked(group()), "a read sets it")

        // Leaving reads the Groups again (start-a-group 09): one begun before a tap doesn't undo it.
        asks.send = { _, _ in }
        asks.read([group()])
        let began = asks.taps
        await asks.toggle(group())
        asks.read([group()], asOf: began)
        XCTAssertTrue(asks.isAsked(group()), "a read from before the tap says nothing of it")
        asks.read([group()], asOf: asks.taps)
        XCTAssertFalse(asks.isAsked(group()), "a newer one does")
    }
}
