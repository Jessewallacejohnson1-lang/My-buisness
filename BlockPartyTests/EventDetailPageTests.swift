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

    /// A place Google can't be asked about (no `KnownVenues` anchor) is a known "no
    /// photo" at once, so the page starts without a hero instead of a skeleton.
    func testAVenueWithNoAnchorIsKnownToHaveNoPhoto() {
        let known = FeedCardVenuePhoto.known(name: "Somebody's back yard", hint: "Garage sale")
        XCTAssertNotNil(known, "known without a lookup")
        XCTAssertNil(known.flatMap { $0 }, "and known to have no photo")
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

    /// Signed out, a Join fails before any network (a Town fixture always does). It
    /// still shows "Going" for `rollbackFloor`, so the turn back reads as deliberate,
    /// then returns count and all. Join lands first; only then does it count one failed
    /// rollback (the page shakes the button on it, with the error buzz), so the shake
    /// never runs over the two labels cross-fading. A tap during the shake joins again
    /// at once; a tap between the turn back and the shake cancels that shake. A tap
    /// while it waits goes straight back to Join, and is no failure to shake about.
    func testAFailedJoinHoldsGoingThenRollsBack() async throws {
        let model = FeedEventDetailModel(item: FeedCardItem(event(imageUrl: nil, rsvpd: false)), auth: AuthStore())

        var tapped = ContinuousClock.now
        model.toggleGoing()
        XCTAssertTrue(model.isGoing, "Going at once")
        XCTAssertEqual(model.goingCount, 13)
        XCTAssertEqual(model.failedRollbacks, 0, "nothing has failed yet")

        try await waitWhile(model.isGoing)
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - tapped, FeedEventDetailModel.rollbackFloor,
                                    "turned back before it could be seen")
        XCTAssertFalse(model.isGoing, "a failed Join turns back")
        XCTAssertEqual(model.goingCount, 12)
        XCTAssertEqual(model.failedRollbacks, 0, "Join first: no shake while it turns back")

        let flipped = ContinuousClock.now
        try await waitWhile(model.failedRollbacks == 0)
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - flipped, .seconds(FeedEventDetailModel.flip) - .milliseconds(40),
                                    "the shake waits for Join to land")
        XCTAssertEqual(model.failedRollbacks, 1, "then the turn back counts as a failure: one shake")

        // Straight away, while the shake is running: the tap acts at once.
        tapped = ContinuousClock.now
        model.toggleGoing()
        XCTAssertTrue(model.isGoing, "a tap during the shake shows Going at once")
        XCTAssertEqual(model.goingCount, 13)
        try await waitWhile(model.isGoing)
        XCTAssertEqual(model.failedRollbacks, 1, "Join is back, its shake not yet due")

        // A tap between that turn back and its shake: Going at once, and no shake for it.
        model.toggleGoing()
        XCTAssertTrue(model.isGoing, "a tap before the shake shows Going at once")
        try await waitWhile(model.isGoing)
        try await waitWhile(model.failedRollbacks == 1)
        XCTAssertEqual(model.failedRollbacks, 2, "only the Join that ran its course shakes")

        model.toggleGoing()
        try await Task.sleep(for: .milliseconds(50))
        model.toggleGoing()
        XCTAssertFalse(model.isGoing, "a tap during the wait shows Join at once")
        XCTAssertEqual(model.goingCount, 12)
        try await Task.sleep(for: FeedEventDetailModel.rollbackFloor * 2)
        XCTAssertFalse(model.isGoing, "and nothing flips it back to Going")
        XCTAssertEqual(model.goingCount, 12)
        XCTAssertEqual(model.failedRollbacks, 2, "a turn back the neighbour asked for does not shake")
    }

    /// Popped mid-rollback: the failed Join makes no shake and no buzz on the screen
    /// underneath.
    func testAClosedPageNeverShakesAfterAFailedJoin() async throws {
        let model = FeedEventDetailModel(item: FeedCardItem(event(imageUrl: nil, rsvpd: false)), auth: AuthStore())

        model.toggleGoing()
        model.pageClosed()
        try await Task.sleep(for: FeedEventDetailModel.rollbackFloor + .seconds(FeedEventDetailModel.flip) + .milliseconds(300))
        XCTAssertEqual(model.failedRollbacks, 0, "no shake, and so no buzz, once the page has gone")
    }

    /// Polls every 10 ms until `condition` is false, for at most 5 s.
    private func waitWhile(_ condition: @autoclosure () -> Bool) async throws {
        let start = ContinuousClock.now
        while condition(), ContinuousClock.now - start < .seconds(5) {
            try await Task.sleep(for: .milliseconds(10))
        }
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
