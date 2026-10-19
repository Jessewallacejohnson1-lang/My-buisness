//
//  AvatarPhotoTests.swift
//  Block Party — a picked profile photo shrinks before it uploads (BP app backlog 03).
//  The one live avatar was the full camera image, 4.7 MB.
//

import UIKit
import XCTest
@testable import BlockParty

final class AvatarPhotoTests: XCTestCase {

    /// A town photo blown up to a camera's 4,000 x 3,000 comes back a 400 px square, under
    /// 100 KB. A real photo, not a flat colour, which would be small at any size.
    func testACameraPhotoUploadsAsA400PixelSquareUnder100KB() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "downtown", ofType: "jpg"))
        let town = try XCTUnwrap(UIImage(contentsOfFile: path))
        let camera = draw(width: 4000, height: 3000) { town.draw(in: $0) }

        let data = try XCTUnwrap(ProfileModel.avatarJPEG(camera))
        let sent = try XCTUnwrap(UIImage(data: data)?.cgImage)
        XCTAssertEqual(sent.width, 400)
        XCTAssertEqual(sent.height, 400)
        XCTAssertLessThan(data.count, 100_000)
    }

    /// A photo taken with the phone turned stays upright, and a small one isn't enlarged.
    /// Its pixels are 300 x 200, red on the left and blue on the right, marked turned right:
    /// shown, it is 200 x 300 with red on top.
    func testATurnedPhotoStaysUprightAndASmallOneIsNotEnlarged() throws {
        let pixels = draw(width: 300, height: 200) { rect in
            UIColor.red.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: rect.width / 2, height: rect.height))
            UIColor.blue.setFill()
            UIRectFill(CGRect(x: rect.width / 2, y: 0, width: rect.width / 2, height: rect.height))
        }
        let turned = UIImage(cgImage: try XCTUnwrap(pixels.cgImage), scale: 1, orientation: .right)

        let sent = try XCTUnwrap(UIImage(data: try XCTUnwrap(ProfileModel.avatarJPEG(turned)))?.cgImage)
        XCTAssertEqual(sent.width, 200)
        XCTAssertEqual(sent.height, 200)
        let top = pixel(sent, x: 100, y: 20), bottom = pixel(sent, x: 100, y: 180)
        XCTAssertTrue(top.red > 200 && top.blue < 60, "red on top: \(top)")
        XCTAssertTrue(bottom.blue > 200 && bottom.red < 60, "blue at the bottom: \(bottom)")
    }

    private func draw(width: CGFloat, height: CGFloat, _ body: (CGRect) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        return UIGraphicsImageRenderer(size: rect.size, format: format).image { _ in body(rect) }
    }

    /// The colour at x, y counted from the top left.
    private func pixel(_ image: CGImage, x: Int, y: Int) -> (red: UInt8, blue: UInt8) {
        var rgba = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(image, in: CGRect(x: -x, y: y + 1 - image.height, width: image.width, height: image.height))
        return (rgba[0], rgba[2])
    }
}
