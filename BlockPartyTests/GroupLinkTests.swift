//
//  GroupLinkTests.swift
//  BlockPartyTests — a Group's own link (BP app docs/plans/start-a-group, ticket 07): what Share link, Copy link
//  and the Group's code hold, and which Group an opened link names. An opened link is anyone's words, so only a
//  Block Party link with a real id names a Group.
//

import XCTest
@testable import BlockParty

final class GroupLinkTests: XCTestCase {

    private let id = "f2d1fa78-8031-4902-8d91-dd010e789c46"

    func testTheLinkIsTheWebsitesGroupPage() {
        XCTAssertEqual(GroupLink.link(for: id).absoluteString, "https://blockpartymn.com/g/\(id)")
        XCTAssertEqual(GroupLink.link(for: id.uppercased()).absoluteString, "https://blockpartymn.com/g/\(id)")
    }

    func testTheLinkAndTheAppLinkNameTheGroup() {
        XCTAssertEqual(GroupLink.groupID(from: GroupLink.link(for: id)), id)
        XCTAssertEqual(GroupLink.groupID(from: URL(string: "https://www.blockpartymn.com/g/\(id.uppercased())")!), id)
        // The website's Open in Block Party, which works before app links are on (BP app backlog 10).
        XCTAssertEqual(GroupLink.groupID(from: URL(string: "blockparty://group/\(id)")!), id)
    }

    func testAnythingElseNamesNoGroup() {
        for words in [
            "https://blockpartymn.com/g/",
            "https://blockpartymn.com/n/\(id)",
            "https://blockpartymn.com/g/\(id)/more",
            "http://blockpartymn.com/g/\(id)",
            "https://blockpartymn.com.evil.com/g/\(id)",
            "https://evil.com/g/\(id)",
            "blockparty://neighbor/\(id)",
            "blockparty://group/not-an-id",
            "otherapp://group/\(id)",
        ] {
            XCTAssertNil(GroupLink.groupID(from: URL(string: words)!), words)
        }
    }

    // MARK: Opened before the tabs are up

    func testAGroupLinkWaitsForTheTabsAndOpensOnce() {
        var waiting = WaitingCode()
        XCTAssertTrue(waiting.opened(GroupLink.link(for: id), signedOut: false))
        XCTAssertNil(waiting.takeGroup(ready: false), "the launch or the Done island is still up")
        XCTAssertEqual(waiting.takeGroup(ready: true), id)
        XCTAssertNil(waiting.takeGroup(ready: true), "once")
    }

    func testAGroupLinkLeavesAWaitingNeighbourAlone() {
        let neighbor = "6f1c2a9e-3b4d-4e8f-9a1b-2c3d4e5f6a7b"
        var waiting = WaitingCode()
        waiting.opened(URL(string: "blockparty://neighbor/\(neighbor)")!, signedOut: true)
        waiting.opened(GroupLink.link(for: id), signedOut: true)
        XCTAssertEqual(waiting.take(ready: true)?.id, neighbor)
        XCTAssertEqual(waiting.takeGroup(ready: true), id, "taking the neighbour leaves the Group")
    }

    func testAnAccountThatEndsForgetsTheGroup() {
        var waiting = WaitingCode()
        waiting.opened(GroupLink.link(for: id), signedOut: false)
        waiting.forget()
        XCTAssertNil(waiting.takeGroup(ready: true))
    }

    // MARK: Share link

    func testShareLinkSendsTheGroupsOwnLink() {
        var group = TownGroup(id: id, name: "River Runners")
        group.pageUrl = "https://riverrunners.example"
        let payload = SharePayload.group(group)
        XCTAssertTrue(payload.shareText.hasSuffix("https://blockpartymn.com/g/\(id)"), payload.shareText)
        XCTAssertFalse(payload.shareText.contains("riverrunners.example"), "one link, the Group's own")
        XCTAssertEqual(payload.copied, payload.shareText, "Copy link adds no second website")
    }
}
