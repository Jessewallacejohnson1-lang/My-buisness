//
//  TabBarTests.swift
//  Block Party — pins the tab bar: four destinations, Instagram's measured
//  geometry, and the one ink it draws.
//
//  The first two tests keep the bar at four: `Tab` names the four destinations in
//  order, and the bar draws one slot per `Tab` case and nothing else. (It carried a
//  fifth, non-tab Create slot from 2026-09-21 until posting was paused 2026-09-24.)
//
//  The geometry tests pin `TabBarMetric` to Instagram's bar (2026-09-27,
//  `references/instagram-tab-bar/MEASURED.md`): equal slots inside a 9pt side
//  inset, the bubble one slot wide and 5pt inside the capsule top and bottom.
//  Everything is capsule-local: x = 0 at the capsule's edge.
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
        XCTAssertEqual(Tab.allCases, [.town, .daily, .search, .you])
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

    /// Instagram's layout rule, at the 393pt phone's capsule and the Air's: the end
    /// bubbles sit 9pt in, neighbouring bubbles touch, and every bubble is 5pt inside
    /// the capsule top and bottom.
    func testSlotsSplitTheCapsuleEvenlyInsideInstagramsInset() {
        XCTAssertEqual(TabBarMetric.height, 60)
        XCTAssertEqual((TabBarMetric.height - TabBarMetric.bubbleHeight) / 2, 5)
        for width: CGFloat in [351, 378] {
            let bubble = TabBarMetric.bubbleWidth(capsuleWidth: width)
            let centre = { (tab: Tab) in TabBarMetric.centreX(of: tab, capsuleWidth: width) }
            XCTAssertEqual(centre(.town) - bubble / 2, 9, accuracy: 0.001, "first bubble at \(width)")
            XCTAssertEqual(centre(.you) + bubble / 2, width - 9, accuracy: 0.001, "last bubble at \(width)")
            XCTAssertEqual(TabBarMetric.pitch(capsuleWidth: width), bubble, accuracy: 0.001,
                           "neighbouring bubbles touch at \(width)")
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
    /// beyond the end centres (Apple's MEASURED overshoot, `references/tab-bar/
    /// MEASURED.md` §3.5; the left end mirrors it).
    func testLensCentreFollowsFingerAndClampsAtTheEnds() {
        let width: CGFloat = 351
        let first = TabBarMetric.centreX(of: .town, capsuleWidth: width) - 9
        let last = TabBarMetric.centreX(of: .you, capsuleWidth: width) + 9
        for finger in stride(from: CGFloat(50), through: 300, by: 25) {
            XCTAssertEqual(TabBarMetric.lensCentreX(fingerX: finger, capsuleWidth: width), finger, accuracy: 0.001)
        }
        for finger: CGFloat in [-80, 0, 30] {
            XCTAssertEqual(TabBarMetric.lensCentreX(fingerX: finger, capsuleWidth: width), first, accuracy: 0.001)
        }
        for finger: CGFloat in [320, width, width + 80] {
            XCTAssertEqual(TabBarMetric.lensCentreX(fingerX: finger, capsuleWidth: width), last, accuracy: 0.001)
        }
    }

    // MARK: - Ink (item row only, no glass)

    /// Instagram's selected tab is its icon filled, in the same ink as the rest: the
    /// filled house covers far more of its box than the outline does.
    func testSelectedIconIsFilledInTheSameInk() throws {
        let selected = try renderedItems(selected: .town)
        let unselected = try renderedItems(selected: .daily)
        let inkPixels = { (bitmap: TabBarBitmap) in
            bitmap.pixels(in: self.iconBox(.town)).filter { self.isInkDark($0.0, $0.1, $0.2, $0.3) }.count
        }
        XCTAssertGreaterThan(Double(inkPixels(selected)), Double(inkPixels(unselected)) * 1.5,
                             "the selected house is not filled")
    }

    func testEveryIconIsInkAndNothingIsYellow() throws {
        let bitmap = try renderedItems(selected: .town)

        for tab in Tab.allCases {
            let darkest = try XCTUnwrap(bitmap.pixels(in: iconBox(tab)).filter { $0.3 > 200 }
                .min { Int($0.0) + Int($0.1) + Int($0.2) < Int($1.0) + Int($1.1) + Int($1.2) },
                "\(tab) icon: nothing drawn")
            for channel in [darkest.0, darkest.1, darkest.2] {
                XCTAssertLessThanOrEqual(abs(Int(channel) - 0x11), 3, "\(tab) icon core is not #111111: \(darkest)")
            }
        }

        var yellow = 0
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width {
                let (r, g, b, a) = bitmap.pixel(x: x, y: y)
                if a > 200, Int(r) - Int(b) > 40, Int(g) - Int(b) > 40 { yellow += 1 }
            }
        }
        XCTAssertEqual(yellow, 0, "yellow drawn in the tab bar")
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

    /// A 30pt square around the icon's centre.
    private func iconBox(_ tab: Tab) -> CGRect {
        let x = TabBarMetric.centreX(of: tab, capsuleWidth: width)
        return pixelRect(x: x - 15, y: TabBarMetric.iconCentreY - 15, width: 30, height: 30)
    }

    private func pixelRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale).integral
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
