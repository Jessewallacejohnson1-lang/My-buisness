//
//  SeveralPhotosTests.swift
//  Several photos in a post (BP app town-feed 46): the feed's later photos in order, New post's picks cut, sent and
//  taken out, and Instagram's dots under them.
//

import XCTest
@testable import BlockParty

@MainActor
final class SeveralPhotosTests: XCTestCase {
    /// A post row as `get_town_feed` sends it, its later photos in the poster column.
    private func postRow(_ more: String) -> String {
        """
        [{"id":"p1","title":"Millstream","location":null,"image_url":"https://x/event-images/u/p1.jpg",
          "created_at":"2026-10-08T14:00:00+00:00","leaves_at":"2099-10-15T14:00:00+00:00","kind":"post",
          "poster":{"id":"u1","name":"Avery","aspect":0.8\(more)}}]
        """
    }

    func testAPostsLaterPhotosComeInThePostersOrderAfterItsFirst() throws {
        let lines = try CommunityAPI.townFeedLines(from: Data(postRow(#","more_photos":["https://x/p1-3.jpg","https://x/p1-2.jpg"]"#).utf8))
        guard case .post(let post) = lines.first else { return XCTFail("\(lines)") }
        XCTAssertEqual(post.photos.map(\.absoluteString),
                       ["https://x/event-images/u/p1.jpg", "https://x/p1-3.jpg", "https://x/p1-2.jpg"])
        XCTAssertEqual(post.photoAspect, 0.8, "one shape for all, the first's")
    }

    func testAPostWithOnePhotoReadsAsBefore() throws {
        let lines = try CommunityAPI.townFeedLines(from: Data(postRow("").utf8))
        guard case .post(let post) = lines.first else { return XCTFail("\(lines)") }
        XCTAssertEqual(post.photos.map(\.absoluteString), ["https://x/event-images/u/p1.jpg"])
        XCTAssertEqual(post.morePhotos, [])
    }

    func testNewPostSendsTheFirstPhotoAsThePhotoAndTheRestInOrder() {
        var draft = NewPostDraft()
        draft.words = "Millstream"
        let input = draft.input(id: "p1", photos: ["https://x/p1.jpg", "https://x/p1-2.jpg", "https://x/p1-3.jpg"], aspect: 0.8)
        XCTAssertEqual(input.imageURL, "https://x/p1.jpg")
        XCTAssertEqual(input.morePhotos, ["https://x/p1-2.jpg", "https://x/p1-3.jpg"])
        XCTAssertEqual(input.aspect, 0.8)
        XCTAssertEqual(draft.input(id: "p1", photos: ["https://x/p1.jpg"], aspect: 1.5).morePhotos, [], "one photo sends none")
    }

    /// A tall photo is cut into 4:5 and saved as the JPEG that goes up, so New post shows its file as the card will.
    func testAPickedPhotoIsCutIntoTheLimitsAndSaved() throws {
        let tall = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 300)).image { _ in }
        let photo = try XCTUnwrap(PickedPhoto.make(tall, id: "a"))
        XCTAssertEqual(photo.aspect, 0.8)
        XCTAssertEqual(photo.id, "a")
        let saved = try XCTUnwrap(UIImage(contentsOfFile: photo.file.path))
        XCTAssertEqual(saved.size.width / saved.size.height, 0.8, accuracy: 0.02)
    }

    /// The first photo sets every photo's shape; the trash takes one out, and with the first gone the next sets it.
    /// Any change to the photos is a new post, so a retry never reuses files sent under the old id.
    func testTheFirstPhotoSetsTheShapeAndTheTrashTakesOneOut() {
        let model = NewPostModel()
        let wide = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200)).image { _ in }
        let tall = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 300)).image { _ in }
        let first = model.id
        model.use([wide, tall, tall])
        XCTAssertEqual(model.photos.count, 3)
        XCTAssertEqual(model.aspect, 1.5, accuracy: 0.01)
        XCTAssertTrue(model.ready, "photos alone are a post")
        XCTAssertNotEqual(model.id, first)
        let picked = model.id
        model.remove(at: 0)
        XCTAssertEqual(model.photos.count, 2)
        XCTAssertEqual(model.aspect, 0.8, accuracy: 0.01, "the next one sets it, inside 4:5")
        XCTAssertNotEqual(model.id, picked)
        model.remove(at: 5)
        XCTAssertEqual(model.photos.count, 2, "past the end takes nothing")
    }

    func testNewPostTakesTenPhotos() {
        let model = NewPostModel()
        let square = UIGraphicsImageRenderer(size: CGSize(width: 50, height: 50)).image { _ in }
        model.use(Array(repeating: square, count: 12))
        XCTAssertEqual(model.photos.count, NewPostDraft.photoLimit)
        XCTAssertEqual(NewPostDraft.photoLimit, 10)
    }

    /// Up to 5 photos, a full dot each; past 5, Instagram's window: three full, then 4.3 and 2 pt, the rest hidden,
    /// with seven slots so the full three stay centred.
    func testInstagramsDotsShrinkAtTheEndsPastFive() {
        XCTAssertEqual(EventPageDots.slots(count: 4, page: 2), [0, 1, 2, 3])
        XCTAssertEqual((0..<4).compactMap { EventPageDots.size($0, count: 4, page: 2) }, [6, 6, 6, 6])
        let first = EventPageDots.slots(count: 9, page: 0)
        XCTAssertEqual(first, [-2, -1, 0, 1, 2, 3, 4])
        XCTAssertEqual(first.map { EventPageDots.size($0, count: 9, page: 0) }, [nil, nil, 6, 6, 6, 4.3, 2])
        let middle = EventPageDots.slots(count: 9, page: 4)
        XCTAssertEqual(middle.map { EventPageDots.size($0, count: 9, page: 4) }, [2, 4.3, 6, 6, 6, 4.3, 2])
        let last = EventPageDots.slots(count: 9, page: 8)
        XCTAssertEqual(last.map { EventPageDots.size($0, count: 9, page: 8) }, [2, 4.3, 6, 6, 6, nil, nil])
        XCTAssertNil(EventPageDots.size(1, count: 10, page: 9), "far past the window: hidden")
    }
}
