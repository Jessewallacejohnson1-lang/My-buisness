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

    private func event(
        imageUrl: String?,
        rsvpd: Bool = true,
        category: EventCategory = .outdoors
    ) -> UpcomingEvent {
        UpcomingEvent(
            id: "event-1",
            title: "Neighborhood walk",
            eventDate: "2033-05-18",
            startTime: "7:00 PM",
            location: "Millstream Park",
            goingCount: 12,
            createdAt: "2033-05-01T12:00:00Z",
            imageUrl: imageUrl,
            rsvpd: rsvpd,
            clubName: "Wobegon Walkers",
            category: category
        )
    }
}
