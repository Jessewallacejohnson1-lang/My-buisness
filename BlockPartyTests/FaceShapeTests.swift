//
//  FaceShapeTests.swift
//  Block Party — a person's picture is the Photo step's squircle, everything else round (BP app backlog 40).
//

import SwiftUI
import XCTest
@testable import BlockParty

final class FaceShapeTests: XCTestCase {

    /// The corner is cut as far in as the Photo step's: a point 10% of the side in from the corner is outside,
    /// 14% in is inside (measured 11.7%), at a tab bar face's size and at the Photo step's.
    func testTheCornerIsTheSameShareOfEverySize() {
        for side: CGFloat in [18, 25, 40, 96, 160] {
            let path = FaceShape().path(in: CGRect(x: 0, y: 0, width: side, height: side))
            XCTAssertFalse(path.contains(CGPoint(x: side * 0.10, y: side * 0.10)), "\(side) pt corner too square")
            XCTAssertTrue(path.contains(CGPoint(x: side * 0.14, y: side * 0.14)), "\(side) pt corner too round")
        }
    }

    /// A ring drawn inside keeps to the picture: the inset shape's box is the box, inset.
    func testAnInsetKeepsToTheBox() {
        let box = FaceShape().inset(by: 2).path(in: CGRect(x: 0, y: 0, width: 96, height: 96)).boundingRect
        XCTAssertEqual(box.minX, 2, accuracy: 0.5)
        XCTAssertEqual(box.width, 92, accuracy: 0.5)
    }

    /// People are the squircle, with or without a photo; a place, group or host is round unless it is a person.
    func testOnlyAPersonIsTheSquircle() {
        XCTAssertTrue(Avatar(nil, size: 40).person)
        XCTAssertFalse(Avatar(nil, size: 40, blank: .initial("Kay's Kitchen")).person)
        XCTAssertFalse(Avatar(nil, size: 40, person: false).person, "a neighbour who hosts an Event is round")
    }
}
