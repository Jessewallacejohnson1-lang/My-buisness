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

    private func fit(_ view: some View) -> CGSize {
        UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}
