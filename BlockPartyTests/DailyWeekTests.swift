//
//  DailyWeekTests.swift
//  BlockPartyTests — the week at the top of Daily (BP app daily-tab 16): its seven Town days,
//  the day the page shows, the friends going each day, and the other days' reads.
//

import XCTest
@testable import BlockParty

final class DailyWeekTests: XCTestCase {
    /// 3 PM in St. Joseph on Wednesday, Oct 21 2026.
    private let wednesday = Date(timeIntervalSince1970: 1_792_612_800)

    /// Today and the six days after it, in the Town's time.
    func testTheWeekIsTodayAndTheSixDaysAfter() {
        let days = DailyWeek.days(from: wednesday)
        XCTAssertEqual(days.map(\.id), ["2026-10-21", "2026-10-22", "2026-10-23", "2026-10-24",
                                        "2026-10-25", "2026-10-26", "2026-10-27"])
        XCTAssertEqual(days.map(\.weekday), ["Wed", "Thu", "Fri", "Sat", "Sun", "Mon", "Tue"])
        XCTAssertEqual(days.map(\.number), ["21", "22", "23", "24", "25", "26", "27"])
        XCTAssertEqual(days[0].spokenWeekday, "Wednesday")
        XCTAssertEqual(days[0].start, Date(timeIntervalSince1970: 1_792_558_800), "midnight in St. Joseph")
    }

    /// 10:30 PM in St. Joseph is already Thursday in UTC: the week still starts on the Town's Wednesday.
    func testTheWeekRunsOnTheTownsClock() {
        let late = Date(timeIntervalSince1970: 1_792_639_800)
        XCTAssertEqual(DailyWeek.days(from: late).first?.id, "2026-10-21")
    }

    /// Across the end of daylight time (Nov 1), every day still starts at the Town's midnight.
    func testTheWeekKeepsItsMidnightsAcrossTheClockChange() {
        let days = DailyWeek.days(from: Date(timeIntervalSince1970: 1_793_379_600))
        XCTAssertEqual(days.map(\.id), ["2026-10-30", "2026-10-31", "2026-11-01", "2026-11-02",
                                        "2026-11-03", "2026-11-04", "2026-11-05"])
        XCTAssertEqual(days.map(\.number), ["30", "31", "1", "2", "3", "4", "5"])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Town.timeZone
        XCTAssertTrue(days.allSatisfy { calendar.component(.hour, from: $0.start) == 0 })
        XCTAssertEqual(days[3].start.timeIntervalSince(days[2].start), 25 * 3600, "Nov 1 is 25 hours long")
    }

    /// The page shows the picked day, or today with none picked or once the picked day has gone by.
    func testThePageShowsThePickedDayUntilItGoesBy() {
        XCTAssertEqual(DailyWeek.shown(picked: nil, today: "2026-10-21"), "2026-10-21")
        XCTAssertEqual(DailyWeek.shown(picked: "2026-10-24", today: "2026-10-21"), "2026-10-24")
        XCTAssertEqual(DailyWeek.shown(picked: "2026-10-21", today: "2026-10-21"), "2026-10-21")
        XCTAssertEqual(DailyWeek.shown(picked: "2026-10-20", today: "2026-10-21"), "2026-10-21",
                       "past midnight, yesterday's pick gives way to today")
    }

    #if DEBUG
    /// Each friend shows once a day, in the Town feed's order; a card with no day adds nobody.
    @MainActor
    func testFriendsGoingIsEachFaceOnceADayInFeedOrder() {
        let sam = FeedFriend(name: "Sam", photo: nil)
        let ana = FeedFriend(name: "Ana", photo: nil)
        let kim = FeedFriend(name: "Kim", photo: nil)
        func card(_ id: String, day: String?, _ friends: [FeedFriend]) -> FeedCardItem {
            var item = event(id).item
            item.eventDate = day
            item.friendsGoing = friends
            return item
        }
        let friends = DailyWeek.friendsGoing(in: [
            card("a", day: "2026-10-24", [sam, ana]),
            card("b", day: "2026-10-24", [ana, kim]),
            card("c", day: "2026-10-25", []),
            card("d", day: nil, [kim]),
        ])
        XCTAssertEqual(friends["2026-10-24"], [sam, ana, kim])
        XCTAssertNil(friends["2026-10-25"])
        XCTAssertEqual(friends.count, 1)
    }

    /// Another day's pick is read once, again only after 10 minutes, and again at once for a new
    /// account; a failed read keeps what the day had, and a day never read shows nothing.
    @MainActor
    func testAnotherDaysPicksReadOnlyWhenItMatters() async {
        let days = DailyWeek.days(from: wednesday)
        let saturday = days[3]
        let pick = event("sat")
        var reads: [String] = []
        var fails = false
        let model = DailyDayPicks(read: { day in
            reads.append(day.id)
            if fails { throw URLError(.notConnectedToInternet) }
            return [pick]
        })
        await model.refresh(saturday, now: wednesday)
        await model.refresh(saturday, now: wednesday.addingTimeInterval(9 * 60))
        XCTAssertEqual(reads, ["2026-10-24"])
        XCTAssertEqual(model.picks["2026-10-24"]?.map(\.id), ["sat"])

        fails = true
        await model.refresh(saturday, now: wednesday.addingTimeInterval(10 * 60))
        XCTAssertEqual(reads.count, 2)
        XCTAssertEqual(model.picks["2026-10-24"]?.map(\.id), ["sat"], "a failed read keeps the pick")

        // Sunday has its own read; failing with nothing read yet, it shows nothing and reads again.
        await model.refresh(days[4], now: wednesday)
        XCTAssertEqual(model.picks["2026-10-25"]?.count, 0)
        fails = false
        await model.refresh(days[4], now: wednesday)
        XCTAssertEqual(model.picks["2026-10-25"]?.map(\.id), ["sat"])

        model.accountChanged()
        await model.refresh(saturday, now: wednesday.addingTimeInterval(11 * 60))
        XCTAssertEqual(reads.count, 5)
    }

    private func event(_ id: String) -> DailyEvent {
        DailyEvent.sample(id: id, title: "Plant Bingo", host: "Milk & Honey Ciders", photo: "farmers-market",
                          place: "Milk & Honey Ciders", starts: wednesday, ends: wednesday.addingTimeInterval(3600),
                          category: .food, description: "")
    }
    #endif
}
