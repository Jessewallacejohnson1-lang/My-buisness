//
//  PageChromeTests.swift
//  Block Party — pins a pushed page's top bar (BP app codebase-health 19): 44pt tall, 20pt down
//  its sheet (where Apple's own bar sat), the page's whole width, and a back chevron that is
//  44pt square to the finger.
//

import SwiftUI
import XCTest
@testable import BlockParty

@MainActor
final class PageChromeTests: XCTestCase {
    private let width: CGFloat = 402

    func testTheBarIs44TallUnderTheSheets20AndItsBackIs44Square() {
        XCTAssertEqual(fit(PageBar(title: "Saved") {}), CGSize(width: width, height: 64))
        XCTAssertEqual(fit(PageBar(title: "Restaurants", top: 0) {}), CGSize(width: width, height: 44))
        XCTAssertEqual(fit(BackButton {}), CGSize(width: 44, height: 44))
    }

    /// A small mark's tap area grows to 44 each way around its centre (BP app hit-targets); a big
    /// one, or side 0, keeps its own.
    func testTapAreaGrowsASmallMarkTo44AroundItsCentre() {
        let line = TapArea().path(in: CGRect(x: 20, y: 96, width: 49, height: 20)).boundingRect
        XCTAssertEqual(line, CGRect(x: 20, y: 84, width: 49, height: 44))
        let row = CGRect(x: 0, y: 0, width: 284, height: 60)
        XCTAssertEqual(TapArea().path(in: row).boundingRect, row)
        XCTAssertEqual(TapArea(side: 0).path(in: CGRect(x: 0, y: 0, width: 30, height: 20)).boundingRect,
                       CGRect(x: 0, y: 0, width: 30, height: 20))
    }

    private func fit(_ view: some View) -> CGSize {
        UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}
