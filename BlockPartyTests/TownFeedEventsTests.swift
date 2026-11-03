//
//  TownFeedEventsTests.swift
//  The Town feed (`TownFeed`): what `get_town_feed` sends becomes cards in its order,
//  the list survives a failed read, and a card goes when its time is up. What is in
//  the feed, when, and in what order are the function's, tested in
//  supabase/tests/town_feed.test.mjs.
//

import XCTest
@testable import BlockParty

@MainActor
final class TownFeedEventsTests: XCTestCase {

    /// Noon on 2026-10-07, the Town's time.
    private let now = Town.midnight("2026-10-07")!.addingTimeInterval(12 * 3600)

    private struct Offline: Error {}

    private func row(_ id: String, leavesIn hours: Double = 24, club: String? = nil,
                     source: String? = "City of St. Joseph", going: Int = 0,
                     recurrence: String? = nil) -> TownFeedRow {
        let event = UpcomingEvent(id: id, title: "Event \(id)", eventDate: "2026-10-12",
                                  startTime: "6 PM", location: nil, goingCount: going,
                                  createdAt: "2026-10-06T16:08:20+00:00", clubName: club,
                                  sourceName: source)
        return TownFeedRow(event: event, recurrence: recurrence,
                           leavesAt: now.addingTimeInterval(hours * 3600))
    }

    private func feed(_ rows: [TownFeedRow]) -> TownFeed {
        TownFeed { rows.map(TownFeed.entry) }
    }

    /// Town news comes in the feed's own rows, kind "news", under the events (town-feed 35): it
    /// keeps its place, its facts line (else its title), its post and its place's picture. News
    /// with no post to open is dropped, and the events' cards never count it.
    func testNewsRowsBecomeTownNewsInTheirPlace() async throws {
        let json = """
        [{"id":"e1","recurrence":null,"leaves_at":"2099-10-24T00:00:00+00:00","kind":"event",
         "card":{"id":"e1","title":"Fish fry","event_date":"2026-10-23","start_time":"5 PM",
         "location":null,"image_url":null,"category":"dining","club_name":null,"source_name":"Church of St. Joseph",
         "end_at":null,"all_day":false,"created_at":"2026-10-06T16:08:20+00:00","going_count":0,
         "source_url":null,"going":false}},
         {"id":"n1","title":"Flight Friday","event_date":null,"start_time":null,"location":null,
         "image_url":null,"category":"business","club_name":null,"source_name":"The Wandering Cow",
         "end_at":null,"all_day":false,"created_at":"2026-10-22T23:44:07+00:00","going_count":0,
         "rsvpd":false,"recurrence":null,"leaves_at":"2099-10-29T23:44:07+00:00","reason":"interest",
         "reason_name":"dining","description":"Four scoops for $5 at Wandering Cow on Fridays.",
         "place_picture":{"url":"https://x/cow-logo.webp","kind":"logo","hue":19},"kind":"news",
         "source_url":"https://www.instagram.com/p/Deki5CwgiQG/"},
         {"id":"n2","title":"Happy hour","event_date":null,"start_time":null,"location":null,
         "image_url":null,"category":"business","club_name":null,"source_name":"Neighbors Route 75",
         "end_at":null,"all_day":false,"created_at":"2026-10-22T23:44:07+00:00","going_count":0,
         "rsvpd":false,"recurrence":null,"leaves_at":"2099-10-29T23:44:07+00:00","description":" ",
         "place_picture":null,"kind":"news","source_url":"https://www.facebook.com/x/posts/1"},
         {"id":"n3","title":"No link","event_date":null,"start_time":null,"location":null,
         "image_url":null,"category":"business","club_name":null,"source_name":"Somewhere",
         "end_at":null,"all_day":false,"created_at":"2026-10-22T23:44:07+00:00","going_count":0,
         "rsvpd":false,"recurrence":null,"leaves_at":"2099-10-29T23:44:07+00:00","kind":"news",
         "source_url":null}]
        """
        let lines = try CommunityAPI.townFeedLines(from: Data(json.utf8))
        XCTAssertEqual(lines.count, 3)
        guard case .event(let fish) = lines[0], case .news(let flight) = lines[1], case .news(let happy) = lines[2]
        else { return XCTFail("\(lines)") }
        XCTAssertEqual(fish.event.title, "Fish fry")
        XCTAssertNil(fish.event.sourceURL)
        let found = try CommunityAPI.townFeedRows(from: Data(json.replacingOccurrences(
            of: #""source_url":null,"going":false"#,
            with: #""source_url":"https://www.milkandhoneyciders.com/events","going":false"#).utf8))
        XCTAssertEqual(TownFeed.card(found[0]).sourceURL?.absoluteString,
                       "https://www.milkandhoneyciders.com/events", "the Event page's link rides the card")
        XCTAssertEqual(flight.place, "The Wandering Cow")
        XCTAssertEqual(flight.words, "Four scoops for $5 at Wandering Cow on Fridays.")
        XCTAssertEqual(flight.post.absoluteString, "https://www.instagram.com/p/Deki5CwgiQG/")
        XCTAssertEqual(flight.picture?.kind, .logo)
        XCTAssertEqual(flight.title, "Flight Friday", "its headline rides along for the card")
        XCTAssertEqual(happy.words, "Happy hour", "no facts line: its title")
        XCTAssertNil(happy.picture)
        // The ••• sheet's why line (news-menu): the interest it shares, else only that it's News.
        XCTAssertEqual(FeedCardMenuSheet(isPresented: .constant(false), news: flight).why, "Matches Food & dining")
        XCTAssertEqual(FeedCardMenuSheet(isPresented: .constant(false), news: happy).why, "News")
        // The events' own readers (the Event of the day, a kept list) never see news.
        XCTAssertEqual(try CommunityAPI.townFeedRows(from: Data(json.utf8)).map(\.event.id), ["e1"])

        let town = TownFeed { lines.map(TownFeed.entry) }
        await town.refresh()
        XCTAssertEqual(town.shown.map(\.id), ["e1", "n1", "n2"])
        XCTAssertEqual(town.cards.map(\.id), ["e1"])
    }

    /// A neighbour's post comes in the feed's own rows, kind "post" (town-feed 29): its words, photo and
    /// shape, Place, who posted it, the friends they tagged and who can see it, in the feed's order. One
    /// with no poster to name is left out, never the feed; the events' cards never count a post.
    func testPostRowsBecomeTownPostsInTheirPlace() async throws {
        let json = """
        [{"id":"p1","title":"Burger night. Who's in?","event_date":null,"start_time":null,
         "location":"Sal's","image_url":"https://x/event-images/u/p1.jpg","category":null,
         "club_name":null,"source_name":null,"end_at":null,"all_day":false,"created_at":"2026-10-07T15:00:00+00:00",
         "going_count":0,"rsvpd":false,"recurrence":null,"leaves_at":"2099-10-14T15:00:00+00:00",
         "heart_count":3,"hearted":true,"kind":"post","source_url":null,"poster":{"id":"u1",
         "name":"Jesse","photo":"https://x/avatars/u1/a.jpg","tagged":[{"id":"u2","name":"Sam Lee"}],
         "aspect":0.8,"friends_only":true}},
         {"id":"e1","recurrence":null,"leaves_at":"2099-10-24T00:00:00+00:00","kind":"event",
         "card":{"id":"e1","title":"Fish fry","event_date":"2026-10-23","start_time":"5 PM",
         "location":null,"image_url":null,"category":"dining","club_name":null,"source_name":"Church of St. Joseph",
         "end_at":null,"all_day":false,"created_at":"2026-10-06T16:08:20+00:00","going_count":0,
         "source_url":null,"going":false}},
         {"id":"p2","title":"","event_date":null,"start_time":null,"location":null,
         "image_url":null,"category":null,"club_name":null,"source_name":null,"end_at":null,
         "all_day":false,"created_at":"2026-10-07T15:00:00+00:00","going_count":0,"rsvpd":false,
         "recurrence":null,"leaves_at":"2099-10-14T15:00:00+00:00","kind":"post","source_url":null,
         "poster":{"id":"u3"}}]
        """
        let lines = try CommunityAPI.townFeedLines(from: Data(json.utf8))
        XCTAssertEqual(lines.count, 2, "a post whose poster doesn't decode is left out")
        guard case .post(let post) = lines[0] else { return XCTFail("\(lines)") }
        XCTAssertEqual(post.words, "Burger night. Who's in?")
        XCTAssertEqual(post.poster, TownPost.Person(id: "u1", name: "Jesse"))
        XCTAssertEqual(post.posterPhoto?.absoluteString, "https://x/avatars/u1/a.jpg")
        XCTAssertEqual(post.photo?.absoluteString, "https://x/event-images/u/p1.jpg")
        XCTAssertEqual(post.photoAspect, 0.8)
        XCTAssertEqual(post.place, "Sal's")
        XCTAssertEqual(post.tagged.map(\.name), ["Sam Lee"])
        XCTAssertTrue(post.friendsOnly)
        XCTAssertEqual(post.heartCount, 3)
        XCTAssertTrue(post.hearted)
        XCTAssertEqual(post.line, "Jesse is with Sam Lee at Sal's.")
        XCTAssertEqual(try CommunityAPI.townFeedRows(from: Data(json.utf8)).map(\.event.id), ["e1"])

        let town = TownFeed { lines.map(TownFeed.entry) }
        await town.refresh()
        XCTAssertEqual(town.shown.map(\.id), ["p1", "e1"])
        XCTAssertEqual(town.cards.map(\.id), ["e1"])
        // Report and Not interested match a post by its id (photo-only posts share an empty name).
        XCTAssertEqual(FeedCardMenuSheet(isPresented: .constant(false), post: post).id, "p1")
    }

    /// Your own post's Delete: out at once; one the server didn't take comes back.
    func testDeletingYourPostTakesItOutAndBringsItBackIfItFails() async {
        let post = TownPost(id: "p1", poster: .init(id: "me", name: "Jesse"), words: "Hi", posted: now,
                            leavesAt: now.addingTimeInterval(86_400))
        let entries = [TownFeedEntry(item: .post(post), leavesAt: post.leavesAt)]
        var deleted: [String] = []
        let town = TownFeed(read: { entries }, deletePost: { deleted.append($0.id) })
        await town.refresh(at: now)
        await town.delete(post)
        XCTAssertEqual(town.shown.map(\.id), [])
        XCTAssertEqual(deleted, ["p1"])
        let offline = TownFeed(read: { entries }, deletePost: { _ in throw Offline() })
        await offline.refresh(at: now)
        await offline.delete(post)
        XCTAssertEqual(offline.shown.map(\.id), ["p1"], "the server didn't take it: it comes back")
    }

    /// The name line, Facebook's: the name alone, with friends, at a Place, or both.
    func testAPostsNameLineSaysWhoTheyreWithAndWhere() {
        XCTAssertEqual(TownPost.line(name: "Jesse", with: [], at: nil), "Jesse")
        XCTAssertEqual(TownPost.line(name: "Jesse", with: [], at: " Sal's "), "Jesse is at Sal's.")
        XCTAssertEqual(TownPost.line(name: "Jesse", with: ["Sam"], at: nil), "Jesse is with Sam.")
        XCTAssertEqual(TownPost.line(name: "Jesse", with: ["Sam", "Ana"], at: "Sal's"), "Jesse is with Sam and Ana at Sal's.")
        XCTAssertEqual(TownPost.line(name: "Jesse", with: ["Sam", "Ana", "Bo"], at: nil), "Jesse is with Sam and 2 others.")
    }

    /// A News card's words (found-posts): its headline over the picture and its facts under it;
    /// with no headline the facts stand in for it, and nothing is said twice.
    func testNewsCardSaysItsHeadlineThenItsFacts() {
        let post = URL(string: "https://www.instagram.com/p/Deki5CwgiQG/")!
        let flight = TownNews(id: "n1", place: "The Wandering Cow", words: "Four scoops for $5 on Fridays.",
                              post: post, leavesAt: .distantFuture, title: "Flight Friday")
        XCTAssertEqual(flight.headline, "Flight Friday")
        XCTAssertEqual(flight.facts, "Four scoops for $5 on Fridays.")
        let untitled = TownNews(id: "n2", place: "Sal's", words: "Meat raffle moved to Saturday", post: post,
                                leavesAt: .distantFuture, title: "  ")
        XCTAssertEqual(untitled.headline, "Meat raffle moved to Saturday")
        XCTAssertNil(untitled.facts)
        let same = TownNews(id: "n3", place: "Neighbors", words: "Happy hour", post: post, leavesAt: .distantFuture,
                            title: "Happy hour")
        XCTAssertNil(same.facts, "nothing said twice")
    }

    /// The columns `get_town_feed` returns, as PostgREST sends them. A renamed column
    /// on either side fails here rather than emptying the feed.
    func testTheFunctionsRowsBecomeEventsWithTheirRepeatAndLeavingTime() throws {
        let json = """
        [{"id":"e1","recurrence":"Every 1st & 3rd Monday","leaves_at":"2026-10-20T04:59:00+00:00",
         "card":{"id":"e1","title":"City Council Meeting","event_date":"2026-10-19",
         "start_time":"6 PM","location":"City Hall","image_url":null,"category":null,
         "club_name":null,"source_name":"City of St. Joseph","end_at":"2026-10-20T04:59:00+00:00",
         "all_day":false,"created_at":"2026-10-06T16:08:20.123+00:00","going_count":2,
         "going":true}}]
        """
        let rows = try CommunityAPI.townFeedRows(from: Data(json.utf8))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].recurrence, "Every 1st & 3rd Monday")
        XCTAssertEqual(rows[0].leavesAt, DateHelpers.timestamp("2026-10-20T04:59:00Z"))
        XCTAssertEqual(rows[0].event.endAt, rows[0].leavesAt)
        XCTAssertEqual(rows[0].event.goingCount, 2)
        XCTAssertTrue(rows[0].event.rsvpd)

        let card = TownFeed.card(rows[0])
        XCTAssertEqual(card.recurrence, "Every 1st & 3rd Monday")
        XCTAssertEqual(card.hostName, "City of St. Joseph")
        // A row from before the recipe (a kept list) says no reason: no ••• menu.
        XCTAssertNil(card.why)
        XCTAssertNil(card.score)
        // And from before hearts, none: the next read brings them.
        XCTAssertEqual(card.likeCount, 0)
        XCTAssertFalse(card.isLiked)
    }

    /// A place photo's size reaches its card, which takes the photo's shape inside Instagram's
    /// limits (BP app event-card 01): 4:5 at its tallest, 1.91:1 at its widest, 3:2 without a size.
    func testAPlacePhotosSizeShapesItsCard() throws {
        let json = """
        [{"id":"e1","recurrence":null,"leaves_at":"2026-10-20T04:59:00+00:00","card":{"id":"e1",
         "title":"Choir","event_date":"2026-10-19","start_time":"7 PM","location":null,
         "image_url":null,"category":null,"club_name":null,"source_name":"CSB SJU",
         "end_at":"2026-10-20T04:59:00+00:00","all_day":false,"created_at":"2026-10-06T16:08:20+00:00",
         "going_count":0,"place_picture":{"url":"https://x/hall.webp","kind":"photo",
         "site":"https://csbsju.edu","credit":null,"w":1600,"h":1067},"going":false}}]
        """
        let card = TownFeed.card(try CommunityAPI.townFeedRows(from: Data(json.utf8))[0])
        XCTAssertEqual(card.image.cardAspect, 1600.0 / 1067.0, accuracy: 0.0001)

        let photo = { (w: Int?, h: Int?) in
            FeedCardImageSource(PlacePicture(url: URL(string: "https://x/p.webp")!, kind: .photo, width: w, height: h))
        }
        XCTAssertEqual(photo(1067, 1600).cardAspect, 0.8, accuracy: 0.0001, "taller than 4:5 is trimmed to 4:5")
        XCTAssertEqual(photo(1080, 1350).cardAspect, 0.8, accuracy: 0.0001, "4:5 itself")
        XCTAssertEqual(photo(1000, 1000).cardAspect, 1, accuracy: 0.0001, "square")
        XCTAssertEqual(photo(1600, 500).cardAspect, 1.91, accuracy: 0.0001, "wider than 1.91:1 is trimmed")
        XCTAssertEqual(photo(nil, nil).cardAspect, 1.5, accuracy: 0.0001, "no size: 3:2")
        XCTAssertEqual(photo(0, 900).cardAspect, 1.5, accuracy: 0.0001, "a broken size: 3:2")
        let logo = PlacePicture(url: URL(string: "https://x/logo.webp")!, kind: .logo, width: 1024, height: 1024)
        XCTAssertEqual(FeedCardImageSource(logo).cardAspect, 1.5, accuracy: 0.0001, "a logo keeps 3:2")
        XCTAssertEqual(FeedCardImageSource.fallback.cardAspect, 1.5, accuracy: 0.0001, "ink keeps 3:2")
    }

    /// A card with no photo is the short white card (BP app references/no-photo-cards): its place's
    /// logo or nothing at all makes it one; a photo or a game never does. News the same.
    func testACardWithNoPhotoIsTheShortWhiteCard() throws {
        let row = { (id: String, extra: String) in """
        {"id":"\(id)","recurrence":null,"leaves_at":"2026-10-31T17:00:00+00:00",
         "card":{"id":"\(id)","title":"Fall Craft Day","event_date":"2026-10-31","start_time":"10 AM",
         "location":"Fire Hall","image_url":null,"category":null,"club_name":null,"source_name":"City of St. Joseph",
         "end_at":null,"all_day":false,"created_at":"2026-10-06T16:08:20+00:00","going_count":0,"going":false\(extra)}}
        """ }
        let json = "[" + [
            row("logo", ##","place_picture":{"url":"https://x/logo.webp","kind":"logo","hue":35}"##),
            row("ink", ""),
            row("photo", ##","place_picture":{"url":"https://x/hall.webp","kind":"photo","w":1600,"h":1067}"##),
            row("game", ##","game":{"sport":"Football","teams":[{"name":"Saint John's","short":"Saint John's"},{"name":"Concordia","short":"Concordia"}]}"##),
        ].joined(separator: ",") + "]"
        let cards = try CommunityAPI.townFeedRows(from: Data(json.utf8)).map { TownFeed.card($0) }
        XCTAssertEqual(cards.map(\.isPhotoless), [true, true, false, false], "logo, ink, photo, game")

        let post = URL(string: "https://www.instagram.com/p/1/")!
        let news = { (picture: PlacePicture?) in
            TownNews(id: "n", place: "The Wandering Cow", words: "Four scoops for $5", post: post,
                     picture: picture, leavesAt: .distantFuture)
        }
        XCTAssertTrue(news(nil).isPhotoless, "no picture: its first letter")
        XCTAssertTrue(news(PlacePicture(url: URL(string: "https://x/cow.webp")!, kind: .logo)).isPhotoless)
        XCTAssertFalse(news(PlacePicture(url: URL(string: "https://x/cow.jpg")!, kind: .photo)).isPhotoless)
    }

    /// The place's other photos reach the card (BP app event-card 02): the card and its page
    /// show the cover, then the rest in order, each once with its own credit; one that doesn't
    /// decode is left out and the cover kept.
    func testAPlacesOtherPhotosReachTheCardAndABadOneCostsNothing() throws {
        let json = """
        [{"id":"e1","recurrence":null,"leaves_at":"2026-10-20T04:59:00+00:00","card":{"id":"e1",
         "title":"Choir","event_date":"2026-10-19","start_time":"7 PM","location":null,
         "image_url":null,"category":null,"club_name":null,"source_name":"CSB SJU",
         "end_at":"2026-10-20T04:59:00+00:00","all_day":false,"created_at":"2026-10-06T16:08:20+00:00",
         "going_count":0,"place_picture":{"url":"https://x/a.webp","kind":"photo","site":"https://csbsju.edu",
         "credit":null,"w":1600,"h":1067,"more":[{"url":"https://x/b.webp","kind":"photo",
         "site":"https://csbsju.edu","credit":"Ada Lovelace · CC BY 4.0","w":1067,"h":1600},
         {"kind":"photo"},{"url":"https://x/c.webp","kind":"photo","site":"https://www.sju.edu/x",
         "credit":null}]},"going":false}}]
        """
        let card = TownFeed.card(try CommunityAPI.townFeedRows(from: Data(json.utf8))[0])
        XCTAssertEqual(card.photos().compactMap { $0.url?.lastPathComponent }, ["a.webp", "b.webp", "c.webp"])
        XCTAssertEqual(card.photos()[1].attribution, "Ada Lovelace · CC BY 4.0")
        XCTAssertEqual(card.photos()[2].attribution, "sju")
        XCTAssertEqual(card.image.cardAspect, 1600.0 / 1067.0, accuracy: 0.0001, "the cover sets the card's shape")
    }

    /// What it is in a few words (event-card 05) reaches the card, which shows it beside the title
    /// unless the title already says it or the card is a game, whose title is already its sport.
    func testWhatItIsReachesTheCardBesideTheTitle() throws {
        let json = """
        [{"id":"e1","recurrence":null,"leaves_at":"2026-11-13T03:00:00+00:00","card":{"id":"e1",
         "title":"Rev. Daniel Groody: Koch Chair Lecture","event_date":"2026-11-12",
         "start_time":"7 PM","location":"Gorecki Center","image_url":null,"category":"faith",
         "club_name":null,"source_name":"CSB SJU Campus Events","end_at":null,"all_day":false,
         "created_at":"2026-10-06T16:08:20+00:00","going_count":0,"what":"Talk","going":false}},
         {"id":"e2","recurrence":null,"leaves_at":"2026-11-06T17:00:00+00:00","card":{"id":"e2",
         "title":"Christmas Craft Sale","event_date":"2026-11-06","start_time":"9 AM",
         "location":null,"image_url":null,"category":null,"club_name":null,"source_name":"Saint Benedict's Monastery",
         "end_at":null,"all_day":false,"created_at":"2026-10-06T16:08:20+00:00","going_count":0,
         "what":"Craft sale","going":false}},
         {"id":"e3","recurrence":null,"leaves_at":"2026-11-06T17:00:00+00:00","card":{"id":"e3",
         "title":"Kiln Firing","event_date":"2026-11-06","start_time":"9 AM","location":null,
         "image_url":null,"category":null,"club_name":null,"source_name":"CSB SJU Campus Events",
         "end_at":null,"all_day":false,"created_at":"2026-10-06T16:08:20+00:00","going_count":0,
         "going":false}}]
        """
        let cards = try CommunityAPI.townFeedRows(from: Data(json.utf8)).map { TownFeed.card($0) }
        XCTAssertEqual(cards.map(\.what), ["Talk", "Craft sale", nil], "a feed read before the words still decodes")
        XCTAssertEqual(cards.map(\.whatLine), ["Talk", nil, nil], "none when the title already says it")
        var game = cards[0]
        game.game = try JSONDecoder().decode(Game.self, from: Data(#"{"sport":"Football","teams":[]}"#.utf8))
        XCTAssertNil(game.whatLine, "a game's title is already its sport")
        func card(_ title: String, what: String) -> FeedCardItem {
            var item = FeedCardItem(id: "c", title: title, dateChip: "", metaLine: "", image: .fallback,
                                    recurrence: nil, goingCount: 0, goingAvatars: [], likeCount: 0,
                                    isLiked: false, isSaved: false, isJoined: false)
            item.what = what
            return item
        }
        XCTAssertNil(card("City Council — regular meeting", what: "Council meeting").whatLine,
                     "every word already in the title, though not side by side")
        XCTAssertEqual(card("Martin's exhibit", what: "Art exhibit").whatLine, "Art exhibit",
                       "whole words: \"art\" isn't in \"Martin's\"")
    }

    /// Scrolled down, the Event of the day poster holds at when the feed left the top (event-card
    /// 03): scrolling further doesn't move that moment, and back at the top it lets go.
    @MainActor
    func testThePosterHoldsFromWhenTheFeedLeftTheTop() {
        let town = feed([row("a")])
        town.scrolled(to: 120, at: now)
        XCTAssertTrue(town.holding)
        town.scrolled(to: 640, at: now.addingTimeInterval(60))
        XCTAssertEqual(town.heldAt, now, "scrolling further keeps the moment it left the top")
        town.scrolled(to: 0, at: now.addingTimeInterval(120))
        XCTAssertFalse(town.holding)
        town.scrolled(to: 50, at: now.addingTimeInterval(180))
        XCTAssertEqual(town.heldAt, now.addingTimeInterval(180), "leaving the top again holds from then")
    }

    /// An Event of the day pick from Parks, on from `start` to `end` hours after noon.
    private func pick(_ id: String, from start: Double, to end: Double) throws -> DailyEvent {
        let card = try XCTUnwrap(TownFeed.entry(row(id, source: "Parks")).card)
        return DailyEvent(item: card, starts: now.addingTimeInterval(start * 3600),
                          ends: now.addingTimeInterval(end * 3600))
    }

    /// The column's poster is never a pick you said Not interested to, nor one whose host you
    /// muted (ticket 21): the next pick takes the top, and with none left the cards open it.
    func testAHiddenPickNeverTopsTheFeed() async throws {
        let town = await choosingFeed(Chooser())
        let picks = [try pick("x", from: 1, to: 2), try pick("y", from: 3, to: 4)]
        XCTAssertEqual(town.column(eventOfTheDay: picks, now: now).first?.id, "event-of-the-day:x")
        await town.hide(id: "x", host: "Parks", mute: false)
        town.undoEnded("x")
        XCTAssertEqual(town.column(eventOfTheDay: picks, now: now).first?.id, "event-of-the-day:y")
        await town.hide(id: "y", host: "Parks", mute: true)
        town.undoEnded("y")
        XCTAssertEqual(town.column(eventOfTheDay: picks, now: now).map(\.id), ["event:c", "caught-up"],
                       "Parks' pick and cards all go; the list still ends on its line (town-feed 23)")
    }

    /// Scrolled down, the poster holds at what it showed when the feed left the top, a pick that
    /// has since ended included; back at the top the next pick takes it (event-card 03).
    func testThePosterHoldsWhileScrolled() async throws {
        let town = feed([row("a")])
        await town.reload(at: now)
        let picks = [try pick("x", from: -1, to: 0.5), try pick("y", from: 2, to: 3)]
        let later = now.addingTimeInterval(3600)
        town.scrolled(to: 300, at: now)
        XCTAssertEqual(town.column(eventOfTheDay: picks, now: later).first?.id, "event-of-the-day:x")
        XCTAssertEqual(town.posterClock(at: later), now, "the poster's \"Now\" holds too")
        town.scrolled(to: 0, at: later)
        XCTAssertEqual(town.column(eventOfTheDay: picks, now: later).first?.id, "event-of-the-day:y")
        XCTAssertEqual(town.posterClock(at: later), later)
    }

    /// The recipe's columns (ticket 18): the reason becomes the card's line, and the
    /// admin's score comes through whole.
    func testTheRecipesReasonAndScoreReachTheCard() throws {
        let json = """
        [{"id":"e1","recurrence":null,"leaves_at":"2026-10-12T22:00:00+00:00","reason":"interest",
         "reason_name":"live_music","score":{"interest":3,"friend":0,"follow":0,"popular":0,
         "size":1.5,"sizeStep":2,"daysAway":2.12,"soon":0.8105,"acted":1,"spacing":0.5,
         "newSpot":false,"total":1.8236,"spot":2,"of":5,"tapped":2,"draw":1.5,"topicSpacing":0.7,
         "new":2},"heart_count":4,"hearted":true,"card":{"id":"e1","title":"Choir concert",
         "event_date":"2026-10-12","start_time":"3 PM","location":null,"image_url":null,
         "category":"live_music","club_name":null,"source_name":"Arts center","end_at":null,
         "all_day":false,"created_at":"2026-10-06T16:08:20+00:00","going_count":0,"going":false}},
         {"id":"e2","recurrence":null,"leaves_at":"2026-10-08T18:00:00+00:00","reason":"today",
         "reason_name":null,"score":null,"card":{"id":"e2","title":"Bake sale","event_date":"2026-10-08",
         "start_time":"11 AM","location":null,"image_url":null,"category":null,"club_name":null,
         "source_name":"Parish","end_at":null,"all_day":false,"created_at":"2026-10-06T16:08:20+00:00",
         "going_count":0,"going":false}},
         {"id":"e3","recurrence":null,"leaves_at":"2026-10-08T20:00:00+00:00","reason":"today",
         "reason_name":null,"score":{"spot":3,"newSpot":null},"card":{"id":"e3","title":"Fair",
         "event_date":"2026-10-08","start_time":"1 PM","location":null,"image_url":null,
         "category":null,"club_name":null,"source_name":"Fair board","end_at":null,
         "all_day":false,"created_at":"2026-10-06T16:08:20+00:00","going_count":0,"going":false}}]
        """
        let cards = try CommunityAPI.townFeedRows(from: Data(json.utf8)).map { TownFeed.card($0) }
        XCTAssertEqual(cards.map(\.why), ["Matches Live music", "Happening today", "Happening today"])
        XCTAssertEqual(cards[0].score?.spot, 2)
        XCTAssertEqual(cards[0].score?.spacing, 0.5)
        XCTAssertEqual(cards[0].score?.sizeStep, 2)
        // The newer terms (town-feed 30, 34, 32), and none from a breakdown read before them.
        XCTAssertEqual([cards[0].score?.tapped, cards[0].score?.draw, cards[0].score?.topicSpacing], [2, 1.5, 0.7])
        XCTAssertEqual(cards[0].score?.new, 2, "New (town-feed 36)")
        let older = try JSONDecoder().decode(FeedScore.self, from: Data("""
            {"interest":0,"friend":0,"follow":0,"popular":0,"size":0,"sizeStep":1,"daysAway":1,"soon":1,
             "acted":1,"spacing":1,"newSpot":false,"total":1,"spot":1,"of":1}
            """.utf8))
        XCTAssertNil(older.tapped)
        XCTAssertNil(older.new)
        XCTAssertNil(cards[1].score)
        // Everyone's hearts, and whether you hearted it (ticket 03).
        XCTAssertEqual(cards[0].likeCount, 4)
        XCTAssertTrue(cards[0].isLiked)
        // A breakdown that doesn't read costs only the breakdown, never the feed.
        XCTAssertNil(cards[2].score)
    }

    /// Friends Going (town-feed 28) come through with the reason that names the first of them;
    /// a feed kept on disk before the column existed still reads, with none.
    func testFriendsGoingReachTheCardAndAnOlderKeptFeedStillReads() throws {
        let json = """
        [{"id":"e1","recurrence":null,"leaves_at":"2026-10-13T02:00:00+00:00","reason":"friend",
         "reason_name":"Anna","score":null,"card":{"id":"e1","title":"Quiz night","event_date":"2026-10-12",
         "start_time":"7 PM","location":null,"image_url":null,"category":null,"club_name":null,
         "source_name":"Bad Habit","end_at":null,"all_day":false,"created_at":"2026-10-06T16:08:20+00:00",
         "going_count":12,"friends_going":[{"name":"Anna","photo":"https://example.com/anna.jpg"},
         {"name":"Ben","photo":null}],"going":false}},
         {"id":"e2","recurrence":null,"leaves_at":"2026-10-08T18:00:00+00:00","reason":"today",
         "reason_name":null,"score":null,"card":{"id":"e2","title":"Bake sale","event_date":"2026-10-08",
         "start_time":"11 AM","location":null,"image_url":null,"category":null,"club_name":null,
         "source_name":"Parish","end_at":null,"all_day":false,"created_at":"2026-10-06T16:08:20+00:00",
         "going_count":3,"going":false}}]
        """
        let cards = try CommunityAPI.townFeedRows(from: Data(json.utf8)).map { TownFeed.card($0) }
        XCTAssertEqual(cards[0].friendsGoing, [FeedFriend(name: "Anna", photo: URL(string: "https://example.com/anna.jpg")),
                                               FeedFriend(name: "Ben", photo: nil)])
        XCTAssertEqual(cards[0].why, "Anna is going")
        XCTAssertEqual(cards[1].friendsGoing, [])
    }

    /// A group's Event (rsvp-and-groups 07) carries the group and whether you're in it, for the
    /// card's Join; a feed kept on disk before the columns existed reads with no group.
    func testAGroupsEventCarriesItsGroupAndAnOlderKeptFeedStillReads() throws {
        let json = """
        [{"id":"e1","recurrence":null,"leaves_at":"2026-10-20T02:00:00+00:00","reason":"today",
         "reason_name":null,"score":null,"club_id":"6f1c2c43-6b4b-4a4e-9f43-1f2d3c4b5a69",
         "in_club":true,"card":{"id":"e1","title":"Monthly Meeting","event_date":"2026-10-19",
         "start_time":"7 PM","location":null,"image_url":null,"category":null,"club_name":"St. Joe Rod and Gun Club",
         "source_name":"St Joe Rod and Gun Club","end_at":null,"all_day":false,"created_at":"2026-10-06T16:08:20+00:00",
         "going_count":0,"going":false}},
         {"id":"e2","recurrence":null,"leaves_at":"2026-10-19T18:00:00+00:00","reason":"today",
         "reason_name":null,"score":null,"card":{"id":"e2","title":"Bake sale","event_date":"2026-10-19",
         "start_time":"11 AM","location":null,"image_url":null,"category":null,"club_name":null,
         "source_name":"Parish","end_at":null,"all_day":false,"created_at":"2026-10-06T16:08:20+00:00",
         "going_count":3,"going":false}}]
        """
        let cards = try CommunityAPI.townFeedRows(from: Data(json.utf8)).map { TownFeed.card($0) }
        XCTAssertEqual(cards[0].groupID, "6f1c2c43-6b4b-4a4e-9f43-1f2d3c4b5a69")
        XCTAssertTrue(cards[0].inGroup)
        XCTAssertEqual(cards[0].hostName, "St. Joe Rod and Gun Club", "the group's own name")
        XCTAssertNil(cards[1].groupID)
        XCTAssertFalse(cards[1].inGroup)
    }

    /// A game (game-card 01) carries its sport, special night and both teams, the host's first,
    /// each with its logo and color when known; a misread logo or color is none, and a game that
    /// doesn't name two teams leaves the card a photo card. A feed kept from before reads too.
    func testAGamesTeamsReachTheCardAndABadOneLeavesAPhotoCard() throws {
        let row = { (id: String, game: String) in """
        {"id":"\(id)","recurrence":null,"leaves_at":"2026-10-17T20:00:00+00:00",
         "card":{"id":"\(id)","title":"SJU Football vs Concordia: Homecoming","event_date":"2026-10-17",
         "start_time":"1 PM","location":"Clemens Stadium, Collegeville","image_url":null,"category":null,
         "club_name":null,"source_name":"SJU Athletics","end_at":null,"all_day":false,
         "created_at":"2026-10-06T16:08:20+00:00","going_count":0,"going":false\(game)}}
        """ }
        let json = "[" + [
            row("e1", ##","game":{"sport":"Football","occasion":"Homecoming","teams":[{"name":"Saint John's","short":"Saint John's","logo":"https://x/sju.png","color":"#C20430"},{"name":"Concordia","short":"Concordia","logo":null,"color":"red"}]}"##),
            row("e2", ##","game":{"sport":"Football","occasion":null,"teams":[{"name":"Saint John's","short":"Saint John's"}]}"##),
            row("e3", ##","game":null"##),
            row("e4", ""),
        ].joined(separator: ",") + "]"
        let cards = try CommunityAPI.townFeedRows(from: Data(json.utf8)).map { TownFeed.card($0) }
        let game = try XCTUnwrap(cards[0].game)
        XCTAssertEqual(game.sport, "Football")
        XCTAssertEqual(game.occasion, "Homecoming")
        XCTAssertEqual(game.teams.map(\.short), ["Saint John's", "Concordia"], "the host's team first")
        XCTAssertEqual(game.teams[0].logo, URL(string: "https://x/sju.png"))
        XCTAssertEqual(game.teams[0].rgb, 0xC20430)
        XCTAssertNil(game.teams[1].rgb, "a color that isn't #RRGGBB is none")
        XCTAssertEqual(game.teams.map(\.initial), ["S", "C"], "the disc's letter until a logo lands")
        XCTAssertEqual(game.spoken, "Football, Saint John's versus Concordia")
        XCTAssertNil(cards[1].game, "one team is no game")
        XCTAssertNil(cards[2].game)
        XCTAssertNil(cards[3].game, "a feed kept from before games")
        XCTAssertEqual(cards.count, 4, "no row is lost to its game")
    }

    /// A game's final (game-card 02) reads in its teams' order, the winner is the side with more, a
    /// tie has none, and a final that doesn't read is none, so the card stays VS.
    func testAGamesFinalReadsInTeamOrderAndABadOneKeepsVS() throws {
        func game(_ final: String) throws -> Game? {
            let json = #"{"sport":"Football","teams":[{"name":"Saint John's"},{"name":"Concordia"}]"# + final + "}"
            return try JSONDecoder().decode(Game.Lenient.self, from: Data(json.utf8)).value
        }
        let won = try XCTUnwrap(try game(#","final":[33,23]"#))
        XCTAssertEqual(won.final, [33, 23])
        XCTAssertEqual(won.winner, 0)
        XCTAssertEqual(won.spoken, "Football, Saint John's 33, Concordia 23, final")
        XCTAssertEqual(try game(#","final":[0,2]"#)?.winner, 1, "the host lost")
        let tie = try XCTUnwrap(try game(#","final":[2,2]"#))
        XCTAssertEqual(tie.final, [2, 2])
        XCTAssertNil(tie.winner, "a tie fades neither side")
        for bad in [#","final":null"#, #","final":[1]"#, #","final":[-1,3]"#, #","final":"33-23""#, ""] {
            let kept = try XCTUnwrap(try game(bad), "the game stays: \(bad)")
            XCTAssertNil(kept.final, bad)
            XCTAssertNil(kept.winner, bad)
            XCTAssertEqual(kept.spoken, "Football, Saint John's versus Concordia", bad)
        }
    }

    /// Volleyball's sets (game-card 09): one chip per set from SIDEARM's periods, the newest one being
    /// played while the match is on and none once it's complete; any other sport has no sets.
    func testVolleyballsSetsAreItsPeriodsWithTheNewestBeingPlayed() throws {
        func game(_ more: String, sport: String = "Volleyball") throws -> Game {
            let json = #"{"sport":"\#(sport)","teams":[{"name":"Saint Benedict"},{"name":"Carleton"}]"# + more + "}"
            return try XCTUnwrap(try JSONDecoder().decode(Game.Lenient.self, from: Data(json.utf8)).value)
        }
        let on = try game(#","live":{"score":[2,1],"period":"Set 4","complete":false,"periods":[[25,23,25,18],[21,25,19,14]]}"#)
        XCTAssertEqual(on.sets, [[25, 21], [23, 25], [25, 19], [18, 14]])
        XCTAssertEqual(on.setPlaying, 3, "the newest set is the one being played")
        let between = try game(#","live":{"score":[2,1],"period":"Set 3","complete":false,"periods":[[25,23,25],[21,25,19]]}"#)
        XCTAssertNil(between.setPlaying, "set 3 just won, set 4 not begun: every set listed is over")
        let final = try game(#","final":[3,1],"live":{"score":[3,1],"period":"Set 4","complete":true,"periods":[[25,23,25,25],[21,25,19,22]]}"#)
        XCTAssertEqual(final.sets.count, 4, "every set stays past the final")
        XCTAssertNil(final.setPlaying)
        let complete = try game(#","live":{"score":[3,0],"period":"Set 3","complete":true,"periods":[[25,25,25],[17,21,21]]}"#)
        XCTAssertNil(complete.setPlaying, "complete, its final on the way: no set is being played")
        XCTAssertEqual(try game("").sets, [], "before the first serve")
        XCTAssertEqual(try game(#","live":{"score":[7,0],"period":"Q1","complete":false,"periods":[[7],[0]]}"#, sport: "Football").sets,
                       [], "football's quarters are no sets")
        XCTAssertEqual(try game(#","live":{"score":[0,0],"period":"Set 1","complete":false,"periods":[[3,1],[2]]}"#).sets,
                       [], "uneven columns read as none")
    }

    /// Soccer's minute ring (game-card 09): the minute runs on from the last push and holds at each period's
    /// end through the break; halftime is the first half's clock stopped at 45:00; no other sport has a minute.
    func testSoccersMinuteRunsOnAndHoldsAtEachPeriodsEnd() throws {
        func live(_ period: String, _ seconds: Int, sport: String = "Soccer") throws -> Game.Live {
            let json = #"{"sport":"\#(sport)","teams":[{"name":"Saint John's"},{"name":"Augsburg"}],"live":{"score":[1,0],"period":"\#(period)","clock":"\#(seconds / 60 + 1)'","clock_s":\#(seconds),"complete":false,"at":"2026-11-03T20:30:00Z"}}"#
            return try XCTUnwrap(try JSONDecoder().decode(Game.Lenient.self, from: Data(json.utf8)).value?.live)
        }
        let first = try live("1st half", 1330), at = try XCTUnwrap(first.at)
        XCTAssertEqual(first.minute(at: at), 23)
        XCTAssertEqual(first.minute(at: at.addingTimeInterval(5 * 60)), 28, "it runs on between pushes")
        XCTAssertEqual(first.minute(at: at.addingTimeInterval(60 * 60)), 45, "held at 45")
        XCTAssertFalse(first.isHalftime)
        let half = try live("1st half", 2700)
        XCTAssertTrue(half.isHalftime, "the clock stopped at 45:00")
        XCTAssertEqual(half.minute(at: at.addingTimeInterval(15 * 60)), 45, "held through the break")
        let second = try live("2nd half", 2700)
        XCTAssertFalse(second.isHalftime, "the second half has begun")
        XCTAssertEqual(second.minute(at: at), 46)
        XCTAssertEqual(second.minute(at: at.addingTimeInterval(60 * 60)), 90, "held at 90")
        XCTAssertEqual(try live("OT", 5400).minute(at: at.addingTimeInterval(30 * 60)), 100, "the first overtime holds at 100")
        XCTAssertEqual(try live("OT", 6000).minute(at: at.addingTimeInterval(5 * 60)), 100, "its break too")
        XCTAssertEqual(try live("OT", 6060).minute(at: at.addingTimeInterval(30 * 60)), 110, "the second holds at 110")
        let football = try XCTUnwrap(try JSONDecoder().decode(Game.Lenient.self, from: Data(#"{"sport":"Football","teams":[{"name":"Saint John's"},{"name":"Gustavus"}],"live":{"score":[7,0],"period":"Q1","clock":"9:18","clock_s":558,"complete":false,"at":"2026-10-31T19:40:00Z"}}"#.utf8)).value?.live)
        XCTAssertNil(football.minute(at: .now), "a football clock is no minute")
    }

    /// Basketball's bar (game-card 09): one part per quarter or half and one for overtime, the played ones full and
    /// the one being played as far as its clock has run; the Bonus from the other team's 5th foul of a quarter or 7th
    /// of a half, a count from a period that's over read as none; no bar for any other sport or an old read.
    func testBasketballsBarFillsWithTheClockAndTheBonusComesFromTheOtherTeamsFouls() throws {
        func live(_ period: Int, of regulation: Int = 4, clock: Int, length: Int = 600, fouls: String? = nil,
                  sport: String = "Basketball", bar: Bool = true) throws -> Game.Live {
            let extra = (bar ? #","period_n":\#(period),"regulation":\#(regulation),"period_s":\#(length)"# : "")
                + (fouls.map { #","fouls":\#($0)"# } ?? "")
            let json = #"{"sport":"\#(sport)","teams":[{"name":"Saint Benedict"},{"name":"Loras"}],"live":{"score":[34,29],"period":"Q\#(period)","clock":"3:48","clock_s":\#(clock),"complete":false,"at":"2026-11-07T20:30:00Z"\#(extra)}}"#
            return try XCTUnwrap(try JSONDecoder().decode(Game.Lenient.self, from: Data(json.utf8)).value?.live)
        }
        XCTAssertEqual(try live(2, clock: 150).barFill, [1, 0.75, 0, 0], "Q2 with 2:30 left")
        XCTAssertEqual(try live(1, clock: 600).barFill, [0, 0, 0, 0], "tip-off")
        XCTAssertEqual(try live(4, clock: 0).barFill, [1, 1, 1, 1], "the 4th's buzzer")
        XCTAssertEqual(try live(5, clock: 150, length: 300).barFill, [1, 1, 1, 1, 0.5], "overtime adds a part")
        XCTAssertEqual(try live(6, clock: 300, length: 300).barFill, [1, 1, 1, 1, 0], "a second overtime refills it")
        XCTAssertEqual(try live(2, of: 2, clock: 300, length: 1200).barFill, [1, 0.75], "SJU's men: two halves")

        let quarter = try live(2, clock: 228, fouls: #"{"period":2,"ids":[["a","b"],["c","d","e","f","g"]]}"#)
        XCTAssertEqual(quarter.fouls, [2, 5])
        XCTAssertTrue(quarter.inBonus(0), "Loras's 5th foul of the quarter: Saint Ben's in the bonus")
        XCTAssertFalse(quarter.inBonus(1))
        XCTAssertFalse(try live(2, clock: 228, fouls: #"{"period":2,"ids":[[],["c","d","e","f"]]}"#).inBonus(0), "four is not yet")
        XCTAssertNil(try live(3, clock: 600, fouls: #"{"period":2,"ids":[[],["c","d","e","f","g"]]}"#).fouls,
                     "last quarter's count is none")
        XCTAssertTrue(try live(5, clock: 151, length: 300, fouls: #"{"period":4,"ids":[["a","b","c","d","e"],[]]}"#).inBonus(1),
                      "overtime counts with the 4th")
        let half = #"{"period":2,"ids":[[],["a","b","c","d","e","f"]]}"#
        XCTAssertFalse(try live(2, of: 2, clock: 372, length: 1200, fouls: half).inBonus(0), "a half takes seven")
        XCTAssertTrue(try live(2, of: 2, clock: 372, length: 1200, fouls: half.replacingOccurrences(of: #""f"]"#, with: #""f","g"]"#)).inBonus(0))

        XCTAssertNil(try live(2, clock: 228, bar: false).bar, "an old read has no bar")
        XCTAssertEqual(try live(2, clock: 228, bar: false).barFill, [])
        XCTAssertFalse(try live(2, clock: 228, fouls: #"{"period":2,"ids":[["a"]]}"#).inBonus(0), "a count that doesn't read is none")
        let football = try XCTUnwrap(try JSONDecoder().decode(Game.Lenient.self, from: Data(#"{"sport":"Football","teams":[{"name":"Saint John's"},{"name":"Gustavus"}],"live":{"score":[7,0],"period":"Q1","clock":"9:18","clock_s":558,"complete":false,"at":"2026-10-31T19:40:00Z"}}"#.utf8)).value)
        XCTAssertNil(football.live?.bar, "football has no bar")
        XCTAssertFalse(football.isBasketball)
        XCTAssertTrue(try XCTUnwrap(try JSONDecoder().decode(Game.Lenient.self, from: Data(#"{"sport":"Girls Basketball","teams":[{"name":"Sartell"},{"name":"Foley"}]}"#.utf8)).value).isBasketball)
    }

    /// Soccer's scorers (game-card 09): one line per player under their team, a second goal joining the
    /// first's line, a goal with no name read as "Goal"; kept past the final; none for any other sport.
    func testSoccersScorersAreOneLinePerPlayerUnderTheirTeam() throws {
        func game(_ plays: [(String, String, Int)], sport: String = "Soccer", final: Bool = false) throws -> Game {
            let list = plays.enumerated().map { i, p in
                #"{"id":"\#(i)","text":"\#(p.0)","period":"2nd half","clock":"\#(p.1)","side":\#(p.2),"score":[1,0]}"#
            }.joined(separator: ",")
            let json = #"{"sport":"\#(sport)","teams":[{"name":"Saint John's"},{"name":"Augsburg"}]"#
                + (final ? #","final":[2,1]"# : "") + #","plays":["# + list + "]}"
            return try XCTUnwrap(try JSONDecoder().decode(Game.Lenient.self, from: Data(json.utf8)).value)
        }
        let goals = [("Goal by SJU Hanson,Ben, top left", "41'", 0), ("Goal by AUG Larkin,Sam", "58'", 1),
                     ("Goal by SJU Hanson,Ben", "71'", 0), ("Goal by SJU", "88'", 0)]
        XCTAssertEqual(try game(goals).scorers, [["Hanson 41', 71'", "Goal 88'"], ["Larkin 58'"]])
        XCTAssertEqual(try game(goals, final: true).scorers, [["Hanson 41', 71'", "Goal 88'"], ["Larkin 58'"]], "kept past the final")
        XCTAssertEqual(try game([]).scorers, [[], []], "no goals yet")
        XCTAssertEqual(try game(goals, sport: "Girls Soccer").scorers.first?.first, "Hanson 41', 71'")
        XCTAssertEqual(try game(goals, sport: "Hockey").scorers, [], "only soccer has the row")
    }

    /// A game's live score (game-card 03) reads in its teams' order with the period and clock; the
    /// clock goes once it's two minutes old and Live after ten; only the server's final ends it; a bad one is none.
    func testAGamesLiveScoreReadsAndCompleteCountsAsTheFinal() throws {
        func game(_ more: String) throws -> Game {
            let json = #"{"sport":"Football","teams":[{"name":"Saint John's"},{"name":"Concordia"}]"# + more + "}"
            return try XCTUnwrap(try JSONDecoder().decode(Game.Lenient.self, from: Data(json.utf8)).value)
        }
        let on = try game(#","final":null,"live":{"score":[14,7],"period":"Q3","clock":"4:12","complete":false,"at":"2026-10-31T19:40:00.123456+00:00"}"#)
        let live = try XCTUnwrap(on.live)
        XCTAssertEqual(live.score, [14, 7])
        XCTAssertNil(on.final)
        XCTAssertNil(on.winner, "nobody fades while it's on")
        XCTAssertEqual(on.spoken, "Football, Saint John's 14, Concordia 7, Q3", "the chip says Live")
        let at = try XCTUnwrap(live.at)
        XCTAssertEqual(live.line(at: at.addingTimeInterval(60)), "Q3 · 4:12")
        XCTAssertEqual(live.line(at: at.addingTimeInterval(121)), "Q3", "a clock that stopped coming in is hidden")
        XCTAssertTrue(live.isLive(at: at.addingTimeInterval(599)))
        XCTAssertFalse(live.isLive(at: at.addingTimeInterval(601)), "ten quiet minutes: no longer Live")
        // Soccer's minute runs on between pushes and holds at the half's end through stoppage time.
        let soccer = try XCTUnwrap(try game(#","live":{"score":[0,0],"period":"1st half","clock":"2'","clock_s":94,"complete":false,"at":"2026-10-24T18:01:34Z"}"#).live)
        let pushed = try XCTUnwrap(soccer.at)
        XCTAssertEqual(soccer.line(at: pushed), "1st half · 2'")
        XCTAssertEqual(soccer.line(at: pushed.addingTimeInterval(65 * 60)), "1st half · 45'", "held at 45 through the break")
        XCTAssertEqual(soccer.line(at: pushed.addingTimeInterval(10 * 60)), "1st half · 12'", "no push for ten minutes, still running")
        let volleyball = try game(#","live":{"score":[2,0],"period":"Set 3","clock":null,"complete":false}"#)
        XCTAssertEqual(volleyball.live?.line(at: .now), "Set 3")

        let once = try game(#","live":{"score":[3,0],"period":"Set 3","clock":null,"complete":true}"#)
        XCTAssertNil(once.final, "complete once is not the final: volleyball took one back on 2026-10-24")
        XCTAssertEqual(once.live?.score, [3, 0])
        let both = try game(#","final":[33,23],"live":{"score":[30,23],"period":"Q4","complete":false}"#)
        XCTAssertEqual(both.final, [33, 23], "a final always wins over a live score")
        XCTAssertNil(both.live)
        for bad in [#","live":{"score":[1],"period":"Q1"}"#, #","live":{"score":[1,-2],"period":"Q1"}"#, #","live":"7-0""#] {
            XCTAssertNil(try game(bad).live, bad)
        }

        // Scoring plays and set scores (game-card 05): a play that doesn't read is left out, not the list.
        let plays = try game(#","live":{"score":[7,3],"period":"Q2","complete":false,"periods":[[7,0],[0,3]]},"plays":[{"id":"1","text":"C. Kern 1 yd TD run","period":"Q1","clock":"9:18","side":0,"score":[7,0]},{"id":"2","text":"bad"},{"id":"3","text":"T. Lund 34 yd field goal","period":"Q2","clock":null,"side":1,"score":[7,3]}]"#)
        XCTAssertEqual(plays.plays.map(\.id), ["1", "3"])
        XCTAssertEqual(plays.plays.map(\.when), ["Q1 · 9:18", "Q2"])
        XCTAssertEqual(plays.periods, [[7, 0], [0, 3]])
        XCTAssertEqual(plays.with(final: [7, 3], live: nil).plays.count, 2, "the plays stay past the final")

        // The map refetches for a change it shows, never for a score alone (game-card 03).
        let row = RealtimeClient.Change.Row(id: "g1", eventDate: "2026-10-31", startTime: "1 PM", status: "approved",
                                            kind: "event", title: "SJU Football vs Gustavus", location: "Clemens Stadium")
        var scored = row
        scored.liveScore = Data(#"{"score":[7,0]}"#.utf8)
        scored.finalScore = [7, 0]
        XCTAssertNotEqual(row, scored)
        XCTAssertEqual(row.withoutScores, scored.withoutScores)

        // A realtime update moves the scores on the card's game, and back to none.
        let updated = on.with(final: nil, live: try JSONDecoder().decode(Game.Live.self, from: Data(
            #"{"score":[21,7],"period":"Q4","clock":"0:45","complete":false}"#.utf8)))
        XCTAssertEqual(updated.live?.score, [21, 7])
        XCTAssertEqual(updated.with(final: [21, 7], live: nil).final, [21, 7])
        XCTAssertNil(updated.with(final: [21, 7], live: nil).live)
    }

    /// A live football game's down, distance and spot (game-card 08), as `private.sidearm_drive` writes them:
    /// the line over the field bar, the first-down marker toward the goal its team is going for, and one that
    /// doesn't read leaving the score as it was.
    func testALiveFootballGamesDriveReadsAndABadOneCostsNothing() throws {
        func live(_ drive: String) throws -> Game.Live {
            try JSONDecoder().decode(Game.Live.self, from: Data((#"{"score":[14,3],"period":"Q3","clock":"4:12","drive":"# + drive + "}").utf8))
        }
        let ours = try XCTUnwrap(try live(#"{"down":2,"togo":"7","spot":"GAC34","side":0,"ball":66}"#).drive)
        XCTAssertEqual(ours.line, "2nd & 7 · GAC 34")
        XCTAssertEqual(ours.firstDown, 73, "the host goes right, toward 100")
        XCTAssertEqual(ours.spoken(teams: try XCTUnwrap(try JSONDecoder().decode(Game.Lenient.self, from: Data(
            #"{"sport":"Football","teams":[{"name":"Saint John's"},{"name":"Gustavus Adolphus","short":"Gustavus"}]}"#.utf8)).value).teams),
                       "2nd and 7 on the GAC 34, Saint John's ball")
        let theirs = try XCTUnwrap(try live(#"{"down":3,"togo":"4","spot":"SJU12","side":1,"ball":12}"#).drive)
        XCTAssertEqual(theirs.firstDown, 8, "the other team goes left, toward 0")
        let goal = try XCTUnwrap(try live(#"{"down":1,"togo":"Goal","spot":"GAC3","side":0,"ball":97}"#).drive)
        XCTAssertEqual(goal.line, "1st & Goal · GAC 3")
        XCTAssertNil(goal.firstDown, "at the goal line the goal is the marker")
        XCTAssertEqual(try XCTUnwrap(try live(#"{"down":4,"togo":"1","spot":"50","side":0,"ball":50}"#).drive).line, "4th & 1 · 50")
        XCTAssertNil(try XCTUnwrap(try live(#"{"down":1,"togo":"10","spot":"XYZ20","side":0,"ball":null}"#).drive).firstDown,
                     "a spot naming neither team: the words, no marker")
        for bad in [#"{"down":5,"togo":"1","spot":"50","side":0}"#, #"{"down":1,"togo":"10","spot":"50","side":2}"#, #""2nd & 7""#] {
            let read = try live(bad)
            XCTAssertNil(read.drive, bad)
            XCTAssertEqual(read.score, [14, 3], "the score still reads")
        }
        XCTAssertNil(try JSONDecoder().decode(Game.Live.self, from: Data(#"{"score":[0,0],"period":"Set 1"}"#.utf8)).drive, "other sports have none")
    }

    /// A game's Attend takes our team's own color (game-card 12): the team around St. Joseph, else the home team,
    /// at the marks' brightness, with ink on it where ink reads better than white, as on BP yellow.
    func testAGamesAttendTakesOurTeamsColor() throws {
        func game(_ teams: String) throws -> Game {
            try JSONDecoder().decode(Game.self, from: Data(#"{"sport":"Soccer","teams":[\#(teams)]}"#.utf8))
        }
        let sju = ##"{"name":"Saint John's","color":"#C20430","local":true}"##
        let augsburg = ##"{"name":"Augsburg","color":"#702038"}"##
        let kennedy = ##"{"name":"Kennedy","local":true,"colors":["#1B2859"]}"##
        XCTAssertEqual(try game("\(augsburg),\(sju)").ours, 1, "ours on the right")
        XCTAssertEqual(try game("\(sju),\(augsburg)").ours, 0)
        XCTAssertEqual(try game("\(kennedy),\(sju)").ours, 0, "both ours: the home team")
        XCTAssertEqual(try game(##"{"name":"Sauk Centre"},{"name":"Minnewaska"}"##).ours, 0, "neither: the home team")
        let attend = GameMatchup.attend(try game("\(augsburg),\(sju)"))
        XCTAssertEqual(attend, GameMatchup.tone(0xC20430, lightness: 0.58, saturationFloor: 0.7), "Saint John's own cardinal")
        XCTAssertNil(GameMatchup.attend(try game(##"{"name":"Somebody","local":true},\##(augsburg)"##)), "no color: BP yellow")
        XCTAssertTrue(MeetupPillStyle.inkReads(on: try XCTUnwrap(attend)), "ink on Saint John's cardinal")
        XCTAssertTrue(MeetupPillStyle.inkReads(on: Hue.brandYellowHex), "ink on BP yellow, as before")
        let navy = try XCTUnwrap(GameMatchup.attend(try game("\(kennedy),\(augsburg)")))
        XCTAssertFalse(MeetupPillStyle.inkReads(on: navy), "white on Kennedy's navy, brightened")
    }

    /// The page's colors (game-card 08): each team's color at Apple Sports' depth, hue kept; a black or grey
    /// one (Gustavus, St. Olaf) takes its logo's first real color; none at all is none.
    func testAGamesColorsDeepenAndABlackTeamTakesItsLogosColor() throws {
        func team(_ json: String) throws -> Game.Team { try JSONDecoder().decode(Game.Team.self, from: Data(json.utf8)) }
        let sju = try team(##"{"name":"Saint John's","color":"#C20430"}"##)
        XCTAssertEqual(GameMatchup.vivid(sju), 0xC20430)
        let deep = GameMatchup.tone(0xC20430, lightness: 0.21)
        let (r, g, b) = (deep >> 16, (deep >> 8) & 0xFF, deep & 0xFF)
        XCTAssertTrue(r > 80 && r < 110 && g < 20 && b < 40, String(deep, radix: 16))
        XCTAssertEqual(GameMatchup.tone(0x000000, lightness: 0.21), 0x363636, "grey stays grey")
        let gustavus = try team(##"{"name":"Gustavus Adolphus","color":"#000000","colors":["#000000","#F2C80F","#8A8A8A"]}"##)
        XCTAssertEqual(GameMatchup.vivid(gustavus), 0xF2C80F, "black takes the logo's gold")
        XCTAssertNil(GameMatchup.vivid(try team(##"{"name":"Somebody"}"##)), "no color known")
        XCTAssertNil(GameMatchup.vivid(try team(##"{"name":"St. Olaf","color":"#000000","colors":["#000000","#FFFFFF"]}"##)))
    }

    /// Two teams in one color take two (game-card 10): Tuesday 2026-11-03's games came out one deep red. The
    /// away team takes its next color that isn't close; with none, the home team its own; with neither, the
    /// away side goes charcoal. Teams far apart keep their own.
    func testTwoTeamsInOneColorTakeTwoColors() throws {
        func team(_ json: String) throws -> Game.Team { try JSONDecoder().decode(Game.Team.self, from: Data(json.utf8)) }
        let sju = try team(##"{"name":"Saint John's","color":"#C20430","colors":["#BC0E33","#02A2E2"]}"##)
        let augsburg = try team(##"{"name":"Augsburg","color":"#702038","colors":["#74243D","#A9AAAB"]}"##)
        let csb = try team(##"{"name":"Saint Benedict","color":"#BD0F34","colors":["#BB2037","#0F9CD7"]}"##)
        let macalester = try team(##"{"name":"Macalester","color":"#D04828","colors":["#E44924","#315371","#AF4734"]}"##)
        XCTAssertEqual(GameMatchup.colors([csb, macalester]), [0xBD0F34, 0x315371], "the away team takes its navy")
        XCTAssertEqual(GameMatchup.colors([sju, augsburg]), [0x02A2E2, 0x702038], "Augsburg has only grey: Saint John's takes its blue")
        let rocori = try team(##"{"name":"ROCORI","color":"#D82008"}"##)
        let detroitLakes = try team(##"{"name":"Detroit Lakes","color":"#C02020"}"##)
        XCTAssertEqual(GameMatchup.colors([rocori, detroitLakes]), [0xD82008, GameMatchup.charcoal], "neither has another: charcoal")
        XCTAssertEqual(GameMatchup.tone(GameMatchup.charcoal, lightness: 0.21), 0x363636, "charcoal stays grey at the page's depth")
        let scholastica = try team(##"{"name":"St. Scholastica","color":"#004070"}"##)
        XCTAssertEqual(GameMatchup.colors([sju, scholastica]), [0xC20430, 0x004070], "red and blue keep their own")
        XCTAssertEqual(GameMatchup.colors([sju, try team(##"{"name":"Somebody"}"##)]), [0xC20430, nil], "none known stays none")
    }

    /// A scoring play that lands while a game is on is a moment (game-card 07): football's touchdown,
    /// field goal and safety and a goal, each with its scorer when SIDEARM's words name one, in its
    /// summary's words or its live ones; an extra point, a basket, the first read and the final are quiet.
    func testALiveGamesScoringPlayIsAMomentAndTheRestStayQuiet() throws {
        func play(_ text: String, side: Int = 0) -> Game.Play {
            let json = #"{"id":"p","text":"\#(text)","period":"Q3","clock":"4:12","side":\#(side),"score":[13,3]}"#
            return try! JSONDecoder().decode(Game.Play.self, from: Data(json.utf8))
        }
        func moment(_ text: String, sport: String = "Football", side: Int = 0) -> [String?] {
            guard let m = GameMoment.of(play(text, side: side), sport: sport) else { return [] }
            return [m.label, m.detail, String(m.side)]
        }
        XCTAssertEqual(moment("J. Jeffrey 52 yd TD run (M. Olson kick)"), ["Touchdown", "Jeffrey", "0"])
        XCTAssertEqual(moment("S. Berg 18 yd TD pass from C. Kern (M. Olson kick)"), ["Touchdown", "Berg", "0"], "the catch, not the throw")
        XCTAssertEqual(moment("Jeffrey,John rush for 52 yards to the GAC0, TOUCHDOWN, clock 03:51."), ["Touchdown", "Jeffrey", "0"])
        XCTAssertEqual(moment("Kern,Cole pass complete to Berg,Sam for 18 yards to the GAC0, TOUCHDOWN"), ["Touchdown", "Berg", "0"])
        XCTAssertEqual(moment("52 yd TD run"), ["Touchdown", nil, "0"], "no name: the label alone")
        XCTAssertEqual(moment("T. Lund 41 yd field goal", side: 1), ["Field goal", "Lund, 41 yd", "1"])
        XCTAssertEqual(moment("Lund,Tom field goal attempt from 41 GOOD", side: 1), ["Field goal", "Lund", "1"])
        XCTAssertEqual(moment("Team safety", side: 1), ["Safety", nil, "1"])
        XCTAssertEqual(moment("M. Olson kick attempt good"), [], "an extra point is quiet")
        XCTAssertEqual(moment("Goal by SJU Franzman,Gabe, low right", sport: "Soccer"), ["Goal", "Franzman", "0"])
        XCTAssertEqual(moment("Jump shot by SJU Smith,Al", sport: "Basketball"), [], "a basket is quiet")

        func game(_ more: String, sport: String = "Football") throws -> Game {
            let json = #"{"sport":"\#(sport)","teams":[{"name":"Saint John's","short":"Saint John's"},{"name":"Gustavus","short":"Gustavus"}]"# + more + "}"
            return try XCTUnwrap(try JSONDecoder().decode(Game.Lenient.self, from: Data(json.utf8)).value)
        }
        let live = #","live":{"score":[13,3],"period":"Q3","complete":false}"#
        let td = #"{"id":"3","text":"J. Jeffrey 52 yd TD run","period":"Q3","clock":"4:12","side":0,"score":[13,3]}"#
        let before = try game(live + #","plays":[]"#), after = try game(live + #","plays":["# + td + "]")
        XCTAssertEqual(GameMoment.between(before, after)?.label, "Touchdown")
        XCTAssertEqual(GameMoment.between(before, after)?.id, "3", "played once, by its play")
        XCTAssertNil(GameMoment.between(after, after), "the same plays again: quiet")
        XCTAssertNil(GameMoment.between(after, after.with(final: nil, live: try JSONDecoder().decode(Game.Live.self, from: Data(
            #"{"score":[14,3],"period":"Q3","complete":false}"#.utf8)))), "an extra point that brings no new play")
        XCTAssertNil(GameMoment.between(before, after.with(final: [13, 3], live: nil)), "the final has its own look")
        // Volleyball keeps no plays: a set is won when the next one starts.
        let set1 = try game(#","live":{"score":[0,0],"period":"Set 1","complete":false,"periods":[[24],[20]]}"#, sport: "Volleyball")
        let set2 = try game(#","live":{"score":[1,0],"period":"Set 2","complete":false,"periods":[[25,0],[20,0]]}"#, sport: "Volleyball")
        let won = try XCTUnwrap(GameMoment.between(set1, set2))
        XCTAssertEqual([won.label, won.detail, won.id], ["Set 1", "Saint John's", "set-1"])
        XCTAssertNil(GameMoment.between(set2, set2))
        let first = try game(#","live":{"score":[0,0],"period":"Set 1","complete":false,"periods":[[0],[0]]}"#, sport: "Volleyball")
        XCTAssertNil(GameMoment.between(try game("", sport: "Volleyball"), first), "the first set starting is no moment")
        // Football's quarters come as periods too: a new one is no set.
        let q1 = try game(#","live":{"score":[7,0],"period":"Q1","complete":false,"periods":[[7],[0]]}"#)
        let q2 = try game(#","live":{"score":[7,0],"period":"Q2","complete":false,"periods":[[7,0],[0,0]]}"#)
        XCTAssertNil(GameMoment.between(q1, q2), "a quarter starting is no moment")

        // Back after the app was away: the feed's fresh read brings the touchdown missed meanwhile, and
        // its last update is minutes after the one on screen. Not replayed; a play seconds after is.
        func at(_ time: String, _ plays: String) throws -> Game {
            try game(#","live":{"score":[13,3],"period":"Q3","complete":false,"at":"\#(time)"},"plays":["# + plays + "]")
        }
        let seen = try at("2026-10-31T19:40:00Z", "")
        XCTAssertNil(GameMoment.between(seen, try at("2026-10-31T19:52:00Z", td)), "missed while away: quiet")
        XCTAssertEqual(GameMoment.between(seen, try at("2026-10-31T19:40:40Z", td))?.label, "Touchdown", "live: a moment")
    }

    /// Every reason the database sends has a line; one this app doesn't know has none,
    /// so a newer database never puts a wrong line on an older app.
    func testEachReasonHasItsLine() {
        XCTAssertEqual(FeedCardMenu.line(reason: "new", name: nil), "New")
        XCTAssertEqual(FeedCardMenu.line(reason: "size", name: nil), "Big in town")
        XCTAssertEqual(FeedCardMenu.line(reason: "tomorrow", name: nil), "Happening tomorrow")
        XCTAssertEqual(FeedCardMenu.line(reason: "soon", name: nil), "Coming up soon")
        XCTAssertEqual(FeedCardMenu.line(reason: "final", name: nil), "Final score", "a game that's over (game-card 02)")
        XCTAssertEqual(FeedCardMenu.line(reason: "friend", name: "Sam"), "Sam is going")
        XCTAssertEqual(FeedCardMenu.line(reason: "tapped", name: "Sal's Bar and Grill"),
                       "You've been into Sal's Bar and Grill lately")
        XCTAssertNil(FeedCardMenu.line(reason: "tapped", name: nil))
        XCTAssertNil(FeedCardMenu.line(reason: "friend", name: nil))
        XCTAssertNil(FeedCardMenu.line(reason: "something-new", name: nil))
    }

    func testAFoundEventIsHostedByItsSourceAndAClubEventByItsClub() async {
        let town = feed([row("a"), row("b", club: "Lions Club", source: nil)])
        await town.reload(at: now)
        XCTAssertEqual(town.cards.map(\.hostName), ["City of St. Joseph", "Lions Club"])
    }

    /// The database's order, untouched: the app never re-sorts.
    func testCardsKeepTheFunctionsOrder() async {
        let town = feed([row("later", leavesIn: 2), row("sooner", leavesIn: 48), row("going", leavesIn: 1)])
        await town.reload(at: now)
        XCTAssertEqual(town.cards.map(\.id), ["later", "sooner", "going"])
    }

    /// Every list the feed takes, kept or read, sets each Event's Going in
    /// `RealLifeActions`, so an event page pushed before a read shows the read's count.
    func testEveryListTellsRealLifeActions() async {
        let actions = RealLifeActions(signedIn: true, needsAccount: true, hold: .zero, flip: .zero,
                                      setGoing: { _, _ in }, setHeart: { _, _ in },
                                      setSave: { _, _ in }, knownEvents: { _ in [] })
        var going = 3
        let town = TownFeed(read: { [TownFeed.entry(self.row("a", going: going))] },
                            kept: { [TownFeed.entry(self.row("a", going: 1))] },
                            actions: actions)
        let pushed = TownFeed.card(row("a", going: 0))

        going = 5
        await town.reload(at: now)
        XCTAssertEqual(actions.going(pushed).count, 5)
        XCTAssertEqual(actions.rsvp(town.cards[0])?.top, "5 going")

        // Offline at launch: the kept list is all there is, and it sets the base too.
        let offlineActions = RealLifeActions(signedIn: true, needsAccount: true, hold: .zero, flip: .zero,
                                             setGoing: { _, _ in }, setHeart: { _, _ in },
                                      setSave: { _, _ in }, knownEvents: { _ in [] })
        let offline = TownFeed(read: { throw Offline() },
                               kept: { [TownFeed.entry(self.row("a", going: 1))] },
                               actions: offlineActions)
        await offline.reload(at: now)
        XCTAssertTrue(offline.failed)
        XCTAssertEqual(offlineActions.going(pushed).count, 1)
    }

    /// A card goes once its time is up, and the feed knows when to read again.
    func testACardLeavesWhenItsTimeIsUp() async {
        let town = feed([row("short", leavesIn: 1), row("long", leavesIn: 5)])
        await town.reload(at: now)
        XCTAssertEqual(town.cards.map(\.id), ["short", "long"])
        XCTAssertEqual(town.nextLeave, now.addingTimeInterval(3600))

        await town.reload(at: now.addingTimeInterval(2 * 3600))
        XCTAssertEqual(town.cards.map(\.id), ["long"])
        XCTAssertEqual(town.nextLeave, now.addingTimeInterval(5 * 3600))
    }

    /// Scrolled down, a card whose time is up keeps its place, so nothing moves under the
    /// finger, while the leave timer moves on; back at the top it goes (Jesse, 2026-10-21).
    func testAFinishedCardWaitsForTheTopBeforeItLeaves() async {
        let town = feed(answers: [[TownFeed.entry(row("short", leavesIn: 1)), TownFeed.entry(row("long", leavesIn: 5))],
                                  [TownFeed.entry(row("long", leavesIn: 5))]])
        await town.reload(at: now)
        town.scrolled(to: 300)
        await town.refresh(at: now.addingTimeInterval(2 * 3600))
        XCTAssertEqual(town.cards.map(\.id), ["short", "long"])
        XCTAssertEqual(town.nextLeave, now.addingTimeInterval(5 * 3600), "the leave timer still moves on")
        town.scrolled(to: 0)
        XCTAssertEqual(town.cards.map(\.id), ["long"])
    }

    /// Scrolled down, a card the read no longer has (called off, say) keeps its place too, and
    /// leaves at the top with the finished ones.
    func testACardTheReadDropsWaitsForTheTopToo() async {
        let town = feed(answers: [entries(["a", "b"]), entries(["a"])])
        await town.reload(at: now)
        town.scrolled(to: 300)
        await town.refresh(at: now.addingTimeInterval(60))
        XCTAssertEqual(town.cards.map(\.id), ["a", "b"])
        town.scrolled(to: 0)
        XCTAssertEqual(town.cards.map(\.id), ["a"])
    }

    /// The clock moves only once the read is done. The feed's leave timer is keyed on
    /// `nextLeave`, which the clock decides: moved first, it cancelled the timer's own
    /// read, so a series' next date never came in.
    func testTheClockMovesOnlyOnceTheReadIsDone() async {
        final class Probe { var town: TownFeed?; var clockDuringRead: Date? }
        let probe = Probe()
        let town = TownFeed {
            probe.clockDuringRead = probe.town?.clock
            return [TownFeed.entry(self.row("a"))]
        }
        probe.town = town
        let before = town.clock
        await town.reload(at: now)
        XCTAssertEqual(probe.clockDuringRead, before)
        XCTAssertEqual(town.clock, now)
    }

    /// Skeleton until the first answer; a failed first read shows the retry; a failed
    /// refresh keeps the list already showing.
    func testAFailedReadKeepsTheListAlreadyShowing() async {
        var answers: [Result<[TownFeedEntry], Error>] = [
            .failure(Offline()),
            .success([TownFeed.entry(row("a"))]),
            .failure(Offline()),
        ]
        let town = TownFeed { try answers.removeFirst().get() }
        XCTAssertNil(town.entries)

        await town.reload(at: now)
        XCTAssertTrue(town.failed)
        XCTAssertNil(town.entries)

        await town.reload(at: now)
        XCTAssertFalse(town.failed)
        XCTAssertEqual(town.cards.map(\.id), ["a"])

        await town.reload(at: now)
        XCTAssertTrue(town.failed, "a failed refresh over a list says it's offline")
        XCTAssertEqual(town.cards.map(\.id), ["a"])
    }

    // MARK: When the order changes (ticket 11)

    private func entries(_ ids: [String], going: Int = 0) -> [TownFeedEntry] {
        ids.map { TownFeed.entry(row($0, going: going)) }
    }

    /// A feed whose reads answer in turn.
    private func feed(answers: [[TownFeedEntry]], kept: [TownFeedEntry]? = nil) -> TownFeed {
        var answers = answers
        return TownFeed(read: { answers.removeFirst() }, kept: { kept })
    }

    /// Back within 30 minutes, the order on screen stays: cards update in place, a
    /// card that went drops out, and a new one waits for the next fresh order.
    func testBackSoonKeepsTheOrderOnScreen() async {
        let town = feed(answers: [entries(["a", "b", "c"]),
                                  entries(["new", "c", "a"], going: 5)])
        town.cameBack(at: now)
        await town.reload(at: now)
        town.scrolled(to: 300)
        town.left(at: now)
        town.scrolled(to: 0)  // another tab: the rebuilt screen starts at the top
        town.cameBack(at: now.addingTimeInterval(29 * 60))
        await town.refresh(at: now.addingTimeInterval(29 * 60))
        XCTAssertEqual(town.cards.map(\.id), ["a", "c"])
        XCTAssertEqual(town.cards.map(\.goingCount), [5, 5])
    }

    /// The admin's Score names each card's place on screen, not the database's, so it
    /// holds after a read that kept the order.
    func testScoreNamesTheCardsPlaceOnScreen() async {
        func scored(_ ids: [String]) -> [TownFeedEntry] {
            ids.enumerated().map { place, id in
                var row = row(id)
                row.score = FeedScore(interest: 0, friend: 0, follow: 0, popular: 0, size: 0,
                                      sizeStep: 1, daysAway: 1, soon: 0.9, acted: 1, spacing: 1,
                                      newSpot: false, total: 0.9, spot: place + 1, of: ids.count)
                return TownFeed.entry(row)
            }
        }
        let town = feed(answers: [scored(["a", "b", "c"]), scored(["new", "c", "a"])])
        town.cameBack(at: now)
        await town.reload(at: now)
        town.scrolled(to: 300)
        town.left(at: now)
        town.scrolled(to: 0)  // another tab: the rebuilt screen starts at the top
        town.cameBack(at: now.addingTimeInterval(29 * 60))
        await town.refresh(at: now.addingTimeInterval(29 * 60))
        XCTAssertEqual(town.cards.map(\.id), ["a", "c"])
        XCTAssertEqual(town.cards.map { $0.score?.spot }, [1, 2])
        XCTAssertEqual(town.cards.map { $0.score?.of }, [2, 2])
    }

    /// Back after 30 minutes or more, still at the top: the fresh order.
    func testBackAfterHalfAnHourAtTheTopTakesTheFreshOrder() async {
        let town = feed(answers: [entries(["a", "b"]), entries(["new", "b", "a"])])
        town.cameBack(at: now)
        await town.reload(at: now)
        town.left(at: now)
        town.cameBack(at: now.addingTimeInterval(30 * 60))
        await town.refresh(at: now.addingTimeInterval(30 * 60))
        XCTAssertEqual(town.cards.map(\.id), ["new", "b", "a"])
    }

    /// Already scrolling when the fresh order lands: it waits for the next pull, so
    /// nothing moves under the finger.
    func testAFreshOrderWaitsForAPullOnceTheScreenHasScrolled() async {
        let town = feed(answers: [entries(["a", "b"]), entries(["new", "b", "a"]),
                                  entries(["new", "b", "a"])])
        town.cameBack(at: now)
        await town.reload(at: now)
        town.left(at: now)
        town.cameBack(at: now.addingTimeInterval(60 * 60))
        town.scrolled(to: 300)
        await town.refresh(at: now.addingTimeInterval(60 * 60))
        XCTAssertEqual(town.cards.map(\.id), ["a", "b"])

        await town.reload(at: now.addingTimeInterval(60 * 60))
        XCTAssertEqual(town.cards.map(\.id), ["new", "b", "a"])
    }

    /// A launch shows the list kept on the phone at once, before its read answers,
    /// then the fresh order (a launch counts as long away).
    func testALaunchShowsTheKeptListAtOnceThenTheFreshOrder() async {
        final class Probe { var town: TownFeed?; var shownDuringRead: [String]? }
        let probe = Probe()
        let town = TownFeed(read: {
            probe.shownDuringRead = probe.town?.cards.map(\.id)
            return self.entries(["new", "a"])
        }, kept: { self.entries(["a"]) })
        probe.town = town
        town.cameBack(at: now)
        await town.refresh(at: now)
        XCTAssertEqual(probe.shownDuringRead, ["a"])
        XCTAssertEqual(town.cards.map(\.id), ["new", "a"])
    }

    /// Offline at launch: the kept list stays and the feed says it's offline. A kept
    /// list with nothing still on shows the skeleton, not an empty feed.
    func testOfflineAtLaunchKeepsTheKeptList() async {
        let offline = TownFeed(read: { throw Offline() }, kept: { self.entries(["a"]) })
        await offline.refresh(at: now)
        XCTAssertEqual(offline.cards.map(\.id), ["a"])
        XCTAssertTrue(offline.failed)

        let gone = [TownFeed.entry(row("old", leavesIn: -1))]
        let stale = TownFeed(read: { throw Offline() }, kept: { gone })
        await stale.refresh(at: now)
        XCTAssertNil(stale.entries)
    }

    /// Back within 30 minutes it lands where it was; after, from the top.
    func testComingBackLandsWhereItWasUnlessLongAway() {
        let town = feed(answers: [])
        town.cameBack(at: now)
        town.scrolled(to: 900)
        town.left(at: now)
        town.scrolled(to: 0)    // the rebuilt screen starts at the top
        town.cameBack(at: now.addingTimeInterval(10 * 60))
        XCTAssertEqual(town.returnY, 900)

        town.scrolled(to: 900)
        town.left(at: now)
        town.cameBack(at: now.addingTimeInterval(45 * 60))
        XCTAssertEqual(town.returnY, 0)
    }

    /// Reads overlap: a slow one that lands last never overwrites a newer answer.
    func testOnlyTheNewestReadIsKept() async {
        final class Gate { var open: (() -> Void)?; var calls = 0 }
        let gate = Gate()
        let town = TownFeed(read: {
            gate.calls += 1
            if gate.calls == 1 {
                await withCheckedContinuation { done in gate.open = { done.resume() } }
                return self.entries(["older"])
            }
            return self.entries(["newer"])
        })
        let slow = Task { await town.reload(at: now) }
        while gate.open == nil { await Task.yield() }
        await town.reload(at: now)
        gate.open?()
        await slow.value
        XCTAssertEqual(town.cards.map(\.id), ["newer"])
    }

    /// The kept list and the kept Event of the day read back what was saved, each its own, and
    /// signing out clears both.
    func testTheKeptListIsClearedOnSignOut() {
        TownFeedCache.save(Data("[1]".utf8))
        TownFeedCache.save(Data("[2]".utf8), .eventOfTheDay)
        XCTAssertEqual(TownFeedCache.load(), Data("[1]".utf8))
        XCTAssertEqual(TownFeedCache.load(.eventOfTheDay), Data("[2]".utf8))
        TownFeedCache.clear()
        XCTAssertNil(TownFeedCache.load())
        XCTAssertNil(TownFeedCache.load(.eventOfTheDay))
    }

    // MARK: Views and opens (ticket 20)

    /// Keeps every batch it's sent, and fails when told to.
    @MainActor
    private final class Sender {
        var batches: [[FeedAction]] = []
        var error: Error?
        func send(_ batch: [FeedAction]) async throws {
            if let error { throw error }
            batches.append(batch)
        }
    }

    /// A feed on screen with cards a, b and c, its views going to `sender`.
    private func shownFeed(_ sender: Sender, ids: [String] = ["a", "b", "c"]) async -> TownFeed {
        let rows = ids.map { row($0) }
        let town = TownFeed(read: { rows.map(TownFeed.entry) }, send: sender.send)
        await town.reload(at: now)
        town.cameBack(at: now)
        return town
    }

    private func views(_ town: TownFeed) -> [String] {
        town.unsent.filter { $0.kind == .view }.map(\.itemID)
    }

    func testOneSecondHalfOnScreenIsOneViewAndLessIsNone() async {
        let town = await shownFeed(Sender())
        town.cardOnScreen("a", true, at: now)
        town.cardOnScreen("a", false, at: now.addingTimeInterval(1))
        town.cardOnScreen("b", true, at: now)
        town.cardOnScreen("b", false, at: now.addingTimeInterval(0.9))
        XCTAssertEqual(views(town), ["a"])
    }

    func testACardSeenTwiceInOneFeedLoadIsOneView() async {
        let town = await shownFeed(Sender())
        for start in [0.0, 5.0] {
            town.cardOnScreen("a", true, at: now.addingTimeInterval(start))
            town.cardOnScreen("a", false, at: now.addingTimeInterval(start + 2))
        }
        XCTAssertEqual(views(town), ["a"])
    }

    /// Leaving counts a card still on screen; time away counts nothing, and back on
    /// screen its second starts over.
    func testLeavingCountsWhatsOnScreenAndTimeAwayCountsNothing() async {
        let town = await shownFeed(Sender())
        town.cardOnScreen("a", true, at: now)
        town.cardOnScreen("b", true, at: now.addingTimeInterval(0.5))
        town.left(at: now.addingTimeInterval(1.2))
        XCTAssertEqual(views(town), ["a"], "a was on 1.2 s, b only 0.7 s")

        town.cameBack(at: now.addingTimeInterval(600))
        town.cardOnScreen("b", false, at: now.addingTimeInterval(600.5))
        XCTAssertEqual(views(town), ["a"], "ten minutes away is not ten minutes seen")
    }

    /// A tab switch rebuilds the screen: its cards never report going off, so they're
    /// forgotten, and a later feed load counts only what the rebuilt screen reports.
    func testCardsFromAScreenThatWentAreNotCountedAgain() async {
        let town = await shownFeed(Sender())
        town.cardOnScreen("c", true, at: now)
        town.left(at: now.addingTimeInterval(2), viewGone: true)
        XCTAssertEqual(views(town), ["c"])

        town.cameBack(at: now.addingTimeInterval(31 * 60))
        await town.reload(at: now.addingTimeInterval(31 * 60))
        town.left(at: now.addingTimeInterval(32 * 60))
        XCTAssertEqual(views(town), ["c"], "c was never on the rebuilt screen")
    }

    func testAFreshOrderStartsANewFeedLoad() async {
        let town = await shownFeed(Sender())
        town.cardOnScreen("a", true, at: now)
        town.cardOnScreen("a", false, at: now.addingTimeInterval(1))
        await town.reload(at: now.addingTimeInterval(60))
        town.cardOnScreen("a", true, at: now.addingTimeInterval(61))
        town.cardOnScreen("a", false, at: now.addingTimeInterval(62))
        XCTAssertEqual(views(town), ["a", "a"])
    }

    func testACardNoLongerInTheListIsNotCounted() async {
        let town = await shownFeed(Sender(), ids: ["a"])
        town.cardOnScreen("gone", true, at: now)
        town.cardOnScreen("gone", false, at: now.addingTimeInterval(2))
        XCTAssertEqual(views(town), [])
    }

    func testOneBatchEvery30SecondsAndAtOnceWhenTheAppLeaves() async {
        let sender = Sender()
        let town = await shownFeed(sender)
        town.opened("a")
        await town.send(at: now)
        XCTAssertEqual(sender.batches, [[FeedAction(itemID: "a", kind: .open)]], "the first goes at once")

        town.opened("b")
        await town.send(at: now.addingTimeInterval(29))
        XCTAssertEqual(sender.batches.count, 1, "nothing before 30 s")
        await town.send(at: now.addingTimeInterval(30))
        XCTAssertEqual(sender.batches.count, 2)

        town.opened("c")
        await town.send(at: now.addingTimeInterval(31), always: true)
        XCTAssertEqual(sender.batches.last, [FeedAction(itemID: "c", kind: .open)], "leaving sends now")
    }

    /// No network or no account: the batch waits for the next. A refused one is dropped.
    func testAFailedBatchJoinsTheNextAndARefusedOneIsDropped() async {
        let sender = Sender()
        let town = await shownFeed(sender)
        sender.error = URLError(.notConnectedToInternet)
        town.opened("a")
        await town.send(at: now)
        sender.error = SupabaseError(message: "no session", status: 401)
        town.opened("b")
        await town.send(at: now.addingTimeInterval(30))
        sender.error = nil
        town.opened("c")
        await town.send(at: now.addingTimeInterval(60))
        XCTAssertEqual(sender.batches.last?.map(\.itemID), ["a", "b", "c"])

        sender.error = SupabaseError(message: "bad row", status: 400)
        town.opened("d")
        await town.send(at: now.addingTimeInterval(90))
        sender.error = nil
        town.opened("e")
        await town.send(at: now.addingTimeInterval(120))
        XCTAssertEqual(sender.batches.last?.map(\.itemID), ["e"], "a refused batch would fail every one after it")
    }

    func testANewAccountDropsTheLastOnesWaitingViews() async {
        let sender = Sender()
        let town = await shownFeed(sender)
        town.opened("a")
        town.accountChanged()
        await town.send(at: now, always: true)
        XCTAssertEqual(sender.batches, [])
    }

    /// The Town feed's own default sends nowhere, so tests and previews never write.
    func testAFeedBuiltForTestsSendsNowhere() async {
        let town = TownFeed(read: { [] })
        town.opened("a")
        await town.send(at: now, always: true)
        XCTAssertEqual(town.unsent, [])
    }

    // MARK: Not interested and Mute (ticket 21)

    /// Keeps every choice it's told, answers a Mute with its host, and fails when told to.
    @MainActor
    private final class Chooser {
        var told: [FeedChoice] = []
        var error: Error?
        var muted: [MutedHost] = []
        var delay: Duration?
        func choose(_ choice: FeedChoice) async throws -> String? {
            if let delay { try await Task.sleep(for: delay) }
            if let error { throw error }
            told.append(choice)
            if case .mute = choice { return "parks-key" }
            return nil
        }
    }

    /// Cards a and b from Parks, c from the City, on screen.
    private func choosingFeed(_ chooser: Chooser, rows extra: [TownFeedRow] = []) async -> TownFeed {
        let rows = [row("a", source: "Parks"), row("b", source: "Parks"), row("c")] + extra
        let town = TownFeed(read: { rows.map(TownFeed.entry) }, choose: chooser.choose,
                            readMuted: { chooser.muted })
        await town.reload(at: now)
        return town
    }

    private func ids(_ town: TownFeed) -> [String] { town.cards.map(\.id) }

    func testNotInterestedFoldsTheCardToItsUndoLineThenItGoesAndIsSent() async {
        let chooser = Chooser()
        let town = await choosingFeed(chooser)
        await town.hide(town.cards[0], mute: false)
        XCTAssertEqual(chooser.told, [.notInterested("a")], "sent straight away")
        XCTAssertEqual(town.undo, FeedHide(id: "a", hostName: "Parks", mute: false))
        XCTAssertEqual(ids(town), ["a", "b", "c"], "a stays in, drawn as its Undo line")
        town.undoEnded("a")
        XCTAssertNil(town.undo)
        XCTAssertEqual(ids(town), ["b", "c"])
    }

    func testMuteTakesEveryCardFromTheHost() async {
        let chooser = Chooser()
        let town = await choosingFeed(chooser)
        await town.hide(town.cards[1], mute: true)
        XCTAssertEqual(chooser.told, [.mute("b")])
        XCTAssertEqual(ids(town), ["b", "c"], "a goes at once; b shows its Undo line")
        town.undoEnded("b")
        XCTAssertEqual(ids(town), ["c"])
    }

    func testUndoBringsTheCardBackAndTakesTheChoiceBack() async {
        let chooser = Chooser()
        let town = await choosingFeed(chooser)
        await town.hide(town.cards[0], mute: false)
        await town.undoHide()
        await town.hide(town.cards[1], mute: true)
        await town.undoHide()
        XCTAssertEqual(chooser.told, [.notInterested("a"), .undoNotInterested("a"), .mute("b"), .unmute("parks-key")])
        XCTAssertNil(town.undo)
        XCTAssertEqual(ids(town), ["a", "b", "c"])
    }

    // MARK: News's ••• (news-menu)

    /// Event a from Parks, then Parks' news p1 and p2 and the City's news c1.
    private func newsFeed(_ chooser: Chooser) async -> TownFeed {
        let news = [("p1", "Parks"), ("p2", "Parks"), ("c1", "City of St. Joseph")].map { id, place in
            TownNews(id: id, place: place, words: "News \(id)", post: URL(string: "https://x/\(id)")!,
                     leavesAt: now.addingTimeInterval(86_400))
        }
        let entries = [TownFeed.entry(row("a", source: "Parks"))]
            + news.map { TownFeedEntry(item: .news($0), leavesAt: $0.leavesAt) }
        let town = TownFeed(read: { entries }, choose: chooser.choose)
        await town.reload(at: now)
        return town
    }

    func testNotInterestedOnNewsFoldsThatPostAloneAndSendsItsID() async {
        let chooser = Chooser()
        let town = await newsFeed(chooser)
        await town.hide(id: "p1", host: "Parks", mute: false)
        XCTAssertEqual(chooser.told, [.notInterested("p1")])
        XCTAssertEqual(town.shown.map(\.id), ["a", "p1", "p2", "c1"], "p1 stays in, drawn as its Undo line")
        town.undoEnded("p1")
        XCTAssertEqual(town.shown.map(\.id), ["a", "p2", "c1"])
    }

    func testMuteOnNewsTakesItsPlacesNewsAndEventsAndUndoBringsThemBack() async {
        let chooser = Chooser()
        let town = await newsFeed(chooser)
        await town.hide(id: "p2", host: "Parks", mute: true)
        XCTAssertEqual(chooser.told, [.mute("p2")])
        XCTAssertEqual(town.shown.map(\.id), ["p2", "c1"], "p2 shows its Undo line")
        await town.undoHide()
        XCTAssertEqual(chooser.told, [.mute("p2"), .unmute("parks-key")])
        XCTAssertEqual(town.shown.map(\.id), ["a", "p1", "p2", "c1"])
    }

    func testTheUndoLineFindsNewsByItsOwnID() {
        let news = DailyFeedItem.news(TownNews(id: "p1", place: "Parks", words: "x", post: URL(string: "https://x")!,
                                               leavesAt: .distantFuture))
        XCTAssertEqual(news.hideID, "p1")
        XCTAssertNil(news.eventID, "views still go for Events only")
    }

    // MARK: Report (ticket 22)

    func testReportSendsTheReasonThenTheCardFoldsAndUndoLiftsOnlyTheHide() async throws {
        let chooser = Chooser()
        let town = await choosingFeed(chooser)
        try await town.report(town.cards[0], .scam)
        XCTAssertEqual(chooser.told, [.report("a", .scam)])
        XCTAssertEqual(ids(town), ["a", "b", "c"], "nothing moves while the sheet is open")
        town.hideReported(town.cards[0])
        XCTAssertEqual(town.undo, FeedHide(id: "a", hostName: "Parks", mute: false))
        await town.undoHide()
        XCTAssertEqual(chooser.told, [.report("a", .scam), .undoNotInterested("a")], "the report stays sent")
        XCTAssertEqual(ids(town), ["a", "b", "c"])
    }

    func testAReportThatFailsThrowsAndHidesNothing() async {
        let chooser = Chooser()
        chooser.error = URLError(.notConnectedToInternet)
        let town = await choosingFeed(chooser)
        do {
            try await town.report(town.cards[0], .nudity)
            XCTFail("the sheet must hear it failed")
        } catch {}
        XCTAssertEqual(ids(town), ["a", "b", "c"])
        XCTAssertNil(town.undo)
    }

    func testWrongPhotoOnlyWithASavedPhotoWrongInfoOnlyOnAFoundEventAndNeitherHides() {
        XCTAssertEqual(ReportReason.offered(photo: false, found: false).map(\.label),
                       ["Scam, fraud or spam", "Bullying or unwanted contact", "Violence, hate or exploitation",
                        "Nudity or sexual activity", "Selling or promoting restricted items",
                        "Suicide, self-injury or eating disorders"])
        XCTAssertEqual(ReportReason.offered(photo: true, found: true).prefix(2), [.wrongPhoto, .wrongInfo])
        XCTAssertEqual(ReportReason.allCases.filter { !$0.hides }, [.wrongPhoto, .wrongInfo])
    }

    /// A slow network: Undo tapped while the Mute is still on its way waits for it, so the server
    /// gets the Mute first and Undo knows which host to unmute.
    func testUndoWaitsForTheChoiceStillOnItsWay() async {
        let chooser = Chooser()
        let town = await choosingFeed(chooser)
        chooser.delay = .milliseconds(200)
        let card = town.cards[0]
        let hiding = Task { await town.hide(card, mute: true) }
        while town.undo == nil { await Task.yield() }
        await town.undoHide()
        await hiding.value
        XCTAssertEqual(chooser.told, [.mute("a"), .unmute("parks-key")])
        XCTAssertEqual(ids(town), ["a", "b", "c"])
    }

    func testAChoiceThatDoesntGoThroughBringsTheCardBack() async {
        let chooser = Chooser()
        chooser.error = URLError(.notConnectedToInternet)
        let town = await choosingFeed(chooser)
        await town.hide(town.cards[0], mute: true)
        XCTAssertNil(town.undo)
        XCTAssertEqual(ids(town), ["a", "b", "c"])
    }

    func testAReadThatRacedTheChoiceDoesntBringTheCardBack() async {
        let chooser = Chooser()
        let town = await choosingFeed(chooser)
        await town.hide(town.cards[2], mute: false)
        town.undoEnded("c")
        await town.reload(at: now)
        XCTAssertEqual(ids(town), ["a", "b"])
    }

    func testUnmuteTakesTheHostOffTheListAndBringsItsCardsBack() async {
        let chooser = Chooser()
        chooser.muted = [MutedHost(host: "parks-key", name: "Parks"), MutedHost(host: "x", name: "Loso's")]
        let town = await choosingFeed(chooser)
        await town.hide(town.cards[0], mute: true)
        town.undoEnded("a")
        XCTAssertEqual(ids(town), ["c"])
        await town.refreshMuted()
        await town.unmute(chooser.muted[0], at: now)
        XCTAssertEqual(town.muted, [MutedHost(host: "x", name: "Loso's")])
        XCTAssertEqual(chooser.told.last, .unmute("parks-key"))
        XCTAssertEqual(ids(town), ["a", "b", "c"])
    }

    func testAFailedUnmuteKeepsTheRowAndCountsAFailure() async {
        let chooser = Chooser()
        chooser.muted = [MutedHost(host: "parks-key", name: "Parks")]
        let town = await choosingFeed(chooser)
        await town.refreshMuted()
        chooser.error = URLError(.notConnectedToInternet)
        await town.unmute(chooser.muted[0])
        XCTAssertEqual(town.muted, chooser.muted)
        XCTAssertEqual(town.unmuteFailures["parks-key"], 1)
    }

    func testANewAccountForgetsTheLastOnesHiddenCards() async {
        let town = await choosingFeed(Chooser())
        await town.hide(town.cards[0], mute: true)
        town.accountChanged()
        XCTAssertNil(town.undo)
        XCTAssertEqual(ids(town), ["a", "b", "c"])
    }

    func testAScoreFromBeforeNotInterestedStillReads() throws {
        let json = #"{"interest":0,"friend":0,"follow":0,"popular":0,"viewers":0,"size":0,"sizeStep":1,"daysAway":1,"soon":1,"acted":1,"spacing":1,"newSpot":false,"total":1,"spot":1,"of":1}"#
        XCTAssertNil(try JSONDecoder().decode(FeedScore.self, from: Data(json.utf8)).notInterested)
        let newer = #"{"interest":0,"friend":0,"follow":0,"popular":0,"viewers":0,"size":0,"sizeStep":1,"daysAway":1,"soon":1,"acted":1,"notInterested":0.3,"spacing":1,"newSpot":false,"total":1,"spot":1,"of":1}"#
        XCTAssertEqual(try JSONDecoder().decode(FeedScore.self, from: Data(newer.utf8)).notInterested, 0.3)
    }

    // MARK: After the best (town-feed 23)

    private func place(_ id: String) -> SearchItem {
        let logo = SearchLogo(placeId: id, row: .init(url: URL(string: "https://x/\(id).webp")!, hue: 0, chroma: false))
        return SearchItem(id: "p:\(id)", kind: .business, name: "Place \(id)", logo: logo, placeID: id)
    }

    func testNearTheEndTheFirstRoundBringsTheLineLaterEventsAndPlaces() async {
        let asked = Box<[Int]>([])
        let town = TownFeed(read: { [self] in [row("a"), row("b")].map(TownFeed.entry) },
                            readLater: { [self] in [row("x"), row("b")].map(TownFeed.entry) },
                            readMore: { round, opened, shown in
                                asked.value.append(round)
                                XCTAssertEqual(opened, ["p2"])
                                XCTAssertEqual(shown, ["a", "b"], "the list on screen: the only repeats")
                                return [.init(kind: .place, id: "p1"), .init(kind: .place, id: "gone"),
                                        .init(kind: .place, id: "p2"), .init(kind: .unknown, id: "?")]
                            },
                            opened: { ["p2"] })
        await town.reload(at: now)
        XCTAssertEqual(town.column(eventOfTheDay: [], now: now).map(\.id), ["event:a", "event:b", "caught-up"],
                       "the list ends on the line at once; nothing past it until its end comes near")
        await town.loadMore()
        let items = town.column(eventOfTheDay: [], now: now) { ["p1", "p2"].contains($0) ? self.place($0) : nil }
        XCTAssertEqual(items.map(\.id), ["event:a", "event:b", "caught-up", "event:x", "place:0:p:p1", "place:0:p:p2"],
                       "b is already above; a place Search can't open, and an unknown kind, are left out")
        XCTAssertEqual(asked.value, [0])
    }

    func testEachRoundAppendsBelowWithRepeatsOfOnlyWhatsStillAbove() async {
        let town = TownFeed(read: { [self] in [row("a"), row("b")].map(TownFeed.entry) },
                            readMore: { round, _, _ in
                                round == 0 ? [.init(kind: .place, id: "p1")]
                                    : [.init(kind: .place, id: "p1"), .init(kind: .again, id: "a"),
                                       .init(kind: .again, id: "hidden-or-gone")]
                            })
        await town.reload(at: now)
        await town.loadMore()
        await town.loadMore()
        let items = town.column(eventOfTheDay: [], now: now) { $0 == "p1" ? self.place($0) : nil }
        XCTAssertEqual(items.map(\.id), ["event:a", "event:b", "caught-up", "place:0:p:p1", "place:1:p:p1",
                                         "again:1:a"])
        XCTAssertEqual(items.last?.hideID, "a", "Not interested on a repeat folds it in place")
        XCTAssertNil(items.last?.eventID, "a repeat's view is counted where it first showed")
    }

    func testAFreshOrderClearsWhatsPastTheListAndARoundItOvertookNeverLands() async {
        let feedBox = Box<TownFeed?>(nil)
        let reorder = Box(false)
        let town = TownFeed(read: { [self] in [row("a")].map(TownFeed.entry) },
                            readMore: { _, _, _ in
                                if reorder.value { await feedBox.value?.reload() }
                                return [.init(kind: .place, id: "p1")]
                            })
        feedBox.value = town
        await town.reload(at: now)
        await town.loadMore()
        XCTAssertEqual(town.rounds.count, 1)
        await town.reload(at: now)
        XCTAssertTrue(town.rounds.isEmpty, "a fresh order starts past the list again")
        reorder.value = true
        await town.loadMore()
        XCTAssertTrue(town.rounds.isEmpty, "the round a fresh order overtook is dropped")
        XCTAssertFalse(town.loadingMore)
        town.accountChanged()
        XCTAssertTrue(town.later.isEmpty && town.rounds.isEmpty)
    }

    func testNothingPastAnEmptyListAndAFailedRoundIsAskedAgain() async {
        let asked = Box(0)
        let fail = Box(true)
        let empty = TownFeed(read: { [] }, readMore: { _, _, _ in asked.value += 1; return [] })
        await empty.reload(at: now)
        await empty.loadMore()
        XCTAssertEqual(asked.value, 0, "an empty list keeps its own quiet screen")
        XCTAssertTrue(empty.column(eventOfTheDay: [], now: now).isEmpty)
        let town = TownFeed(read: { [self] in [row("a")].map(TownFeed.entry) },
                            readMore: { _, _, _ in
                                if fail.value { throw Offline() }
                                return [.init(kind: .place, id: "p1")]
                            })
        await town.reload(at: now)
        await town.loadMore()
        XCTAssertTrue(town.rounds.isEmpty)
        XCTAssertFalse(town.loadingMore, "a failed round leaves no skeleton")
        XCTAssertEqual(town.column(eventOfTheDay: [], now: now).map(\.id), ["event:a", "caught-up"],
                       "offline the list still ends on the line, which asks again when it comes back on screen")
        fail.value = false
        await town.loadMore()
        XCTAssertEqual(town.rounds.count, 1)
    }

    func testALaterEventSaidNotInterestedToStaysOut() async {
        let town = TownFeed(read: { [self] in [row("a")].map(TownFeed.entry) },
                            choose: { _ in nil },
                            readLater: { [self] in [row("x"), row("y")].map(TownFeed.entry) },
                            readMore: { _, _, _ in [] })
        await town.reload(at: now)
        await town.loadMore()
        await town.hide(id: "x", host: "City of St. Joseph", mute: false)
        town.undoEnded("x")
        XCTAssertEqual(town.column(eventOfTheDay: [], now: now).map(\.id), ["event:a", "caught-up", "event:y"])
    }
}


private extension TownFeed {
    /// A card's own hide, as its ••• sheet sends it.
    func hide(_ card: FeedCardItem, mute: Bool) async { await hide(id: card.id, host: card.hostName, mute: mute) }

}

/// A value the test and a feed's closures share.
private final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

