//
//  SearchRowLineTests.swift
//  Block Party — a Search row says why it is there (BP app search-helpful 08): an Event's when and its best
//  reason, a place's kind and hours, friends first among people.
//

import XCTest
@testable import BlockParty

@MainActor
final class SearchRowLineTests: XCTestCase {
    /// Monday, November 16, 2026, in the Town's clock.
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Town.gregorian.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func event(day: String, time: String?, going: Int = 0, friends: [String] = [],
                       location: String? = "The House Food & Tap, St. Joseph, MN") -> SearchItem {
        let card = FeedCardItem(id: "e", title: "Trivia Night", dateChip: "", metaLine: "", image: .fallback, recurrence: nil,
                                goingCount: going, goingAvatars: [],
                                friendsGoing: friends.map { FeedFriend(name: $0, photo: nil) },
                                likeCount: 0, isLiked: false, isJoined: false, eventDate: day, startTime: time,
                                location: location)
        return SearchItem(id: "e:e", kind: .event, name: card.title, card: card)
    }

    func testAnEventSaysWhenThenItsPlace() {
        let monday = at(16, 10, 40)
        XCTAssertEqual(event(day: "2026-11-16", time: "7 PM").rowLine(monday), "Tonight 7 PM · The House Food & Tap")
        XCTAssertEqual(event(day: "2026-11-16", time: "1 PM").rowLine(monday), "Today 1 PM · The House Food & Tap")
        XCTAssertEqual(event(day: "2026-11-17", time: "6:30 PM").rowLine(monday), "Tomorrow 6:30 PM · The House Food & Tap")
        XCTAssertEqual(event(day: "2026-11-19", time: "6:30 PM").rowLine(monday), "Thu 6:30 PM · The House Food & Tap")
        XCTAssertEqual(event(day: "2026-11-16", time: "11 AM").rowLine(monday), "In 20 min · The House Food & Tap")
        XCTAssertEqual(event(day: "2026-11-28", time: "7 PM").rowLine(monday), "Nov 28, 7 PM · The House Food & Tap")
        XCTAssertEqual(event(day: "2026-11-19", time: nil, location: nil).rowLine(monday), "Thu", "no time, no place")
    }

    func testFriendsGoingBeatACountWhichBeatsThePlace() {
        let monday = at(16, 10, 40)
        XCTAssertEqual(event(day: "2026-11-17", time: "6:30 PM", going: 12, friends: ["Sam", "Maria"]).rowLine(monday),
                       "Tomorrow 6:30 PM · Sam and Maria going")
        XCTAssertEqual(event(day: "2026-11-17", time: "6:30 PM", going: 12, friends: ["Sam", "Maria", "Ana"]).rowLine(monday),
                       "Tomorrow 6:30 PM · Sam and 2 friends going")
        XCTAssertEqual(event(day: "2026-11-19", time: "6:30 PM", going: 12).rowLine(monday), "Thu 6:30 PM · 12 Going")
        XCTAssertEqual(event(day: "2026-11-19", time: "6:30 PM", going: 2).rowLine(monday),
                       "Thu 6:30 PM · The House Food & Tap", "under 3 Going says the place")
    }

    /// Gary's Pizza's real week: 3:30 to 10 most days, to 1:30 AM Friday and Saturday.
    private let garys = try! JSONDecoder().decode(PlaceHours.self, from: Data("""
    {"sun": [["11:00", "22:00"]], "mon": [["15:30", "22:00"]], "tue": [["15:30", "22:00"]], "wed": [["15:30", "22:00"]],
     "thu": [["15:30", "22:00"]], "fri": [["15:30", "01:30"]], "sat": [["11:00", "01:30"]]}
    """.utf8))

    func testAPlaceSaysItsKindAndHours() {
        let place = SearchItem(id: "p", kind: .restaurant, name: "Gary's Pizza", sub: "Pizza", hours: garys)
        XCTAssertEqual(place.rowLine(at(16, 10, 40)), "Pizza · Opens 3:30 PM")
        XCTAssertFalse(place.isOpen(at(16, 10, 40)))
        XCTAssertEqual(place.rowLine(at(16, 18)), "Pizza · Open till 10 PM")
        XCTAssertTrue(place.isOpen(at(16, 18)))
        XCTAssertEqual(place.rowLine(at(16, 21, 45)), "Pizza · Closes soon · 10 PM")
        XCTAssertEqual(place.rowLine(at(16, 23)), "Pizza · Opens Tue 3:30 PM")
        XCTAssertEqual(SearchItem(id: "q", kind: .business, name: "Cost Cutters", sub: "Hair salon").rowLine(at(16, 10)),
                       "Hair salon", "no hours: its kind alone")
    }

    func testOnlyAnOpenPlacesOpenIsGreen() {
        let green = { (line: AttributedString) in
            line.runs.filter { $0.foregroundColor != nil }.map { String(line[$0.range].characters) }
        }
        XCTAssertEqual(green(ItemRow.line("Restaurant · Open till 11 AM", open: true)), ["Open"])
        XCTAssertEqual(green(ItemRow.line("Pizza · Opens 3:30 PM", open: false)), [], "shut stays grey")
    }

    func testAPhotoShowsOnARowEvenWhenCredited() {
        let picture = PlacePicture(url: URL(string: "https://x/p.webp")!, kind: .photo, site: URL(string: "https://flourandflower.com"))
        let place = SearchItem(id: "p", kind: .business, name: "Flour & Flower", photos: [picture])
        XCTAssertEqual(place.rowPhoto, .saved(picture))
        XCTAssertNil(SearchItem(id: "q", kind: .business, name: "Birdie's").rowPhoto)
    }

    func testFriendsFirstThenSharedFriends() {
        let person = { (name: String, relation: Neighbor.Relation, mutual: Int) in
            Neighbor(userId: name, displayName: name, avatarUrl: nil, since: nil, relation: relation, mutualFriends: mutual)
        }
        let found = [person("Ana", .stranger, 0), person("Sadie", .stranger, 2), person("Sam", .friends, 0),
                     person("Sara", .stranger, 2)]
        XCTAssertEqual(Neighbor.friendsFirst(found).map(\.displayName), ["Sam", "Sadie", "Sara", "Ana"])
    }
}
