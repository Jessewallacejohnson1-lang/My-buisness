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
    private let now = YourDayLogic.townDay("2026-10-07")!.addingTimeInterval(12 * 3600)

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
        [{"id":"e1","title":"Fish fry","event_date":"2026-10-23","start_time":"5 PM","location":null,
          "image_url":null,"category":"dining","club_name":null,"source_name":"Church of St. Joseph",
          "end_at":null,"all_day":false,"created_at":"2026-10-06T16:08:20+00:00","going_count":0,
          "rsvpd":false,"recurrence":null,"leaves_at":"2099-10-24T00:00:00+00:00","kind":"event","source_url":null},
         {"id":"n1","title":"Flight Friday","event_date":null,"start_time":null,"location":null,
          "image_url":null,"category":"business","club_name":null,"source_name":"The Wandering Cow",
          "end_at":null,"all_day":false,"created_at":"2026-10-22T23:44:07+00:00","going_count":0,
          "rsvpd":false,"recurrence":null,"leaves_at":"2099-10-29T23:44:07+00:00","reason":"interest",
          "reason_name":"dining","description":"Four scoops for $5 at Wandering Cow on Fridays.",
          "place_picture":{"url":"https://x/cow-logo.webp","kind":"logo","hue":19},
          "kind":"news","source_url":"https://www.instagram.com/p/Deki5CwgiQG/"},
         {"id":"n2","title":"Happy hour","event_date":null,"start_time":null,"location":null,
          "image_url":null,"category":"business","club_name":null,"source_name":"Neighbors Route 75",
          "end_at":null,"all_day":false,"created_at":"2026-10-22T23:44:07+00:00","going_count":0,
          "rsvpd":false,"recurrence":null,"leaves_at":"2099-10-29T23:44:07+00:00","description":" ",
          "place_picture":null,"kind":"news","source_url":"https://www.facebook.com/x/posts/1"},
         {"id":"n3","title":"No link","event_date":null,"start_time":null,"location":null,"image_url":null,
          "category":"business","club_name":null,"source_name":"Somewhere","end_at":null,"all_day":false,
          "created_at":"2026-10-22T23:44:07+00:00","going_count":0,"rsvpd":false,"recurrence":null,
          "leaves_at":"2099-10-29T23:44:07+00:00","kind":"news","source_url":null}]
        """
        let lines = try CommunityAPI.townFeedLines(from: Data(json.utf8))
        XCTAssertEqual(lines.count, 3)
        guard case .event(let fish) = lines[0], case .news(let flight) = lines[1], case .news(let happy) = lines[2]
        else { return XCTFail("\(lines)") }
        XCTAssertEqual(fish.event.title, "Fish fry")
        XCTAssertEqual(flight.place, "The Wandering Cow")
        XCTAssertEqual(flight.words, "Four scoops for $5 at Wandering Cow on Fridays.")
        XCTAssertEqual(flight.post.absoluteString, "https://www.instagram.com/p/Deki5CwgiQG/")
        XCTAssertEqual(flight.picture?.kind, .logo)
        XCTAssertEqual(happy.words, "Happy hour", "no facts line: its title")
        XCTAssertNil(happy.picture)
        // The events' own readers (the Event of the day, a kept list) never see news.
        XCTAssertEqual(try CommunityAPI.townFeedRows(from: Data(json.utf8)).map(\.event.id), ["e1"])

        let town = TownFeed { lines.map(TownFeed.entry) }
        await town.refresh()
        XCTAssertEqual(town.shown.map(\.id), ["e1", "n1", "n2"])
        XCTAssertEqual(town.cards.map(\.id), ["e1"])
    }

    /// The columns `get_town_feed` returns, as PostgREST sends them. A renamed column
    /// on either side fails here rather than emptying the feed.
    func testTheFunctionsRowsBecomeEventsWithTheirRepeatAndLeavingTime() throws {
        let json = """
        [{"id":"e1","title":"City Council Meeting","event_date":"2026-10-19","start_time":"6 PM",
          "location":"City Hall","image_url":null,"category":null,"club_name":null,
          "source_name":"City of St. Joseph","end_at":"2026-10-20T04:59:00+00:00","all_day":false,
          "created_at":"2026-10-06T16:08:20.123+00:00","going_count":2,
          "rsvpd":true,"recurrence":"Every 1st & 3rd Monday",
          "leaves_at":"2026-10-20T04:59:00+00:00"}]
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
        [{"id":"e1","title":"Choir","event_date":"2026-10-19","start_time":"7 PM","location":null,
          "image_url":null,"category":null,"club_name":null,"source_name":"CSB SJU",
          "end_at":"2026-10-20T04:59:00+00:00","all_day":false,"created_at":"2026-10-06T16:08:20+00:00",
          "going_count":0,"rsvpd":false,"recurrence":null,"leaves_at":"2026-10-20T04:59:00+00:00",
          "place_picture":{"url":"https://x/hall.webp","kind":"photo","site":"https://csbsju.edu",
                           "credit":null,"w":1600,"h":1067}}]
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

    /// The place's other photos reach the card (BP app event-card 02): the card and its page
    /// show the cover, then the rest in order, each once with its own credit; one that doesn't
    /// decode is left out and the cover kept.
    func testAPlacesOtherPhotosReachTheCardAndABadOneCostsNothing() throws {
        let json = """
        [{"id":"e1","title":"Choir","event_date":"2026-10-19","start_time":"7 PM","location":null,
          "image_url":null,"category":null,"club_name":null,"source_name":"CSB SJU",
          "end_at":"2026-10-20T04:59:00+00:00","all_day":false,"created_at":"2026-10-06T16:08:20+00:00",
          "going_count":0,"rsvpd":false,"recurrence":null,"leaves_at":"2026-10-20T04:59:00+00:00",
          "place_picture":{"url":"https://x/a.webp","kind":"photo","site":"https://csbsju.edu","credit":null,
                           "w":1600,"h":1067,
                           "more":[{"url":"https://x/b.webp","kind":"photo","site":"https://csbsju.edu",
                                    "credit":"Ada Lovelace · CC BY 4.0","w":1067,"h":1600},
                                   {"kind":"photo"},
                                   {"url":"https://x/c.webp","kind":"photo","site":"https://www.sju.edu/x",
                                    "credit":null}]}}]
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
        [{"id":"e1","title":"Rev. Daniel Groody: Koch Chair Lecture","event_date":"2026-11-12","start_time":"7 PM",
          "location":"Gorecki Center","image_url":null,"category":"faith","club_name":null,
          "source_name":"CSB SJU Campus Events","end_at":null,"all_day":false,
          "created_at":"2026-10-06T16:08:20+00:00","going_count":0,"rsvpd":false,
          "recurrence":null,"leaves_at":"2026-11-13T03:00:00+00:00","what":"Talk"},
         {"id":"e2","title":"Christmas Craft Sale","event_date":"2026-11-06","start_time":"9 AM",
          "location":null,"image_url":null,"category":null,"club_name":null,
          "source_name":"Saint Benedict's Monastery","end_at":null,"all_day":false,
          "created_at":"2026-10-06T16:08:20+00:00","going_count":0,"rsvpd":false,
          "recurrence":null,"leaves_at":"2026-11-06T17:00:00+00:00","what":"Craft sale"},
         {"id":"e3","title":"Kiln Firing","event_date":"2026-11-06","start_time":"9 AM",
          "location":null,"image_url":null,"category":null,"club_name":null,
          "source_name":"CSB SJU Campus Events","end_at":null,"all_day":false,
          "created_at":"2026-10-06T16:08:20+00:00","going_count":0,"rsvpd":false,
          "recurrence":null,"leaves_at":"2026-11-06T17:00:00+00:00"}]
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
    func testThePosterHoldsFromWhenTheFeedLeftTheTop() async {
        let town = feed([row("a")])
        town.scrollY = 120
        XCTAssertTrue(town.holding)
        let left = town.heldAt
        try? await Task.sleep(for: .milliseconds(20))
        town.scrollY = 640
        XCTAssertEqual(town.heldAt, left, "scrolling further keeps the moment it left the top")
        town.scrollY = 0
        XCTAssertFalse(town.holding)
        town.scrollY = 50
        XCTAssertGreaterThan(town.heldAt, left, "leaving the top again holds from then")
    }

    /// The recipe's columns (ticket 18): the reason becomes the card's line, and the
    /// admin's score comes through whole.
    func testTheRecipesReasonAndScoreReachTheCard() throws {
        let json = """
        [{"id":"e1","title":"Choir concert","event_date":"2026-10-12","start_time":"3 PM",
          "location":null,"image_url":null,"category":"live_music","club_name":null,
          "source_name":"Arts center","end_at":null,"all_day":false,
          "created_at":"2026-10-06T16:08:20+00:00","going_count":0,"rsvpd":false,
          "recurrence":null,"leaves_at":"2026-10-12T22:00:00+00:00",
          "reason":"interest","reason_name":"live_music",
          "score":{"interest":3,"friend":0,"follow":0,"popular":0,"size":1.5,"sizeStep":2,
                   "daysAway":2.12,"soon":0.8105,"acted":1,"spacing":0.5,"newSpot":false,
                   "total":1.8236,"spot":2,"of":5,"tapped":2,"draw":1.5,"topicSpacing":0.7},
          "heart_count":4,"hearted":true},
         {"id":"e2","title":"Bake sale","event_date":"2026-10-08","start_time":"11 AM",
          "location":null,"image_url":null,"category":null,"club_name":null,
          "source_name":"Parish","end_at":null,"all_day":false,
          "created_at":"2026-10-06T16:08:20+00:00","going_count":0,"rsvpd":false,
          "recurrence":null,"leaves_at":"2026-10-08T18:00:00+00:00",
          "reason":"today","reason_name":null,"score":null},
         {"id":"e3","title":"Fair","event_date":"2026-10-08","start_time":"1 PM",
          "location":null,"image_url":null,"category":null,"club_name":null,
          "source_name":"Fair board","end_at":null,"all_day":false,
          "created_at":"2026-10-06T16:08:20+00:00","going_count":0,"rsvpd":false,
          "recurrence":null,"leaves_at":"2026-10-08T20:00:00+00:00",
          "reason":"today","reason_name":null,"score":{"spot":3,"newSpot":null}}]
        """
        let cards = try CommunityAPI.townFeedRows(from: Data(json.utf8)).map { TownFeed.card($0) }
        XCTAssertEqual(cards.map(\.why), ["Matches Live music", "Happening today", "Happening today"])
        XCTAssertEqual(cards[0].score?.spot, 2)
        XCTAssertEqual(cards[0].score?.spacing, 0.5)
        XCTAssertEqual(cards[0].score?.sizeStep, 2)
        // The newer terms (town-feed 30, 34, 32), and none from a breakdown read before them.
        XCTAssertEqual([cards[0].score?.tapped, cards[0].score?.draw, cards[0].score?.topicSpacing], [2, 1.5, 0.7])
        let older = try JSONDecoder().decode(FeedScore.self, from: Data("""
            {"interest":0,"friend":0,"follow":0,"popular":0,"size":0,"sizeStep":1,"daysAway":1,"soon":1,
             "acted":1,"spacing":1,"newSpot":false,"total":1,"spot":1,"of":1}
            """.utf8))
        XCTAssertNil(older.tapped)
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
        [{"id":"e1","title":"Quiz night","event_date":"2026-10-12","start_time":"7 PM",
          "location":null,"image_url":null,"category":null,"club_name":null,
          "source_name":"Bad Habit","end_at":null,"all_day":false,
          "created_at":"2026-10-06T16:08:20+00:00","going_count":12,"rsvpd":false,
          "recurrence":null,"leaves_at":"2026-10-13T02:00:00+00:00",
          "reason":"friend","reason_name":"Anna","score":null,
          "friends_going":[{"name":"Anna","photo":"https://example.com/anna.jpg"},{"name":"Ben","photo":null}]},
         {"id":"e2","title":"Bake sale","event_date":"2026-10-08","start_time":"11 AM",
          "location":null,"image_url":null,"category":null,"club_name":null,
          "source_name":"Parish","end_at":null,"all_day":false,
          "created_at":"2026-10-06T16:08:20+00:00","going_count":3,"rsvpd":false,
          "recurrence":null,"leaves_at":"2026-10-08T18:00:00+00:00",
          "reason":"today","reason_name":null,"score":null}]
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
        [{"id":"e1","title":"Monthly Meeting","event_date":"2026-10-19","start_time":"7 PM",
          "location":null,"image_url":null,"category":null,"club_name":"St. Joe Rod and Gun Club",
          "source_name":"St Joe Rod and Gun Club","end_at":null,"all_day":false,
          "created_at":"2026-10-06T16:08:20+00:00","going_count":0,"rsvpd":false,
          "recurrence":null,"leaves_at":"2026-10-20T02:00:00+00:00","reason":"today","reason_name":null,
          "score":null,"club_id":"6f1c2c43-6b4b-4a4e-9f43-1f2d3c4b5a69","in_club":true},
         {"id":"e2","title":"Bake sale","event_date":"2026-10-19","start_time":"11 AM",
          "location":null,"image_url":null,"category":null,"club_name":null,
          "source_name":"Parish","end_at":null,"all_day":false,
          "created_at":"2026-10-06T16:08:20+00:00","going_count":3,"rsvpd":false,
          "recurrence":null,"leaves_at":"2026-10-19T18:00:00+00:00",
          "reason":"today","reason_name":null,"score":null}]
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
        {"id":"\(id)","title":"SJU Football vs Concordia: Homecoming","event_date":"2026-10-17","start_time":"1 PM",
         "location":"Clemens Stadium, Collegeville","image_url":null,"category":null,"club_name":null,
         "source_name":"SJU Athletics","end_at":null,"all_day":false,"created_at":"2026-10-06T16:08:20+00:00",
         "going_count":0,"rsvpd":false,"recurrence":null,"leaves_at":"2026-10-17T20:00:00+00:00"\(game)}
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

    /// Every reason the database sends has a line; one this app doesn't know has none,
    /// so a newer database never puts a wrong line on an older app.
    func testEachReasonHasItsLine() {
        XCTAssertEqual(FeedCardMenu.line(reason: "new", name: nil), "New in town")
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
        town.scrollY = 300
        await town.refresh(at: now.addingTimeInterval(2 * 3600))
        XCTAssertEqual(town.cards.map(\.id), ["short", "long"])
        XCTAssertEqual(town.nextLeave, now.addingTimeInterval(5 * 3600), "the leave timer still moves on")
        town.scrollY = 0
        XCTAssertEqual(town.cards.map(\.id), ["long"])
    }

    /// Scrolled down, a card the read no longer has (called off, say) keeps its place too, and
    /// leaves at the top with the finished ones.
    func testACardTheReadDropsWaitsForTheTopToo() async {
        let town = feed(answers: [entries(["a", "b"]), entries(["a"])])
        await town.reload(at: now)
        town.scrollY = 300
        await town.refresh(at: now.addingTimeInterval(60))
        XCTAssertEqual(town.cards.map(\.id), ["a", "b"])
        town.scrollY = 0
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
        town.scrollY = 300
        town.left(at: now)
        town.scrollY = 0  // another tab: the rebuilt screen starts at the top
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
        town.scrollY = 300
        town.left(at: now)
        town.scrollY = 0  // another tab: the rebuilt screen starts at the top
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
        town.scrollY = 300
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
        town.scrollY = 900
        town.left(at: now)
        town.scrollY = 0    // the rebuilt screen starts at the top
        town.cameBack(at: now.addingTimeInterval(10 * 60))
        XCTAssertEqual(town.returnY, 900)

        town.scrollY = 900
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
}

