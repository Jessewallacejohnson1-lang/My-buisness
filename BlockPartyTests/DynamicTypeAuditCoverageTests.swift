//
//  DynamicTypeAuditCoverageTests.swift
//  Block Party — an audit only covers what it opens.
//
//  `DynamicTypeAuditTests` (UI target) launches the app at accessibility text sizes
//  and lets iOS report what clips, truncates, or overlaps. It is only as good as
//  the list of screens it opens, and that list does not grow by itself. A screen
//  added next month that nobody adds to the walk is not "passing" — it is unseen,
//  which reads exactly the same in a green build and is the way this whole effort
//  quietly dies.
//
//  So every presented screen in the app is accounted for HERE, in one of two ways:
//  it is audited, or it is on the record as not yet audited with a reason. A new
//  `.sheet` or `.fullScreenCover` that is in neither fails this test. That is the
//  point — the failure is a prompt to make a decision, not busywork.
//
//  This runs in the unit target because it reads source, needs no simulator, and
//  finishes in milliseconds. It is a ledger, not a renderer.
//

import XCTest

final class DynamicTypeAuditCoverageTests: XCTestCase {

    /// Where a presented screen stands with the accessibility audit.
    enum Coverage {
        /// Opened by `DynamicTypeAuditTests`, under this surface id.
        case audited(surface: String)
        /// Not opened yet, and why. Shrinking this list is the work; nothing here
        /// is a permanent exemption, and an entry with a vague reason is a bug in
        /// the entry.
        case notYetAudited(reason: String)
    }

    /// Every `.sheet` / `.fullScreenCover` in the app, keyed `File.swift:$binding`
    /// — stable when lines move, and loud when a binding is renamed.
    static let ledger: [String: Coverage] = [
        "RootView.swift:$showProfileSheet": .audited(surface: "you-profile"),

        // The town menu is audited through `-open-menu`; it is not a sheet, so it
        // has no key here — it is listed to explain why the walk has more surfaces
        // than this ledger has entries.

        "RootView.swift:$showMap": .notYetAudited(reason: "The full-screen map. Needs a launch flag; its own text is mostly frozen map-marker chrome, so the payoff is the search and filter row, not the map."),
        "RootView.swift:$composing": .notYetAudited(reason: "Compose speed dial. Needs a launch flag."),
        "RootView.swift:$composeKind": .notYetAudited(reason: "Add form. A form at AX5 is exactly where truncation hurts — high priority once a launch flag exists."),
        "AddView.swift:$selected": .notYetAudited(reason: "Add-kind picker, reached from compose."),
        "FeedView.swift:$route": .notYetAudited(reason: "Feed detail routes. Needs a fixture-driven launch flag."),
        "FeedEventCard.swift:$commentsPresented": .notYetAudited(reason: "Event comments. User-generated text of any length — high priority."),
        "PostingCard.swift:$commentsPresented": .notYetAudited(reason: "Post comments. Same as above."),
        "DayScheduleSheet.swift:$detailEvent": .notYetAudited(reason: "Day event detail. Reached from the Your Day sheet."),
        "DayScheduleSheet.swift:$isComposing": .notYetAudited(reason: "Compose from the day sheet."),
        "PinDetailSheet.swift:$showingFullDetails": .notYetAudited(reason: "Full place details, behind the map."),
        "SJMapView.swift:$showingHelp": .notYetAudited(reason: "Map help. Long explanatory copy — likely to truncate."),
        "ProfileView.swift:$editing": .notYetAudited(reason: "Edit profile. A form; same priority as the add form."),
        "ProfileView.swift:$showAbout": .notYetAudited(reason: "About. Long copy."),
        "ProfileView.swift:$showModeration": .notYetAudited(reason: "Moderation. Long copy."),
        "EditProfileView.swift:$showInterests": .notYetAudited(reason: "Interest picker; a grid of chips, which is what breaks first at AX5."),
        "BoardView.swift:$link": .notYetAudited(reason: "Safari view — system UI, scales on its own."),
        "UtilityRowView.swift:$model.showCustomize": .notYetAudited(reason: "Utility customise sheet."),
    ]

    /// A new screen must be a deliberate decision, not a silent gap.
    func testEveryPresentedScreenIsAccountedFor() throws {
        let presented = try presentedScreens()
        let missing = presented.subtracting(Self.ledger.keys).sorted()

        XCTAssertTrue(missing.isEmpty, """
            These screens are presented by the app but are not in the audit ledger, \
            so nothing checks them at accessibility text sizes. Add each one to \
            `ledger` — `.audited` once `DynamicTypeAuditTests` opens it, or \
            `.notYetAudited` with a real reason:
            \(missing.map { "  • \($0)" }.joined(separator: "\n"))
            """)
    }

    /// A ledger that outlives the screens it describes stops being read.
    func testLedgerHasNoStaleEntries() throws {
        let presented = try presentedScreens()
        let stale = Set(Self.ledger.keys).subtracting(presented).sorted()

        XCTAssertTrue(stale.isEmpty, """
            These ledger entries no longer match any presentation in the app — the \
            screen was removed or its binding renamed. Delete or update them:
            \(stale.map { "  • \($0)" }.joined(separator: "\n"))
            """)
    }

    // MARK: - Scanning

    private func presentedScreens() throws -> Set<String> {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("BlockParty")

        guard let walker = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else {
            XCTFail("Could not read \(sources.path) — the coverage ledger did not run")
            return []
        }

        // `.sheet(isPresented: $x)` / `.sheet(item: $x)` / `.fullScreenCover(…)`.
        let pattern = try NSRegularExpression(
            pattern: #"\.(?:sheet|fullScreenCover)\((?:isPresented|item):\s*\$([A-Za-z_][A-Za-z0-9_.]*)"#
        )

        var found: Set<String> = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for line in text.components(separatedBy: .newlines) {
                let code = line.trimmingCharacters(in: .whitespaces)
                if code.hasPrefix("//") { continue }
                let range = NSRange(code.startIndex..., in: code)
                for match in pattern.matches(in: code, range: range) {
                    guard let binding = Range(match.range(at: 1), in: code) else { continue }
                    found.insert("\(url.lastPathComponent):$\(code[binding])")
                }
            }
        }
        return found
    }
}
