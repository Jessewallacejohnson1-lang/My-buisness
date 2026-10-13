//
//  NeighborSearchTests.swift
//  BlockPartyTests — finding a neighbour by name (`NeighborSearch`, BP app docs/plans/friends,
//  ticket 02), driven the way the Friends page and Search drive it, against a stand-in server.
//

import XCTest
@testable import BlockParty

@MainActor
final class NeighborSearchTests: XCTestCase {

    /// Answers by name start, records every ask, and fails or takes its time when told to.
    @MainActor
    private final class Server {
        var asked: [String] = []
        var failing = false
        var delays: [String: Duration] = [:]
        let people = ["Sam Rivera", "Samantha Ostendorf", "Ana Samuels"].map {
            Neighbor(userId: $0, displayName: $0, avatarUrl: nil, since: "2026-03-02T10:00:00Z")
        }

        func find(_ words: String) async throws -> [Neighbor] {
            asked.append(words)
            if let delay = delays[words] { try? await Task.sleep(for: delay) }
            if failing { throw URLError(.notConnectedToInternet) }
            return people.filter { $0.displayName.lowercased().split(separator: " ").contains { $0.hasPrefix(words) } }
        }
    }

    private func search(_ server: Server, anonymous: Bool = false) -> NeighborSearch {
        NeighborSearch(find: { try await server.find($0) }, isAnonymous: { anonymous })
    }

    /// Waits past the typing pause and the answer.
    private func settle(_ extra: Duration = .zero) async {
        try? await Task.sleep(for: NeighborSearch.pause + .milliseconds(150) + extra)
    }

    private func names(_ state: NeighborSearch.State) -> [String] {
        if case .found(let people) = state { return people.map(\.displayName) }
        return []
    }

    func testNothingTypedIsTheEmptyPageAndAsksNobody() async {
        let server = Server()
        let s = search(server)
        s.search("   ")
        await settle()
        XCTAssertEqual(s.state, .idle)
        XCTAssertEqual(server.asked, [])
    }

    func testTypedWordsFindNeighbours() async {
        let server = Server()
        let s = search(server)
        s.search(" sam ")
        XCTAssertEqual(s.state, .loading)
        await settle()
        XCTAssertEqual(names(s.state), ["Sam Rivera", "Samantha Ostendorf", "Ana Samuels"])
        XCTAssertEqual(server.asked, ["sam"])
    }

    func testNoMatchSaysNoResults() async {
        let server = Server()
        let s = search(server)
        s.search("zz")
        await settle()
        XCTAssertEqual(s.state, .none)
    }

    func testAnAnonymousAccountIsAskedToLogInAndNeverAsksTheServer() async {
        let server = Server()
        let s = search(server, anonymous: true)
        s.search("")
        XCTAssertEqual(s.state, .needsAccount)
        s.search("sam")
        XCTAssertEqual(s.state, .needsAccount)
        await settle()
        XCTAssertEqual(server.asked, [])
    }

    /// "No results found" stays while the next letter is asked about, then gives way.
    func testNoResultsStaysWhileTheNextWordsAreAsked() async {
        let server = Server()
        let s = search(server)
        s.search("zz")
        await settle()
        s.search("zzz")
        XCTAssertEqual(s.state, .none)
        s.search("ana")
        XCTAssertEqual(s.state, .none)
        await settle()
        XCTAssertEqual(names(s.state), ["Ana Samuels"])
    }

    func testAFailedAskSaysSoAndTheNextWordsAskAgain() async {
        let server = Server()
        server.failing = true
        let s = search(server)
        s.search("sam")
        await settle()
        XCTAssertEqual(s.state, .failed)
        server.failing = false
        s.search("ana")
        await settle()
        XCTAssertEqual(names(s.state), ["Ana Samuels"])
    }

    func testTypingFastAsksOnlyForTheLastWords() async {
        let server = Server()
        let s = search(server)
        s.search("s")
        s.search("sa")
        s.search("sam")
        await settle()
        XCTAssertEqual(server.asked, ["sam"])
    }

    /// A slow answer to older words never lands over the newer words' answer.
    func testAnOldAnswerNeverLandsOverANewOne() async {
        let server = Server()
        server.delays["sam"] = .milliseconds(600)
        let s = search(server)
        s.search("sam")
        await settle()                       // "sam" is now asked, and slow
        s.search("ana")
        await settle(.milliseconds(600))     // both answers are in
        XCTAssertEqual(names(s.state), ["Ana Samuels"])
    }

    /// What was found stays up while the next words are asked about, then gives way.
    func testFoundPeopleStayWhileTheNextWordsAreAsked() async {
        let server = Server()
        let s = search(server)
        s.search("sam")
        await settle()
        s.search("samantha")
        XCTAssertEqual(names(s.state), ["Sam Rivera", "Samantha Ostendorf", "Ana Samuels"])
        await settle()
        XCTAssertEqual(names(s.state), ["Samantha Ostendorf"])
    }

    func testClearingTheWordsGoesBackToTheEmptyPage() async {
        let server = Server()
        let s = search(server)
        s.search("sam")
        await settle()
        s.search("")
        XCTAssertEqual(s.state, .idle)
    }

    func testNeighborSinceReadsAsTheProfileSaysIt() {
        let sam = Neighbor(userId: "1", displayName: "Sam", avatarUrl: nil, since: "2026-03-02T10:00:00+00:00")
        XCTAssertEqual(sam.sinceLine, "Neighbor since March 2026")
        XCTAssertNil(Neighbor(userId: "2", displayName: "Ana", avatarUrl: nil, since: nil).sinceLine)
    }

    /// `search_neighbors`' rows as the server sends them.
    func testDecodesTheServersRows() throws {
        let json = #"[{"user_id":"7c1","display_name":"Sam Rivera","avatar_url":null,"since":"2026-10-13T15:30:00.123456+00:00"}]"#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let rows = try decoder.decode([Neighbor].self, from: Data(json.utf8))
        XCTAssertEqual(rows.first?.displayName, "Sam Rivera")
        XCTAssertEqual(rows.first?.sinceLine, "Neighbor since October 2026")
    }
}
