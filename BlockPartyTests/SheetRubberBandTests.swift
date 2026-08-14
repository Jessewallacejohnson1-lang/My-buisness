//
//  SheetRubberBandTests.swift
//  Block Party — the map sheet's overdrag resistance curve (map polish Phase 5).
//
//  `SheetRubberBand` is pure geometry (nonisolated): inside [min, max] the
//  height tracks the finger 1:1; past either bound the visible travel is
//  give·√overdrag, capped at maxStretch. These pin the curve's contract —
//  passthrough, compression, floor symmetry, and the cap.
//

import XCTest
@testable import BlockParty

final class SheetRubberBandTests: XCTestCase {

    private let lower: CGFloat = 96    // MapSheet.peekHeight on a phone
    private let upper: CGFloat = 700   // a full-detent height in the same ballpark

    func testInBoundsHeightPassesThroughUntouched() {
        XCTAssertEqual(SheetRubberBand.height(raw: lower, min: lower, max: upper), lower)
        XCTAssertEqual(SheetRubberBand.height(raw: 400, min: lower, max: upper), 400)
        XCTAssertEqual(SheetRubberBand.height(raw: upper, min: lower, max: upper), upper)
    }

    func testOverdragPastFullCompressesButStaysMonotonic() {
        let near = SheetRubberBand.height(raw: upper + 25, min: lower, max: upper)
        let far = SheetRubberBand.height(raw: upper + 100, min: lower, max: upper)
        // give·√25 = 15, give·√100 = 30 — well under the raw overdrag…
        XCTAssertEqual(near, upper + SheetRubberBand.give * 5, accuracy: 0.001)
        XCTAssertEqual(far, upper + SheetRubberBand.give * 10, accuracy: 0.001)
        // …and monotonic: more finger always means at least a little more sheet.
        XCTAssertGreaterThan(far, near)
    }

    func testUnderdragBelowPeekMirrorsTheSameCurve() {
        let squished = SheetRubberBand.height(raw: lower - 25, min: lower, max: upper)
        XCTAssertEqual(squished, lower - SheetRubberBand.give * 5, accuracy: 0.001)
    }

    func testStretchIsCappedSoTheSheetNeverReachesTheChrome() {
        let extreme = SheetRubberBand.height(raw: upper + 10_000, min: lower, max: upper)
        XCTAssertEqual(extreme, upper + SheetRubberBand.maxStretch)
        let floorExtreme = SheetRubberBand.height(raw: lower - 10_000, min: lower, max: upper)
        XCTAssertEqual(floorExtreme, lower - SheetRubberBand.maxStretch)
    }
}
