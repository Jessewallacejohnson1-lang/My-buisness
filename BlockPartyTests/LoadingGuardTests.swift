//
//  LoadingGuardTests.swift
//  Block Party — the gate that keeps "loading is a skeleton" true as the app grows.
//
//  The rule (DESIGN.md, AGENTS.md): a surface waiting on a fetch renders placeholder
//  shapes in the content's own layout, so the real data resolves IN PLACE. It never
//  renders a spinner, and it is never hidden behind a full-screen cover.
//
//  That rule was written down long before it was true. The app carried a dark
//  full-screen `TabLoadingCover` and five spinners-as-content, and the debt list in
//  AGENTS.md sat unactioned while new screens copied the pattern. Both were removed
//  on 2026-09-21. This test is what stops them growing back — it is a source-level
//  gate, cheap, and it runs in the existing CI job.
//
//  If this test fails, do NOT add your file to the allowlist. Build a skeleton from
//  `Features/Components/Skeleton.swift` in your content's own shape.
//

import XCTest
@testable import BlockParty

final class LoadingGuardTests: XCTestCase {

    /// The ONLY legitimate use of `ProgressView`: an action the user already tapped,
    /// in flight, inside the control that started it. There is no content shape to
    /// stand in for there, so a spinner is honest. Content — a screen, a list, a
    /// card, a feed section, an image well — never gets one.
    private static let spinnerAllowlist: Set<String> = [
        "Features/Auth/LoginView.swift",          // sign-in button, mid-request
        "Features/Add/AddFormView.swift",         // submit button, mid-post
        "Features/Profile/EditProfileView.swift", // save button, mid-save
        "Features/Components/InlineAction.swift", // the shared inline button itself
    ]

    func testNoSpinnersOutsideTappedControls() throws {
        let offenders = try scanSources(allowlist: Self.spinnerAllowlist) { line in
            line.contains("ProgressView(")
        }
        XCTAssertTrue(
            offenders.isEmpty,
            """
            Spinner used as content. Loading is a skeleton, never a spinner and never \
            a blank screen — build placeholder shapes in the content's own layout \
            (Features/Components/Skeleton.swift) so the data resolves in place:
            \(offenders.joined(separator: "\n"))
            """
        )
    }

    /// The full-screen loading cover and its readiness plumbing, deleted 2026-09-21.
    /// It had begun covering content that was already on screen: the Town tab renders
    /// from local data, but its readiness was wired to the briefing RPC, so a slow
    /// network dropped a dark screen over a finished one.
    func testNoFullScreenLoadingCover() throws {
        let banned = [
            "TabLoadingCover", "TabLoadingHost", "RainbowWaveIndicator",
            "TabReadyPreferenceKey", "tabReady(", "LaunchLoaderView",
        ]
        let offenders = try scanSources(allowlist: []) { line in
            banned.contains { line.contains($0) }
        }
        XCTAssertTrue(
            offenders.isEmpty,
            """
            The full-screen loading cover is back. A tab that is still fetching \
            renders its own skeleton in its own layout; nothing is hidden behind a \
            cover, and no tab reports "readiness" to the shell:
            \(offenders.joined(separator: "\n"))
            """
        )
    }

    // MARK: - Scanner (same shape as TypographyScalingGuardTests)

    private func scanSources(
        allowlist: Set<String>,
        matching isOffending: (String) -> Bool
    ) throws -> [String] {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // BlockPartyTests
            .deletingLastPathComponent()      // repo root
            .appendingPathComponent("BlockParty")

        guard let walker = FileManager.default.enumerator(
            at: sources,
            includingPropertiesForKeys: nil
        ) else {
            return ["Could not read \(sources.path) — the guard did not run"]
        }

        var offenders: [String] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let relative = url.path.replacingOccurrences(of: sources.path + "/", with: "")
            if allowlist.contains(relative) { continue }

            let text = try String(contentsOf: url, encoding: .utf8)
            for (index, line) in text.components(separatedBy: .newlines).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                if code.hasPrefix("//") || code.hasPrefix("///") || code.hasPrefix("*") { continue }
                if isOffending(code) {
                    offenders.append("\(relative):\(index + 1): \(code)")
                }
            }
        }
        return offenders.sorted()
    }
}
