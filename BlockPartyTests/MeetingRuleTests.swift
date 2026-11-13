//
//  MeetingRuleTests.swift
//  BlockPartyTests — when something meets, in words (`MeetingRule.words`, BP app nothing-scheduled 03): a school club's
//  row on its school's page and a Group's rule read the same, the weekly pattern and never a date. Rules come in as the
//  server sends them (`team_page`'s `meets`, `clubs.meets`); words as the approved mock says them
//  (references/club-meeting-times/mock.template.html).
//

import XCTest
@testable import BlockParty

@MainActor
final class MeetingRuleTests: XCTestCase {

    private func words(_ json: String) throws -> String? {
        try JSONDecoder().decode(MeetingRule.self, from: Data(json.utf8)).words
    }

    /// Sartell's Bible Study, Crochet & Knitting and FCA: the day, then the time.
    func testAWeeklyMeetingSaysItsDayAndTime() throws {
        XCTAssertEqual(try words(#"{"days": ["fri"], "time": "08:00"}"#), "Fridays · 8 AM")
        XCTAssertEqual(try words(#"{"days": ["thu"], "time": "07:45"}"#), "Thursdays · 7:45 AM")
        XCTAssertEqual(try words(#"{"days": ["tue"], "time": "18:30"}"#), "Tuesdays · 6:30 PM")
        XCTAssertEqual(try words(#"{"days": ["tue", "thu"]}"#), "Tuesdays and Thursdays")
    }

    /// A time the school gives only in words stays its words: Sartell's K-Pop Dance Cover Club.
    func testATimeInWordsStaysWords() throws {
        XCTAssertEqual(try words(#"{"days": ["wed"], "time": "After school"}"#), "Wednesdays · After school")
    }

    /// Honor Society and Letters of Love meet once a month; S.A.F.E. twice, at 8.
    func testAMonthlyMeetingNamesItsWeek() throws {
        XCTAssertEqual(try words(#"{"days": ["tue"], "weeks": [2]}"#), "2nd Tuesday of each month")
        XCTAssertEqual(try words(#"{"days": ["fri"], "weeks": [2]}"#), "2nd Friday of each month")
        XCTAssertEqual(try words(#"{"days": ["mon"], "weeks": [1, 3], "time": "08:00"}"#),
                       "1st and 3rd Monday of each month · 8 AM")
    }

    /// Path to Healthcare: every other Friday.
    func testEveryOtherWeek() throws {
        XCTAssertEqual(try words(#"{"days": ["fri"], "every": 2, "time": "07:45"}"#), "Every other Friday · 7:45 AM")
    }

    /// A Group's rule, as `clubs.meets` holds it live (its what, a null week list, months off), reads the same way.
    func testAGroupsRuleReadsTheSame() throws {
        XCTAssertEqual(try words(#"{"what": "Meeting", "days": ["tue"], "weeks": [1, 3], "time": "18:00"}"#),
                       "1st and 3rd Tuesday of each month · 6 PM")
        XCTAssertEqual(try words(#"{"what": "Quilting", "days": ["mon"], "weeks": null, "time": "07:00", "months_off": [4, 5]}"#),
                       "Mondays · 7 AM")
        XCTAssertEqual(try words(#"{"what": "Meeting", "days": ["mon"], "time": null, "weeks": [2]}"#),
                       "2nd Monday of each month")
    }

    /// A mistyped rule costs only itself: no day it knows, no words; a field of the wrong kind reads as missing.
    func testAMistypedRuleSaysNothingWrong() throws {
        XCTAssertNil(try words(#"{"days": "fri", "time": "08:00"}"#))
        XCTAssertNil(try words(#"{"days": ["someday"]}"#))
        XCTAssertEqual(try words(#"{"days": ["fri"], "time": 8, "weeks": "2nd"}"#), "Fridays")
        XCTAssertNil(try words(#""Fridays""#))
    }

    // MARK: The school page's row

    /// Three of Sartell's rows as `team_page` sends them: an Event coming, a meeting time, neither.
    private static let sartell = """
    {"id": "u-sartell", "name": "Sartell High School", "short": "Sartell", "logo": null, "colors": ["#1A4EA2"],
     "games": [], "events": [],
     "activities": [
       {"id": "theatre", "name": "Children's Theatre", "note": null, "kind": "arts", "following": false,
        "meets": null, "next": {"title": "Frozen Jr.", "date": "2026-11-21", "time": "11 AM"}},
       {"id": "birding", "name": "Birding Club", "note": null, "kind": "club", "following": false,
        "meets": [{"days": ["tue"], "time": "08:00"}],
        "next": {"title": "Birding walk", "date": "2026-11-17", "time": "3 PM"}},
       {"id": "bible", "name": "Bible Study", "note": null, "kind": "club", "following": true,
        "meets": [{"days": ["fri"], "time": "08:00"}], "next": null},
       {"id": "art", "name": "Art Club", "note": null, "kind": "club", "following": false, "meets": null, "next": null},
       {"id": "chess", "name": "Chess Club", "note": null, "kind": "club", "following": false, "next": null}]}
    """

    /// The grey line: an Event coming wins, else the meeting time, else "No events yet" (an older read has no meets).
    func testTheRowSaysItsEventElseItsMeetingElseNoEventsYet() throws {
        let page: TeamProfile = try Supabase.decode(Data(Self.sartell.utf8))
        XCTAssertEqual(page.activities.map(TeamPage.line), [
            "Sat, Nov 21 · 11 AM", "Tue, Nov 17 · 3 PM", "Fridays · 8 AM", "No events yet", "No events yet",
        ])
    }

    /// A rule that isn't an object leaves its row saying "No events yet", and the page's other rows as they are.
    func testAMistypedRuleKeepsThePage() throws {
        let json = Self.sartell.replacingOccurrences(of: #"[{"days": ["fri"], "time": "08:00"}]"#, with: #"["Fridays"]"#)
        let page: TeamProfile = try Supabase.decode(Data(json.utf8))
        XCTAssertEqual(page.activities.count, 5)
        XCTAssertEqual(page.activities.map(TeamPage.line)[2], "No events yet")
    }
}
