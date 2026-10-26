//
//  TownNamesGuardTests.swift
//  Block Party — the gate that keeps the town's name in one place (`Town`), so shared screens
//  and words carry over to the next town (MEMORY.md; codebase-health 14 in the BP app folder).
//
//  A source scan, like TypographyScalingGuardTests: it fails on "St. Joseph", "Saint Joseph",
//  "St. Joe", "St Joseph" or "JoeTown" written in a string anywhere in the app's live code.
//  Comments and DEBUG samples may name the town; so may the files that are St. Joseph's own
//  place data, until those become `places` rows (the map's Not yet specified).
//

import XCTest

final class TownNamesGuardTests: XCTestCase {

    /// The files allowed to name the town, and why.
    private static let allowlist: Set<String> = [
        "Models/Town.swift",              // where the names live
        "Backend/CityParks.swift",        // St. Joseph's parks, addresses and all
        "Backend/KnownVenues.swift",      // its buildings' coordinates
        "Features/Components/KnownLocalPhoto.swift",  // bundled photos by real place name
        "Models/Place.swift",             // its curated places, with addresses
    ]

    private static var townName: Regex<Substring> { #/"[^"]*(\bS(ain)?t\.? ?Jo(seph|e)\b|[Jj]oe[Tt]own)/# }

    func testTheTownIsNamedOnlyThroughTown() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // BlockPartyTests
            .deletingLastPathComponent()      // repo root
            .appendingPathComponent("BlockParty")
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil),
                                   "Could not read \(sources.path)")
        var offenders: [String] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let relative = url.path.replacingOccurrences(of: sources.path + "/", with: "")
            if Self.allowlist.contains(relative) { continue }
            var debugDepth = 0
            for (index, line) in try String(contentsOf: url, encoding: .utf8).components(separatedBy: .newlines).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                if code.hasPrefix("#if DEBUG") || (debugDepth > 0 && code.hasPrefix("#if")) { debugDepth += 1; continue }
                if debugDepth > 0 && code.hasPrefix("#endif") { debugDepth -= 1; continue }
                if debugDepth > 0 || code.hasPrefix("//") { continue }
                if code.contains(Self.townName) { offenders.append("\(relative):\(index + 1): \(code)") }
            }
        }
        XCTAssertEqual(offenders, [], "Name the town through Town (Town.name, .everyday, .nickname, .display)")
    }

    /// The scan itself: it catches the ways the town gets written, and lets Saint John's be.
    func testThePatternCatchesTheTownAndNotItsNeighbours() {
        for line in [#"Text("St. Joseph, MN")"#, #""Saint Joseph""#, #""Quiet in St. Joe today.""#,
                     #""\(name) St Joseph MN""#, #""JoeTown""#] {
            XCTAssertTrue(line.contains(Self.townName), line)
        }
        for line in [#""Saint John's Abbey""#, #""St. John's""#, #"Text(Town.everyday)"#] {
            XCTAssertFalse(line.contains(Self.townName), line)
        }
    }
}
