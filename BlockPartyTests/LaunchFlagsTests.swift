//
//  LaunchFlagsTests.swift
//  Block Party — the DEBUG launch flags have one reader, and docs/debug-flags.md lists
//  exactly the flags it knows (codebase-health 21).
//

import XCTest
@testable import BlockParty

final class LaunchFlagsTests: XCTestCase {

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()      // BlockPartyTests
        .deletingLastPathComponent()      // repo root

    /// Sample mode's writes go nowhere, so a Join on a sample card never reaches the live
    /// database; offline's always fail, and offline wins when both are passed, on every screen.
    func testOfflineBeatsSamples() {
        XCTAssertEqual(LaunchFlags.backend(for: ["-open-tab", "town", "-town-samples"]), .samples)
        XCTAssertEqual(LaunchFlags.backend(for: ["-town-offline"]), .offline)
        XCTAssertEqual(LaunchFlags.backend(for: ["-town-samples", "-town-offline"]), .offline)
        XCTAssertEqual(LaunchFlags.backend(for: ["-town-offline", "-town-samples"]), .offline)
        XCTAssertEqual(LaunchFlags.backend(for: []), .live)
    }

    /// A flag's value is the argument after it, once per time it's passed; a flag last in
    /// the list has none.
    func testValuesAreTheArgumentAfterTheFlag() {
        let arguments = ["BlockParty", "-map-zoom", "14", "-open-tab", "you", "-map-zoom", "16", "-tilt"]
        XCTAssertEqual(LaunchFlags.values(.mapZoom, in: arguments), ["14", "16"])
        XCTAssertEqual(LaunchFlags.values(.openTab, in: arguments), ["you"])
        XCTAssertEqual(LaunchFlags.values(.tilt, in: arguments), [])
        XCTAssertEqual(LaunchFlags.values(.dailyHour, in: arguments), [])
    }

    /// Every flag the app reads is in docs/debug-flags.md, and every flag documented there
    /// (above its "Dead flags" list) is one the app reads. Dotted names such as
    /// `-onboarding.step` are UserDefaults keys, not flags.
    func testEveryFlagIsDocumentedAndEveryDocumentedFlagIsRead() throws {
        let doc = try String(contentsOf: Self.root.appendingPathComponent("docs/debug-flags.md"), encoding: .utf8)
        let live = doc.components(separatedBy: "## Dead flags").first ?? doc
        let spans = live.matches(of: /`([^`]+)`/).map { String($0.1) }
        let documented = Set(spans.flatMap { span in
            span.matches(of: /(?:^|[^\w-])(-[a-z][a-z0-9.\-]*[a-z0-9])/).map { String($0.1) }
        }.filter { !$0.contains(".") })
        let read = Set(LaunchFlags.Flag.allCases.map(\.rawValue))

        XCTAssertEqual(read.subtracting(documented).sorted(), [], "read by the app but not in docs/debug-flags.md")
        XCTAssertEqual(documented.subtracting(read).sorted(), [],
                       "in docs/debug-flags.md but read by nothing: move it to the Dead flags list")
    }

    /// No screen reads the launch arguments itself: it asks `LaunchFlags`, so every screen
    /// resolves samples and offline the same way and Release reads none.
    func testOnlyLaunchFlagsReadsTheArguments() throws {
        let sources = Self.root.appendingPathComponent("BlockParty")
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in walker where url.pathExtension == "swift" && url.lastPathComponent != "LaunchFlags.swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for (index, line) in text.components(separatedBy: .newlines).enumerated()
            where line.contains(".arguments") {
                offenders.append("\(url.lastPathComponent):\(index + 1)")
            }
        }
        XCTAssertEqual(offenders, [], "read flags with LaunchFlags.has, .value or .backend")
    }
}
