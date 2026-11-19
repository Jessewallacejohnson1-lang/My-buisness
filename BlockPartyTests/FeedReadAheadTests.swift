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
        func ahead(_ count: Int, after index: Int, screens: CGFloat = 2, height: CGFloat = 300) -> Range<Int> {
            // A photo card holds one photo; a short white one none.
            FeedReadAhead.ahead(count: count, after: index, width: 402, screens: screens) { _ in (height, height > 200 ? 1 : 0) }
        }
        XCTAssertEqual(ahead(20, after: 0), 1..<7)
        XCTAssertEqual(ahead(20, after: 0, height: 140), 1..<14)
        XCTAssertEqual(ahead(20, after: 0, screens: 1), 1..<4)
        XCTAssertEqual(ahead(5, after: 3), 4..<5)
        XCTAssertEqual(ahead(5, after: 4), 5..<5)
        // Before the column is measured the first cards ask from the top.
        XCTAssertEqual(ahead(20, after: -1), 0..<6)
        // Only the cards it reads ahead for are looked at.
        var looked: [Int] = []
        _ = FeedReadAhead.ahead(count: 100, after: 10, width: 402, screens: 2) { looked.append($0); return (300, 1) }
        XCTAssertEqual(looked, Array(11..<17))
    }

    /// A window stops at about 12 photos (Jesse's pick): Search's Around town fills two screens with seven blocks of
    /// five, but reads three. Rows with no photo (faces, logos) stop only at two screens.
    func testAWindowHoldsAboutTwelvePhotos() {
        XCTAssertEqual(FeedReadAhead.ahead(count: 20, after: 0, width: 402, screens: 2) { _ in (268, 5) }, 1..<4)
        XCTAssertEqual(FeedReadAhead.ahead(count: 40, after: 0, width: 402, screens: 2) { _ in (76, 0) }, 1..<24)
    }

    /// Around town's block: its first tile two squares tall, the four others square, a flyer whole; a tile with no
    /// photo asks for nothing (its logo is read up front).
    func testAnAroundTownBlocksPhotos() {
        let url = { (n: Int) in URL(string: "https://x/\(n).jpg")! }
        func tile(_ n: Int, _ photo: SearchItem.Photo?) -> SearchItem {
            SearchItem(id: "\(n)", kind: .business, name: "\(n)", photo: photo)
        }
        let picture = { (n: Int) in PlacePicture(url: url(n), kind: .photo) }
        let block = [tile(0, .saved(picture(0))), tile(1, .saved(picture(1))), tile(2, nil),
                     tile(3, .saved(picture(3))), tile(4, .saved(picture(4)))]
        let pictures = ExploreBlock.pictures(block, width: 404)
        XCTAssertEqual(pictures.photos.map(\.url), [url(0), url(1), url(3), url(4)])
        XCTAssertEqual(pictures.photos[0].box, CGSize(width: 400.0 / 3, height: 800.0 / 3 + 2))
        XCTAssertEqual(pictures.photos[1].box, CGSize(width: 400.0 / 3, height: 400.0 / 3))
        XCTAssertEqual(pictures.height, 800.0 / 3 + 4)
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
