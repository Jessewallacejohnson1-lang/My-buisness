//
//  YourCodeTests.swift
//  BlockPartyTests — what Your code holds and what a scanned or opened link names (`YourCode`, BP
//  app docs/plans/friends, ticket 07). A scanned code is anyone's words, so only a Block Party
//  link with a real id names a neighbour.
//

import CoreImage
import XCTest
@testable import BlockParty

final class YourCodeTests: XCTestCase {

    private let id = "6f1c2a9e-3b4d-4e8f-9a1b-2c3d4e5f6a7b"

    func testYourLinkIsTheAppLink() {
        XCTAssertEqual(YourCode.link(for: id).absoluteString, "blockparty://neighbor/\(id)")
        XCTAssertEqual(YourCode.link(for: id.uppercased()).absoluteString, "blockparty://neighbor/\(id)")
    }

    func testYourLinkNamesYou() {
        XCTAssertEqual(YourCode.userID(from: YourCode.link(for: id)), id)
        XCTAssertEqual(YourCode.userID(from: "blockparty://neighbor/\(id.uppercased())"), id)
        XCTAssertEqual(YourCode.userID(from: " blockparty://neighbor/\(id)\n"), id)
    }

    /// The website's form, for when app links are on (BP app backlog 10).
    func testTheWebsitesLinkNamesThemToo() {
        XCTAssertEqual(YourCode.userID(from: "https://blockpartymn.com/n/\(id)"), id)
        XCTAssertEqual(YourCode.userID(from: "https://www.blockpartymn.com/n/\(id)"), id)
    }

    func testAnythingElseNamesNobody() {
        for words in [
            "https://blockpartymn.com",
            "https://blockpartymn.com/n/",
            "https://blockpartymn.com/x/\(id)",
            "https://evil.com/n/\(id)",
            "http://blockpartymn.com/n/\(id)",
            "https://blockpartymn.com.evil.com/n/\(id)",
            "blockparty://event/\(id)",
            "blockparty://neighbor/not-an-id",
            "blockparty://neighbor/\(id)/more",
            "otherapp://neighbor/\(id)",
            "WIFI:S:Cafe;T:WPA;P:secret;;",
            "",
        ] {
            XCTAssertNil(YourCode.userID(from: words), words)
        }
    }

    /// The picture says your link back to a reader, framed in white for sharing.
    func testTheCodeReadsBackAsYourLink() throws {
        let link = YourCode.link(for: id)
        let picture = try XCTUnwrap(YourCode.image(for: link, scale: 12, margin: 4))
        let image = try XCTUnwrap(CIImage(image: picture))
        let reader = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                              options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let codes = reader.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        XCTAssertEqual(codes, [link.absoluteString])
        XCTAssertEqual(picture.size.width, picture.size.height)
        XCTAssertEqual(Int(picture.size.width) % 12, 0, "whole pixels a module, so it stays sharp")
    }
}
