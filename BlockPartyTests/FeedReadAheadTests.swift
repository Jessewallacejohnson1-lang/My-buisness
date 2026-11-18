//
//  FeedReadAheadTests.swift
//  BlockPartyTests — the Town feed asks for the pictures of the cards two screens below before they scroll on
//  (BP app tab-lag 03): how many cards that is, what each card asks for, and when a bitmap read ahead serves.
//

import XCTest
@testable import BlockParty

@MainActor
final class FeedReadAheadTests: XCTestCase {
    /// Two screens of a 402 pt column (iPhone 16 Pro): six 300 pt photo cards, or thirteen short white ones; one
    /// screen with Low Data Mode; near the list's end, what's left.
    func testTwoScreensBelow() {
        let photos = [CGFloat](repeating: 300, count: 20), white = [CGFloat](repeating: 140, count: 20)
        XCTAssertEqual(FeedReadAhead.ahead(photos, after: 0, width: 402, screens: 2), 1..<7)
        XCTAssertEqual(FeedReadAhead.ahead(white, after: 0, width: 402, screens: 2), 1..<14)
        XCTAssertEqual(FeedReadAhead.ahead(photos, after: 0, width: 402, screens: 1), 1..<4)
        XCTAssertEqual(FeedReadAhead.ahead(Array(photos.prefix(5)), after: 3, width: 402, screens: 2), 4..<5)
        XCTAssertEqual(FeedReadAhead.ahead(Array(photos.prefix(5)), after: 4, width: 402, screens: 2), 5..<5)
        // Before the column is measured the first cards ask from the top.
        XCTAssertEqual(FeedReadAhead.ahead(photos, after: -1, width: 402, screens: 2), 0..<6)
    }

    /// A bitmap serves a frame it fills at its own size or larger (2% stretch at most); a flyer shown whole only has
    /// to fill one side.
    func testABitmapServesAFrameItFills() {
        XCTAssertTrue(FeedCardImageLoader.serves(width: 1110, height: 740, for: (1110, 740), fit: false))
        XCTAssertTrue(FeedCardImageLoader.serves(width: 1110, height: 740, for: (900, 600), fit: false))
        XCTAssertTrue(FeedCardImageLoader.serves(width: 1110, height: 740, for: (1120, 745), fit: false))
        XCTAssertFalse(FeedCardImageLoader.serves(width: 1110, height: 740, for: (1260, 840), fit: false))
        XCTAssertTrue(FeedCardImageLoader.serves(width: 600, height: 900, for: (1110, 900), fit: true))
        XCTAssertFalse(FeedCardImageLoader.serves(width: 600, height: 900, for: (1200, 1000), fit: true))
    }

    /// An Event card asks for its photo at the card's own shape, its host's logo and the faces going; with no photo,
    /// its place's logo.
    func testAnEventCardsPictures() {
        let photo = URL(string: "https://x/photo.jpg")!, logo = URL(string: "https://x/logo.png")!
        let face = URL(string: "https://x/face.jpg")!
        func card(_ image: FeedCardImageSource) -> FeedCardItem {
            FeedCardItem(id: "a", title: "a", dateChip: "", metaLine: "", image: image, recurrence: nil,
                         goingCount: 1, goingAvatars: [face], likeCount: 0, isLiked: false, isJoined: false)
        }
        var item = card(.placePhoto(photo, credit: nil, aspect: 1.5))
        item.hostPicture = PlacePicture(url: logo, kind: .logo)
        let pictures = FeedPictures.of(item, width: 370)
        XCTAssertEqual(pictures.photos, [.init(url: photo, box: CGSize(width: 370, height: 370 / 1.5))])
        XCTAssertEqual(pictures.logos, [logo])
        XCTAssertEqual(pictures.faces, [face])
        let white = FeedPictures.of(card(.placeLogo(PlacePicture(url: logo, kind: .logo))), width: 370)
        XCTAssertEqual(white.photos, [])
        XCTAssertEqual(white.logos, [logo])
    }
}
