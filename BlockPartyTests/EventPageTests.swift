//
//  EventPageTests.swift
//  BlockPartyTests — what the event page is handed, and what it starts from.
//
//  Town and Your Day open the one event page from a `FeedCardItem`. These pin the
//  Your Day conversion and the page's pure rules, with no network. Its Join is
//  `RealLifeActions`', tested in RealLifeActionsTests.
//

import SwiftUI
import UIKit
import XCTest
@testable import BlockParty

@MainActor
final class EventPageTests: XCTestCase {

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
        [{"id":"e1","recurrence":null,"leaves_at":"2026-10-20T01:00:00+00:00","card":{"id":"e1",
         "title":"City Council Meeting","event_date":"2026-10-19","start_time":"6 PM",
         "location":null,"image_url":null,"category":null,"club_name":null,"source_name":"City of St. Joseph",
         "end_at":null,"all_day":false,"created_at":"2026-10-06T16:08:20+00:00","going_count":0,
         "place_picture":{"url":"https://example.com/joetown.webp","kind":"logo","hue":24},
         "description":"Open to the public.","going":false}},
         {"id":"e2","recurrence":null,"leaves_at":"2026-10-22T05:00:00+00:00","card":{"id":"e2",
         "title":"Bake sale","event_date":"2026-10-21","start_time":null,"location":null,
         "image_url":null,"category":null,"club_name":null,"source_name":"City of St. Joseph",
         "end_at":null,"all_day":false,"created_at":"2026-10-06T16:08:20+00:00","going_count":0,
         "place_picture":{"kind":"poster"},"going":false}},
         {"id":"e3","recurrence":null,"leaves_at":"2026-10-22T05:00:00+00:00","card":{"id":"e3",
         "title":"Fall Festival","event_date":"2026-10-21","start_time":null,"location":null,
         "image_url":null,"category":null,"club_name":null,"source_name":"City of St. Joseph",
         "end_at":null,"all_day":false,"created_at":"2026-10-06T16:08:20+00:00","going_count":0,
         "going":false}}]
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
        [{"card":{"id":"e1","title":"Plant Bingo","event_date":"2026-10-24","start_time":"4 PM",
         "location":"Milk & Honey Ciders","image_url":null,"category":null,"club_name":null,
         "source_name":"Milk & Honey Ciders","end_at":null,"all_day":false,"created_at":"2026-10-06T16:08:20+00:00",
         "going_count":1,"place_picture":{"url":"https://example.com/orchard.webp",
         "kind":"photo","credit":null,"site":"https://www.milkandhoneyciders.com/events"},
         "description":"Plant bingo for Angel Reins Stable.","going":true}}]
        """
        let event = try XCTUnwrap(CommunityAPI.myGoingRows(from: Data(going.utf8)).first)
        XCTAssertEqual(FeedCardItem(event).image.attribution, "milkandhoneyciders")
        XCTAssertEqual(FeedCardItem(event).description, "Plant bingo for Angel Reins Stable.", "the You tab's page has its About")
    }

    /// A tall flyer starts under the clock, so the island never covers its title; a wide one sits with
    /// even gaps, on the Event page's 402 x 310 frame (Jesse, 2026-11-05).
    func testATallFlyerStartsUnderTheClockAndAWideOneDoesnt() {
        let room = CGSize(width: 402, height: 310)
        XCTAssertEqual(FeedCardURLPhoto.flyerTop(image: CGSize(width: 1254, height: 1568), room: room, top: 62), 62)
        XCTAssertEqual(FeedCardURLPhoto.flyerTop(image: CGSize(width: 1080, height: 1080), room: room, top: 62), 62)
        XCTAssertEqual(FeedCardURLPhoto.flyerTop(image: CGSize(width: 1600, height: 960), room: room, top: 62), 0)
        XCTAssertEqual(FeedCardURLPhoto.flyerTop(image: CGSize(width: 1254, height: 1568), room: room, top: 0), 0,
                       "the Block Party tab's cards start at their own top")
    }

    /// A flyer on the poster stops above the words, and pressing Attend doesn't move it: the going
    /// line's room is kept whether it shows or not (370 x 470 on a 402 pt phone).
    func testAPostersFlyerKeepsClearOfItsWordsAndAttendDoesntMoveIt() {
        let side: CGFloat = 370
        // 120 pt of words, the going line's 34, the Attend row's 16 + 38, the words' 15 + 15 and an 8 pt gap.
        let foot = EventOfTheDayPoster.wholeFoot(side: side, words: 120)
        XCTAssertEqual(foot, 470 - 120 - 34 - 54 - 30 - 8, accuracy: 0.01, "the same with Attend pressed or not")

        let stops = EventOfTheDayPoster.wholeFade(foot: foot, side: side)
        XCTAssertEqual(stops.first?.location ?? 0, foot / side, accuracy: 0.001, "clear down to the flyer's foot")
        XCTAssertEqual(stops.map(\.location), stops.map(\.location).sorted(), "a gradient's stops only go down")
        XCTAssertLessThanOrEqual(stops.last?.location ?? 2, 1)
    }

    /// A town card's flyer stops above its words, and they keep the shade today's card gives them.
    func testATownCardsFlyerKeepsItsWordsReadable() {
        let height: CGFloat = 300, words: CGFloat = 52
        let foot = DailyTownCard.wholeFoot(height: height, words: words)
        XCTAssertEqual(foot, 300 - 52 - 12 - 20, accuracy: 0.01)
        let stops = DailyTownCard.wholeShade(foot: foot, height: height, words: words)
        XCTAssertEqual(stops.map(\.location), stops.map(\.location).sorted())
        XCTAssertEqual(stops.first?.location ?? 0, foot / height, accuracy: 0.001)
        XCTAssertEqual(stops[1].location, (300 - 52 - 12) / 300, accuracy: 0.001, "as dark as today's card by the words' top")
    }

    /// The page shows the Event's own picture alone, and the place's photos no longer follow it
    /// (BP app inside-cards 15).
    func testThePageShowsOnlyTheEventsOwnPicture() {
        let event = FeedCardImageSource.eventPhoto(Self.photoURL)
        let venue = FeedCardImageSource.placePhoto(Self.url("park"), credit: "Ada Lovelace")
        let more = (1...3).map { FeedCardImageSource.eventPhoto(Self.url("\($0)")) }
        let page = EventPage.self

        XCTAssertEqual(page.photoList(event: event, venue: [venue]), [event], "the place's photo no longer follows")
        XCTAssertEqual(page.photoList(event: event, venue: more), [event])
        let logo = FeedCardItem({ var e = self.event(imageUrl: nil)
            e.placePicture = PlacePicture(url: Self.url("sals"), kind: .logo); return e }()).image
        XCTAssertEqual(page.photoList(event: logo, venue: [venue]), [venue],
                       "a logo is not a photo: an Event with none of its own shows the place's")
        XCTAssertEqual(page.photoList(event: .fallback, venue: []), [])
    }

    func testAFlyersPageShowsTheFlyerAlone() {
        var flyer = FeedCardItem({ var e = self.event(imageUrl: nil)
            e.placePicture = PlacePicture(url: Self.photoURL, kind: .photo, whole: true); return e }())
        flyer.placeMore = [.placePhoto(Self.url("park"), credit: nil)]
        XCTAssertTrue(flyer.whole)
        XCTAssertEqual(flyer.photos().compactMap(\.url), [Self.photoURL], "it doesn't swipe to the place's photo")
        XCTAssertEqual(flyer.photos(failed: [Self.photoURL]).compactMap(\.url), [Self.url("park")],
                       "a flyer that fails gives way to the place's photo")
    }

    func testAPictureThatFailsToLoadGivesWayToTheNext() {
        let event = FeedCardImageSource.eventPhoto(Self.photoURL)
        let venue = FeedCardImageSource.placePhoto(Self.url("park"), credit: "Ada Lovelace")
        let page = EventPage.self

        XCTAssertEqual(page.photoList(event: event, venue: [venue], failed: [Self.photoURL]), [venue],
                       "the place's photo takes its place, never a hole")
        XCTAssertEqual(page.photoList(event: event, venue: [.placePhoto(Self.photoURL, credit: "Ada")],
                                      failed: [Self.photoURL]), [],
                       "the same picture under another name has failed too")
        XCTAssertEqual(page.photoList(event: event, venue: [], failed: [Self.photoURL]), [],
                       "nothing loaded, no hero")
    }

    /// The page's hero (420.33 pt on iPhone Air) asks for the same decode as its card
    /// (420 pt), so the photo is decoded once and cached once.
    func testThePageHeroSharesItsCardsDecodeWidth() {
        XCTAssertEqual(FeedCardURLPhoto.pixelWidth(points: 420 + 1.0 / 3, scale: 3), 1260)
        XCTAssertEqual(FeedCardURLPhoto.pixelWidth(points: 420, scale: 3), 1260)
        XCTAssertEqual(FeedCardURLPhoto.pixelWidth(points: 32, scale: 3), 96, "an avatar is unchanged")
    }

    /// A photo fills its frame around where the eye goes (photo-focus): a face near a tall photo's
    /// top moves the photo down as far as its edge allows; the centre, and a photo already the
    /// frame's shape, move nothing.
    func testAPhotoFillsItsFrameAroundItsFocus() {
        // A 1000 × 2000 photo fills the 393 × 303 hero at 0.393: 393 × 786, 241.5 pt spare above and below.
        let tall = CGSize(width: 1000, height: 2000), hero = CGSize(width: 393, height: 303)
        XCTAssertEqual(FeedCardURLPhoto.offset(image: tall, box: hero, focus: .center), .zero)
        XCTAssertEqual(FeedCardURLPhoto.offset(image: tall, box: hero, focus: UnitPoint(x: 0.5, y: 0.3)).height,
                       157.2, accuracy: 0.001)
        XCTAssertEqual(FeedCardURLPhoto.offset(image: tall, box: hero, focus: .top).height, 241.5, accuracy: 0.001,
                       "never past the photo's top edge")
        XCTAssertEqual(FeedCardURLPhoto.offset(image: tall, box: hero, focus: UnitPoint(x: 0.9, y: 0.5)).width, 0,
                       "no room sideways")
        XCTAssertEqual(FeedCardURLPhoto.offset(image: hero, box: hero, focus: .topLeading), .zero)
    }

    /// Faces keep their own room in the photo cache (codebase-health 18): 13 photos and 50 faces,
    /// oldest first, drop the oldest photo and the two oldest faces, and nothing else.
    func testFacesAndPhotosEachKeepTheirNewest() {
        let sizes = Array(repeating: 1260, count: 25) + Array(repeating: 96, count: 50)
        XCTAssertEqual(FeedCardImageLoader.overflow(sizes).sorted(), [0, 25, 26])
        XCTAssertEqual(FeedCardImageLoader.overflow(Array(repeating: 288, count: 48)), [], "a 96 pt profile photo is a face")
        XCTAssertEqual(FeedCardImageLoader.overflow(Array(repeating: 1260, count: 24) + [96]), [])
    }

    /// Leaving keeps the six newest photos, for what coming back draws, and every face.
    func testLeavingKeepsTheNewestPhotosAndEveryFace() {
        let sizes = [96] + Array(repeating: 1260, count: 8) + [96]
        XCTAssertEqual(FeedCardImageLoader.droppedOnLeaving(sizes).sorted(), [1, 2])
        XCTAssertEqual(FeedCardImageLoader.droppedOnLeaving(Array(repeating: 1260, count: 6)), [])
        XCTAssertEqual(FeedCardImageLoader.droppedOnLeaving(Array(repeating: 96, count: 50)), [])
    }

    func testCounterShowsOnlyForTwoOrMorePhotos() {
        let page = EventPage.self

        XCTAssertNil(page.counterText(page: 0, count: 0))
        XCTAssertNil(page.counterText(page: 0, count: 1), "one photo has nothing to count")
        XCTAssertEqual(page.counterText(page: 0, count: 2), "1/2")
        XCTAssertEqual(page.counterText(page: 1, count: 3), "2/3")
    }

    /// A found event links its page under About as the Business page links: Facebook and Instagram
    /// by name, a site by its own, and no row for a neighbour's event (Jesse, 2026-10-27).
    func testFoundPageLinkRow() {
        let page = EventPage.self
        let row = { (s: String) in page.sourceLink(URL(string: s)) }

        XCTAssertEqual(row("https://www.milkandhoneyciders.com/events")?.text, "milkandhoneyciders.com")
        XCTAssertEqual(row("https://www.milkandhoneyciders.com/events")?.url.absoluteString,
                       "https://www.milkandhoneyciders.com/events", "opens the page it was found on")
        XCTAssertEqual(row("https://www.facebook.com/Wanderingcowicecream/posts/1")?.text, "Facebook")
        XCTAssertEqual(row("https://www.instagram.com/p/De-oNqKjGq5/")?.glyph, "camera")
        XCTAssertNil(page.sourceLink(nil))
        XCTAssertNil(row("mailto:a@b.c"))
    }

    func testEmptyFieldsHideTheirRows() {
        let page = EventPage.self

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

    /// The price line (inside-cards 14): one line under the place when a source says what it costs, as words;
    /// nothing when unknown, never a placeholder.
    func testThePriceLineShowsOnlyWhenKnown() {
        let page = EventPage.self
        XCTAssertNil(page.priceText(nil))
        XCTAssertNil(page.priceText(" \n"), "blank is unknown")
        XCTAssertEqual(page.priceText(" Free\n"), "Free")
        XCTAssertEqual(page.priceText("$22, $20 seniors, $15 students"), "$22, $20 seniors, $15 students")

        var priced = event(imageUrl: nil)
        priced.price = "$5 at the door"
        XCTAssertEqual(FeedCardItem(priced).price, "$5 at the door", "the card carries it to the page")
        XCTAssertNil(FeedCardItem(event(imageUrl: nil)).price)
    }

    /// The card sends the price (`private.event_cards`, inside-cards 14); a card from before the field says none.
    func testTheCardCarriesThePrice() throws {
        let card = """
        {"id":"e1","title":"Christmas at Saint John's","event_date":"2026-12-04","start_time":"7:30 PM",
         "location":"Abbey Church","image_url":null,"category":"music_arts","club_name":null,
         "source_name":"CSB SJU Campus Events","end_at":null,"all_day":false,"created_at":"2026-10-01T12:00:00+00:00",
         "going_count":0,"going":false,"heart_count":0,"hearted":false,"cancelled":false,"place_picture":null,
         "host_picture":null,"description":"The colleges' holiday tradition.","price":"$22, $20 seniors, $15 students",
         "what":"Concert","source_url":null,"game":null,"friends_going":[],"live_kind":true,"recurrence":null}
        """
        XCTAssertEqual(try Supabase.decode(Data(card.utf8), as: UpcomingEvent.self).price, "$22, $20 seniors, $15 students")
        let before = card.replacingOccurrences(of: #""price":"$22, $20 seniors, $15 students","#, with: "")
        XCTAssertNil(try Supabase.decode(Data(before.utf8), as: UpcomingEvent.self).price)
    }

    /// The day row (event-page-formats 06): the day in full over its hours, the end only when the
    /// Event gives one; its year only past six months; days it runs over, and words we can't read.
    func testTheDayRowSaysTheDayInFullOverItsHours() {
        let page = EventPage.self
        let now = Town.midnight("2026-10-30")!.addingTimeInterval(12 * 3600)
        let nov30 = Town.midnight("2026-11-30")!
        var item = FeedCardItem(event(imageUrl: nil))
        item.eventDate = "2026-11-30"
        let lines = { page.dayLines(item, now: now) }

        item.startTime = "4:30 PM"
        XCTAssertEqual(lines(), .init(first: "Monday, November 30", second: "4:30 PM"), "no end given, no end said")
        item.endAt = nov30.addingTimeInterval(18 * 3600)
        XCTAssertEqual(lines(), .init(first: "Monday, November 30", second: "4:30 – 6 PM"))
        XCTAssertEqual(lines()?.spoken, "Monday, November 30, 4:30 to 6 PM")
        item.startTime = "11 AM"
        item.endAt = nov30.addingTimeInterval(13 * 3600)
        XCTAssertEqual(lines()?.second, "11 AM – 1 PM")
        item.startTime = "9 PM"
        item.endAt = nov30.addingTimeInterval(25 * 3600)
        XCTAssertEqual(lines()?.second, "9 PM – 1 AM", "past midnight is still that night")
        item.startTime = "7 PM"
        item.endAt = nov30.addingTimeInterval((48 + 21) * 3600)
        XCTAssertEqual(lines()?.second, "7 PM until Wednesday, December 2")

        item.startTime = "after dark"
        item.endAt = nil
        XCTAssertEqual(lines(), .init(first: "Monday, November 30", second: "after dark"), "as written")
        item.startTime = nil
        item.allDay = true
        XCTAssertEqual(lines(), .init(first: "Monday, November 30"), "all day: the day alone")
        item.eventDate = "2026-11-16"
        item.endAt = Town.midnight("2026-11-26")
        XCTAssertEqual(lines(), .init(first: "Monday, November 16", second: "Until Wednesday, November 25"))

        item.eventDate = "2027-06-01"
        item.endAt = nil
        XCTAssertEqual(lines()?.first, "Tuesday, June 1, 2027")
    }

    /// The repeat left the card's small line for the day row, after the hours (BP app inside-cards 11).
    func testTheDayRowSaysHowItRepeatsAfterItsHours() {
        let now = Town.midnight("2026-11-01")!
        var repeating = event(imageUrl: nil)
        repeating.recurrence = "Every Sunday"
        var item = FeedCardItem(repeating)
        item.eventDate = "2026-11-08"
        item.startTime = "9 AM"
        XCTAssertEqual(EventPage.dayLines(item, now: now), .init(first: "Sunday, November 8", second: "9 AM · Every Sunday"))
        item.startTime = nil
        item.allDay = true
        XCTAssertEqual(EventPage.dayLines(item, now: now), .init(first: "Sunday, November 8", second: "Every Sunday"),
                       "no hours: the repeat alone")
    }

    /// The Event page's one date line (inside-cards 17): the short day, its hours, then the repeat, as
    /// Apple Invites writes "Sat, 8 Feb, 6:00–8:00 PM".
    func testTheDateLineIsOneLine() {
        let now = Town.midnight("2026-11-01")!
        let nov19 = Town.midnight("2026-11-19")!
        var item = FeedCardItem(event(imageUrl: nil))
        item.eventDate = "2026-11-19"
        item.startTime = "6 PM"
        item.endAt = nov19.addingTimeInterval(20 * 3600)
        XCTAssertEqual(EventPage.dateLine(item, now: now)?.oneLine, "Thu, Nov 19, 6 – 8 PM")
        XCTAssertEqual(EventPage.dateLine(item, now: now)?.spoken, "Thu, Nov 19, 6 to 8 PM")

        var repeating = event(imageUrl: nil)
        repeating.recurrence = "Every Sunday"
        var sunday = FeedCardItem(repeating)
        sunday.eventDate = "2026-11-08"
        sunday.startTime = "9 AM"
        XCTAssertEqual(EventPage.dateLine(sunday, now: now)?.oneLine, "Sun, Nov 8, 9 AM · Every Sunday")
        sunday.startTime = nil
        sunday.allDay = true
        XCTAssertEqual(EventPage.dateLine(sunday, now: now)?.oneLine, "Sun, Nov 8, Every Sunday", "no hours: the day, then the repeat")

        item.startTime = "after dark"
        item.endAt = nil
        XCTAssertEqual(EventPage.dateLine(item, now: now)?.oneLine, "Thu, Nov 19, after dark", "as written")
        item.startTime = nil
        item.allDay = true
        XCTAssertEqual(EventPage.dateLine(item, now: now)?.oneLine, "Thu, Nov 19", "all day: the day alone")
        item.endAt = Town.midnight("2026-11-26")
        XCTAssertEqual(EventPage.dateLine(item, now: now)?.oneLine, "Thu, Nov 19, until Wednesday, November 25")
        item.eventDate = "2027-06-01"
        item.endAt = nil
        XCTAssertEqual(EventPage.dateLine(item, now: now)?.oneLine, "Tue, Jun 1, 2027", "the year past six months off")
    }

    /// The Attend bar's day over its time while nobody's going (inside-cards 18), as the approved mock's "Thu, Nov 19"
    /// over "6 – 8 PM": the date line's words with no repeat (the line above says it), every day short to fit.
    func testTheBarsDayIsOverItsTime() {
        let now = Town.midnight("2026-11-01")!
        let nov19 = Town.midnight("2026-11-19")!
        var repeating = event(imageUrl: nil)
        repeating.recurrence = "Every Thursday"
        var item = FeedCardItem(repeating)
        item.eventDate = "2026-11-19"
        item.startTime = "6 PM"
        item.endAt = nov19.addingTimeInterval(20 * 3600)
        XCTAssertEqual(EventPage.barDay(item, now: now), .init(first: "Thu, Nov 19", second: "6 – 8 PM"), "no repeat")
        item.endAt = nil
        XCTAssertEqual(EventPage.barDay(item, now: now), .init(first: "Thu, Nov 19", second: "6 PM"), "no end: the start")
        item.startTime = "after dark"
        XCTAssertEqual(EventPage.barDay(item, now: now), .init(first: "Thu, Nov 19", second: "after dark"), "as written")
        item.startTime = nil
        item.allDay = true
        XCTAssertEqual(EventPage.barDay(item, now: now), .init(first: "Thu, Nov 19"), "all day: the day alone")
        item.endAt = Town.midnight("2026-11-26")
        XCTAssertEqual(EventPage.barDay(item, now: now), .init(first: "Thu, Nov 19", second: "until Wed, Nov 25"),
                       "over days: its last day short too")
        item.eventDate = "2027-06-01"
        item.endAt = nil
        XCTAssertEqual(EventPage.barDay(item, now: now), .init(first: "Tue, Jun 1, 2027"), "the year past six months off")
    }

    /// The big button's word: Facebook and Instagram by name, anything else Website.
    func testTheFoundPagesButtonSaysItsApp() {
        let page = EventPage.self
        XCTAssertEqual(page.sourceLink(URL(string: "https://www.facebook.com/x/posts/1")).map(page.linkWord), "Facebook")
        XCTAssertEqual(page.sourceLink(URL(string: "https://www.instagram.com/p/De/")).map(page.linkWord), "Instagram")
        XCTAssertEqual(page.sourceLink(URL(string: "https://www.milkandhoneyciders.com/events")).map(page.linkWord), "Website")
    }

    /// The page's colour is its picture's most common colourful hue, weighted by saturation squared: greys,
    /// near-blacks, near-whites and see-through pixels don't count, and a picture with no colour is grey.
    func testThePageTakesItsPicturesMostCommonColourfulHue() {
        func pixels(_ colours: [(UInt32, Int, UInt8)]) -> [UInt8] {
            colours.flatMap { rgb, count, alpha in
                Array(repeating: [UInt8(rgb >> 16 & 0xFF), UInt8(rgb >> 8 & 0xFF), UInt8(rgb & 0xFF), alpha], count: count).flatMap { $0 }
            }
        }
        // Mostly a dull blue (saturation 0.43, so each pixel counts 0.18), with a seventh as many fully saturated
        // reds (each counts 1): the blue's count carries it. Greys never count, however many.
        let sky = EventLook.dominant(pixels: pixels([(0x4060A0, 700, 255), (0xFF2020, 100, 255), (0x808080, 2000, 255)]))
        XCTAssertEqual(sky >> 16 & 0xFF, 0x40)
        XCTAssertEqual(sky & 0xFF, 0xA0)
        // Saturated reds a quarter as many as a pale blue win: 0.9² against 0.3².
        let red = EventLook.dominant(pixels: pixels([(0x8090A0, 400, 255), (0xE02020, 150, 255)]))
        XCTAssertEqual(red >> 16 & 0xFF, 0xE0)
        XCTAssertEqual(EventLook.dominant(pixels: pixels([(0x808080, 100, 255), (0x101010, 100, 255), (0xF8F8F8, 100, 255)])),
                       EventLook.grey, "no colourful hue: grey")
        XCTAssertEqual(EventLook.dominant(pixels: pixels([(0xFF2020, 100, 20), (0x2020FF, 10, 255)])) & 0xFF, 0xFF,
                       "see-through pixels don't count")
        XCTAssertEqual(EventLook.dominant(pixels: []), EventLook.grey)

        XCTAssertGreaterThan(EventLook.brightness(pixels: pixels([(0xF0F0F0, 10, 255)])), EventLook.pale, "a pale picture")
        XCTAssertLessThan(EventLook.brightness(pixels: pixels([(0x203040, 10, 255), (0xFFFFFF, 10, 0)])), EventLook.pale,
                          "a dark one, its see-through pixels not counted")
    }

    /// White reads on the page's top colour at 5 to 1 or better for every hue (Apple's measures 2.7; Jesse
    /// agreed to darker), the colours go darker down the page, the lines' tint is light, and a grey stays grey.
    func testWhiteReadsOnEveryPageColour() {
        for hue in stride(from: 0.0, to: 360, by: 10) {
            let (r, g, b) = Hue.hslToRGB(hue, 100, 50)
            let rgb = UInt32(r * 255) << 16 | UInt32(g * 255) << 8 | UInt32(b * 255)
            let wash = EventLook.wash(rgb)
            XCTAssertGreaterThanOrEqual(EventLook.contrastWithWhite(wash.top), 5, "hue \(hue): \(String(wash.top, radix: 16))")
            XCTAssertGreaterThanOrEqual(EventLook.luminance(wash.top), EventLook.luminance(wash.mid) - 0.0001, "hue \(hue)")
            XCTAssertGreaterThan(EventLook.luminance(wash.mid), EventLook.luminance(wash.low), "hue \(hue)")
            XCTAssertGreaterThan(EventLook.luminance(wash.tint), 0.65, "hue \(hue): a light tint (pure blue's at 92% measures 0.70)")
        }
        let grey = EventLook.wash(EventLook.grey)
        XCTAssertEqual(grey.top >> 16 & 0xFF, grey.top & 0xFF, "a grey stays grey")
        XCTAssertEqual(grey.tint >> 16 & 0xFF, grey.tint & 0xFF)
        // Apple's own: #63818B under the lines, which the mock measured.
        XCTAssertGreaterThanOrEqual(EventLook.contrastWithWhite(EventLook.wash(0x63818B).top), 5)
    }

    /// The day row adds the Event to the phone's calendar only while it's still to come: not once
    /// it's called off or over (event-page-formats 05).
    func testTheDayRowAddsToTheCalendarOnlyWhileItsStillOn() {
        let page = EventPage.self
        let start = Town.midnight("2026-11-30")!.addingTimeInterval(16.5 * 3600)
        var item = FeedCardItem(event(imageUrl: nil, location: "Saint John's Abbey Arboretum, Collegeville"))
        item.eventDate = "2026-11-30"
        item.startTime = "4:30 PM"
        let now = Town.midnight("2026-10-30")!

        XCTAssertEqual(page.calendarEntry(item, now: now),
                       CalendarEntry(title: "Neighborhood walk", starts: start, ends: start.addingTimeInterval(2 * 3600),
                                     allDay: false, place: "Saint John's Abbey Arboretum, Collegeville"),
                       "two hours when it gives no end, as the app keeps it")
        item.endAt = start.addingTimeInterval(1.5 * 3600)
        XCTAssertEqual(page.calendarEntry(item, now: now)?.ends, item.endAt)
        XCTAssertNotNil(page.calendarEntry(item, now: start), "on now: still worth adding")
        XCTAssertNil(page.calendarEntry(item, now: item.endAt!), "over")
        item.cancelled = true
        XCTAssertNil(page.calendarEntry(item, now: now), "called off")
        item.cancelled = false
        item.startTime = nil
        item.allDay = true
        XCTAssertEqual(page.calendarEntry(item, now: now)?.allDay, true)
    }

    /// The place row: the name over the rest after its first comma; one line without one.
    func testThePlaceRowSplitsAtTheFirstComma() {
        let page = EventPage.self

        XCTAssertEqual(page.placeLines("Saint John's Abbey Arboretum, Collegeville"),
                       .init(first: "Saint John's Abbey Arboretum", second: "Collegeville"))
        XCTAssertEqual(page.placeLines("St. Joseph American Legion, St. Joseph, MN"),
                       .init(first: "St. Joseph American Legion", second: "St. Joseph, MN"))
        XCTAssertEqual(page.placeLines("St. Cloud Cathedral High School Holy Angels Performing Arts Center"),
                       .init(first: "St. Cloud Cathedral High School Holy Angels Performing Arts Center"))
        XCTAssertEqual(page.placeLines(", Collegeville"), .init(first: ", Collegeville"), "no name before it: as written")
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
