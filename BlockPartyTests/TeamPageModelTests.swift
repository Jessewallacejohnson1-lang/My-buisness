//
//  TeamPageModelTests.swift
//  BlockPartyTests — a school's page (`TeamPageModel`, BP app school-search 05 and its review), driven as the page
//  drives it against an in-memory server: one message when the page can't be read, the events beside the page on a
//  refresh, and a shared event's icon from the activities' own order whichever read lands first.
//

import XCTest
@testable import BlockParty

@MainActor
final class TeamPageModelTests: XCTestCase {

    /// Answers `team_page` and each activity's `activity_events` from memory, after each one's own wait, and keeps
    /// the functions asked in order.
    @MainActor
    private final class Server {
        var page: String? = TeamPageModelTests.kennedy
        var events: [String: String] = [:]
        var waits: [String: Duration] = [:]
        var asked: [String] = []
        /// In the order they answered.
        var answered: [String] = []

        var send: Supabase.Send {
            Supabase.Send { @MainActor [self] request in
                let function = request.url!.lastPathComponent
                let args = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                let activity = args?["p_activity"] as? String
                asked.append(activity.map { "\(function) \($0)" } ?? function)
                if let wait = waits[activity ?? function] { try await Task.sleep(for: wait) }
                answered.append(function)
                let body = function == "team_page" ? page : activity.flatMap { events[$0] }
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
       {"id": "chess", "name": "Chess Club", "note": null, "kind": "club", "following": false, "next": null}]}
    """

    private func model(_ server: Server) -> TeamPageModel {
        TeamPageModel(team: Game.Team(school: LocalSchool(id: "kennedy", uuid: "u-kennedy", name: "Kennedy",
                                                         schoolName: "Kennedy Community School", logoUrl: nil)),
                      supabase: Supabase(auth: FakeTokenProvider(), send: server.send))
    }

    private let actions = RealLifeActions(signedIn: true, needsAccount: true, hold: .zero, flip: .zero,
                                          setGoing: { _, _ in }, setHeart: { _, _ in })

    /// The page's read failing (signed out, `team_page` runs past the 3 s limit) says so once: the events card has
    /// nothing to read and stays quiet, rather than saying it again.
    func testAFailedPageSaysSoOnce() async {
        let server = Server()
        server.page = nil
        let model = model(server)
        await model.load(actions)
        XCTAssertTrue(model.failed)
        XCTAssertFalse(model.eventsFailed, "one message, not two")
        XCTAssertNil(model.events)
        XCTAssertEqual(server.asked, ["team_page"], "no events read without the activities")
    }

    /// The page read, each activity with a coming event is read for its events, and they show as one list with each
    /// activity's icon and no level tag on a title. An activity with no next event isn't asked.
    func testThePageReadsEachActivitysEvents() async throws {
        let server = Server()
        server.events = ["bball": #"[{"id": "g1", "title": "Girls Basketball vs Stride Academy · MS", "date": "2026-11-12", "time": "4 PM", "location": "Stride Academy"}]"#,
                         "kbowl": #"[{"id": "m1", "title": "Eden Valley Knowledge Bowl Meet", "date": "2026-11-16", "time": "4 PM", "location": null}]"#]
        let model = model(server)
        await model.load(actions)
        XCTAssertFalse(model.failed)
        XCTAssertEqual(model.profile?.activities.count, 3)
        let events = try XCTUnwrap(model.events)
        XCTAssertEqual(events.map(\.title), ["Girls Basketball vs Stride Academy", "Eden Valley Knowledge Bowl Meet"])
        XCTAssertEqual(events.map(\.symbol), ["basketball", "brain.head.profile"])
        XCTAssertEqual(Set(server.asked), ["team_page", "activity_events bball", "activity_events kbowl"])
    }

    /// An event two activities share takes the icon of the one listed first, whichever read lands first.
    func testASharedEventTakesTheFirstActivitysIcon() async throws {
        let server = Server()
        let shared = #"[{"id": "s1", "title": "Activities Night", "date": "2026-11-12", "time": "6 PM", "location": null}]"#
        server.events = ["bball": shared, "kbowl": shared]
        server.waits = ["bball": .milliseconds(150)]
        let model = model(server)
        await model.load(actions)
        XCTAssertEqual(try XCTUnwrap(model.events).map(\.symbol), ["basketball"], "Basketball is listed first")
    }

    /// A pull to refresh reads the events of the activities already on screen beside the page, so a slow or failed
    /// page read holds them up no longer, and the page on screen stays.
    func testARefreshReadsTheEventsBesideThePage() async throws {
        let server = Server()
        server.events = ["bball": #"[{"id": "g1", "title": "Game", "date": "2026-11-12", "time": "4 PM", "location": null}]"#,
                         "kbowl": "[]"]
        let model = model(server)
        await model.load(actions)
        server.page = nil
        server.waits = ["team_page": .milliseconds(150)]
        server.events["bball"] = #"[{"id": "g2", "title": "Game moved", "date": "2026-11-13", "time": "4 PM", "location": null}]"#
        server.answered = []
        await model.load(actions)
        XCTAssertEqual(try XCTUnwrap(model.events).map(\.title), ["Game moved"])
        XCTAssertNotNil(model.profile, "the page on screen stays")
        XCTAssertFalse(model.failed)
        XCTAssertEqual(server.answered.first, "activity_events", "the events didn't wait for the page")
    }

    /// Every events read failing says so on the card, once, under a page that did load.
    func testFailedEventsSaySoOnTheCard() async {
        let server = Server()
        let model = model(server)
        await model.load(actions)
        XCTAssertFalse(model.failed)
        XCTAssertTrue(model.eventsFailed)
        XCTAssertNil(model.events)
    }
}
