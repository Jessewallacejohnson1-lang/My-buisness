//
//  EditGroupTests.swift
//  BlockPartyTests — Edit group (BP app docs/plans/start-a-group, ticket 04): the draft's Save (only for a change, and
//  a name the server takes), what goes to the check, the Who can add events picker, and the read of `events_by`.
//

import XCTest
@testable import BlockParty

final class EditGroupTests: XCTestCase {

    private func group() -> TownGroup {
        var g = TownGroup(id: "g", name: "Joetown Sewing Circle", kind: "Crafts", memberCount: 3)
        g.about = "We sew on Tuesdays."
        return g
    }

    func testSaveOnlyForAChangeTheServerTakes() {
        let start = EditGroupDraft(group(), editors: [])
        var draft = start
        XCTAssertFalse(draft.canSave(from: start), "nothing changed")
        draft.isPrivate = true
        XCTAssertTrue(draft.canSave(from: start))
        draft.isPrivate = false
        draft.name = "  Joetown   Sewing Circle "
        XCTAssertFalse(draft.canSave(from: start), "the same name, spaces aside")
        draft.name = "ab"
        XCTAssertFalse(draft.canSave(from: start), "start_group's name rule: 3 to 60 with a letter")
        draft.name = "Joetown Quilters"
        XCTAssertTrue(draft.canSave(from: start))
    }

    func testOnlyNameKindAboutAndPhotoGoToTheCheck() {
        let start = EditGroupDraft(group(), editors: [])
        var draft = start
        draft.isPrivate = true
        draft.eventsBy = .members
        XCTAssertFalse(draft.needsCheck(from: start), "Private and Who can add events land at once")
        draft.about = "We sew and quilt."
        XCTAssertTrue(draft.needsCheck(from: start))
        draft = start
        draft.kind = "Games"
        XCTAssertTrue(draft.needsCheck(from: start))
        draft = start
        draft.newPhoto = true
        XCTAssertTrue(draft.needsCheck(from: start))
        XCTAssertTrue(draft.canSave(from: start))
    }

    func testWhoCanAddEventsPicker() {
        XCTAssertEqual(EditGroupDraft.EventsBy.allCases.map(\.title), ["Only me", "Members I pick", "All members"])
        XCTAssertEqual(EditGroupDraft(group(), editors: []).eventsBy, .admin, "Only me unless the Group says")
        let start = EditGroupDraft(group(), editors: ["a"])
        var draft = start
        draft.editors.insert("b")
        XCTAssertTrue(draft.canSave(from: start), "a member picked")
        XCTAssertFalse(draft.needsCheck(from: start))
        XCTAssertEqual(EditGroupDraft.pickedLine(["Junie Ross", "Dale Ek"]), "Junie, Dale")
        XCTAssertEqual(EditGroupDraft.pickedLine(["Junie Ross", "Dale Ek", "Al Bo", "Cy Do"]), "Junie, Dale and 2 more")
        XCTAssertNil(EditGroupDraft.pickedLine([]))
    }

    func testAGroupReadsWhoAddsEvents() throws {
        let json = """
        [{"id": "a", "name": "A", "events_by": "picked"}, {"id": "b", "name": "B"}, {"id": "c", "name": "C", "events_by": "x"}]
        """
        let groups: [TownGroup] = try Supabase.decode(Data(json.utf8))
        XCTAssertEqual(groups.map { EditGroupDraft($0, editors: []).eventsBy }, [.picked, .admin, .admin])
    }

    func testTheAdminRunsIt() {
        var g = group()
        XCTAssertFalse(g.isAdmin, "requests come only to the Admin")
        g.requests = 0
        XCTAssertTrue(g.isAdmin)
        g.status = "rejected"
        XCTAssertFalse(g.isAdmin, "a turned-down Group has nothing to edit")
    }
}
