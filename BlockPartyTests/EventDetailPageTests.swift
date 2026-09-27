//
//  EventDetailPageTests.swift
//  BlockPartyTests — what the event page is handed, and what it starts from.
//
//  Town and Your Day open the one event page from a `FeedCardItem`. These pin the
//  Your Day conversion and the page model's seed. Both are pure, with no network.
//

import XCTest
@testable import BlockParty

@MainActor
final class EventDetailPageTests: XCTestCase {

    private static let photoURL = URL(string: "https://example.com/walk.jpg")!

    func testUpcomingEventBecomesFeedCardItem() {
        let item = FeedCardItem(event(imageUrl: Self.photoURL.absoluteString))

        XCTAssertEqual(item.id, "event-1")
        XCTAssertEqual(item.title, "Neighborhood walk")
        XCTAssertTrue(item.isJoined, "rsvpd becomes isJoined")
        XCTAssertEqual(item.goingCount, 12)
        XCTAssertEqual(item.category, .outdoors)
        XCTAssertEqual(item.hostName, "Wobegon Walkers", "the club is the host")
        XCTAssertEqual(item.image, .eventPhoto(Self.photoURL))
        XCTAssertNil(item.description, "Your Day events carry no description, so About hides")

        // No photo of its own: the venue is looked up, the title only a hint.
        let noPhoto = FeedCardItem(event(imageUrl: nil))
        XCTAssertEqual(noPhoto.image, .venueLookup(name: "Millstream Park", hint: "Neighborhood walk"))

        // `.other` is the fallback for a null column, not a category: nothing fills in.
        XCTAssertNil(FeedCardItem(event(imageUrl: nil, category: .other)).category)
    }

    func testPhotoListPutsEventPhotoFirstDedupesAndCapsAtThree() {
        let event = FeedCardImageSource.eventPhoto(Self.photoURL)
        let venue = FeedCardImageSource.placesPhoto(Self.url("park"), attribution: "Ada Lovelace")
        let page = FeedEventDetailDestination.self

        XCTAssertEqual(page.photoList(event: event, venue: [venue]), [event, venue],
                       "the event's own photo leads, the venue's follows")
        XCTAssertEqual(page.photoList(event: .venueLookup(name: "Millstream Park", hint: nil), venue: [venue]),
                       [venue], "an unresolved lookup is not a photo")
        XCTAssertEqual(page.photoList(event: event, venue: [.placesPhoto(Self.photoURL, attribution: "Ada")]),
                       [event], "the same picture twice is shown once")

        let more = (1...3).map { FeedCardImageSource.eventPhoto(Self.url("\($0)")) }
        XCTAssertEqual(page.photoList(event: event, venue: more), [event, more[0], more[1]],
                       "four photos stop at three")
        XCTAssertEqual(page.photoList(event: .fallback, venue: []), [])
    }

    func testAPhotoThatFailsToLoadLeavesTheListAndTheCounter() {
        let event = FeedCardImageSource.eventPhoto(Self.photoURL)
        let venue = FeedCardImageSource.placesPhoto(Self.url("park"), attribution: "Ada Lovelace")
        let page = FeedEventDetailDestination.self

        let list = page.photoList(event: event, venue: [venue], failed: [Self.url("park")])
        XCTAssertEqual(list, [event], "a venue photo that failed is dropped, not left as a skeleton")
        XCTAssertNil(page.counterText(page: 0, count: list.count), "one photo left, no counter")
        XCTAssertEqual(page.photoList(event: event, venue: [], failed: [Self.photoURL]), [],
                       "nothing loaded, no hero")
    }

    func testPlacesPhotoDownloadCarriesTheBundleHeader() throws {
        // The key is restricted to this app's bundle id, which Google reads from this
        // header; without it every photo download is a 403. No real key here.
        let media = URL(string: "https://places.googleapis.com/v1/places/abc/photos/def/media?maxWidthPx=400")!
        let request = GooglePlacesService.mediaRequest(for: media)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Ios-Bundle-Identifier"),
                       try XCTUnwrap(Bundle.main.bundleIdentifier))

        XCTAssertNil(GooglePlacesService.mediaRequest(for: Self.photoURL).value(forHTTPHeaderField: "X-Ios-Bundle-Identifier"),
                     "only Google gets the header")
    }

    func testCounterShowsOnlyForTwoOrMorePhotos() {
        let page = FeedEventDetailDestination.self

        XCTAssertNil(page.counterText(page: 0, count: 0))
        XCTAssertNil(page.counterText(page: 0, count: 1), "one photo has nothing to count")
        XCTAssertEqual(page.counterText(page: 0, count: 2), "1/2")
        XCTAssertEqual(page.counterText(page: 1, count: 3), "2/3")
    }

    func testEmptyFieldsHideTheirRows() {
        let page = FeedEventDetailDestination.self

        XCTAssertNil(page.aboutText(nil))
        XCTAssertNil(page.aboutText(" \n\t "), "whitespace is not an About")
        XCTAssertEqual(page.aboutText("  Bring a chair.\n"), "Bring a chair.")

        XCTAssertNil(page.categoryText(nil))
        XCTAssertNil(page.categoryText(.other), "never an Other row")
        XCTAssertEqual(page.categoryText(.outdoors), "Outdoors")

        XCTAssertEqual(page.placeText(FeedCardItem(event(imageUrl: nil))), "Millstream Park")
        XCTAssertNil(page.placeText(FeedCardItem(event(imageUrl: nil, location: nil))), "no location, no pill")
        XCTAssertNil(page.placeText(FeedCardItem(event(imageUrl: nil, location: "  "))))
    }

    func testDetailModelSeedsFromCardItem() {
        let model = FeedEventDetailModel(item: FeedCardItem(event(imageUrl: Self.photoURL.absoluteString)))

        XCTAssertTrue(model.isGoing, "isJoined becomes isGoing")
        XCTAssertEqual(model.goingCount, 12)
        XCTAssertEqual(model.organizerImageURL, Self.photoURL)

        // A venue lookup is not the organizer's photo.
        let venueOnly = FeedEventDetailModel(item: FeedCardItem(event(imageUrl: nil, rsvpd: false)))
        XCTAssertFalse(venueOnly.isGoing)
        XCTAssertNil(venueOnly.organizerImageURL)
    }

    private static func url(_ name: String) -> URL {
        URL(string: "https://example.com/\(name).jpg")!
    }

    private func event(
        imageUrl: String?,
        rsvpd: Bool = true,
        location: String? = "Millstream Park",
        category: EventCategory = .outdoors
    ) -> UpcomingEvent {
        UpcomingEvent(
            id: "event-1",
            title: "Neighborhood walk",
            eventDate: "2033-05-18",
            startTime: "7:00 PM",
            location: location,
            goingCount: 12,
            createdAt: "2033-05-01T12:00:00Z",
            imageUrl: imageUrl,
            rsvpd: rsvpd,
            clubName: "Wobegon Walkers",
            category: category
        )
    }
}
