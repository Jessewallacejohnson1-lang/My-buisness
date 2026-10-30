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
        // Was `.audited(surface: "you-profile")` until 2026-09-22, when the walk was
        // scoped to developed pages (Jesse). `ProfileView` is a real screen but is
        // still moving, and its unfinished states — "No plans yet", "a neighbor",
        // "Around town" — were what the auditor kept reporting. It goes back to
        // `.audited` the day the page is finished; the surface is parked in
        // `DynamicTypeAuditTests.notDevelopedYet`, ready to move one line.
        "RootView.swift:$showProfileSheet": .notYetAudited(reason: "The You tab's profile. Not a developed page yet — see DynamicTypeAuditTests.notDevelopedYet. High priority the day it settles: a profile is user-generated text of any length."),

        "OnboardingNamePhoto.swift:$camera": .notYetAudited(reason: "Apple's own camera (UIImagePickerController) for onboarding's photo: no text of ours to scale."),
        "FriendsWaysIn.swift:$showingCode": .notYetAudited(reason: "Your code (friends 07): a photo, a name, a line, the QR code and two buttons in Apple's sheet, as tall as it measures. Text-size checks wait for Jesse (MEMORY.md, 2026-09-24)."),
        "YourCode.swift:$scanning": .notYetAudited(reason: "Scan a code (friends 07): Apple's own scanner (VisionKit) with our round X and a one-line pill; the camera-off note wraps. Text-size checks wait for Jesse (MEMORY.md, 2026-09-24)."),
        "RootView.swift:$showMap": .notYetAudited(reason: "The full-screen map. Its text is the bubbles' time tags, one pill and the event card's four lines; the card's title is one line and truncates at the largest sizes. Text-size checks wait for Jesse (MEMORY.md, 2026-09-24)."),
        "FriendMenu.swift:$addingName": .notYetAudited(reason: "Edit profile, from a friend request refused for want of a name: the same screen as ProfileView.swift:$editing, not yet audited either."),
        "FeedEventCard.swift:$commentsPresented": .notYetAudited(reason: "Event comments. User-generated text of any length — high priority."),
        "FeedCardMenu.swift:$isPresented": .notYetAudited(reason: "A Town feed card's and the Event of the day poster's ••• sheet (one `FeedCardMenuSheet`, ticket 21). Three short lines and a row; its height follows its content. The admin's ten-row Score box has no scroll, so at the largest sizes it can run off the screen. Text-size checks wait for Jesse (MEMORY.md, 2026-09-24)."),
        "FeedCardMenu.swift:$editingInterests": .notYetAudited(reason: "Edit profile, opened from the ••• sheet: the same screen as ProfileView.swift:$editing, not yet audited either."),
        "PostingCard.swift:$commentsPresented": .notYetAudited(reason: "Post comments. Same as above."),
        "ProfileView.swift:$editing": .notYetAudited(reason: "Edit profile. A form at AX5 is exactly where truncation hurts — high priority."),
        "ProfileView.swift:$showAbout": .notYetAudited(reason: "About. Long copy."),
        "TeamPage.swift:$opened": .notYetAudited(reason: "A school activity's coming events (school-activities 02): a plain List of dates and titles, which wraps at any size. Text-size checks wait for Jesse (MEMORY.md, 2026-09-24)."),
        "ProfilePage.swift:$showingPhoto": .notYetAudited(reason: "A profile's photo, whole, with only a close button: no text to grow."),
        "ProfileView.swift:$showModeration": .notYetAudited(reason: "Moderation. Long copy."),
        "EditProfileView.swift:$showInterests": .notYetAudited(reason: "Interest picker; a grid of chips, which is what breaks first at AX5."),
        "ModerationView.swift:$link": .notYetAudited(reason: "Safari view on a found event's page — system UI, scales on its own."),
        "TownNewsCard.swift:$link": .notYetAudited(reason: "Safari view on a town news post (town-feed 35) — system UI, scales on its own."),
        "RootView.swift:$helloLink": .notYetAudited(reason: "Safari view on the hello pill's news post (hello-drop 03) — system UI, scales on its own."),
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
