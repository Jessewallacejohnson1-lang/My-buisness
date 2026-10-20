//
//  EventDetailPageTests.swift
//  BlockPartyTests — what the event page is handed, and what it starts from.
//
//  Town and Your Day open the one event page from a `FeedCardItem`. These pin the
//  Your Day conversion and the page's pure rules, with no network. Its Join is
//  `RealLifeActions`', tested in RealLifeActionsTests.
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
        XCTAssertNil(item.description, "an event without the organizer's words has no About")

        var described = event(imageUrl: nil)
        described.description = "Bring water and a hat."
        XCTAssertEqual(FeedCardItem(described).description, "Bring water and a hat.", "its words are the About")

        // No photo of its own and no saved place picture: ink. Nothing is looked up.
        let noPhoto = FeedCardItem(event(imageUrl: nil))
        XCTAssertEqual(noPhoto.image, .fallback)
        XCTAssertNil(noPhoto.place)

        // `.other` is the fallback for a null column, not a category: nothing fills in.
        XCTAssertNil(FeedCardItem(event(imageUrl: nil, category: .other)).category)
    }

    /// Where it happens, as the feeds send it (`public.place_picture`): its saved photo
    /// with the site or the author that credits it, else its logo on its backdrop.
    func testThePlacesPictureIsTheCardsWhenTheEventHasNone() {
        let site = URL(string: "https://www.stjosephmn.gov/")!
        let photo = PlacePicture(url: Self.url("hall"), kind: .photo, site: site)
        var withPhoto = event(imageUrl: nil)
        withPhoto.placePicture = photo
        let card = FeedCardItem(withPhoto)
        XCTAssertEqual(card.image, .placePhoto(Self.url("hall"), credit: "stjosephmn"), "its site, without www. or .gov")
        XCTAssertEqual(card.image.attribution, "stjosephmn")

        let commons = PlacePicture(url: Self.url("abbey"), kind: .photo, credit: "Bobak Ha'Eri · CC BY 3.0", site: site)
        XCTAssertEqual(commons.creditLine, "Bobak Ha'Eri · CC BY 3.0", "a free photo names its author, not the site")

        // Its own photo leads; the place's photo is the page's second.
        var both = event(imageUrl: Self.photoURL.absoluteString)
        both.placePicture = photo
        let bothCard = FeedCardItem(both)
        XCTAssertEqual(bothCard.image, .eventPhoto(Self.photoURL))
        XCTAssertEqual(bothCard.place, card.image)

        var withLogo = event(imageUrl: nil)
        withLogo.placePicture = PlacePicture(url: Self.url("sals"), kind: .logo, hue: 7)
        let logo = FeedCardItem(withLogo).image.logo
        XCTAssertEqual(logo?.url, Self.url("sals"))
        XCTAssertEqual(logo?.hue, 7)
        XCTAssertEqual(logo?.chroma, true)
        XCTAssertNil(FeedCardItem(withLogo).image.url, "a logo is not a photo")
        XCTAssertNil(PlacePicture(url: Self.url("x"), kind: .logo).creditLine, "a logo has no credit")
        withLogo.placePicture = PlacePicture(url: Self.url("grey"), kind: .logo)
        XCTAssertEqual(FeedCardItem(withLogo).image.logo?.chroma, false, "no hue: a grey backdrop")
    }

    /// A picture that doesn't decode costs only the picture, never the feed, and a feed
    /// kept from before the place picture still reads.
    func testTheFeedsSendThePlacesPictureAndABadOneCostsNothing() throws {
        let feed = """
        [{"id":"e1","title":"City Council Meeting","event_date":"2026-10-19","start_time":"6 PM",
          "location":null,"image_url":null,"category":null,"club_name":null,"source_name":"City of St. Joseph",
          "end_at":null,"all_day":false,"created_at":"2026-10-06T16:08:20+00:00","going_count":0,
          "rsvpd":false,"recurrence":null,"leaves_at":"2026-10-20T01:00:00+00:00",
          "place_picture":{"url":"https://example.com/joetown.webp","kind":"logo","hue":24},
          "description":"Open to the public."},
         {"id":"e2","title":"Bake sale","event_date":"2026-10-21","start_time":null,
          "location":null,"image_url":null,"category":null,"club_name":null,"source_name":"City of St. Joseph",
          "end_at":null,"all_day":false,"created_at":"2026-10-06T16:08:20+00:00","going_count":0,
          "rsvpd":false,"recurrence":null,"leaves_at":"2026-10-22T05:00:00+00:00",
          "place_picture":{"kind":"poster"}},
         {"id":"e3","title":"Fall Festival","event_date":"2026-10-21","start_time":null,
          "location":null,"image_url":null,"category":null,"club_name":null,"source_name":"City of St. Joseph",
          "end_at":null,"all_day":false,"created_at":"2026-10-06T16:08:20+00:00","going_count":0,
          "rsvpd":false,"recurrence":null,"leaves_at":"2026-10-22T05:00:00+00:00"}]
        """
        let rows = try CommunityAPI.townFeedRows(from: Data(feed.utf8))
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].event.placePicture?.kind, .logo)
        XCTAssertEqual(rows[0].event.placePicture?.hue, 24)
        XCTAssertNil(rows[1].event.placePicture, "an unreadable picture is none")
        XCTAssertNil(rows[2].event.placePicture, "a kept feed from before has none")
        XCTAssertEqual(rows[0].event.description, "Open to the public.")
        XCTAssertNil(rows[2].event.description, "a kept feed from before the description still reads")

        let going = """
        [{"id":"e1","title":"Plant Bingo","event_date":"2026-10-24","start_time":"4 PM",
          "location":"Milk & Honey Ciders","image_url":null,"category":null,"club_name":null,
          "source_name":"Milk & Honey Ciders","end_at":null,"all_day":false,
          "created_at":"2026-10-06T16:08:20+00:00","going_count":1,
          "place_picture":{"url":"https://example.com/orchard.webp","kind":"photo","credit":null,
                           "site":"https://www.milkandhoneyciders.com/events"},
          "description":"Plant bingo for Angel Reins Stable."}]
        """
        let event = try XCTUnwrap(CommunityAPI.myGoingRows(from: Data(going.utf8)).first)
        XCTAssertEqual(FeedCardItem(event).image.attribution, "milkandhoneyciders")
        XCTAssertEqual(FeedCardItem(event).description, "Plant bingo for Angel Reins Stable.", "the You tab's page has its About")
    }

    func testPhotoListPutsEventPhotoFirstDedupesAndCapsAtThree() {
        let event = FeedCardImageSource.eventPhoto(Self.photoURL)
        let venue = FeedCardImageSource.placePhoto(Self.url("park"), credit: "Ada Lovelace")
        let page = FeedEventDetailDestination.self

        XCTAssertEqual(page.photoList(event: event, venue: [venue]), [event, venue],
                       "the event's own photo leads, the venue's follows")
        let logo = FeedCardItem({ var e = self.event(imageUrl: nil)
            e.placePicture = PlacePicture(url: Self.url("sals"), kind: .logo); return e }()).image
        XCTAssertEqual(page.photoList(event: logo, venue: [venue]), [venue], "a logo is not a photo")
        XCTAssertEqual(page.photoList(event: event, venue: [.placePhoto(Self.photoURL, credit: "Ada")]),
                       [event], "the same picture twice is shown once")

        let more = (1...3).map { FeedCardImageSource.eventPhoto(Self.url("\($0)")) }
        XCTAssertEqual(page.photoList(event: event, venue: more), [event, more[0], more[1]],
                       "four photos stop at three")
        XCTAssertEqual(page.photoList(event: .fallback, venue: []), [])
    }

    func testAPhotoThatFailsToLoadLeavesTheListAndTheCounter() {
        let event = FeedCardImageSource.eventPhoto(Self.photoURL)
        let venue = FeedCardImageSource.placePhoto(Self.url("park"), credit: "Ada Lovelace")
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

    /// The page's hero (420.33 pt on iPhone Air) asks for the same decode as its card
    /// (420 pt), so the photo is decoded once and cached once.
    func testThePageHeroSharesItsCardsDecodeWidth() {
        XCTAssertEqual(FeedCardURLPhoto.pixelWidth(points: 420 + 1.0 / 3, scale: 3), 1260)
        XCTAssertEqual(FeedCardURLPhoto.pixelWidth(points: 420, scale: 3), 1260)
        XCTAssertEqual(FeedCardURLPhoto.pixelWidth(points: 32, scale: 3), 96, "an avatar is unchanged")
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

    /// Report photo opens the neighbour's own mail app with an email to Block Party naming the
    /// place and the exact photo, so the place-photos skill's retire step needs nothing else
    /// (BP app place-photos 06). A name with "&" in it stays in the subject.
    func testAReportedPhotoMailsUsThePlaceAndTheExactPhoto() throws {
        let photo = URL(string: "https://x.supabase.co/storage/v1/object/public/places/st-joseph/flour/photo-ab12.webp")!
        let mail = PhotoReport(place: "Flour & Flower", photo: photo).mail
        let parts = try XCTUnwrap(URLComponents(url: mail, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(parts.scheme, "mailto")
        XCTAssertEqual(parts.path, "contact@blockpartyapp.com")
        XCTAssertEqual(query["subject"], "Photo of Flour & Flower")
        XCTAssertEqual(query["body"], "Please take this photo off Block Party:\n\(photo.absoluteString)")
        XCTAssertEqual(query.count, 2, "the & in the name doesn't split the subject")

        XCTAssertEqual(
            URLComponents(url: PhotoReport(place: nil, photo: photo).mail, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "subject" }?.value,
            "A photo on Block Party", "no place name, still a subject")
    }

    /// Only a photo Block Party saved of a place can be reported here; the event's own photo,
    /// a logo and ink can't.
    func testOnlyASavedPlacePhotoCanBeReported() {
        let photo = Self.url("place")
        XCTAssertEqual(FeedCardImageSource.placePhoto(photo, credit: "krewemn.com").report(place: "Krewe"),
                       PhotoReport(place: "Krewe", photo: photo))
        XCTAssertNil(FeedCardImageSource.eventPhoto(photo).report(place: "Krewe"))
        XCTAssertNil(FeedCardImageSource.fallback.report(place: "Krewe"))
        XCTAssertNil(FeedCardImageSource.placeLogo(PlacePicture(url: photo, kind: .logo)).report(place: "Krewe"))
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
