//
//  ConcentricRectangleTests.swift
//  Block Party — the concentric corner math.
//
//  `ConcentricRectangle` derives its corner radius as container − inset, floored at
//  `minimumRadius`. These pin that rule plus the two clamps that keep a corner from
//  inverting or overlapping its neighbour.
//

import XCTest
import SwiftUI
@testable import BlockParty

final class ConcentricRectangleTests: XCTestCase {

    func testInnerRadiusIsContainerMinusInset() {
        XCTAssertEqual(
            ConcentricRectangle.innerRadius(containerRadius: 24, inset: 8),
            16
        )
    }

    func testZeroInsetKeepsContainerRadius() {
        XCTAssertEqual(
            ConcentricRectangle.innerRadius(containerRadius: 24, inset: 0),
            24
        )
    }

    func testInsetDeeperThanRadiusClampsToZeroRatherThanInverting() {
        XCTAssertEqual(
            ConcentricRectangle.innerRadius(containerRadius: 12, inset: 20),
            0
        )
    }

    func testMinimumRadiusHoldsASoftCornerOnDeepInsets() {
        XCTAssertEqual(
            ConcentricRectangle.innerRadius(containerRadius: 12, inset: 20, minimum: 4),
            4
        )
    }

    func testMinimumDoesNotOverrideALargerConcentricRadius() {
        XCTAssertEqual(
            ConcentricRectangle.innerRadius(containerRadius: 24, inset: 4, minimum: 6),
            20
        )
    }

    /// The path clamp: a radius wider than half the shorter side must collapse to the capsule
    /// limit, so a short strip draws a stadium instead of self-overlapping arcs.
    func testPathClampsRadiusToHalfTheShorterSide() {
        let shape = ConcentricRectangle(containerRadius: 400, inset: 0)
        let strip = CGRect(x: 0, y: 0, width: 200, height: 40)

        let drawn = shape.path(in: strip)
        let capsule = RoundedRectangle(cornerRadius: 20, style: .continuous).path(in: strip)

        XCTAssertEqual(drawn.boundingRect, strip)
        XCTAssertEqual(
            drawn.description,
            capsule.description,
            "A 400pt radius in a 40pt-tall strip should draw the 20pt capsule limit."
        )
    }

    func testAnimatableDataCarriesRadiusAndInset() {
        var shape = ConcentricRectangle(containerRadius: 24, inset: 8)
        XCTAssertEqual(shape.animatableData, AnimatablePair(24, 8))

        shape.animatableData = AnimatablePair(30, 10)
        XCTAssertEqual(shape.containerRadius, 30)
        XCTAssertEqual(shape.inset, 10)
    }
}
