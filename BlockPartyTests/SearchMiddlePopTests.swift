//
//  SearchMiddlePopTests.swift
//  BlockPartyTests — how much a crest on Search's Schools row grows as it nears the middle of the
//  screen while the row scrolls (BP app search-logo-size 02).
//

import XCTest
@testable import BlockParty

final class SearchMiddlePopTests: XCTestCase {
    private let width: CGFloat = 402

    func testTheMiddleIsTheMost() {
        XCTAssertEqual(SearchMetric.middlePop(midX: width / 2, width: width), 1, accuracy: 0.0001)
    }

    func testNothingFromItsReachOut() {
        let reach = SearchMetric.popReach
        XCTAssertEqual(SearchMetric.middlePop(midX: width / 2 + reach, width: width), 0, accuracy: 0.0001)
        XCTAssertEqual(SearchMetric.middlePop(midX: width / 2 - reach - 40, width: width), 0)
        XCTAssertEqual(SearchMetric.middlePop(midX: -300, width: width), 0)
    }

    func testHalfwayIsHalf() {
        XCTAssertEqual(SearchMetric.middlePop(midX: width / 2 + SearchMetric.popReach / 2, width: width), 0.5, accuracy: 0.0001)
    }

    func testBothSidesAlike() {
        for d in stride(from: CGFloat(0), through: 200, by: 7) {
            XCTAssertEqual(SearchMetric.middlePop(midX: width / 2 - d, width: width),
                           SearchMetric.middlePop(midX: width / 2 + d, width: width), accuracy: 0.0001)
        }
    }

    func testFallsOffSmoothlyNeverBack() {
        var last = SearchMetric.middlePop(midX: width / 2, width: width)
        for d in stride(from: CGFloat(1), through: 200, by: 1) {
            let pop = SearchMetric.middlePop(midX: width / 2 + d, width: width)
            XCTAssertLessThanOrEqual(pop, last)
            XCTAssertLessThan(last - pop, 0.02, "a jump at \(d) pt from the middle")
            last = pop
        }
    }

    /// Before the scroll view has a width there is no middle: nothing grows.
    func testNoWidthNoPop() {
        XCTAssertEqual(SearchMetric.middlePop(midX: 0, width: 0), 0)
    }
}
