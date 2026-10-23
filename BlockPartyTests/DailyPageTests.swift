//
//  DailyPageTests.swift
//  BlockPartyTests — the Daily tab: its sample Spotlight, the low sun that throws the
//  card's shadow across the yellow, and the tilt.
//

import UIKit
import XCTest
@testable import BlockParty

final class DailyPageTests: XCTestCase {
    #if DEBUG
    /// The sample Spotlight names its photos by bundle resource; a renamed or removed
    /// image would leave a grey hole in the card instead of failing anywhere else.
    func testSampleSpotlightPhotosAreBundled() {
        XCTAssertNotNil(DailySpotlight.sample.portrait)
        XCTAssertEqual(DailySpotlight.sample.photos.count, 2)
    }
    #endif

    /// The Spotlight's three faces resolve by PostScript name. A wrong name falls back to
    /// the system font with no error, and "Spotlight" would quietly lose the logo's look.
    func testTheSpotlightFacesAreBundled() {
        registerBlockPartyFonts()
        for face in [Face.logoSerif, Face.eventHeadline, Face.displayMedium] {
            XCTAssertNotNil(UIFont(name: face, size: 20), face)
        }
    }

    /// Morning throws the shadow right, dinner throws it left, both long; midday drops it
    /// short and straight down.
    func testTheSunSwingsTheShadowAcrossTheDay() {
        let sunrise = DailySun.shadow(hour: 6), midday = DailySun.shadow(hour: 13.5)
        let sunset = DailySun.shadow(hour: 21)
        XCTAssertEqual(sunrise.x, 46, accuracy: 0.001)
        XCTAssertEqual(sunset.x, -46, accuracy: 0.001)
        XCTAssertEqual(midday.x, 0, accuracy: 0.001)
        XCTAssertEqual(sunrise.y, 36, accuracy: 0.001)
        XCTAssertEqual(midday.y, 12, accuracy: 0.001)
        XCTAssertGreaterThan(sunrise.blur, midday.blur)
    }

    /// At night the shadow is the midday one, like a streetlight overhead (Jesse, 2026-10-01).
    func testNightKeepsTheMiddayShadow() {
        let midday = DailySun.shadow(hour: 13.5)
        for hour in [0.0, 3, 5.9, 21.1, 23.5] {
            let night = DailySun.shadow(hour: hour)
            XCTAssertEqual(night.x, midday.x, accuracy: 0.001, "hour \(hour)")
            XCTAssertEqual(night.y, midday.y, accuracy: 0.001, "hour \(hour)")
        }
    }

    /// The sun keeps the Town's clock, not the phone's.
    func testTheSunReadsTheTownsHour() {
        // 2026-10-01 12:30 UTC is 7:30 in the morning in St. Joseph (CDT, UTC-5).
        let date = Date(timeIntervalSince1970: 1_790_857_800)
        XCTAssertEqual(DailySun.hour(at: date), 7.5, accuracy: 0.001)
    }

    /// The lean is measured from the way the phone is held, stops at a full lean, and the
    /// rest creeps toward the hand so a new grip reads as level again.
    func testTiltLeansFromTheRestAndTheRestFollows() {
        var rest = (x: 0.0, z: -0.5)
        let lean = PhoneTilt.lean(gravity: (x: 0.6, z: -0.65), rest: &rest)
        XCTAssertEqual(lean.x, 1, accuracy: 0.001, "a lean past the range stops at a full lean")
        XCTAssertEqual(lean.y, -0.5, accuracy: 0.001)
        XCTAssertGreaterThan(rest.x, 0)
        XCTAssertLessThan(rest.x, 0.6)

        for _ in 0..<600 { _ = PhoneTilt.lean(gravity: (x: 0.6, z: -0.65), rest: &rest) }
        let settled = PhoneTilt.lean(gravity: (x: 0.6, z: -0.65), rest: &rest)
        XCTAssertEqual(settled.x, 0, accuracy: 0.01, "held still for 10 s, the grip reads as level")
    }

    #if DEBUG
    // MARK: Event of the day

    /// 2026-10-01 in St. Joseph; the samples sit at 8–12, 16–17 and 19–21 Town time.
    private let day = Date(timeIntervalSince1970: 1_790_857_800)

    private func town(_ hour: Double) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Town.timeZone
        return calendar.startOfDay(for: day).addingTimeInterval(hour * 3600)
    }

    /// Soonest first, three at most; one that has ended gives its spot to the next, and
    /// with none left nothing shows, so the section goes.
    @MainActor
    func testEventOfTheDayKeepsWhatIsStillOnSoonestFirst() {
        let samples = DailyEvent.samples(on: day)
        let morning = DailyEvent.showing(samples.reversed(), now: town(7), limit: 3)
        XCTAssertEqual(morning.map(\.item.title), ["Farmers Market", "Abbey organ recital", "Music in Millstream Park"])
        XCTAssertEqual(DailyEvent.showing(samples, now: town(12), limit: 3).first?.item.title, "Abbey organ recital")
        XCTAssertEqual(DailyEvent.showing(samples, now: town(20), limit: 3).map(\.item.title), ["Music in Millstream Park"])
        XCTAssertTrue(DailyEvent.showing(samples, now: town(21), limit: 3).isEmpty)

        var four = samples
        four.append(samples[0])
        four[3].starts = town(22)
        four[3].ends = town(23)
        XCTAssertEqual(DailyEvent.showing(four, now: town(7), limit: 3).count, 3)
    }

    /// The pill says how soon, then "Now" once it has started.
    @MainActor
    func testEventOfTheDayPillSaysHowSoon() {
        let recital = DailyEvent.samples(on: day)[1]
        XCTAssertEqual(recital.startsLabel(now: town(14)), "In 2 hours")
        XCTAssertEqual(recital.startsLabel(now: town(16.25)), "Now")
    }

    // MARK: Suggestions

    /// Soonest first, ten at most, and never one a section above already shows. The
    /// samples run from 7:30 in the morning to 8:30 at night.
    @MainActor
    func testSuggestionsLeaveOutWhatIsAboveAndStopAtTen() {
        let samples = DailyEvent.suggestionSamples(on: day)
        XCTAssertEqual(DailyEvent.showing(samples.reversed(), now: town(8), without: [samples[2]], limit: 10).map(\.id),
                       ["daily-s1", "daily-s2", "daily-s4", "daily-s5", "daily-s6", "daily-s7"])
        XCTAssertEqual(DailyEvent.showing(samples, now: town(9), limit: 10).first?.id, "daily-s2")

        let many = (0..<12).map { i in
            DailyEvent.sample(id: "many-\(i)", title: "Event \(i)", host: "", photo: "", place: "Here",
                              starts: town(9 + Double(i) / 2), ends: town(10 + Double(i) / 2),
                              category: .other, description: "")
        }
        XCTAssertEqual(DailyEvent.showing(many, now: town(8), limit: 10).map(\.id),
                       (0..<10).map { "many-\($0)" })
    }

    // MARK: Following

    /// Events still to come, soonest first, then today's updates so far, newest first.
    /// The samples: events at 9–13, 15–16 and 17:30–18:30, updates at 7:15 and 11.
    @MainActor
    func testFollowingPutsEventsSoonestFirstThenUpdatesNewestFirst() {
        let samples = DailyFollowing.samples(on: day)
        XCTAssertEqual(DailyFollowing.showing(samples.reversed(), now: town(12), limit: 10).map(\.id),
                       ["follow-1", "follow-2", "follow-3", "follow-4", "follow-5"])
        // At 8 the 11 o'clock update hasn't gone up; at 14 the porch sale is over.
        XCTAssertEqual(DailyFollowing.showing(samples, now: town(8), limit: 10).map(\.id),
                       ["follow-1", "follow-2", "follow-3", "follow-5"])
        XCTAssertEqual(DailyFollowing.showing(samples, now: town(14), limit: 10).map(\.id),
                       ["follow-2", "follow-3", "follow-4", "follow-5"])
        // Not one a section above shows, and no more than the limit.
        XCTAssertEqual(DailyFollowing.showing(samples, now: town(12), without: [samples[1].event!], limit: 3).map(\.id),
                       ["follow-1", "follow-3", "follow-4"])
    }

    /// An event says when it starts; an update says how long ago it went up.
    @MainActor
    func testFollowingTimeIsTheStartOrHowLongAgo() {
        let samples = DailyFollowing.samples(on: day)
        func plain(_ text: String) -> String { text.replacingOccurrences(of: "\u{202F}", with: " ") }
        XCTAssertEqual(plain(samples[2].time(now: town(12))), "5:30 PM")
        XCTAssertEqual(samples[0].time(now: town(12)), "Now")
        XCTAssertEqual(samples[3].time(now: town(13.5)), "2h")
        XCTAssertEqual(samples[3].time(now: town(11.25)), "15m")
        XCTAssertEqual(samples[3].spokenTime(now: town(11.25)), "15 minutes ago")
    }
    #endif

    /// One row as `get_event_of_the_day` sends it (the Town feed's row), read by the feed's decoder.
    private func eventOfTheDayRow(start: String?, allDay: Bool = false, leaves: String) throws -> TownFeedRow {
        let json: [String: Any] = [
            "id": "11111111-2222-3333-4444-555555555555", "title": "Sartell Boys Soccer vs ROCORI",
            "event_date": "2026-10-20", "start_time": start ?? NSNull(), "location": "Sartell High School",
            "image_url": NSNull(), "category": "sports_leagues", "club_name": NSNull(),
            "source_name": "Sartell High School", "end_at": NSNull(), "all_day": allDay,
            "created_at": "2026-10-01T12:00:00+00:00", "going_count": 2, "rsvpd": true,
            "recurrence": NSNull(), "leaves_at": leaves]
        let rows = try CommunityAPI.townFeedRows(from: JSONSerialization.data(withJSONObject: [json]))
        return try XCTUnwrap(rows.first)
    }

    /// A pick becomes Daily's poster: it starts at its own time in the Town, stays until it leaves
    /// the feed, shows its place, and keeps its Going.
    func testAnEventOfTheDayRowIsDailysPoster() throws {
        // 7 PM in St. Joseph on Oct 20 is midnight UTC; the feed lets it go two hours on.
        let row = try eventOfTheDayRow(start: "7 PM", leaves: "2026-10-21T02:00:00+00:00")
        let event = try XCTUnwrap(DailyEvent(row: row))
        XCTAssertEqual(event.starts, Date(timeIntervalSince1970: 1_792_540_800))
        XCTAssertEqual(event.ends, Date(timeIntervalSince1970: 1_792_548_000))
        XCTAssertTrue(event.timed)
        XCTAssertEqual(event.item.whereLine, "Sartell High School")
        XCTAssertTrue(event.item.isJoined)
    }

    /// All day, it runs from the Town's midnight and its card shows no clock.
    func testAnAllDayPickRunsTheWholeDay() throws {
        let row = try eventOfTheDayRow(start: "9 AM", allDay: true, leaves: "2026-10-21T05:00:00+00:00")
        let event = try XCTUnwrap(DailyEvent(row: row))
        XCTAssertFalse(event.timed)
        XCTAssertEqual(event.starts, Date(timeIntervalSince1970: 1_792_472_400))
        XCTAssertEqual(event.startTime(now: event.starts), "All day")
    }

    /// Daily reads again only after 10 minutes, on a new Town day or once a pick is over, since
    /// each read works the whole Town feed out on the server; a failed read keeps the picks.
    @MainActor
    func testEventOfTheDayReadsAgainOnlyWhenItMatters() async throws {
        let pick = try XCTUnwrap(DailyEvent(row: eventOfTheDayRow(start: "7 PM", leaves: "2026-10-21T02:00:00+00:00")))
        var reads = 0
        var fails = false
        let model = EventOfTheDay(read: {
            reads += 1
            if fails { throw URLError(.notConnectedToInternet) }
            return [pick]
        })
        // Noon in St. Joseph on Oct 20.
        let noon = Date(timeIntervalSince1970: 1_792_515_600)
        await model.refresh(now: noon)
        await model.refresh(now: noon.addingTimeInterval(9 * 60))
        XCTAssertEqual(reads, 1)
        fails = true
        await model.refresh(now: noon.addingTimeInterval(10 * 60))
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(model.events?.map(\.id), [pick.id], "a failed read keeps the picks")
        fails = false
        await model.refresh(now: noon.addingTimeInterval(11 * 60))
        XCTAssertEqual(reads, 3)
        // Over at 9 PM: the next one may take its spot.
        await model.refresh(now: pick.ends)
        XCTAssertEqual(reads, 4)
        // A new account reads again at once, keeping these on screen until its own land.
        model.accountChanged()
        XCTAssertEqual(model.events?.map(\.id), [pick.id])
        XCTAssertTrue(model.needsRead(now: noon))

        // Offline with nothing read yet: none, so Daily shows its placeholder, and it reads again.
        let offline = EventOfTheDay(read: { throw URLError(.notConnectedToInternet) })
        await offline.refresh(now: noon)
        XCTAssertEqual(offline.events?.count, 0)
        XCTAssertTrue(offline.needsRead(now: noon))
    }

    /// Today's kept picks show while the first read is out, so the Town poster lands with the
    /// list (event-card 03); they stay when that read fails; picks that are over never show.
    @MainActor
    func testKeptPicksShowUntilTheReadLands() async throws {
        let pick = try XCTUnwrap(DailyEvent(row: eventOfTheDayRow(start: "7 PM", leaves: "2026-10-21T02:00:00+00:00")))
        let noon = Date(timeIntervalSince1970: 1_792_515_600)
        var shownWhileReading: [String]?
        var model: EventOfTheDay!
        model = EventOfTheDay(read: {
            shownWhileReading = model.events?.map(\.id)
            throw URLError(.notConnectedToInternet)
        }, kept: { [pick] })
        await model.refresh(now: noon)
        XCTAssertEqual(shownWhileReading, [pick.id])
        XCTAssertEqual(model.events?.map(\.id), [pick.id], "a failed read keeps the kept picks")
        XCTAssertTrue(model.needsRead(now: noon), "kept picks are no read")

        // Kept from yesterday: all over, so none, and the read decides.
        let stale = EventOfTheDay(read: { [] }, kept: { [pick] })
        await stale.refresh(now: pick.ends)
        XCTAssertEqual(stale.events?.count, 0)

        // Yesterday's pick that runs on past midnight is still not today's.
        var overnight = pick
        overnight.ends = pick.starts.addingTimeInterval(2 * 86_400)
        let nextDay = EventOfTheDay(read: { throw URLError(.notConnectedToInternet) }, kept: { [overnight] })
        await nextDay.refresh(now: noon.addingTimeInterval(86_400))
        XCTAssertEqual(nextDay.events?.count, 0)
    }

    /// The Town column opens on the Event of the day and leaves its card out below; with none,
    /// it's the cards alone (event-card 03). Town news keeps its place among them (town-feed 35).
    func testTheTownColumnOpensOnTheEventOfTheDay() throws {
        let pick = try XCTUnwrap(DailyEvent(row: eventOfTheDayRow(start: "7 PM", leaves: "2026-10-21T02:00:00+00:00")))
        func card(_ id: String) -> FeedCardItem {
            FeedCardItem(id: id, title: id, dateChip: "", metaLine: "", image: .fallback, recurrence: nil,
                         goingCount: 0, goingAvatars: [], likeCount: 0, isLiked: false, isSaved: false, isJoined: false)
        }
        let news = TownNews(id: "n", place: "The Wandering Cow", words: "Four scoops for $5 on Fridays.",
                            post: URL(string: "https://www.instagram.com/p/x/")!, leavesAt: .distantFuture)
        func entries(_ cards: [FeedCardItem]) -> [TownFeedEntry] {
            var all = cards.map { TownFeedEntry(card: $0, leavesAt: .distantFuture) }
            all.insert(TownFeedEntry(item: .news(news), leavesAt: .distantFuture), at: 2)
            return all
        }
        let cards = [card("a"), card(pick.id), card("b")]
        XCTAssertEqual(DailyFeedItem.town(entries(cards), eventOfTheDay: pick).map(\.id),
                       ["event-of-the-day:\(pick.id)", "event:a", "news:n", "event:b"])
        // The Score's place is where each sits on screen: the poster first, then the cards, news counted.
        func scored(_ item: FeedCardItem) -> FeedCardItem {
            var item = item
            item.score = FeedScore(interest: 0, friend: 0, follow: 0, popular: 0, size: 0, sizeStep: 1, daysAway: 1,
                                   soon: 0.9, acted: 1, spacing: 1, newSpot: false, total: 0.9, spot: 9, of: 9)
            return item
        }
        var scoredPick = pick
        scoredPick.item = scored(pick.item)
        let places = DailyFeedItem.town(entries(cards.map(scored)), eventOfTheDay: scoredPick).map { item -> String in
            switch item {
            case .eventOfTheDay(let event): return "\(event.item.score?.spot ?? 0)/\(event.item.score?.of ?? 0)"
            case .event(let card): return "\(card.score?.spot ?? 0)/\(card.score?.of ?? 0)"
            case .posting, .news: return "-"
            }
        }
        XCTAssertEqual(places, ["1/4", "2/4", "-", "4/4"])
        XCTAssertEqual(DailyFeedItem.town(entries(cards), eventOfTheDay: pick).map(\.eventID), [pick.id, "a", nil, "b"])
        XCTAssertEqual(DailyFeedItem.town(entries(cards), eventOfTheDay: nil).map(\.id),
                       ["event:a", "event:\(pick.id)", "news:n", "event:b"])
    }

    // MARK: Topics (daily-tab 19)

    private func topicCard(_ title: String, host: String = "") -> FeedCardItem {
        var card = FeedCardItem(id: title, title: title, dateChip: "", metaLine: "", image: .fallback, recurrence: nil,
                                goingCount: 0, goingAvatars: [], likeCount: 0, isLiked: false, isSaved: false, isJoined: false)
        card.hostName = host
        return card
    }

    /// Your own interests come first, in your order, and only those the day has something for.
    @MainActor
    func testTopicsAreYourInterestsThatTheDayHas() {
        let day = [topicCard("Live jazz", host: "Krewe"), topicCard("Latte art class", host: "Local Blend")]
        XCTAssertEqual(DailyTopic.topics(for: day, mine: ["coffee", "biking", "live_music"]), ["coffee", "live_music"])
    }

    /// With no interests picked (signed out), the day's busiest interests lead.
    @MainActor
    func testWithNoInterestsTheBusiestTopicsLead() {
        let day = [topicCard("Yoga in the park"), topicCard("Park cleanup"), topicCard("Open mic")]
        let topics = DailyTopic.topics(for: day, mine: [])
        XCTAssertEqual(topics.first, "parks_gardens")
        XCTAssertTrue(topics.contains("live_music"))
        XCTAssertFalse(topics.contains("biking"))
        XCTAssertLessThanOrEqual(DailyTopic.topics(for: day, mine: [], limit: 1).count, 1)
    }

    /// A topic keeps the events that match it, by the words "Suggested for you" reads.
    @MainActor
    func testATopicMatchesItsEvents() {
        XCTAssertTrue(DailyTopic.matches(topicCard("Beer and trivia", host: "Bad Habit"), "breweries"))
        XCTAssertFalse(DailyTopic.matches(topicCard("Story time"), "breweries"))
        // Whole words only: "art" isn't in "Block Party", "park" isn't in "parking".
        XCTAssertFalse(DailyTopic.matches(topicCard("Block Party"), "art_exhibits"))
        XCTAssertTrue(DailyTopic.matches(topicCard("Student art show"), "art_exhibits"))
        XCTAssertTrue(DailyTopic.matches(topicCard("Two parks cleanup"), "parks_gardens"))
        XCTAssertFalse(DailyTopic.matches(topicCard("Market in the church parking lot"), "parks_gardens"))
        XCTAssertEqual(DailyTopic.label("live_music"), "Live music")
    }

    // MARK: Friends are going and Suggestions from the Town feed (daily-tab 20, 21)

    private func dayCard(_ title: String, day: String, at time: String, friends: [String] = []) -> FeedCardItem {
        var card = topicCard(title)
        card.eventDate = day
        card.startTime = time
        card.friendsGoing = friends.map { FeedFriend(name: $0, photo: nil) }
        return card
    }

    private var dayStart: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Town.timeZone
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 22))!
    }

    /// The day's events that match your interests, in the feed's order; with none, the day's all.
    @MainActor
    func testSuggestionsAreTheDaysEventsForYourInterestsInFeedOrder() {
        let cards = [dayCard("Live jazz", day: "2026-10-22", at: "7 PM"),
                     dayCard("Live band", day: "2026-10-23", at: "7 PM"),
                     dayCard("Book club", day: "2026-10-22", at: "6 PM"),
                     dayCard("Latte art", day: "2026-10-22", at: "9 AM")]
        func titles(_ interests: [String], without: [DailyEvent] = [], left: (FeedCardItem) -> Bool = { _ in true }) -> [String] {
            DailyEvent.suggestions(from: cards, day: "2026-10-22", interests: interests, now: dayStart,
                                   without: without, left: left).map(\.item.title)
        }
        XCTAssertEqual(titles(["live_music", "coffee"]), ["Live jazz", "Latte art"])
        XCTAssertEqual(titles([]), ["Live jazz", "Book club", "Latte art"])
        XCTAssertEqual(titles(["live_music", "coffee"], left: { $0.title != "Latte art" }), ["Live jazz"])
        let shown = DailyEvent.suggestions(from: [cards[0]], day: "2026-10-22", interests: [], now: dayStart,
                                           without: [], left: { _ in true })
        XCTAssertEqual(titles(["live_music", "coffee"], without: shown), ["Latte art"])
    }

    /// Most friends first, then soonest; only the days asked for, only events with friends.
    @MainActor
    func testFriendsAreGoingLeadsWithMostFriendsThenSoonest() {
        let cards = [dayCard("Two friends", day: "2026-10-22", at: "7 PM", friends: ["Kim", "Tom"]),
                     dayCard("Three, Thursday", day: "2026-10-22", at: "9 AM", friends: ["Kim", "Tom", "Joe"]),
                     dayCard("Three, Friday", day: "2026-10-23", at: "8 AM", friends: ["Ana", "Ben", "Sam"]),
                     dayCard("Nobody", day: "2026-10-22", at: "8 AM")]
        let week = DailyEvent.friendsGoing(from: cards, days: ["2026-10-22", "2026-10-23"], now: dayStart, without: [])
        XCTAssertEqual(week.map(\.item.title), ["Three, Thursday", "Three, Friday", "Two friends"])
        var off = dayCard("Called off", day: "2026-10-22", at: "6 PM", friends: ["Kim", "Tom", "Joe", "Ana"])
        off.cancelled = true
        XCTAssertFalse(DailyEvent.friendsGoing(from: cards + [off], days: ["2026-10-22"], now: dayStart, without: [])
            .contains { $0.item.title == "Called off" })
        XCTAssertTrue(DailyEvent.suggestions(from: [off], day: "2026-10-22", interests: [], now: dayStart,
                                             without: [], left: { _ in true }).isEmpty)
        let friday = DailyEvent.friendsGoing(from: cards, days: ["2026-10-23"], now: dayStart, without: [])
        XCTAssertEqual(friday.map(\.item.title), ["Three, Friday"])
    }
}
