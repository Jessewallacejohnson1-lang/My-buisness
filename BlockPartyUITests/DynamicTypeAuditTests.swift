//
//  DynamicTypeAuditTests.swift
//  Block Party — does the app still WORK when the text gets big?
//
//  `TypographyScalingGuardTests` (unit target) proves every font scales. Scaling is
//  the easy half. This is the other half: a layout that was measured at 13pt has to
//  survive the same text at 40pt, and nothing in the type system can promise that —
//  whether a row wraps, stacks, or drops its icon is a design decision per surface.
//
//  So this does not try to prove the layouts are right. It launches the real app at
//  the accessibility text sizes Apple names in the App Store "Larger Text" criteria
//  (AX3 and AX5) and asks iOS's own auditor what is clipped, truncated, or
//  overlapping. Failures arrive with a screenshot attached.
//
//  Two things to know before reading a failure:
//
//  1. `.dynamicType` is documented by other teams as producing false positives —
//     it flags elements that are using a standard text style perfectly well. Every
//     suppression in `isFrozenByDesign` names WHY, and nothing goes in that list
//     because it was noisy.
//  2. The surface list is not decoration. `DynamicTypeAuditCoverageTests` in the
//     unit target fails if a screen exists that this walk never visits, because an
//     audit only ever covers what it opens.
//

import XCTest

final class DynamicTypeAuditTests: XCTestCase {

    /// A screen the audit opens, and the launch arguments that get there.
    ///
    /// Every entry drives the app through the DEBUG flags it already has for
    /// headless screenshots (`-open-tab`, `-open-menu`, `-open-profile`,
    /// `-feed-scrolled`) rather than tapping through the UI, because a tap that
    /// misses is a flaky test and a launch argument is not.
    struct Surface {
        let id: String
        let arguments: [String]
    }

    /// AUDIT-SURFACES-BEGIN — parsed by the coverage test. Keep one entry per line.
    static let surfaces: [Surface] = [
        Surface(id: "town", arguments: ["-open-tab", "town"]),
        Surface(id: "town-menu", arguments: ["-open-tab", "town", "-open-menu"]),
        Surface(id: "town-scrolled", arguments: ["-open-tab", "town", "-feed-scrolled"]),
        Surface(id: "daily", arguments: ["-open-tab", "daily"]),
        Surface(id: "business", arguments: ["-open-tab", "business"]),
        Surface(id: "you", arguments: ["-open-tab", "you"]),
        Surface(id: "you-profile", arguments: ["-open-tab", "you", "-open-profile"]),
    ]
    /// AUDIT-SURFACES-END

    /// The two sizes Apple's App Store "Larger Text" criteria names by name. AX5 is
    /// the worst case; AX3 is where most real users who enlarge text actually sit,
    /// and a layout can pass AX5 by collapsing in a way that looks broken at AX3.
    static let contentSizes: [(name: String, category: String)] = [
        ("AX3", "UICTContentSizeCategoryAccessibilityXL"),
        ("AX5", "UICTContentSizeCategoryAccessibilityXXXL"),
    ]

    /// What is broken TODAY, measured, so the gate can block what breaks TOMORROW.
    ///
    /// The layout work has not been done — the fonts scale, the layouts that were
    /// measured around them do not yet hold. Failing the build on all of it would
    /// make this test permanently red, and a permanently red gate gets deleted, so
    /// these counts are the ratchet instead: MORE issues than the baseline fails,
    /// and FEWER also fails, with a note to lower the number. The list only goes
    /// down, and it is meant to reach zero and then this constant is deleted.
    ///
    /// Verified stable across two consecutive runs before being written down. A
    /// surface absent from this map must be clean.
    ///
    /// ponytail: counts, not fingerprints — swapping one broken label for another
    /// at the same count slips through. Fingerprints churn on fixture copy, which
    /// would make the gate cry wolf; move to them if this ever masks a real one.
    static let knownIssueCounts: [String: Int] = [
        "town@AX3": 4,            "town@AX5": 4,
        "town-menu@AX3": 6,       "town-menu@AX5": 5,
        "town-scrolled@AX3": 2,   "town-scrolled@AX5": 1,
        "you@AX3": 3,             "you@AX5": 3,
        "you-profile@AX3": 3,     "you-profile@AX5": 3,
        // daily and business are clean at both sizes, and stay that way.
    ]

    func testEverySurfaceHoldsItsLayoutAtAccessibilityTextSizes() throws {
        for size in Self.contentSizes {
            for surface in Self.surfaces {
                XCTContext.runActivity(named: "\(surface.id) @ \(size.name)") { _ in
                    audit(surface, atContentSize: size.category, named: size.name)
                }
            }
        }
    }

    // MARK: - One surface, one size

    private func audit(_ surface: Surface, atContentSize category: String, named sizeName: String) {
        let app = XCUIApplication()
        app.launchArguments = surface.arguments + [
            "-UIPreferredContentSizeCategoryName", category,
        ]
        app.launch()

        // The feed reveals asynchronously. Auditing a half-drawn screen reports
        // clipping that resolves a frame later, so wait for the app to settle
        // rather than racing it.
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 20),
            "\(surface.id) never reached the foreground"
        )
        _ = app.descendants(matching: .any).firstMatch.waitForExistence(timeout: 10)

        // The handler collects instead of letting XCTest report each issue on its
        // own. Raw audit failures name the audit type and nothing else — "Text
        // clipped", twenty times, with no element and no screen — which is a count,
        // not a bug report. Collecting them lets one failure name the surface, the
        // size, and every element, which is the difference between a gate someone
        // acts on and a gate someone disables.
        var findings: [String] = []
        do {
            try app.performAccessibilityAudit(for: [.dynamicType, .textClipped]) { issue in
                if self.isFrozenByDesign(issue) { return true }
                let element = issue.element?.label ?? "(unnamed element)"
                findings.append("  • \(issue.compactDescription) — \"\(element)\"")
                return true
            }
        } catch {
            XCTFail("\(surface.id): the audit itself failed to run — \(error)")
        }

        app.terminate()

        let key = "\(surface.id)@\(sizeName)"
        let baseline = Self.knownIssueCounts[key] ?? 0
        let unique = Array(Set(findings)).sorted()

        if unique.count > baseline {
            XCTFail("""
                \(key): \(unique.count) layout issues at accessibility text size, \
                up from a baseline of \(baseline). Something regressed, or a new \
                screen landed without its layout being adapted:
                \(unique.joined(separator: "\n"))
                """)
        } else if unique.count < baseline {
            XCTFail("""
                \(key): \(unique.count) layout issues, DOWN from \(baseline) — \
                good. Lower the baseline in `knownIssueCounts` to lock the fix in, \
                or delete the entry if it is now 0. Still outstanding:
                \(unique.isEmpty ? "  (none)" : unique.joined(separator: "\n"))
                """)
        }
    }

    // MARK: - What is allowed not to grow

    /// Chrome that holds its size on purpose, and is therefore not a finding.
    ///
    /// This list is SHORT and it stays short. Jesse's rule: scale the text that
    /// makes sense to scale, and rule out the tab bar and the logo. Everything
    /// ruled out here is already frozen deliberately in the app through
    /// `Font.glyph` or `Font.logo` — this is the same decision, stated where the
    /// auditor can read it.
    ///
    /// A thing in this list owes the reader another way in. The tab bar's labels
    /// still scale (only the icons are frozen), and the frozen chrome needs
    /// `.accessibilityShowsLargeContentViewer()` so a long press enlarges it —
    /// which is Apple's requirement for a custom bar, not a nicety.
    private func isFrozenByDesign(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        guard let label = issue.element?.label else { return false }

        // The tab bar. Four fixed destinations in a bar with a fixed height; a
        // grown tab bar eats the screen the content needs.
        if ["Town", "Daily", "Business", "You"].contains(label) { return true }

        // The wordmark. A logo is a mark, not text — it holds its proportions
        // against the artwork beside it at every content size.
        if label.localizedCaseInsensitiveContains("block party") { return true }

        return false
    }
}
