//
//  EventMeltBitmapTests.swift
//  BlockPartyTests — the Event page's photo and its melt, baked into one picture (BP app event-hero-foot).
//

import CoreGraphics
import SwiftUI
import XCTest
@testable import BlockParty

final class EventMeltBitmapTests: XCTestCase {
    /// A solid red photo, baked at 2x on a 100 x 80 pt hero with a 40 pt melt: the picture covers the hero and
    /// its melt, the photo is whole at the top, and the melt is gone by the bottom.
    func testThePhotoIsWholeAtTheTopAndTheMeltGoneAtTheFoot() throws {
        let photo = try XCTUnwrap(Self.solid(width: 300, height: 200))
        let look = EventMeltBitmap.Look(width: 100, height: 80, reach: 40, scale: 2, focus: .center)
        let baked = try XCTUnwrap(EventMeltBitmap.make(photo, look))
        XCTAssertEqual(baked.width, 200)
        XCTAssertEqual(baked.height, 240)

        let pixels = try XCTUnwrap(Self.rgba(baked))
        func alpha(row: Int) -> UInt8 { pixels[(row * baked.width + baked.width / 2) * 4 + 3] }
        func red(row: Int) -> UInt8 { pixels[(row * baked.width + baked.width / 2) * 4] }
        XCTAssertEqual(alpha(row: 0), 255, "the photo is whole at the top")
        XCTAssertGreaterThan(red(row: 0), 240)
        XCTAssertLessThan(alpha(row: baked.height - 1), 8, "the melt is gone at the foot")
        // No step anywhere down the middle: each row's alpha within a few levels of the one above.
        for row in 1..<baked.height {
            XCTAssertLessThan(abs(Int(alpha(row: row)) - Int(alpha(row: row - 1))), 6, "row \(row)")
        }
    }

    private static func solid(width: Int, height: Int) -> CGImage? {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context?.makeImage()
    }

    /// Premultiplied RGBA bytes, top row first.
    private static func rgba(_ image: CGImage) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return drawn ? bytes : nil
    }
}
