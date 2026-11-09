//
//  PhotoPinchTests.swift
//  Block Party — a pinched photo grows as the fingers spread, stretches past its ends, darkens what's
//  behind it with its scale, and keeps the point under the fingers there (BP app photo-zoom).
//

import XCTest
@testable import BlockParty

final class PhotoPinchTests: XCTestCase {

    /// Between 1× and the most, the photo is the fingers' scale; past either end it stretches less.
    func testScaleFollowsTheFingersAndStretchesAtTheEnds() {
        XCTAssertEqual(PinchMath.shown(1), 1)
        XCTAssertEqual(PinchMath.shown(2.5), 2.5)
        XCTAssertEqual(PinchMath.shown(PinchMath.most), PinchMath.most)
        XCTAssertEqual(PinchMath.shown(PinchMath.most + 2), PinchMath.most + 0.5, accuracy: 0.0001)
        XCTAssertEqual(PinchMath.shown(0.5), 1 - 0.5 * 0.35, accuracy: 0.0001)
        XCTAssertGreaterThan(PinchMath.shown(0), 0, "pinched shut, it never vanishes or flips")
    }

    /// Clear at rest, darkening with the scale, darkest from 2× on.
    func testBehindDarkensWithTheScale() {
        XCTAssertEqual(PinchMath.dim(1), 0)
        XCTAssertEqual(PinchMath.dim(0.8), 0)
        XCTAssertEqual(PinchMath.dim(1.5), PinchMath.dimMost / 2, accuracy: 0.0001)
        XCTAssertEqual(PinchMath.dim(2), PinchMath.dimMost)
        XCTAssertEqual(PinchMath.dim(3.5), PinchMath.dimMost)
    }

    /// The point of the photo under the fingers stays under them as they spread and move.
    func testThePointUnderTheFingersStaysUnderThem() {
        let landed = CGPoint(x: 120, y: 200)
        let anchor = PinchMath.anchor(fingers: landed, offset: .zero, scale: 1)
        XCTAssertEqual(anchor, landed)

        let moved = CGPoint(x: 150, y: 260)
        let offset = PinchMath.offset(anchor: anchor, fingers: moved, scale: 2.5)
        XCTAssertEqual(offset.x + anchor.x * 2.5, moved.x, accuracy: 0.0001)
        XCTAssertEqual(offset.y + anchor.y * 2.5, moved.y, accuracy: 0.0001)

        // Caught as drawn, the fingers' point maps back to the same point of the photo.
        let caught = PinchMath.anchor(fingers: moved, offset: offset, scale: 2.5)
        XCTAssertEqual(caught.x, anchor.x, accuracy: 0.0001)
        XCTAssertEqual(caught.y, anchor.y, accuracy: 0.0001)
    }
}
