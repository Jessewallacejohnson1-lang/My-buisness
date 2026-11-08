//
//  EventCardTests.swift
//  The Event card (BP app codebase-health-2, tickets 02 and 03): the Town feed, Daily's Event of the day, Liked
//  and the bell each send it alone, beside only their own, and read it through the one Event decoder, so an
//  Event shows its found link, host picture and score from every tab. The Going read's card is
//  `YouCalendarTests.testTheGoingReadsEventCardDecodesFullAndBare`; what each read sends is supabase/tests/
//  (town_feed, my_going, moved_notices).
//

import XCTest
@testable import BlockParty

@MainActor
final class EventCardTests: XCTestCase {

    /// A found volleyball match, its live score coming in, as `private.event_cards` sends it.
    private let card = """
    {"id":"e1","title":"Saint Benedict Volleyball vs Sartell","event_date":"2026-11-05","start_time":"7 PM",
     "location":"Clemens Gym","image_url":"https://x/flyer.jpg","category":"sports",
     "club_name":"Bennie Volleyball Boosters","source_name":"CSB Athletics","end_at":null,"all_day":false,
     "created_at":"2026-10-01T12:00:00+00:00","going_count":2,"going":true,"heart_count":3,"hearted":true,
     "cancelled":false,
     "place_picture":{"url":"https://x/gym.webp","kind":"photo","credit":null,"site":"https://csbsju.edu/","more":[]},
     "host_picture":{"url":"https://x/csb-logo.webp","kind":"logo","hue":20},
     "description":"Senior night.","what":"Volleyball match",
     "source_url":"https://gobennies.com/sports/volleyball/schedule",
     "game":{"sport":"Volleyball","occasion":"Senior night","final":null,"plays":null,
             "live":{"score":[2,1],"period":"Set 4","clock":null,"complete":false},
             "teams":[{"name":"Saint Benedict","short":"CSB"},{"name":"Sartell","short":"Sartell"}]},
     "friends_going":[{"name":"Anna","photo":"https://x/anna.jpg"}],"recurrence":"Every Thursday"}
    """

    /// The card's facts, wherever it came from.
    private func assertIsTheCard(_ event: UpcomingEvent, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(event.title, "Saint Benedict Volleyball vs Sartell", file: file, line: line)
        XCTAssertEqual(event.clubName, "Bennie Volleyball Boosters", file: file, line: line)
        XCTAssertEqual(event.sourceURL, URL(string: "https://gobennies.com/sports/volleyball/schedule"), file: file, line: line)
        XCTAssertEqual(event.hostPicture?.url, URL(string: "https://x/csb-logo.webp"), file: file, line: line)
        XCTAssertEqual(event.placePicture?.url, URL(string: "https://x/gym.webp"), file: file, line: line)
        XCTAssertEqual(event.game?.live?.score, [2, 1], "the score comes with the card", file: file, line: line)
        XCTAssertEqual(event.recurrence, "Every Thursday", "the repeat comes with the card (inside-cards 23)",
                       file: file, line: line)
        XCTAssertEqual(event.description, "Senior night.", file: file, line: line)
        XCTAssertEqual(event.what, "Volleyball match", file: file, line: line)
        XCTAssertEqual(event.goingCount, 2, file: file, line: line)
        XCTAssertTrue(event.rsvpd, file: file, line: line)
        XCTAssertEqual(event.heartCount, 3, "every account's hearts ride the card (inside-cards 16)", file: file, line: line)
        XCTAssertTrue(event.hearted, "and yours", file: file, line: line)
    }

    /// The Town feed's Event rows are their card; the feed's own extras (reason, hearts, leaving time) stay
    /// the row's, and the old `saved` column builds before inside-cards 16 read is passed over. An Event row with no card, or one that doesn't decode, is left out, never the feed; news and
    /// posts carry no card.
    func testTheTownFeedsRowsReadTheirCard() throws {
        let json = """
        [{"id":"e1","title":null,"recurrence":null,"leaves_at":"2026-11-06T04:00:00+00:00","reason":"friend",
          "reason_name":"Anna","score":null,"heart_count":5,"hearted":true,"saved":true,"club_id":null,
          "in_club":false,"kind":"event","poster":null,"card":\(card)},
         {"id":"e2","title":null,"recurrence":null,"leaves_at":"2026-11-07T04:00:00+00:00","kind":"event",
          "card":{"title":"Quiz night"}},
         {"id":"e3","title":null,"recurrence":"Every Saturday","leaves_at":"2026-11-08T04:00:00+00:00","kind":"event",
          "card":null},
         {"id":"n1","title":"Road work on Minnesota St","location":null,"image_url":null,"source_name":"City",
          "created_at":"2026-11-02T15:00:00+00:00","recurrence":null,"leaves_at":"2026-11-09T15:00:00+00:00",
          "kind":"news","source_url":"https://x/road","card":null}]
        """
        let lines = try CommunityAPI.townFeedLines(from: Data(json.utf8))
        XCTAssertEqual(lines.count, 2, "the Event and the news; the two Events without a card are left out")
        let rows = try CommunityAPI.townFeedRows(from: Data(json.utf8))
        XCTAssertEqual(rows.map(\.event.id), ["e1"], "news never becomes an Event")

        assertIsTheCard(rows[0].event)
        XCTAssertEqual([rows[0].reason, rows[0].reasonName], ["friend", "Anna"])
        XCTAssertEqual(rows[0].heartCount, 5)
        XCTAssertEqual(rows[0].leavesAt, DateHelpers.timestamp("2026-11-06T04:00:00+00:00"))
        let page = TownFeed.card(rows[0])
        XCTAssertEqual(page.sourceURL, URL(string: "https://gobennies.com/sports/volleyball/schedule"))
        XCTAssertEqual(page.hostPicture?.kind, .logo)
        XCTAssertEqual(page.game?.live?.score, [2, 1])
        XCTAssertEqual(page.friendsGoing.map(\.name), ["Anna"], "the card's friends ride the card")
        XCTAssertEqual(page.recurrence, "Every Thursday", "the repeat is the card's, not the row's")
        XCTAssertEqual([page.likeCount], [5], "the row's hearts, as a feed kept from before the card had them shows")
        XCTAssertTrue(page.isLiked)
    }

    /// Daily's Event of the day had no found link or host picture of its own: its card brings them to the
    /// Event page it opens.
    func testTheEventOfTheDayBringsItsLinkWithTheCard() throws {
        let json = """
        [{"id":"e1","recurrence":null,"leaves_at":"2026-11-06T04:00:00+00:00","reason":"today","reason_name":null,
          "score":null,"heart_count":0,"hearted":false,"saved":false,"club_id":null,"in_club":false,
          "card":\(card)}]
        """
        let row = try XCTUnwrap(CommunityAPI.townFeedRows(from: Data(json.utf8)).first)
        assertIsTheCard(row.event)
        let daily = try XCTUnwrap(DailyEvent(row: row))
        XCTAssertEqual(daily.item.sourceURL, URL(string: "https://gobennies.com/sports/volleyball/schedule"))
        XCTAssertEqual(daily.item.hostPicture?.url, URL(string: "https://x/csb-logo.webp"))
    }

    /// Liked's rows are their card alone, hearted as the card says, Going only where the card says so (inside-cards
    /// 16). A row whose card doesn't decode is left out, never the list.
    func testLikedReadsTheCard() throws {
        let notGoing = card.replacingOccurrences(of: #""going":true"#, with: #""going":false"#)
        let json = """
        [{"card":\(notGoing)}, {"card":{"title":"Quiz night"}}, {"card":null}]
        """
        let likes = try CommunityAPI.myGoingRows(from: Data(json.utf8))
        XCTAssertEqual(likes.map(\.id), ["e1"])
        let event = try XCTUnwrap(likes.first)
        XCTAssertEqual(event.sourceURL, URL(string: "https://gobennies.com/sports/volleyball/schedule"))
        XCTAssertEqual(event.game?.live?.score, [2, 1])
        XCTAssertFalse(event.rsvpd, "the card says not Going")
        let page = FeedCardItem(event)
        XCTAssertEqual([page.likeCount], [3])
        XCTAssertTrue(page.isLiked, "the Event page opened from Liked shows the heart as yours")
        XCTAssertEqual(page.sourceURL, URL(string: "https://gobennies.com/sports/volleyball/schedule"))
    }

    /// A card kept from before it carried the heart still decodes, saying none.
    func testACardWithoutTheHeartSaysNone() throws {
        let old = card.replacingOccurrences(of: #""heart_count":3,"hearted":true,"#, with: "")
        XCTAssertNotEqual(old, card)
        let event = try XCTUnwrap(CommunityAPI.myGoingRows(from: Data("[{\"card\":\(old)}]".utf8)).first)
        XCTAssertEqual([event.heartCount], [0])
        XCTAssertFalse(event.hearted)
    }

    /// The bell's rows are their card, its game with the live score, beside what changed, where it moved from
    /// and what you follow that it is of. A row whose card doesn't decode is left out, never the bell.
    func testTheBellReadsTheCardWithItsScore() throws {
        let json = """
        [{"card":{"title":"Quiz night"},"changed_at":"2026-11-02T16:00:00+00:00","moved_from":null,
          "followed":null,"followed_logo":null},
         {"card":\(card),"changed_at":"2026-11-02T15:00:00+00:00",
          "moved_from":{"event_date":"2026-11-05","start_time":"6 PM","location":"Clemens Gym"},
          "followed":"CSB Volleyball","followed_logo":"https://x/csb.png"}]
        """
        let notices = try CommunityAPI.changeRows(from: Data(json.utf8))
        XCTAssertEqual(notices.map(\.event.id), ["e1"])
        let notice = try XCTUnwrap(notices.first)
        assertIsTheCard(notice.event)
        XCTAssertEqual(notice.movedFrom?.startTime, "6 PM")
        XCTAssertEqual(notice.followed, "CSB Volleyball")
        XCTAssertEqual(notice.changedAt, DateHelpers.timestamp("2026-11-02T15:00:00+00:00"))
        XCTAssertEqual(FeedCardItem(notice.event).sourceURL, URL(string: "https://gobennies.com/sports/volleyball/schedule"))
    }

    /// An Event sent in a chat, and a Going chat's Event, are their card: their Event page says how it repeats
    /// (BP app inside-cards 23). A card from before the repeat says none.
    func testAChatsEventSaysHowItRepeats() throws {
        let json = """
        [{"id":"1","client_id":"E","sender_id":"sam","kind":"event","body":null,"photo_path":null,"photo_w":null,
          "photo_h":null,"card":\(card),"created_at":"2026-11-03T18:00:00+00:00"}]
        """
        let message = try XCTUnwrap(ChatAPI.messages(from: Data(json.utf8)).first)
        guard case .event(let item) = message.content else { return XCTFail("an Event message") }
        XCTAssertEqual(item?.recurrence, "Every Thursday")
        XCTAssertEqual(try Supabase.decode(Data(card.utf8), as: ChatEvent.self).card?.recurrence, "Every Thursday")
        let before = card.replacingOccurrences(of: #","recurrence":"Every Thursday""#, with: "")
        XCTAssertNil(try Supabase.decode(Data(before.utf8), as: ChatEvent.self).card?.recurrence)
    }
}
