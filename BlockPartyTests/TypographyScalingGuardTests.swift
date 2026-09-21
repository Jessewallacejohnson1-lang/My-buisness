//
//  TypographyScalingGuardTests.swift
//  Block Party — the gate that keeps Dynamic Type working as the app grows.
//
//  The defect this exists to prevent is subtle and was app-wide for months:
//  `Font.system(size:)` is a FROZEN point size and never scales with Dynamic
//  Type, while `Font.custom(_:size:)` scales with no ceiling. Mixing them means
//  that at large text settings the body copy stays small for the user who asked
//  for it to be large, while the headings inflate until they truncate.
//
//  So this is a source-level gate, not a rendering test: text takes a ROLE, never
//  a raw point size, and the only file allowed to name a size is the token layer.
//  It is cheap, it runs in the existing CI job, and it fails the moment someone
//  writes a frozen font anywhere else.
//
//  If this test fails, do NOT add your file to the allowlist. Use a `Font` helper
//  from `BlockPartyFont.swift`.
//

import SwiftUI
import XCTest
@testable import BlockParty

final class TypographyScalingGuardTests: XCTestCase {

    /// The only files permitted to name a raw point size, and why.
    ///
    /// - `BlockPartyFont.swift` is the token layer itself: it is where sizes are
    ///   converted into scaling fonts, so it is definitionally the exception.
    private static let allowlist: Set<String> = [
        "Theme/BlockPartyFont.swift",
    ]

    /// `.system(size:` — a frozen system font. Never scales. Always wrong outside
    /// the token layer.
    func testNoFrozenSystemFonts() throws {
        let offenders = try scanSources { line in
            line.contains(".system(size:")
        }
        XCTAssertTrue(
            offenders.isEmpty,
            """
            Frozen system fonts found. `.system(size:)` does not scale with Dynamic \
            Type, so this text stays small for the user who set a large text size. \
            Use a role helper from BlockPartyFont (.sans(.footnote), .display(…), …):
            \(offenders.joined(separator: "\n"))
            """
        )
    }

    /// `.custom(name, size:)` scales, but with NO ceiling and NO relationship to
    /// the text beside it — which is how a 22pt title reached ~55pt next to body
    /// copy that never moved. A custom font must state the text style it scales
    /// against, or be explicitly frozen via `fixedSize:` (the logo, and only the
    /// logo, wants that).
    func testCustomFontsDeclareAScalingRelationship() throws {
        let offenders = try scanSources { line in
            guard line.contains(".custom(") && line.contains("size:") else { return false }
            return !line.contains("relativeTo:") && !line.contains("fixedSize:")
        }
        XCTAssertTrue(
            offenders.isEmpty,
            """
            Custom fonts without a scaling relationship. `.custom(_:size:)` grows \
            unbounded and independently of the system face beside it. Add \
            `relativeTo:` — or `fixedSize:` if this genuinely must never scale:
            \(offenders.joined(separator: "\n"))
            """
        )
    }

    // MARK: - Scanning

    /// Walks the app sources and returns `path:line: text` for every line the
    /// predicate rejects, skipping the allowlist and skipping comments (the file
    /// headers in this codebase discuss these APIs at length by design).
    private func scanSources(matching isOffending: (String) -> Bool) throws -> [String] {
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
            if Self.allowlist.contains(relative) { continue }

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

    // MARK: - The rule is only worth what it renders

    /// The source rules above are a proxy. This is the thing itself: body text
    /// drawn through the token layer must actually get bigger when the user asks
    /// for bigger text.
    ///
    /// `ImageRenderer` honours `\.dynamicTypeSize`, so the same `Text` is drawn at
    /// the default size and at AX5 and the ink is counted. A frozen font produces
    /// two identical bitmaps — which is exactly what this app did on every screen
    /// before the token layer was fixed, and what no unit test would have caught.
    @MainActor
    func testBodyTextActuallyGrowsAtAccessibilitySizes() throws {
        let atDefault = try inkPixels(dynamicTypeSize: .large)
        let atAX5 = try inkPixels(dynamicTypeSize: .accessibility5)

        XCTAssertGreaterThan(
            atAX5, atDefault,
            """
            Body text did not grow at AX5 (\(atDefault) ink px at .large, \(atAX5)             at .accessibility5). The token layer has gone back to a frozen font, so             the user who set a large text size is reading the small one.
            """
        )
    }

    /// Ink drawn by a body-sized line of text at a given content size.
    @MainActor
    private func inkPixels(dynamicTypeSize: DynamicTypeSize) throws -> Int {
        let renderer = ImageRenderer(
            content: Text("Block Party")
                .font(.sans(13))
                .frame(width: 300, height: 200, alignment: .topLeading)
                .environment(\.dynamicTypeSize, dynamicTypeSize)
        )
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)

        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var ink = 0
        for alpha in stride(from: 3, to: pixels.count, by: 4) where pixels[alpha] > 40 {
            ink += 1
        }
        return ink
    }
}
