//
//  StartGroupTests.swift
//  BlockPartyTests — Start a group's rules (BP app docs/plans/start-a-group, ticket 02): the name as it's sent and
//  when Create can be tapped, the like names under it, invites first in Groups to join, and a Group read with its
//  status, invite and photo.
//

import XCTest
@testable import BlockParty

@MainActor
final class StartGroupTests: XCTestCase {

    func testNameIsTidiedAndCreateWaitsForThreeToSixtyWithALetter() {
        var draft = StartGroupDraft(name: "  Joetown   Knitters ")
        XCTAssertEqual(draft.cleanName, "Joetown Knitters")
        XCTAssertTrue(draft.ready)
        for name in ["", "ab", "  ab  ", "1234", String(repeating: "x", count: 61)] {
            draft.name = name
            XCTAssertFalse(draft.ready, name)
        }
        draft.name = "abc"
        XCTAssertTrue(draft.ready)
        draft.name = String(repeating: "x", count: 60)
        XCTAssertTrue(draft.ready)
    }

    func testLikeNamesShareAWordMostSharedFirstUpToThreeLiveOnly() {
        func group(_ name: String, _ status: String = "approved") -> TownGroup {
            var g = TownGroup(id: name, name: name)
            g.status = status
            return g
        }
        let town = [group("Spinning and Knitting Bee"), group("St. Joseph Lions Club"), group("Knit Night"),
                    group("Knitting Circle of Friends"), group("Knitters waiting", "pending"), group("Book Discussion Group")]
        XCTAssertEqual(StartGroupDraft.similar(to: "Joetown Knitters", in: town).map(\.name),
                       ["Spinning and Knitting Bee", "Knit Night", "Knitting Circle of Friends"], "knit, in the Town's order")
        XCTAssertEqual(StartGroupDraft.similar(to: "Friends who knit", in: town).first?.name, "Knitting Circle of Friends",
                       "two words shared beat one")
        XCTAssertEqual(StartGroupDraft.similar(to: "St. Joseph Club", in: town), [], "plain words find nothing")
        XCTAssertEqual(StartGroupDraft.similar(to: "Books", in: town).map(\.name), ["Book Discussion Group"])
        XCTAssertEqual(StartGroupDraft.similar(to: "Kn", in: town), [])
    }

    func testAnInviteComesFirstInGroupsToJoinAndSaysWho() {
        var invited = TownGroup(id: "b", name: "Sunday Runners", memberCount: 1)
        invited.invitedBy = "Sam"
        let soon = TownGroup(id: "a", name: "Lions", meetings: [.init(what: "Meeting", day: "2026-11-23", time: "18:00")],
                             memberCount: 12)
        let now = ISO8601DateFormatter().date(from: "2026-11-22T12:00:00Z")!
        let open = FriendsHomePage.groups([soon, invited], member: { _ in false }, now: now).open
        XCTAssertEqual(open.map(\.id), ["b", "a"])
        XCTAssertEqual(GroupJoinRow.line(invited, members: 1, now: now), "Sam invited you")
    }

    func testAGroupReadsItsStatusInviteAndPhoto() throws {
        let json = """
        [{"id": "g", "name": "Joetown Knitters", "status": "pending", "invited_by": "Sam",
          "image_url": "https://x/group-g.jpg", "photos": [{"url": "https://x/group-g.jpg", "kind": "photo"}]},
         {"id": "h", "name": "Lions"}]
        """
        let groups: [TownGroup] = try Supabase.decode(Data(json.utf8))
        XCTAssertEqual(groups[0].status, "pending")
        XCTAssertEqual(groups[0].invitedBy, "Sam")
        XCTAssertEqual(groups[0].imageUrl?.absoluteString, "https://x/group-g.jpg")
        XCTAssertEqual(groups[0].photos.count, 1)
        XCTAssertEqual([groups[1].status, groups[1].invitedBy ?? "none"], ["approved", "none"], "a Group from before reads as live")
    }
}
