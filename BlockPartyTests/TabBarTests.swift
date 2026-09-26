//
//  TabBarTests.swift
//  Block Party — pins the tab bar: four destinations, Apple's measured geometry,
//  and the ink and yellow it draws.
//
//  The first two tests keep the bar at four: `Tab` names the four destinations in
//  order, and the bar draws one slot per `Tab` case and nothing else. (It carried a
//  fifth, non-tab Create slot from 2026-09-21 until posting was paused 2026-09-24.)
//
//  The geometry tests pin `TabBarMetric` to Apple's own 4-tab bar, measured at two
//  widths: the 351pt capsule of a 393pt phone (`references/tab-bar/MEASURED.md`
//  §2.2) and the 378pt capsule of the 420pt iPhone Air (`references/tab-bar/air/`,
//  measured 2026-09-25). Everything is capsule-local: x = 0 at the capsule's edge.
//
//  The colour tests render the item row alone, WITHOUT the glass — nothing in this
//  suite has ever rendered `.glassEffect`. The on-device sample over real glass is
//  the check that matters; these catch a wrong token or an outline creeping back.
//
//  Limit: the second test is a source scan, not a render. If the bar ever grows a
//  non-tab control again, upgrade it to a rendered slot count.
//

import XCTest
import SwiftUI
@testable import BlockParty

/// SwiftUI declares its own `Tab`; this file means the app's.
private typealias Tab = BlockParty.Tab

@MainActor
final class TabBarTests: XCTestCase {

    func testTheBarHasExactlyFourDestinationsInOrder() {
        XCTAssertEqual(Tab.allCases, [.town, .daily, .business, .you])
    }

    func testTheBarDrawsOneSlotPerTab() throws {
        let rootView = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // BlockPartyTests
            .deletingLastPathComponent()      // repo root
            .appendingPathComponent("BlockParty/App/RootView.swift")
        let source = try String(contentsOf: rootView, encoding: .utf8)

        // `BlockPartyTabBar`'s declaration, up to the first top-level closing brace.
        let start = try XCTUnwrap(source.range(of: "struct BlockPartyTabBar"),
                                  "BlockPartyTabBar is no longer declared in RootView.swift")
        let end = source.range(of: "\n}\n", range: start.upperBound..<source.endIndex)?.lowerBound
            ?? source.endIndex
        let bar = source[start.lowerBound..<end]

        XCTAssertTrue(
            bar.contains("ForEach(Tab.allCases"),
            "The tab bar must build its slots with ForEach(Tab.allCases), one per destination and nothing else."
        )
    }

    // MARK: - Geometry (capsule-local points)

    /// Apple's item centres, from glyph bounding boxes. 351pt: MEASURED.md §2.2.
    /// 378pt (iPhone Air): the 2026-09-25 TabProbe pre-step.
    private static let appleCentres: [(capsuleWidth: CGFloat, centres: [CGFloat])] = [
        (351, [51.3, 134.5, 216.8, 298.7]),
        (378, [55.33, 144.33, 233.33, 322.33]),
    ]

    func testTabCentresMatchAppleAt393And420() {
        for (width, centres) in Self.appleCentres {
            for (tab, apple) in zip(Tab.allCases, centres) {
                XCTAssertEqual(TabBarMetric.centreX(of: tab, capsuleWidth: width), apple, accuracy: 1,
                               "\(tab) in the \(width)pt capsule")
            }
        }
    }

    /// Picks by x alone. Apple's bar switches on a release 150pt ABOVE it (Air
    /// pre-step (c)), so there is no cancel zone and no nil.
    func testReleasePointPicksTheTabUnderTheFinger() {
        let width: CGFloat = 351
        let centre = { (tab: Tab) in TabBarMetric.centreX(of: tab, capsuleWidth: width) }

        for tab in Tab.allCases {
            XCTAssertEqual(TabBarMetric.tab(atX: centre(tab), capsuleWidth: width), tab)
        }
        for (left, right) in zip(Tab.allCases, Tab.allCases.dropFirst()) {
            let midpoint = (centre(left) + centre(right)) / 2
            XCTAssertEqual(TabBarMetric.tab(atX: midpoint - 1, capsuleWidth: width), left)
            XCTAssertEqual(TabBarMetric.tab(atX: midpoint + 1, capsuleWidth: width), right)
        }
        XCTAssertEqual(TabBarMetric.tab(atX: -60, capsuleWidth: width), .town)
        XCTAssertEqual(TabBarMetric.tab(atX: width + 60, capsuleWidth: width), .you)
    }

    /// Between the stops the Lens sits under the finger; past them it parks 9pt
    /// beyond the end centres (MEASURED at the right end, MEASURED.md §3.5: 307.7
    /// capsule-local; the left end mirrors it).
    func testLensCentreFollowsFingerAndClampsAtTheEnds() {
        let width: CGFloat = 351
        for finger in stride(from: CGFloat(50), through: 300, by: 25) {
            XCTAssertEqual(TabBarMetric.lensCentreX(fingerX: finger, capsuleWidth: width), finger, accuracy: 0.001)
        }
        for finger: CGFloat in [-80, 0, 30] {
            XCTAssertEqual(TabBarMetric.lensCentreX(fingerX: finger, capsuleWidth: width), 42.3, accuracy: 1)
        }
        for finger: CGFloat in [320, width, width + 80] {
            XCTAssertEqual(TabBarMetric.lensCentreX(fingerX: finger, capsuleWidth: width), 307.7, accuracy: 1)
        }
    }

    // MARK: - Ink and yellow (item row only, no glass)

    func testSelectedIconIsExactBrandYellowWithNoInkOutline() throws {
        let bitmap = try renderedItems(selected: .town)
        var exactYellow = 0
        var ink = 0
        for (r, g, b, a) in bitmap.pixels(in: iconBox(.town)) {
            if isExactBrandYellow(r, g, b, a) { exactYellow += 1 }
            if isInkDark(r, g, b, a) { ink += 1 }
        }
        // A 20pt `house.fill` covers well over 1000 px at @3x; its core must be the
        // exact yellow, not a near-yellow.
        XCTAssertGreaterThan(exactYellow, 600, "selected icon core is not #FCE804 ±2")
        XCTAssertEqual(ink, 0, "the selected icon carries ink — an outline or the old black fill")
    }

    func testEveryOtherIconAndEveryLabelIsInk() throws {
        let bitmap = try renderedItems(selected: .town)

        var boxes = Tab.allCases.map { ("\($0) label", labelBox($0)) }
        boxes += [Tab.daily, .business, .you].map { ("\($0) icon", iconBox($0)) }
        for (name, box) in boxes {
            let darkest = try XCTUnwrap(bitmap.pixels(in: box).filter { $0.3 > 200 }
                .min { Int($0.0) + Int($0.1) + Int($0.2) < Int($1.0) + Int($1.1) + Int($1.2) },
                "\(name): nothing drawn")
            for channel in [darkest.0, darkest.1, darkest.2] {
                XCTAssertLessThanOrEqual(abs(Int(channel) - 0x11), 3, "\(name) core is not #111111: \(darkest)")
            }
        }

        // No yellow anywhere but the selected icon.
        let selected = iconBox(.town)
        var strayYellow = 0
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width where !selected.contains(CGPoint(x: x, y: y)) {
                let (r, g, b, a) = bitmap.pixel(x: x, y: y)
                if a > 200, Int(r) - Int(b) > 40, Int(g) - Int(b) > 40 { strayYellow += 1 }
            }
        }
        XCTAssertEqual(strayYellow, 0, "yellow drawn outside the selected icon")
    }

    // MARK: - Rendering

    private let scale: CGFloat = 3
    private let width: CGFloat = 351

    private func renderedItems(selected: Tab) throws -> TabBarBitmap {
        let renderer = ImageRenderer(
            content: BlockPartyTabBar.Items(selection: selected, capsuleWidth: width, onSelect: { _ in })
                .frame(width: width, height: TabBarMetric.height)
                .background(Hue.paper)
        )
        renderer.scale = scale
        return try TabBarBitmap(cgImage: XCTUnwrap(renderer.cgImage))
    }

    /// A 28pt square around the icon's centre — clear of the label below it.
    private func iconBox(_ tab: Tab) -> CGRect {
        let x = TabBarMetric.centreX(of: tab, capsuleWidth: width)
        return pixelRect(x: x - 14, y: TabBarMetric.iconCentreY - 14, width: 28, height: 28)
    }

    /// The label's line, from above its cap height to below its descender.
    private func labelBox(_ tab: Tab) -> CGRect {
        let x = TabBarMetric.centreX(of: tab, capsuleWidth: width)
        return pixelRect(x: x - 30, y: TabBarMetric.labelBaseline - 10, width: 60, height: 13)
    }

    private func pixelRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale).integral
    }

    private func isExactBrandYellow(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8) -> Bool {
        a == 255 && abs(Int(r) - 0xFC) <= 2 && abs(Int(g) - 0xE8) <= 2 && abs(Int(b) - 0x04) <= 2
    }

    private func isInkDark(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8) -> Bool {
        a > 200 && max(r, g, b) < 90
    }
}

/// RGBA pixels of a rendered image, top-left origin.
private struct TabBarBitmap {
    let width: Int
    let height: Int
    private let rgba: [UInt8]

    init(cgImage: CGImage) throws {
        let width = cgImage.width
        let height = cgImage.height
        self.width = width
        self.height = height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(
                data: storage.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw CocoaError(.coderInvalidValue) }
        rgba = bytes
    }

    func pixel(x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let offset = (y * width + x) * 4
        return (rgba[offset], rgba[offset + 1], rgba[offset + 2], rgba[offset + 3])
    }

    func pixels(in rect: CGRect) -> [(UInt8, UInt8, UInt8, UInt8)] {
        let clipped = rect.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        var out: [(UInt8, UInt8, UInt8, UInt8)] = []
        for y in Int(clipped.minY)..<Int(clipped.maxY) {
            for x in Int(clipped.minX)..<Int(clipped.maxX) { out.append(pixel(x: x, y: y)) }
        }
        return out
    }
}
