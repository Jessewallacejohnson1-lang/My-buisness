//
//  TeamPageModelTests.swift
//  BlockPartyTests — a school's page (`TeamPageModel`, BP app school-search 05 and 06), driven as the page drives it
//  against an in-memory server: one message when the page can't be read, its events in the same read, and a failed
//  refresh keeping what was shown.
//

import XCTest
@testable import BlockParty

@MainActor
final class TeamPageModelTests: XCTestCase {

    /// Answers `team_page` from memory and keeps the functions asked in order.
    @MainActor
    private final class Server {
        var page: String? = TeamPageModelTests.kennedy
        var asked: [String] = []

        var send: Supabase.Send {
            Supabase.Send { @MainActor [self] request in
                let function = request.url!.lastPathComponent
                asked.append(function)
                let body = function == "team_page" ? page : nil
                let response = HTTPURLResponse(url: request.url!, statusCode: body == nil ? 500 : 200, httpVersion: nil,
                                               headerFields: nil)!
                return (Data((body ?? "{}").utf8), response)
            }
        }
    }

    /// Kennedy with two activities that have events, and one that has none.
    nonisolated static let kennedy = """
    {"id": "u-kennedy", "name": "Kennedy Community School", "short": "Kennedy", "logo": null, "colors": ["#1B2859"],
     "games": [],
     "activities": [
       {"id": "bball", "name": "Girls Basketball 6-8", "note": null, "kind": "sport", "following": false,
        "next": {"title": "Girls Basketball vs Stride Academy · MS", "date": "2026-11-12", "time": "4 PM"}},
       {"id": "kbowl", "name": "Knowledge Bowl 6-8", "note": null, "kind": "club", "following": false,
        "next": {"title": "Banquet", "date": "2026-11-16", "time": "4:15 PM"}},
       {"id": "chess", "name": "Chess Club", "note": null, "kind": "club", "following": false, "next": null}],
     "events": [
       {"id": "g1", "title": "Girls Basketball vs Stride Academy · MS", "date": "2026-11-12", "time": "4 PM",
        "location": "Stride Academy", "activity": "bball"},
       {"id": "m1", "title": "Eden Valley Knowledge Bowl Meet", "date": "2026-11-16", "time": "4 PM", "location": null,
        "activity": "kbowl"},
       {"id": "n1", "title": "Activities Night", "date": "2026-11-17", "time": "6 PM", "location": null,
        "activity": "gone"}]}
    """

    private func model(_ server: Server) -> TeamPageModel {
        TeamPageModel(team: Game.Team(school: LocalSchool(id: "kennedy", uuid: "u-kennedy", name: "Kennedy",
                                                         schoolName: "Kennedy Community School", logoUrl: nil)),
                      supabase: Supabase(auth: FakeTokenProvider(), send: server.send))
    }

    private let actions = RealLifeActions(signedIn: true, needsAccount: true, hold: .zero, flip: .zero,
                                          setGoing: { _, _ in }, setHeart: { _, _ in })

    /// The page's read failing says so once: the events card has nothing to read and stays quiet.
    func testAFailedPageSaysSoOnce() async {
        let server = Server()
        server.page = nil
        let model = model(server)
        await model.load(actions)
        XCTAssertTrue(model.failed)
        XCTAssertNil(model.events)
        XCTAssertEqual(server.asked, ["team_page"])
    }

    /// The page brings its events (school-search 06): one read, each event with its activity's icon and no
    /// middle-school tag, yesterday's kept for the card's Yesterday.
    func testThePageBringsItsEvents() async throws {
        let model = model(Server())
        await model.load(actions)
        XCTAssertFalse(model.failed)
        XCTAssertEqual(model.profile?.activities.count, 3)
        let events = try XCTUnwrap(model.events)
        XCTAssertEqual(events.map(\.title), ["Girls Basketball vs Stride Academy", "Eden Valley Knowledge Bowl Meet",
                                             "Activities Night"])
        XCTAssertEqual(events.map(\.symbol), ["basketball", "brain.head.profile", "calendar"],
                       "an activity the page doesn't list: the plain calendar")
    }

    /// A page from a server before school-search 06 has no events key: no events, rather than no page.
    func testAnOlderPageHasNoEvents() async throws {
        let server = Server()
        server.page = #"{"id": "u-kennedy", "name": "Kennedy Community School", "short": "Kennedy", "logo": null, "games": [], "activities": []}"#
        let model = model(server)
        await model.load(actions)
        XCTAssertNotNil(model.profile)
        XCTAssertEqual(model.events, [])
    }

    /// A refresh that fails keeps the page and its events on screen.
    func testAFailedRefreshKeepsThePage() async throws {
        let server = Server()
        let model = model(server)
        await model.load(actions)
        server.page = nil
        await model.load(actions)
        XCTAssertNotNil(model.profile)
        XCTAssertEqual(model.events?.count, 3)
        XCTAssertFalse(model.failed)
        XCTAssertEqual(server.asked, ["team_page", "team_page"], "one read a load")
    }
}
