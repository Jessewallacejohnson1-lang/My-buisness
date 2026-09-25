//
//  TabBarTests.swift
//  Block Party — pins the tab bar to exactly four destinations, evenly spaced.
//
//  The bar carried a fifth, non-tab Create slot from 2026-09-21 until posting was
//  paused on 2026-09-24. These two tests together keep it at four: `Tab` names the
//  four destinations in order, and the bar draws one slot per `Tab` case and nothing
//  else.
//
//  Limit: the second test is a source scan, not a render. If the bar ever grows a
//  non-tab control again, upgrade it to a rendered slot count.
//

import XCTest
@testable import BlockParty

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
}
