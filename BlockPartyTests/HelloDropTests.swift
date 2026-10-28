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
                         groups: [TownGroup] = [], town towns: [DailyEvent] = [], news: [TownNews] = [],
                         joined: Neighbor? = nil) -> String? {
        HelloDrop.message(now: town(now), lastSeen: lastSeen.map(town), going: going,
                          groups: groups, town: towns, news: news, waiting: joined.map(HelloDrop.joined))?.text
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

    /// A fresh memory, its own store each test.
    private func inbox(_ name: String = #function) -> (HelloInbox, UserDefaults) {
        let keep = UserDefaults(suiteName: "HelloInboxTests.\(name)")!
        keep.removePersistentDomain(forName: "HelloInboxTests.\(name)")
        return (HelloInbox(keep: keep), keep)
    }

    private func moments(_ name: String = #function) -> (HelloMoments, HelloInbox) {
        let (inbox, keep) = inbox(name)
        return (HelloMoments(said: keep, inbox: inbox), inbox)
    }

    /// The pill says the next one, then it's told.
    private func take(_ inbox: HelloInbox) -> HelloItem.What? {
        guard let next = inbox.next else { return nil }
        inbox.tell(next.id)
        return next.what
    }

    func testEachMomentIsSaidOnceEver() {
        let (moments, inbox) = moments()
        moments.reach(.firstFriend)
        XCTAssertEqual(take(inbox), .moment(.firstFriend))
        moments.reach(.firstFriend)
        XCTAssertNil(take(inbox))
    }

    /// Two reached together both show, in order.
    func testTwoMomentsAtOnceBothShow() {
        let (moments, inbox) = moments()
        moments.attended(1)
        moments.reach(.firstPlace)
        XCTAssertEqual(take(inbox), .moment(.firstEvent))
        XCTAssertEqual(take(inbox), .moment(.firstPlace))
        XCTAssertNil(take(inbox))
    }

    /// A neighbour already past 10 hears "10th", never "first", and never both.
    func testOnlyTheHighestAttendedMilestoneShows() {
        let (moments, inbox) = moments()
        moments.attended(12)
        XCTAssertEqual(take(inbox), .moment(.tenthEvent))
        moments.attended(13)
        XCTAssertNil(take(inbox))
        XCTAssertTrue(moments.hasSaid(.firstEvent))
        moments.attended(100)
        XCTAssertEqual(take(inbox), .moment(.hundredthEvent))
    }

    /// Only the firsts you make with a tap skip the wait; attended milestones are news.
    func testOnlyYourOwnFirstsSkipTheWait() {
        XCTAssertEqual(HelloMoment.allCases.filter { !$0.yours }, [.firstEvent, .tenthEvent, .hundredthEvent])
    }

    // MARK: The pill's memory (hello-drop 05)

    private let sam = Neighbor(userId: "sam", displayName: "Sam Rivera", avatarUrl: "https://x/sam.jpg", since: nil,
                               relation: .stranger, mutualFriends: 0)

    /// At most 3 a day, an hour apart, and the hour holds over midnight.
    func testThreePillsADayAnHourApart() {
        let (inbox, keep) = inbox()
        XCTAssertTrue(inbox.mayDrop(now: town("2026-10-21 08:00")))
        inbox.dropped(now: town("2026-10-21 08:00"))
        XCTAssertFalse(inbox.mayDrop(now: town("2026-10-21 08:59")))
        XCTAssertTrue(inbox.mayDrop(now: town("2026-10-21 09:00")))
        inbox.dropped(now: town("2026-10-21 12:30"))
        inbox.dropped(now: town("2026-10-21 14:15"))
        XCTAssertFalse(inbox.mayDrop(now: town("2026-10-21 19:00")), "3 today")
        XCTAssertFalse(HelloInbox(keep: keep).mayDrop(now: town("2026-10-21 23:00")), "kept on the phone")
        inbox.dropped(now: town("2026-10-22 23:50"))
        XCTAssertFalse(inbox.mayDrop(now: town("2026-10-23 00:05")), "a new day, but 15 minutes on")
        XCTAssertTrue(inbox.mayDrop(now: town("2026-10-23 00:50")))
    }

    /// Firsts, then finals, then who joined; oldest first within each; one found twice is one.
    func testTheHigherOneFirstAndEachOnce() {
        let (inbox, _) = inbox()
        let johnnies = HelloItem.Final(final([33, 23], mine: 0))!
        inbox.add(.joined(sam), at: town("2026-10-21 07:00"))
        inbox.add(.final(johnnies), at: town("2026-10-21 08:00"))
        inbox.add(.moment(.firstEvent), at: town("2026-10-21 09:00"))
        inbox.add(.moment(.firstPlace), at: town("2026-10-21 09:30"))
        inbox.add(.joined(sam), at: town("2026-10-21 10:00"))
        XCTAssertEqual(inbox.items.count, 4)
        XCTAssertEqual(take(inbox), .moment(.firstEvent))
        XCTAssertEqual(take(inbox), .moment(.firstPlace))
        XCTAssertEqual(take(inbox), .final(johnnies))
        XCTAssertEqual(take(inbox), .joined(sam))
        XCTAssertNil(inbox.next, "nothing new: no dot")
        // Said already: found again, it stays said.
        inbox.add(.joined(sam), at: town("2026-10-22 07:00"))
        XCTAssertNil(inbox.next)
    }

    /// Kept on the phone 7 days, newest first; the bell's page tells them all.
    func testTheBellKeepsAWeek() {
        let (inbox, keep) = inbox()
        inbox.add(.moment(.firstEvent), at: town("2026-10-14 09:00"))
        inbox.add(.joined(sam), at: town("2026-10-20 09:00"))
        let kept = HelloInbox(keep: keep, now: town("2026-10-21 09:00"))
        XCTAssertEqual(kept.recent(now: town("2026-10-21 09:00")).map(\.id), ["joined:sam"], "a week old has gone")
        XCTAssertEqual(kept.next?.id, "joined:sam")
        kept.toldAll()
        XCTAssertNil(kept.next, "seen on the bell: the pill never says it")
        XCTAssertNil(HelloInbox(keep: keep).next)
        // Gone before it could be read: new again.
        kept.tell("joined:sam", false)
        XCTAssertEqual(kept.next?.id, "joined:sam")
        // Friends since, or blocked: today's check no longer has them, so they go.
        kept.keepJoined([])
        XCTAssertTrue(kept.items.isEmpty)
    }

    /// A contact is kept at when they joined, so the bell says how long ago; one who joined a
    /// week ago or more isn't new.
    func testAContactIsKeptAtTheirJoin() {
        let (inbox, _) = inbox()
        let now = town("2026-10-21 09:00")
        inbox.add(.joined(sam), at: town("2026-10-19 09:00"), now: now)
        XCTAssertEqual(inbox.recent(now: now).first?.at, town("2026-10-19 09:00"))
        let kate = Neighbor(userId: "kate", displayName: "Kate", avatarUrl: nil, since: nil, relation: .stranger,
                            mutualFriends: 0)
        inbox.add(.joined(kate), at: town("2026-10-13 09:00"), now: now)
        XCTAssertEqual(inbox.items.map(\.id), ["joined:sam"])
    }

    // MARK: A friend request accepted (hello-drop 06)

    private let kate = Neighbor(userId: "kate", displayName: "Kate Moore", avatarUrl: "https://x/kate.jpg", since: nil,
                                relation: .friends, mutualFriends: 0)

    func testAnAcceptedRequestAsThePillAndTheBellSayIt() {
        let item = HelloItem(what: .accepted(kate), at: Date())
        XCTAssertEqual(item.message?.text, "Kate accepted your friend request")
        XCTAssertEqual(item.message?.target, .person(kate))
        XCTAssertEqual(item.message?.logo, URL(string: "https://x/kate.jpg"))
        XCTAssertEqual(item.message?.photo, true)
        XCTAssertEqual(item.row().name, "Kate Moore")
        XCTAssertEqual(item.row().words, "accepted your friend request.")
        XCTAssertEqual(item.row().picture, .photo("https://x/kate.jpg"))
    }

    /// After a final, ahead of who joined.
    func testAnAcceptanceComesAfterAFinalAheadOfAContact() {
        let (inbox, _) = inbox()
        inbox.add(.joined(sam), at: town("2026-10-21 07:00"))
        inbox.add(.accepted(kate), at: town("2026-10-21 08:00"))
        let johnnies = HelloItem.Final(final([33, 23], mine: 0))!
        inbox.add(.final(johnnies), at: town("2026-10-21 09:00"))
        XCTAssertEqual(take(inbox), .final(johnnies))
        XCTAssertEqual(take(inbox), .accepted(kate))
        XCTAssertEqual(take(inbox), .joined(sam))
        XCTAssertNil(inbox.next)
    }

    /// Seen on the Friends page: never said. Blocked: gone. Another account: its acceptances go.
    func testTheFriendsPageABlockAndAnotherAccount() {
        let (inbox, _) = inbox()
        let now = town("2026-10-21 09:00")
        inbox.add(.accepted(kate), at: now)
        inbox.add(.joined(sam), at: now)
        inbox.tellAccepted(["kate"])
        XCTAssertEqual(inbox.next?.id, "joined:sam")
        inbox.forget("sam")
        XCTAssertEqual(inbox.items.map(\.id), ["accepted:kate"])
        inbox.forgetAccount()
        XCTAssertTrue(inbox.items.isEmpty)
        // One accepted 9 days ago isn't new.
        inbox.add(.accepted(kate), at: town("2026-10-12 09:00"), now: now)
        XCTAssertTrue(inbox.items.isEmpty)
    }

    // MARK: What you follow added (hello-drop 07)

    private func card(_ id: String, followed: String?, found: String, day: String = "2026-10-23",
                      cancelled: Bool = false) -> FeedCardItem {
        var card = FeedCardItem(UpcomingEvent(id: id, title: "Board Game Night", eventDate: day, startTime: "6 PM",
                                              location: nil, goingCount: 0, createdAt: ""))
        card.followed = followed
        card.createdAt = town(found)
        card.cancelled = cancelled
        return card
    }

    /// Only what you follow, not called off: one item a name, the newest found first.
    func testNewEventsOfWhatYouFollowAreOneItemEach() {
        let now = town("2026-10-21 09:00")
        let cards = [card("a", followed: "Clemens Library", found: "2026-10-21 06:00"),
                     card("b", followed: "Clemens Library", found: "2026-10-21 07:00"),
                     card("c", followed: nil, found: "2026-10-21 07:00"),
                     card("e", followed: "Bad Habit Brewing", found: "2026-10-21 08:00", cancelled: true)]
        let found = HelloItem.Added.found(cards, now: now)
        XCTAssertEqual(found.map(\.name), ["Clemens Library"])
        XCTAssertEqual(found.first?.count, 2)
        XCTAssertEqual(found.first?.eventId, "b", "the newest")
        let item = HelloItem(what: .added(found[0]), at: now)
        XCTAssertEqual(item.message?.text, "Clemens Library added 2 events")
        XCTAssertEqual(item.message?.target, .eventID("b"))
        XCTAssertEqual(item.row(now: now).words, "added 2 events.")
        XCTAssertEqual(item.id, "added:Clemens Library:2026-10-21", "one item a day for each")
        let one = HelloItem(what: .added(HelloItem.Added.found(Array(cards.prefix(1)), now: now)[0]), at: now)
        XCTAssertEqual(one.message?.text, "Clemens Library added an event")
        XCTAssertEqual(one.row(now: now).words, "added an event: Board Game Night, Fri 6 PM.")
    }

    /// The bell's when stays short: the day word, the weekday within the week, else the date.
    func testTheAddedRowsWhenIsShort() {
        let now = town("2026-10-21 09:00")
        func when(_ day: String, _ time: String?) -> String? {
            HelloItem.Added(name: "x", day: "", eventId: "", title: "", eventDate: day, startTime: time, count: 1,
                            picture: nil, pictureIsPhoto: false, photo: nil).when(now: now)
        }
        XCTAssertEqual(when("2026-10-21", "7 PM"), "Tonight 7 PM")
        XCTAssertEqual(when("2026-10-22", "6 PM"), "Tomorrow 6 PM")
        XCTAssertEqual(when("2026-10-23", "6 PM"), "Fri 6 PM")
        XCTAssertEqual(when("2026-10-24", nil), "Sat")
        XCTAssertEqual(when("2026-11-20", "6 PM"), "Nov 20")
    }

    /// The first look only notes the feed. After it, a card that wasn't there is new, however long
    /// ago it was found (one posted a month out reaches the feed two weeks before); more the same
    /// day, not yet said, add up.
    func testANewCardOnTheFeedIsNew() {
        let (inbox, _) = inbox()
        let old = card("a", followed: "Clemens Library", found: "2026-10-01 06:00")
        inbox.look(at: [old], now: town("2026-10-21 09:00"))
        XCTAssertNil(inbox.next)
        inbox.look(at: [old, card("b", followed: "Clemens Library", found: "2026-10-02 06:00")], now: town("2026-10-21 10:00"))
        XCTAssertEqual(inbox.next?.id, "added:Clemens Library:2026-10-21")
        XCTAssertEqual(inbox.next?.at, town("2026-10-21 10:00"), "when it reached you")
        inbox.look(at: [old, card("b", followed: "Clemens Library", found: "2026-10-02 06:00"),
                        card("c", followed: "Clemens Library", found: "2026-10-21 11:00")], now: town("2026-10-21 11:30"))
        XCTAssertEqual(inbox.items.count, 1)
        guard case .added(let both) = inbox.next?.what else { return XCTFail("one item") }
        XCTAssertEqual(both.count, 2)
        XCTAssertEqual(both.eventId, "c")
        inbox.forgetAccount()
        XCTAssertNil(inbox.next)
        inbox.look(at: [card("d", followed: "Clemens Library", found: "2026-10-21 12:00")], now: town("2026-10-21 12:30"))
        XCTAssertNil(inbox.next, "another account looks afresh")
    }

    /// On the morning open it comes after your own day, as a contact who joined does.
    func testWhatYouFollowAddedWaitsForYourDay() {
        let added = HelloItem(what: .added(HelloItem.Added.found([card("a", followed: "Clemens Library",
                                                                       found: "2026-10-21 06:00")],
                                                                 now: town("2026-10-21 09:00"))[0]),
                              at: town("2026-10-21 06:00"))
        XCTAssertTrue(added.waitsForYourDay)
        XCTAssertFalse(HelloItem(what: .accepted(kate), at: Date()).waitsForYourDay)
        let rock = event("Rocktoberfest", "2026-10-21", "4 PM")
        XCTAssertEqual(HelloDrop.message(now: town("2026-10-21 09:00"), lastSeen: nil, going: [rock], groups: [],
                                         town: [], waiting: added.message)?.text, "Rocktoberfest is today at 4")
        XCTAssertEqual(HelloDrop.message(now: town("2026-10-21 09:00"), lastSeen: nil, going: [], groups: [],
                                         town: [], waiting: added.message)?.text, "Clemens Library added an event")
    }

    /// Each kind as the pill and the bell say it.
    func testThePillAndTheBellSayEachKind() {
        let joined = HelloItem(what: .joined(sam), at: Date())
        XCTAssertEqual(joined.message?.text, "Sam joined Block Party")
        XCTAssertEqual(joined.row().name, "Sam Rivera")
        XCTAssertEqual(joined.row().words, "joined Block Party.")
        XCTAssertEqual(joined.row().picture, .photo("https://x/sam.jpg"))
        let score = HelloItem(what: .final(HelloItem.Final(TeamFinal.sample(won: true))!), at: Date())
        XCTAssertEqual(score.message?.text, "Johnnies beat Gusties 33–23")
        XCTAssertEqual(score.message?.tint, 0xBC0E33)
        XCTAssertEqual(score.row().name, "Johnnies")
        XCTAssertEqual(score.row().words, "beat Gusties 33–23.")
        XCTAssertEqual(HelloItem.Final(final([33, 23], mine: 0))?.teamPage?.id, "4f0b2c1e-0000-4000-8000-000000000001",
                       "a final opens its team's page")
        XCTAssertNil(HelloItem.Final(final([23, 33], mine: 1))?.teamPage, "a team from away has none")
        let first = HelloItem(what: .moment(.firstEvent), at: Date())
        XCTAssertNil(first.message, "drawn with its tick")
        XCTAssertEqual(first.row().name, "You")
        XCTAssertEqual(first.row().words, "attended your first event!")
        XCTAssertEqual(first.row().picture, .tick)
        XCTAssertNil(HelloItem.Final(final([1, 0], mine: 5)), "a final with no side of yours isn't kept")
    }

    // MARK: A followed team's final (hello-drop 03)

    private func final(_ score: [Int], mine: Int, colors: [String]? = ["#BC0E33", "#02A2E2"]) -> TeamFinal {
        let colorsJSON = colors.map { "[" + $0.map { "\"\($0)\"" }.joined(separator: ",") + "]" } ?? "null"
        let json = """
        {"event_id": "e1", "mine": \(mine), "game": {"sport": "Football", "occasion": null, "final": [\(score[0]), \(score[1])],
          "teams": [{"name": "Saint John's", "short": "Saint John's", "logo": "https://x/sju.png", "color": "#C20430",
                     "id": "4f0b2c1e-0000-4000-8000-000000000001", "local": true, "colors": \(colorsJSON)},
                    {"name": "Gustavus Adolphus", "short": "Gustavus", "logo": null, "color": null, "local": false}]}}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try! decoder.decode(TeamFinal.self, from: Data(json.utf8))
    }

    func testYourTeamsScoreComesFirst() {
        XCTAssertEqual(final([33, 23], mine: 0).text, "Saint John's beat Gustavus 33–23")
        XCTAssertEqual(TeamFinal.sample(won: true).text, "Johnnies beat Gusties 33–23")
        XCTAssertEqual(final([33, 23], mine: 1).text, "Gustavus lost to Saint John's 23–33")
        XCTAssertEqual(final([7, 7], mine: 0).text, "Saint John's tied Gustavus 7–7")
    }

    /// A win takes the team's logo colours, the pill the first and the confetti all; a loss neither.
    func testAWinTakesTheTeamsColours() {
        let win = HelloDrop.final(final([33, 23], mine: 0))
        XCTAssertEqual(win?.tint, 0xBC0E33)
        XCTAssertEqual(win?.confetti, [0xBC0E33, 0x02A2E2])
        XCTAssertNotNil(win?.logo)
        let loss = HelloDrop.final(final([23, 33], mine: 0))
        XCTAssertNil(loss?.tint)
        XCTAssertNil(loss?.confetti)
        // No logo colours yet: its one colour.
        XCTAssertEqual(HelloDrop.final(final([33, 23], mine: 0, colors: nil))?.tint, 0xC20430)
    }

    func testTheTeamsPageIsOnlyForLocalTeams() {
        let game = final([1, 0], mine: 0).game
        XCTAssertTrue(game.teams[0].hasPage)
        XCTAssertFalse(game.teams[1].hasPage)
    }

    /// Cathedral's gold takes ink words; Saint John's red takes white.
    func testLightTintsTakeInk() {
        XCTAssertTrue(HelloDrop.light(0xFEE291))
        XCTAssertFalse(HelloDrop.light(0xBC0E33))
    }

    // MARK: Town news (hello-drop 03)

    private func post(_ id: String, published: String) -> TownNews {
        TownNews(id: id, place: "Sal's", words: "Meat raffle moved to Saturday", post: URL(string: "https://instagram.com/p/x")!,
                 leavesAt: town("2026-10-30 00:00"), published: town(published))
    }

    /// The feed's first post newer than your last open; one you saw before stays quiet.
    func testTownNewsSinceYourLastOpen() {
        let old = post("old", published: "2026-10-20 09:00")
        let new = post("new", published: "2026-10-21 07:00")
        XCTAssertEqual(message("2026-10-21 09:00", lastSeen: "2026-10-20 20:00", news: [old, new]),
                       "Sal's: Meat raffle moved to Saturday")
        // With the place's picture beside them, the words stand alone.
        var pictured = new
        pictured.picture = PlacePicture(url: URL(string: "https://x/sals.png")!, kind: .logo)
        XCTAssertEqual(message("2026-10-21 09:00", lastSeen: "2026-10-20 20:00", news: [pictured]),
                       "Meat raffle moved to Saturday")
        XCTAssertNotEqual(message("2026-10-21 09:00", lastSeen: "2026-10-21 08:00", news: [old, new]),
                          "Sal's: Meat raffle moved to Saturday")
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

    // MARK: A contact who joined (hello-drop 04)

    private func person(_ id: String, _ name: String, since: String?, _ relation: Neighbor.Relation = .stranger,
                        photo: String? = nil) -> Neighbor {
        Neighbor(userId: id, displayName: name, avatarUrl: photo, since: since, relation: relation, mutualFriends: 0)
    }

    /// After your own events and friends going, ahead of the town's news and counts.
    func testAContactWhoJoinedComesAfterYourOwnDay() {
        let sam = person("1", "Sam Rivera", since: "2026-10-21T01:00:00Z")
        let news = [post("new", published: "2026-10-21 07:00")]
        XCTAssertEqual(message("2026-10-21 09:00", lastSeen: "2026-10-20 20:00", news: news, joined: sam),
                       "Sam joined Block Party")
        XCTAssertEqual(message("2026-10-21 09:00", going: [event("Farmers Market", "2026-10-22", "8 AM")], joined: sam),
                       "Farmers Market is tomorrow")
        let said = HelloDrop.joined(person("1", "Sam Rivera", since: nil, photo: "https://x/sam.jpg"))
        XCTAssertEqual(said.target, .person(person("1", "Sam Rivera", since: nil, photo: "https://x/sam.jpg")))
        XCTAssertEqual(said.logo, URL(string: "https://x/sam.jpg"))
        XCTAssertTrue(said.photo, "their photo, round")
        XCTAssertNil(HelloDrop.joined(sam).logo, "no photo: the words alone")
    }

    /// Only someone you could still add, who joined after the cut-off, newest first.
    func testOnlyNewcomersYouCouldAddAreNamed() {
        let since = ISO8601DateFormatter().date(from: "2026-10-20T00:00:00Z")!
        let people = [
            person("old", "Old", since: "2026-10-19T12:00:00Z"),
            person("sam", "Sam", since: "2026-10-20T10:00:00Z"),
            person("kate", "Kate", since: "2026-10-21T10:00:00.123+00:00"),
            person("friend", "Fred", since: "2026-10-21T11:00:00Z", .friends),
            person("blocked", "Bo", since: "2026-10-21T11:00:00Z", .blocked),
            person("asked", "Al", since: "2026-10-21T11:00:00Z", .sent),
            person("odd", "Odd", since: "not a date"),
            person("blank", " ", since: "2026-10-21T11:00:00Z"),
        ]
        XCTAssertEqual(ContactsMatch.newcomers(people, since: since).map(\.userId), ["kate", "sam"])
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
