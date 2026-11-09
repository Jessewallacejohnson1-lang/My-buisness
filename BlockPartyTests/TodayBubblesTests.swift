import XCTest
@testable import BlockParty

/// The rules behind the map's today bubbles (TodayBubbles.swift): when an event counts
/// down, is on, or has ended; how the countdown reads; how much ring is left; which event
/// a spot's bubble shows first; how big the zoom draws it; and how far the squishy drag can pull.
@MainActor
final class TodayBubblesTests: XCTestCase {
    private func ev(_ id: String, _ start: String?, endAt: Date? = nil) -> FeedCardItem {
        var card = FeedCardItem(id: id, title: id, dateChip: "", metaLine: "", image: .fallback, recurrence: nil,
                                goingCount: 0, goingAvatars: [], likeCount: 0, isLiked: false, isJoined: false)
        card.eventDate = "2026-10-25"
        card.startTime = start
        card.endAt = endAt
        return card
    }
    private let sevenPM = Town.midnight("2026-10-25")!.addingTimeInterval(19 * 3600)

    func testPhaseCountsDownThenIsOnUntilItsEndThenEnds() {
        let seven = ev("7", "7 PM")
        XCTAssertEqual(TodayBubbleRules.phase(seven, now: sevenPM - 600), .upcoming(secondsLeft: 600))
        XCTAssertEqual(TodayBubbleRules.phase(seven, now: sevenPM), .live)
        XCTAssertEqual(TodayBubbleRules.phase(seven, now: sevenPM + 2 * 3600 - 1), .live, "two hours with no end")
        XCTAssertEqual(TodayBubbleRules.phase(seven, now: sevenPM + 2 * 3600), .ended)
        let short = ev("short", "7 PM", endAt: sevenPM + 3600)
        XCTAssertEqual(TodayBubbleRules.phase(short, now: sevenPM + 3600), .ended, "its own end_at wins")
        XCTAssertEqual(TodayBubbleRules.phase(ev("none", nil), now: sevenPM), .untimed)
        XCTAssertEqual(TodayBubbleRules.phase(ev("all", "All day"), now: sevenPM), .untimed)
    }

    func testCountdownReadsHoursThenMinutesAndSeconds() {
        XCTAssertEqual(TodayBubbleRules.countdown(5 * 3600 + 3 * 60 + 59), "5h 03m")
        XCTAssertEqual(TodayBubbleRules.countdown(3600), "1h 00m")
        XCTAssertEqual(TodayBubbleRules.countdown(3599), "59:59")
        XCTAssertEqual(TodayBubbleRules.countdown(485), "8:05")
        XCTAssertEqual(TodayBubbleRules.countdown(-3), "0:00")
    }

    func testVoiceOverSaysTheCountdownInWords() {
        XCTAssertEqual(TodayBubbleRules.spokenCountdown(37 * 60 + 30), "37 minutes")
        XCTAssertEqual(TodayBubbleRules.spokenCountdown(3600 + 23 * 60), "1 hour 23 minutes")
        XCTAssertEqual(TodayBubbleRules.spokenCountdown(2 * 3600 + 30), "2 hours")
        XCTAssertEqual(TodayBubbleRules.spokenCountdown(61), "1 minute")
        XCTAssertEqual(TodayBubbleRules.spokenCountdown(20), "under a minute")
    }

    func testRingOnlyInTheLastHourAndEmptiesToTheStart() {
        XCTAssertNil(TodayBubbleRules.ringLeft(3601))
        XCTAssertEqual(TodayBubbleRules.ringLeft(3600), 1)
        XCTAssertEqual(TodayBubbleRules.ringLeft(1800)!, 0.5, accuracy: 0.0001)
        XCTAssertEqual(TodayBubbleRules.ringLeft(0), 0)
    }

    func testOrderPutsOnNowThenNextToStartThenUntimedAndDropsEnded() {
        let morning = ev("morning", "9 AM"), on = ev("on", "6 PM"), next = ev("next", "8 PM"), later = ev("later", "9 PM")
        XCTAssertEqual(TodayBubbleRules.order([later, next, on, morning, ev("allday", nil)], now: sevenPM).map(\.id),
                       ["on", "next", "later", "allday"])
        XCTAssertEqual(TodayBubbleRules.order([morning], now: sevenPM).map(\.id), [])
        var off = ev("off", "8 PM"); off.cancelled = true
        XCTAssertEqual(TodayBubbleRules.phase(off, now: sevenPM), .ended, "called off is over")
    }

    /// Friends on the map (five-tabs 08): each friend once across a spot's events, in the card's order.
    func testABubblesFriendsAreEveryoneGoingThereEachOnce() {
        let sam = FeedFriend(name: "Sam", photo: nil), sarah = FeedFriend(name: "Sarah", photo: nil), blake = FeedFriend(name: "Blake", photo: nil)
        var on = ev("on", "6 PM"), next = ev("next", "8 PM")
        XCTAssertEqual(TodayBubbleRules.friends([on, next]), [])
        on.friendsGoing = [sam, sarah]
        next.friendsGoing = [sarah, blake]
        XCTAssertEqual(TodayBubbleRules.friends([on, next]), [sam, sarah, blake])
        // One event's friends are all different people, however alike they read.
        on.friendsGoing = [sam, sam]
        XCTAssertEqual(TodayBubbleRules.friends([on]).count, 2)
    }

    /// The card opens on the first event friends are Going to, however the bubble orders them.
    func testTheCardOpensOnTheEventFriendsAreGoingTo() {
        var on = ev("on", "6 PM"), next = ev("next", "8 PM"), later = ev("later", "9 PM")
        XCTAssertEqual(TodayBubbleRules.firstPage([on, next, later]), 0, "no friends: its first")
        later.friendsGoing = [FeedFriend(name: "Sam", photo: nil)]
        XCTAssertEqual(TodayBubbleRules.firstPage([on, next, later]), 2)
        next.friendsGoing = later.friendsGoing
        XCTAssertEqual(TodayBubbleRules.firstPage([on, next, later]), 1)
        on.friendsGoing = later.friendsGoing
        XCTAssertEqual(TodayBubbleRules.firstPage([on, next, later]), 0)
    }

    /// The card's last line, in the Event page's words, bold up to where the names end.
    func testTheCardsLastLineNamesFriends() {
        XCTAssertNil(MapEventCard.friendWords([]))
        for (names, bold, rest) in [(["Blake"], "Blake", " is going"),
                                    (["Sam", "Sarah"], "Sam and Sarah", " are going"),
                                    (["Sarah", "Sam", "Blake", "Mia", "Theo"], "Sarah", " and 4 friends are going")] {
            let said = MapEventCard.friendWords(names)
            XCTAssertEqual(said?.names, bold)
            XCTAssertEqual(said?.rest, rest)
            XCTAssertEqual(said.map { $0.names + $0.rest }, RSVPWords.friendsLine(names, bar: false))
        }
    }

    // MARK: Another day's Event (inside-cards 19)

    /// Sunday, Nov 8 2026 at 10 AM in the Town.
    private let sunday = Town.midnight("2026-11-08")!.addingTimeInterval(10 * 3600)
    private func on(_ day: String, _ start: String? = "7 PM", endAt: Date? = nil) -> FeedCardItem {
        var card = ev(day, start, endAt: endAt)
        card.eventDate = day
        return card
    }
    /// An exhibition that opened Oct 28 and runs to 5 PM on Dec 15.
    private var exhibition: FeedCardItem {
        on("2026-10-28", "10 AM", endAt: Town.midnight("2026-12-15")!.addingTimeInterval(17 * 3600))
    }

    /// The tag under another day's bubble says the day, never a countdown ("168h 00m" for next week), or "Until"
    /// its last day while one that began before today is still on; today's keep counting down.
    func testAnotherDaysTagSaysItsDay() {
        XCTAssertEqual(TodayBubbleRules.dayTag(on("2026-11-15"), now: sunday), "Sun, Nov 15", "next week")
        XCTAssertEqual(TodayBubbleRules.dayTag(on("2026-11-09"), now: sunday), "Tomorrow")
        XCTAssertEqual(TodayBubbleRules.dayTag(exhibition, now: sunday), "Until Dec 15", "runs for weeks")
        XCTAssertEqual(TodayBubbleRules.dayTag(on("2026-11-01"), now: sunday), "Sun, Nov 1", "over, last week")
        XCTAssertNil(TodayBubbleRules.dayTag(on("2026-11-08"), now: sunday), "today's counts down")
    }

    /// The map card's time line says another day's day, never "Today, 7 PM" for next week.
    func testTheMapCardSaysAnotherDaysDay() {
        let ten = { (day: String) in Town.midnight(day)!.addingTimeInterval(22 * 3600) }
        XCTAssertEqual(MapEventCard.timeLine(on("2026-11-15", endAt: ten("2026-11-15")), now: sunday), "Sun, Nov 15, 7 – 10 PM")
        XCTAssertEqual(MapEventCard.timeLine(on("2026-11-09"), now: sunday), "Tomorrow, 7 PM")
        XCTAssertEqual(MapEventCard.timeLine(on("2026-11-20", nil), now: sunday), "Fri, Nov 20, all day")
        XCTAssertEqual(MapEventCard.timeLine(exhibition, now: sunday), "Until Dec 15")
        XCTAssertEqual(MapEventCard.timeLine(on("2026-11-08", endAt: ten("2026-11-08")), now: sunday), "Tonight, 7 – 10 PM",
                       "today's as before")
    }

    /// Jesse's sizes: 36 pt zoomed out, 46 at the opening zoom, 72 two steps in, held past either end.
    func testTheBeadGrowsWithTheZoomFrom36To72() {
        let open = SJMapView.openZoom
        XCTAssertEqual(TodayBubbleRules.bead(zoom: open), 46)
        XCTAssertEqual(TodayBubbleRules.bead(zoom: open + 1), 59)
        XCTAssertEqual(TodayBubbleRules.bead(zoom: open + 2), 72)
        XCTAssertEqual(TodayBubbleRules.bead(zoom: open + 4), 72)
        XCTAssertEqual(TodayBubbleRules.bead(zoom: open - 1.6), 36, accuracy: 0.001)
        XCTAssertEqual(TodayBubbleRules.bead(zoom: 10), 36)
    }

    func testDragFollowsThenResistsAndStretchIsCapped() {
        XCTAssertEqual(TodayBubbleRules.rubber(0), 0)
        XCTAssertLessThan(TodayBubbleRules.rubber(10), 10)
        XCTAssertLessThan(TodayBubbleRules.rubber(1000), 23)            // a 40 pt drag moves it about 11 pt
        XCTAssertEqual(TodayBubbleRules.rubber(100), 16.22, accuracy: 0.05)
        XCTAssertEqual(TodayBubbleRules.rubber(-40), -TodayBubbleRules.rubber(40), accuracy: 0.0001)
        XCTAssertEqual(TodayBubbleRules.stretch(distance: 11, speed: 0), 0.1, accuracy: 0.0001)
        XCTAssertEqual(TodayBubbleRules.stretch(distance: 12, speed: 4000), 0.13)
    }

    func testStretchMatrixStretchesAlongThePullAboutTheCentre() {
        let m = TodayEventBubble.stretchMatrix(angle: 0, along: 1.1, across: 1 / 1.1, size: 64)
        let centre = CGPoint(x: 32, y: 32).applying(m)
        XCTAssertEqual(centre.x, 32, accuracy: 0.001); XCTAssertEqual(centre.y, 32, accuracy: 0.001)
        let right = CGPoint(x: 42, y: 32).applying(m)
        XCTAssertEqual(right.x, 43, accuracy: 0.001)                    // 10 pt along the pull becomes 11
        let diag = TodayEventBubble.stretchMatrix(angle: .pi / 4, along: 1.2, across: 1, size: 64)
        let p = CGPoint(x: 42, y: 42).applying(diag)                   // along the 45° pull
        XCTAssertEqual(p.x, 44, accuracy: 0.001); XCTAssertEqual(p.y, 44, accuracy: 0.001)
    }
}
