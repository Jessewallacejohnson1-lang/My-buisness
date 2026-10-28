//
//  TownPageModelTests.swift
//  BlockPartyTests — the Town's two pages (`TownPageModel`, BP app docs/plans/follows ticket 04),
//  driven as the page drives them against an in-memory server: the switch, the City's boards with
//  their next meeting, and Follow on a page and on a board.
//

import XCTest
@testable import BlockParty

@MainActor
final class TownPageModelTests: XCTestCase {

    /// Answers `town_page` from memory, counting each read, and records every follow written.
    @MainActor
    private final class Server {
        var reads: [TownPageKind] = []
        var follows: [String] = []
        var failing = false
        var pages: [TownPageKind: TownPageInfo] = [
            .town: TownPageInfo(id: "town-1", name: "Town", kind: "Town events", picture: nil, pictureKind: "town",
                                events: [.init(id: "e1", title: "Winterwalk", date: "2026-12-04", time: "17:00", location: nil)],
                                boards: []),
            .city: TownPageInfo(id: "city-1", name: "City", kind: "City government", picture: nil, pictureKind: nil,
                                events: [],
                                boards: [.init(id: "b1", name: "City Council", following: false,
                                               next: .init(date: "2026-10-27", time: "18:00")),
                                         .init(id: "b2", name: "Park Board", following: true, next: nil)]),
        ]

        func read(_ kind: TownPageKind) async throws -> TownPageInfo? {
            reads.append(kind)
            if failing { throw URLError(.notConnectedToInternet) }
            return pages[kind]
        }

        func follow(_ target: FollowTarget, _ on: Bool) async throws {
            follows.append("\(target.type.rawValue) \(target.id) \(on)")
        }
    }

    private func actions(_ server: Server) -> RealLifeActions {
        RealLifeActions(signedIn: true, needsAccount: true, hold: .milliseconds(50), flip: .milliseconds(20),
                        retry: .milliseconds(10), setGoing: { _, _ in }, setHeart: { _, _ in }, setSave: { _, _ in },
                        setFollow: server.follow, knownEvents: { _ in [] })
    }

    /// The switch: each page is read when it's shown, and kept, so flipping back shows it at once.
    func testTheSwitchShowsEachPageAndKeepsTheOneLeft() async {
        let server = Server()
        let actions = actions(server)
        let model = TownPageModel(shown: .town, read: server.read)
        XCTAssertNil(model.page, "nothing before the read")

        await model.load(actions)
        XCTAssertEqual(model.page?.name, "Town")
        XCTAssertEqual(model.page?.events.map(\.title), ["Winterwalk"])

        model.shown = .city
        XCTAssertNil(model.page, "the City waits for its own read")
        await model.load(actions)
        XCTAssertEqual(model.page?.name, "City")

        model.shown = .town
        XCTAssertEqual(model.page?.name, "Town", "the Town's page is back at once")
        XCTAssertEqual(server.reads, [.town, .city])
    }

    /// A failed read with nothing kept says so; one with a page kept keeps showing it.
    func testAFailedReadKeepsWhatWasShown() async {
        let server = Server()
        let actions = actions(server)
        let model = TownPageModel(shown: .city, read: server.read)
        server.failing = true
        await model.load(actions)
        XCTAssertTrue(model.failed.contains(.city))

        server.failing = false
        await model.load(actions)
        XCTAssertFalse(model.failed.contains(.city))
        server.failing = true
        await model.load(actions)
        XCTAssertEqual(model.page?.name, "City", "a later failure keeps the page")
        XCTAssertFalse(model.failed.contains(.city))
    }

    /// The City lists its boards, each with its next meeting; the Town's own page has none.
    func testTheCityListsItsBoardsWithTheirNextMeeting() async {
        let server = Server()
        let actions = actions(server)
        let model = TownPageModel(shown: .city, read: server.read)
        await model.load(actions)
        XCTAssertEqual(model.boards.map(\.name), ["City Council", "Park Board"])
        XCTAssertEqual(model.boards.map { TownPageModel.nextMeeting($0.next) }, ["Next meeting Tue, Oct 27 · 6 PM", nil])

        model.shown = .town
        await model.load(actions)
        XCTAssertEqual(model.boards, [])
    }

    /// Follow on a page writes the page; a board's row reads as the page says, and its Follow
    /// writes that board alone.
    func testFollowOnAPageAndOnABoard() async throws {
        let server = Server()
        let actions = actions(server)
        let model = TownPageModel(shown: .city, read: server.read)
        await model.load(actions)
        let page = try XCTUnwrap(model.page)
        let council = model.boards[0].target, parks = model.boards[1].target
        XCTAssertFalse(actions.follow(council).isFollowing)
        XCTAssertTrue(actions.follow(parks).isFollowing, "the page's own word, before any tap")

        actions.toggleFollow(page.target)
        XCTAssertTrue(actions.follow(page.target).isFollowing, "Following at once")
        actions.toggleFollow(council)
        actions.toggleFollow(parks)
        XCTAssertTrue(actions.follow(council).isFollowing)
        XCTAssertFalse(actions.follow(parks).isFollowing, "one tap undoes it")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(Set(server.follows), ["page city-1 true", "board b1 true", "board b2 false"])
    }

    /// A campus calendar's page (follows 08) opens by its id from its host or Following row and reads
    /// like any other; the Town's own two still open by name, behind their switch.
    func testAHostRowOpensItsPage() async {
        let row = { (name: String) in
            FollowRow(targetType: .page, targetId: "id-\(name)", name: name, kind: nil, picture: nil, pictureKind: nil)
        }
        XCTAssertEqual(TownPageKind.of(row(Town.cityPage)), .city)
        XCTAssertEqual(TownPageKind.of(row(Town.townPage)), .town)
        let libraries = TownPageKind.of(row("CSB SJU Libraries"))
        XCTAssertEqual(libraries, .page(id: "id-CSB SJU Libraries", name: "CSB SJU Libraries"))
        XCTAssertEqual(libraries.name, "CSB SJU Libraries", "its name before the read")
        XCTAssertNil(libraries.photo, "its photo comes with its read")
        XCTAssertFalse(TownPageKind.switchable.contains(libraries), "no switch on it")
        XCTAssertEqual(TownPageKind(slug: "city"), .city)
        XCTAssertNil(TownPageKind(slug: "csbsju-libraries"))

        let server = Server()
        server.pages[libraries] = TownPageModel.sample(libraries)
        let model = TownPageModel(shown: libraries, read: server.read)
        await model.load(actions(server))
        XCTAssertEqual(model.page?.pictureCredit, "csbsju.edu")
        XCTAssertEqual(server.reads, [libraries])
    }

    /// `town_page`'s row as PostgREST sends it, its photo's credit included; a read from before the
    /// credit still decodes.
    func testAPageReadsItsPhotosCredit() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let json = #"{"id":"p1","name":"CSB SJU Libraries","kind":"College","picture":"https://x/p.webp","#
            + #""picture_kind":"photo","picture_credit":"csbsju.edu","events":[],"boards":[]}"#
        XCTAssertEqual(try decoder.decode(TownPageInfo.self, from: Data(json.utf8)).pictureCredit, "csbsju.edu")
        let before = json.replacingOccurrences(of: #""picture_credit":"csbsju.edu","#, with: "")
        XCTAssertNil(try decoder.decode(TownPageInfo.self, from: Data(before.utf8)).pictureCredit)
    }

    func testBoardInitials() {
        XCTAssertEqual(TownPageModel.initials("City Council"), "CC")
        XCTAssertEqual(TownPageModel.initials("Economic Development Authority"), "EDA")
        XCTAssertEqual(TownPageModel.initials("Board of Appeal and Equalization"), "BAE")
    }
}
