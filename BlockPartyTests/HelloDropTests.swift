//
//  HelloDropTests.swift
//  BlockPartyTests — the hello drop (BP app hello-drop 01): which hello the day's first open
//  says, and which one message follows it.
//

import XCTest
@testable import BlockParty

@MainActor
final class HelloDropTests: XCTestCase {
    /// "2026-10-21 15:00" in St. Joseph (a Wednesday).
    private func town(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Town.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    private func event(_ id: String, _ day: String, _ time: String?, friends: [String] = [],
                       added: Date? = nil, cancelled: Bool = false) -> DailyEvent {
        var card = FeedCardItem(UpcomingEvent(id: id, title: id, eventDate: day, startTime: time, location: nil,
                                              goingCount: 1, createdAt: "", rsvpd: true))
        card.friendsGoing = friends.map { FeedFriend(name: $0, photo: nil) }
        card.createdAt = added
        card.cancelled = cancelled
        return YouCalendar.event(from: card)!
    }

    private func hello(_ now: String, lastSeen: String? = "2026-10-20 20:00", yesterday: String? = nil) -> String {
        HelloDrop.hello(name: "Jesse", now: town(now), lastSeen: lastSeen.map(town), yesterday: yesterday).text
    }

    private func message(_ now: String, lastSeen: String? = nil, going: [DailyEvent] = [],
                         groups: [TownGroup] = [], town towns: [DailyEvent] = []) -> String? {
        HelloDrop.message(now: town(now), lastSeen: lastSeen.map(town), going: going,
                          groups: groups, town: towns)?.text
    }

    // MARK: The hello

    func testTheTimeOfDaySaysHello() {
        XCTAssertEqual(hello("2026-10-21 08:00"), "Morning, Jesse")
        XCTAssertEqual(hello("2026-10-21 11:00"), "Afternoon, Jesse")
        XCTAssertEqual(hello("2026-10-21 17:30"), "Evening, Jesse")
        XCTAssertEqual(hello("2026-10-21 22:15"), "Night owl, Jesse")
        XCTAssertEqual(hello("2026-10-21 02:00"), "Night owl, Jesse")
    }

    /// Never the same one two days running: an any-time hello stands in.
    func testYesterdaysHelloIsNeverSaidAgain() {
        let said = hello("2026-10-21 08:00", yesterday: "Morning")
        XCTAssertNotEqual(said, "Morning, Jesse")
        XCTAssertTrue(["Hi", "Hey", "Hello", "Hey there", "Good to see you", "There you are"]
            .map { "\($0), Jesse" }.contains(said))
    }

    func testSpecialDaysBeatTheTimeOfDay() {
        XCTAssertEqual(hello("2026-10-23 08:00"), "Happy Friday, Jesse")
        XCTAssertEqual(hello("2026-10-25 08:00", lastSeen: "2026-10-24 20:00"), "Happy Sunday, Jesse")
        XCTAssertEqual(hello("2026-10-31 08:00", lastSeen: "2026-10-30 20:00"), "Happy Halloween, Jesse")
        XCTAssertEqual(hello("2026-11-26 08:00", lastSeen: "2026-11-25 20:00"), "Happy Thanksgiving, Jesse")
        XCTAssertEqual(hello("2026-10-21 08:00", lastSeen: "2026-10-17 20:00"), "Welcome back, Jesse")
        XCTAssertEqual(hello("2026-10-21 08:00", lastSeen: nil), "Welcome to Block Party, Jesse")
    }

    func testNoNameSaysTheHelloAlone() {
        XCTAssertEqual(HelloDrop.hello(name: nil, now: town("2026-10-21 08:00"),
                                       lastSeen: town("2026-10-20 20:00"), yesterday: nil).text, "Morning")
    }

    // MARK: Firsts and milestones (hello-drop 02)

    func testEachMomentSaysOneShortLine() {
        XCTAssertEqual(HelloMoment.firstEvent.text, "Attended your first event!")
        XCTAssertEqual(HelloMoment.tenthEvent.text, "Attended your 10th event!")
        XCTAssertEqual(HelloMoment.firstFriend.text, "Added your first friend!")
        for moment in HelloMoment.allCases {
            XCTAssertTrue(moment.text.hasSuffix("!"), moment.text)
        }
    }

    /// Confetti only on the 10th and 100th; firsts get the tick alone.
    func testOnlyTheTenthAndHundredthGetConfetti() {
        XCTAssertEqual(HelloMoment.allCases.filter(\.confetti), [.tenthEvent, .hundredthEvent])
    }

    /// Attended: Going, not called off, and over.
    func testAttendedCountsOnlyEventsThatAreOver() {
        let now = town("2026-10-21 20:00")
        let over = event("Over", "2026-10-21", "4 PM")
        let later = event("Later", "2026-10-22", "4 PM")
        let off = event("Off", "2026-10-20", "4 PM", cancelled: true)
        XCTAssertEqual(HelloMoment.attendedCount([over, later, off], now: now), 1)
    }

    func testEachMomentIsSaidOnceEver() {
        let defaults = UserDefaults(suiteName: "HelloMomentsTests")!
        defaults.removePersistentDomain(forName: "HelloMomentsTests")
        let moments = HelloMoments(said: defaults)
        moments.reach(.firstFriend)
        XCTAssertEqual(moments.take(), .firstFriend)
        moments.reach(.firstFriend)
        XCTAssertNil(moments.take())
    }

    /// A neighbour already past 10 hears "10th", never "first", and never both.
    func testOnlyTheHighestAttendedMilestoneShows() {
        let defaults = UserDefaults(suiteName: "HelloMomentsTests2")!
        defaults.removePersistentDomain(forName: "HelloMomentsTests2")
        let moments = HelloMoments(said: defaults)
        moments.attended(12)
        XCTAssertEqual(moments.take(), .tenthEvent)
        moments.attended(13)
        XCTAssertNil(moments.take())
        XCTAssertTrue(moments.hasSaid(.firstEvent))
        moments.attended(100)
        XCTAssertEqual(moments.take(), .hundredthEvent)
    }

    // MARK: The message

    /// Top down, the first true one wins.
    func testYourEventTodayComesFirst() {
        let rock = event("Rocktoberfest", "2026-10-21", "4 PM")
        XCTAssertEqual(message("2026-10-21 09:00", going: [rock], town: [event("x", "2026-10-21", "6 PM", friends: ["Sam"])]),
                       "Rocktoberfest is today at 4")
        XCTAssertNotEqual(message("2026-10-21 09:00", going: [event("Gone", "2026-10-21", "4 PM", cancelled: true)]),
                          "Gone is today at 4", "a called-off Event never leads")
    }

    func testYourGroupMeetsToday() {
        var lions = TownGroup(id: "l", name: "Lions Club",
                              meetings: [TownGroup.Meeting(what: "Meeting", day: "2026-10-21", time: "19:00")])
        XCTAssertNil(message("2026-10-21 09:00", groups: [lions]), "only groups you joined")
        lions.joined = true
        XCTAssertEqual(message("2026-10-21 09:00", groups: [lions]), "Lions Club meets tonight at 7")
    }

    func testFriendsGoingToday() {
        let town = [event("Trivia", "2026-10-21", "7 PM", friends: ["Sam", "Ana", "Kim"])]
        XCTAssertEqual(message("2026-10-21 09:00", town: town), "Sam and 2 friends are going tonight")
        XCTAssertEqual(message("2026-10-21 09:00", town: [event("Walk", "2026-10-21", "10 AM", friends: ["Sam"])]),
                       "Sam is going today")
    }

    func testYourEventTomorrow() {
        XCTAssertEqual(message("2026-10-21 09:00", going: [event("Farmers Market", "2026-10-22", "8 AM")]),
                       "Farmers Market is tomorrow")
    }

    func testNewSinceYourLastOpen() {
        let new = (1...9).map { event("n\($0)", "2026-10-24", "6 PM", added: town("2026-10-21 02:00")) }
        let old = event("old", "2026-10-24", "6 PM", added: town("2026-10-19 02:00"))
        XCTAssertEqual(message("2026-10-21 09:00", lastSeen: "2026-10-20 21:00", town: new + [old]),
                       "9 new events overnight")
        XCTAssertEqual(message("2026-10-21 09:00", lastSeen: "2026-10-18 21:00", town: new + [old]),
                       "10 new events since you were last here")
    }

    func testTheCounts() {
        let today = [event("a", "2026-10-21", "6 PM"), event("b", "2026-10-21", "7 PM")]
        XCTAssertEqual(message("2026-10-21 09:00", town: today), "2 things happening today")
        // Wednesday, nothing today: the week to Sunday.
        let week = [event("c", "2026-10-23", "6 PM"), event("d", "2026-10-25", "6 PM"), event("e", "2026-10-27", "6 PM")]
        XCTAssertEqual(message("2026-10-21 09:00", town: week), "2 events this week")
        // Thursday: the weekend, Friday to Sunday.
        XCTAssertEqual(message("2026-10-22 09:00", town: week + [event("f", "2026-10-24", "1 PM")]),
                       "3 events this weekend")
        XCTAssertNil(message("2026-10-21 09:00"), "nothing coming says nothing")
        // A quiet Sunday: the six days after it, not next weekend.
        XCTAssertEqual(message("2026-10-25 09:00", town: [event("g", "2026-10-27", "6 PM"),
                                                          event("h", "2026-10-30", "6 PM")]),
                       "2 events this week")
        XCTAssertEqual(message("2026-10-25 09:00", town: [event("i", "2026-10-25", "8 PM", cancelled: true),
                                                          event("j", "2026-10-31", "6 PM")]),
                       "1 event this week")
    }
}
