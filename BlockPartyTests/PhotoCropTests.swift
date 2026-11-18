//
//  PhotoCropTests.swift
//  BlockPartyTests — Adjust's arithmetic (BP app backlog 32): where a photo sits in its frame, as a part of the photo.
//

import XCTest
@testable import BlockParty

final class PhotoCropTests: XCTestCase {
    private func near(_ a: CGRect, _ b: CGRect, _ line: UInt = #line) {
        for (x, y) in [(a.minX, b.minX), (a.minY, b.minY), (a.width, b.width), (a.height, b.height)] {
            XCTAssertEqual(x, y, accuracy: 0.001, "\(a) vs \(b)", line: line)
        }
    }

    func testTheMiddleIsWhatEveryPhotoGotBefore() {
        // A tall phone photo in a square: its middle square.
        near(PhotoCrop.middle(of: CGSize(width: 1000, height: 2000), aspect: 1), CGRect(x: 0, y: 0.25, width: 1, height: 0.5))
        // A wide photo in a circle: its middle square.
        near(PhotoCrop.middle(of: CGSize(width: 1600, height: 1000), aspect: 1), CGRect(x: 0.1875, y: 0, width: 0.625, height: 1))
        // Already the frame's shape: all of it.
        near(PhotoCrop.middle(of: CGSize(width: 800, height: 1000), aspect: 0.8), CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testFillingTheFrameIsTheLeastZoom() {
        XCTAssertEqual(PhotoCrop.fill(CGSize(width: 1000, height: 2000), frame: CGSize(width: 400, height: 400)), 0.4)
        XCTAssertEqual(PhotoCrop.fill(CGSize(width: 2000, height: 1000), frame: CGSize(width: 400, height: 300)), 0.3)
    }

    func testTheCropFollowsTheScroll() {
        let image = CGSize(width: 1000, height: 2000), frame = CGSize(width: 400, height: 500)
        let inset = UIEdgeInsets(top: 130, left: 0, bottom: 244, right: 0)
        // At the least zoom, scrolled to the top: the photo's top 500 / 0.4 = 1250 of 2000.
        near(PhotoCrop.crop(image: image, frame: frame, zoom: 0.4, offset: CGPoint(x: 0, y: -130), inset: inset),
             CGRect(x: 0, y: 0, width: 1, height: 0.625))
        // Twice that, moved right and down 100 pt.
        near(PhotoCrop.crop(image: image, frame: frame, zoom: 0.8, offset: CGPoint(x: 100, y: -30), inset: inset),
             CGRect(x: 0.125, y: 0.0625, width: 0.5, height: 0.3125))
    }

    func testPlacingACropAndReadingItBackGivesTheSameCrop() {
        let image = CGSize(width: 1600, height: 1060), frame = CGSize(width: 362, height: 362)
        let inset = UIEdgeInsets(top: 256, left: 20, bottom: 256, right: 20)
        let face = CGRect(x: 0.5, y: 0.05, width: 0.4, height: 0.4 * 1600 / 1060)
        let at = PhotoCrop.place(face, image: image, frame: frame, inset: inset)
        near(PhotoCrop.crop(image: image, frame: frame, zoom: at.zoom, offset: at.offset, inset: inset), face)
    }

    func testPlacingNeverZoomsPastTheLimitsOrLeavesThePhoto() {
        let image = CGSize(width: 1000, height: 1000), frame = CGSize(width: 400, height: 400)
        // A crop smaller than 5x allows is shown at 5x.
        XCTAssertEqual(PhotoCrop.place(CGRect(x: 0.45, y: 0.45, width: 0.01, height: 0.01), image: image, frame: frame, inset: .zero).zoom,
                       0.4 * PhotoCrop.maxZoom, accuracy: 0.0001)
        // A crop hanging off the corner comes back inside.
        let at = PhotoCrop.place(CGRect(x: 0.9, y: 0.9, width: 0.5, height: 0.5), image: image, frame: frame, inset: .zero)
        near(PhotoCrop.crop(image: image, frame: frame, zoom: at.zoom, offset: at.offset, inset: .zero), CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
    }

    func testAShapeChangeKeepsTheMiddleAndTakesTheNewShape() {
        let image = CGSize(width: 1000, height: 2000)
        // A 4:5 crop low in a tall photo, turned square: same middle, the same width, square.
        let tall = CGRect(x: 0.2, y: 0.5, width: 0.6, height: 0.6 * 1000 / 2000 * 1.25)
        let square = PhotoCrop.fit(tall, image: image, aspect: 1)
        XCTAssertEqual(square.width * image.width, square.height * image.height, accuracy: 0.5)
        XCTAssertEqual(square.midX, tall.midX, accuracy: 0.001)
        XCTAssertEqual(square.midY, tall.midY, accuracy: 0.001)
    }

    func testTheCutIsTheCropAndStaysUpright() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100)).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            UIColor.blue.setFill(); ctx.fill(CGRect(x: 100, y: 0, width: 100, height: 100))
        }
        let right = PhotoCrop.cut(image, to: CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
        XCTAssertEqual(right.size, CGSize(width: 100, height: 100))
        XCTAssertEqual(rgb(right), [0, 0, 255])
        XCTAssertEqual(rgb(PhotoCrop.cut(image, to: CGRect(x: 0, y: 0, width: 0.5, height: 1))), [255, 0, 0])
    }

    /// The whole picture averaged into one RGB pixel.
    private func rgb(_ image: UIImage) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image.cgImage!, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return Array(px.prefix(3))
    }
}
