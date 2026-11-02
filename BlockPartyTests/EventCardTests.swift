//
//  EventCardTests.swift
//  The Event card (BP app codebase-health-2, ticket 02): the Town feed, Daily's Event of the day, Saved and
//  the bell each read it through the one Event decoder, so an Event shows its found link, host picture and
//  score from every tab. The Going read's card is `YouCalendarTests.testTheGoingReadsEventCardDecodesFullAndBare`;
//  what each read sends is supabase/tests/ (town_feed, my_going, moved_notices).
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
     "created_at":"2026-10-01T12:00:00+00:00","going_count":2,"going":true,"cancelled":false,
     "place_picture":{"url":"https://x/gym.webp","kind":"photo","credit":null,"site":"https://csbsju.edu/","more":[]},
     "host_picture":{"url":"https://x/csb-logo.webp","kind":"logo","hue":20},
     "description":"Senior night.","what":"Volleyball match",
     "source_url":"https://gobennies.com/sports/volleyball/schedule",
     "game":{"sport":"Volleyball","occasion":"Senior night","final":null,"plays":null,
             "live":{"score":[2,1],"period":"Set 4","clock":null,"complete":false},
             "teams":[{"name":"Saint Benedict","short":"CSB"},{"name":"Sartell","short":"Sartell"}]},
     "friends_going":[{"name":"Anna","photo":"https://x/anna.jpg"}]}
    """

    /// The card's facts, wherever it came from.
    private func assertIsTheCard(_ event: UpcomingEvent, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(event.title, "Saint Benedict Volleyball vs Sartell", file: file, line: line)
        XCTAssertEqual(event.clubName, "Bennie Volleyball Boosters", file: file, line: line)
        XCTAssertEqual(event.sourceURL, URL(string: "https://gobennies.com/sports/volleyball/schedule"), file: file, line: line)
        XCTAssertEqual(event.hostPicture?.url, URL(string: "https://x/csb-logo.webp"), file: file, line: line)
        XCTAssertEqual(event.placePicture?.url, URL(string: "https://x/gym.webp"), file: file, line: line)
        XCTAssertEqual(event.game?.live?.score, [2, 1], "the score comes with the card", file: file, line: line)
        XCTAssertEqual(event.description, "Senior night.", file: file, line: line)
        XCTAssertEqual(event.what, "Volleyball match", file: file, line: line)
        XCTAssertEqual(event.goingCount, 2, file: file, line: line)
        XCTAssertTrue(event.rsvpd, file: file, line: line)
    }

    /// The Town feed's rows read their card; the feed's own extras (reason, saved, hearts, leaving time) stay
    /// the row's. A row with no card (a feed kept on disk, or before the migration) or one that doesn't decode
    /// reads its own columns, and news and posts carry none.
    func testTheTownFeedsRowsReadTheirCard() throws {
        let json = """
        [{"id":"e1","title":"Old title","event_date":"2026-11-05","start_time":"7 PM","location":null,
          "image_url":null,"category":null,"club_name":null,"source_name":"CSB Athletics","end_at":null,
          "all_day":false,"created_at":"2026-10-01T12:00:00+00:00","going_count":2,"rsvpd":true,
          "recurrence":null,"leaves_at":"2026-11-06T04:00:00+00:00","reason":"friend","reason_name":"Anna",
          "score":null,"heart_count":5,"hearted":true,"saved":true,"cancelled":false,
          "friends_going":[{"name":"Anna","photo":"https://x/anna.jpg"}],"place_picture":null,"description":null,
          "club_id":null,"in_club":false,"game":null,"what":null,"kind":"event","source_url":null,
          "host_picture":null,"poster":null,"card":\(card)},
         {"id":"e2","title":"Quiz night","event_date":"2026-11-06","start_time":"7 PM","location":null,
          "image_url":null,"category":null,"club_name":null,"source_name":"Bad Habit","end_at":null,
          "all_day":false,"created_at":"2026-10-01T12:00:00+00:00","going_count":5,"rsvpd":false,
          "recurrence":null,"leaves_at":"2026-11-07T04:00:00+00:00","kind":"event",
          "source_url":"https://x/quiz","card":{"title":"Quiz night"}},
         {"id":"e3","title":"Bake sale","event_date":"2026-11-07","start_time":null,"location":null,
          "image_url":null,"category":null,"club_name":null,"source_name":"Parish","end_at":null,
          "all_day":false,"created_at":"2026-10-01T12:00:00+00:00","going_count":1,"rsvpd":false,
          "recurrence":"Every Saturday","leaves_at":"2026-11-08T04:00:00+00:00","source_url":"https://x/bake"},
         {"id":"n1","title":"Road work on Minnesota St","event_date":null,"start_time":null,"location":null,
          "image_url":null,"category":"road","club_name":null,"source_name":"City","end_at":null,"all_day":false,
          "created_at":"2026-11-02T15:00:00+00:00","going_count":0,"rsvpd":false,"recurrence":null,
          "leaves_at":"2026-11-09T15:00:00+00:00","kind":"news","source_url":"https://x/road","card":null}]
        """
        let lines = try CommunityAPI.townFeedLines(from: Data(json.utf8))
        XCTAssertEqual(lines.count, 4)
        let rows = try CommunityAPI.townFeedRows(from: Data(json.utf8))
        XCTAssertEqual(rows.map(\.event.id), ["e1", "e2", "e3"], "news never becomes an Event")

        assertIsTheCard(rows[0].event)
        XCTAssertEqual([rows[0].reason, rows[0].reasonName], ["friend", "Anna"])
        XCTAssertEqual(rows[0].heartCount, 5)
        XCTAssertTrue(rows[0].saved)
        XCTAssertEqual(rows[0].leavesAt, DateHelpers.timestamp("2026-11-06T04:00:00+00:00"))
        let page = TownFeed.card(rows[0])
        XCTAssertEqual(page.sourceURL, URL(string: "https://gobennies.com/sports/volleyball/schedule"))
        XCTAssertEqual(page.hostPicture?.kind, .logo)
        XCTAssertEqual(page.game?.live?.score, [2, 1])
        XCTAssertEqual(page.friendsGoing.map(\.name), ["Anna"])

        XCTAssertEqual([rows[1].event.title, rows[1].event.sourceURL?.absoluteString], ["Quiz night", "https://x/quiz"],
                       "a card that doesn't decode reads the row")
        XCTAssertEqual(rows[1].event.goingCount, 5)
        XCTAssertEqual([rows[2].event.title, rows[2].recurrence], ["Bake sale", "Every Saturday"], "no card: the row")
        XCTAssertEqual(rows[2].event.sourceURL, URL(string: "https://x/bake"))
    }

    /// Daily's Event of the day had no found link or host picture of its own: its card brings them to the
    /// Event page it opens.
    func testTheEventOfTheDayBringsItsLinkWithTheCard() throws {
        let json = """
        [{"id":"e1","title":"Saint Benedict Volleyball vs Sartell","event_date":"2026-11-05","start_time":"7 PM",
          "location":"Clemens Gym","image_url":null,"category":"sports","club_name":null,"source_name":"CSB Athletics",
          "end_at":null,"all_day":false,"created_at":"2026-10-01T12:00:00+00:00","going_count":2,"rsvpd":true,
          "recurrence":null,"leaves_at":"2026-11-06T04:00:00+00:00","reason":"today","reason_name":null,
          "score":null,"heart_count":0,"hearted":false,"saved":false,"cancelled":false,"friends_going":[],
          "place_picture":null,"description":null,"club_id":null,"in_club":false,"game":null,"what":null,
          "card":\(card)}]
        """
        let row = try XCTUnwrap(CommunityAPI.townFeedRows(from: Data(json.utf8)).first)
        assertIsTheCard(row.event)
        let daily = try XCTUnwrap(DailyEvent(row: row))
        XCTAssertEqual(daily.item.sourceURL, URL(string: "https://gobennies.com/sports/volleyball/schedule"))
        XCTAssertEqual(daily.item.hostPicture?.url, URL(string: "https://x/csb-logo.webp"))
    }

    /// Saved's rows read their card, saved, Going only where the card says so.
    func testSavedReadsTheCard() throws {
        let notGoing = card.replacingOccurrences(of: #""going":true"#, with: #""going":false"#)
        let json = """
        [{"id":"e1","title":"Old title","event_date":"2026-11-05","start_time":null,"location":null,
          "image_url":null,"category":null,"club_name":null,"source_name":"CSB Athletics","end_at":null,
          "all_day":false,"created_at":"2026-10-01T12:00:00+00:00","going_count":2,"going":true,
          "card":\(notGoing)}]
        """
        let event = try XCTUnwrap(CommunityAPI.myGoingRows(from: Data(json.utf8), saved: true).first)
        XCTAssertEqual(event.sourceURL, URL(string: "https://gobennies.com/sports/volleyball/schedule"))
        XCTAssertEqual(event.game?.live?.score, [2, 1])
        XCTAssertFalse(event.rsvpd, "the card says not Going")
        XCTAssertTrue(event.saved)
        let page = FeedCardItem(event)
        XCTAssertTrue(page.isSaved)
        XCTAssertEqual(page.sourceURL, URL(string: "https://gobennies.com/sports/volleyball/schedule"))
    }

    /// The bell's rows read their card, its game with the live score, never the old column's game without
    /// one; what changed stays the row's.
    func testTheBellReadsTheCardWithItsScore() throws {
        let json = """
        [{"id":"e1","title":"Old title","event_date":"2026-11-05","start_time":"7 PM","location":null,
          "image_url":null,"category":null,"club_name":null,"source_name":"CSB Athletics","end_at":null,
          "all_day":false,"created_at":"2026-10-01T12:00:00+00:00","going_count":2,"going":true,
          "cancelled":false,"place_picture":null,"description":null,
          "game":{"sport":"Volleyball","teams":[{"name":"Saint Benedict"},{"name":"Sartell"}]},
          "changed_at":"2026-11-02T15:00:00+00:00",
          "moved_from":{"event_date":"2026-11-05","start_time":"6 PM","location":"Clemens Gym"},
          "followed":"CSB Volleyball","followed_logo":"https://x/csb.png","friends_going":[],"card":\(card)}]
        """
        let notice = try XCTUnwrap(CommunityAPI.changeRows(from: Data(json.utf8)).first)
        assertIsTheCard(notice.event)
        XCTAssertEqual(notice.movedFrom?.startTime, "6 PM")
        XCTAssertEqual(notice.followed, "CSB Volleyball")
        XCTAssertEqual(notice.changedAt, DateHelpers.timestamp("2026-11-02T15:00:00+00:00"))
        XCTAssertEqual(FeedCardItem(notice.event).sourceURL, URL(string: "https://gobennies.com/sports/volleyball/schedule"))
    }
}
