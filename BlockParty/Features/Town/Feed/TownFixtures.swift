//
//  TownFixtures.swift
//  Block Party — invented content for the Town feed while there is no backend.
//
//  INVENTED, not real. Names, captions and events here are made up; only the town
//  is real (St. Joseph, Minnesota — Millstream Park, Saint Ben's, Saint John's
//  Abbey, the Lake Wobegon Trail), so string lengths and place names wrap the way
//  the shipped feed will.
//
//  The spread is the point. Every row below is chosen to break a different piece of
//  layout: a caption that runs past two lines, a caption of one word, none at all;
//  a missing avatar; a missing photo; counts at 0, at 4 and at 312 so the monospaced
//  tally changes width; events from tonight to next month, and one already over.
//

#if DEBUG
import CoreLocation
import Foundation

enum TownFixtures {
    /// Everything: the postings, then the events still on.
    static func all(now: Date = Date()) -> [TownFeedItem] {
        postings(now: now).map { .posting($0) } + events(now: now)
    }

    // MARK: - Postings

    static func postings(now: Date = Date()) -> [PostingItem] {
        [
            posting(
                id: "p1", author: "Marlene Ostendorf", avatar: true,
                hoursAgo: 2, photo: true,
                caption: "Somebody left a very good dog tied up outside the co-op for about twenty minutes this morning and I want everyone to know he handled it with more grace than I would have.",
                likes: 41, comments: 12, followed: true, now: now
            ),
            posting(
                id: "p2", author: "Dale Brunner", avatar: true,
                hoursAgo: 5, photo: true,
                caption: "Ice out on the pond.",
                likes: 312, comments: 48, followed: false, now: now
            ),
            posting(
                id: "p3", author: "Kesia Vue", avatar: false,
                hoursAgo: 1, photo: true,
                caption: "",
                likes: 0, comments: 0, followed: false, now: now
            ),
            posting(
                id: "p4", author: "Fr. Thomas Ryan", avatar: true,
                hoursAgo: 9, photo: false,
                caption: "Bells are back. The tower crew finished Thursday and you can hear them from the trailhead again.",
                likes: 88, comments: 7, followed: true, now: now
            ),
            posting(
                id: "p5", author: "Annika Sørensen", avatar: true,
                hoursAgo: 26, photo: true,
                caption: "Three years in St. Joe today. Thank you for the casseroles, the jumper cables, the plow at 6am, and for telling me which road floods.",
                likes: 156, comments: 31, followed: true, now: now
            ),
            posting(
                id: "p6", author: "Marcus Whitefeather", avatar: false,
                hoursAgo: 4, photo: true,
                caption: "Anybody know whose gray cat keeps sitting on the hood of my truck? He is welcome. I would just like to know his name.",
                likes: 4, comments: 2, followed: false, now: now
            ),
            posting(
                id: "p7", author: "Bea Lindgren", avatar: true,
                hoursAgo: 73, photo: true,
                caption: "Rhubarb.",
                likes: 22, comments: 5, followed: true, now: now
            ),
            posting(
                id: "p8", author: "Owen Delacroix-Martinez", avatar: true,
                hoursAgo: 14, photo: false,
                caption: "Reminder that the county recycling trailer is at the fairgrounds lot until Sunday and they take paint, batteries, and the bin of electronics you have been carrying between apartments since 2019.",
                likes: 63, comments: 9, followed: false, now: now
            ),
            posting(
                id: "p9", author: "Junie Okonkwo", avatar: true,
                hoursAgo: 0, photo: true,
                caption: "first tomato",
                likes: 7, comments: 1, followed: true, now: now
            ),
            posting(
                id: "p10", author: "Hal Pedersen", avatar: false,
                hoursAgo: 190, photo: true,
                caption: "Found a wallet on the Wobegon between the trestle and the gravel crossing. Describe it and it is yours.",
                likes: 94, comments: 16, followed: false, now: now
            ),
        ]
    }

    // MARK: - Events

    /// The sample events still on, as feed items (`-town-feed-preview`).
    static func events(now: Date = Date()) -> [TownFeedItem] {
        townEntries(now: now).filter { $0.leavesAt > now }.compactMap { $0.card.map(TownFeedItem.event) }
    }

    /// The sample events as the Town feed gets them (`-town-samples`): soonest first,
    /// as `get_town_feed` sends them, each leaving two hours after it starts, as one
    /// with no end time does.
    static func townEntries(now: Date = Date()) -> [TownFeedEntry] {
        let games = LaunchFlags.has(.townGames) ? gameSamples(now: now) : []
        var events = games + sampleEvents(now: now).sorted { $0.leavesAt < $1.leavesAt }
        // `-town-posts`: two neighbours' posts among the events (town-feed 29), a photo one second.
        if LaunchFlags.has(.townPosts) { events.insert(contentsOf: postSamples(now: now), at: min(1, events.count)) }
        guard LaunchFlags.has(.townNews) else { return events }
        // `-town-news`: tonight's social watch posts as the feed places them (town-feed 35): one that
        // shares your interests among the events, the rest after the last one. Logos read from Storage.
        let news = newsSamples(now: now)
        return Array(events.prefix(2)) + news.prefix(1) + events.dropFirst(2) + news.dropFirst()
    }

    /// Two invented neighbours' posts (town-feed 29): a photo with words, and words alone, tagged. The Block
    /// Party tab's Following samples take them too (daily-tab 23).
    static func postSamples(now: Date) -> [TownFeedEntry] {
        let photo = Bundle.main.url(forResource: "downtown", withExtension: "jpg")
        let posts = [
            TownPost(id: "sample-post-1", poster: .init(id: "sample:Marlene Ostendorf", name: "Marlene Ostendorf"),
                     posterPhoto: avatarURL("p1"), words: "Downtown was packed tonight. Thanks to everyone who came out!",
                     photo: photo, aspect: 4.0 / 3.0, posted: now.addingTimeInterval(-2 * 3600),
                     leavesAt: now.addingTimeInterval(5 * 86_400), heartCount: 12),
            TownPost(id: "sample-post-2", poster: .init(id: "sample:Sam Rivera", name: "Sam Rivera"),
                     words: "Anyone up for sledding after school? The big hill by the river is packed down and fast after last night. Bring a sled, a thermos and dry socks. We will be there from 3:30 until it gets dark, and the porch on Minnesota Street is open for hot chocolate after. Kids of all ages welcome, parents too. Text me if you need a ride.",
                     place: "Millstream Park",
                     tagged: [.init(id: "sample:Ana Nguyen", name: "Ana Nguyen")], friendsOnly: true,
                     posted: now.addingTimeInterval(-40 * 60), leavesAt: now.addingTimeInterval(6 * 86_400)),
        ]
        return posts.map { TownFeedEntry(item: .post($0), leavesAt: $0.leavesAt) }
    }

    /// The places' saved logos in Storage, read from the network.
    private static let logos = "https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/"

    /// JoeTown's new merch with its post's own photo, as the photo step saved it (town-feed 53), first; the rest the
    /// white card, The Wandering Cow's sharing your interests.
    static func newsSamples(now: Date) -> [TownFeedEntry] {
        let samples: [(String, String, String, String, String?)] = [
            ("JoeTown", "New Joetown merch",
             "Fresh Joetown tees, sweatshirts, winter caps and baseball hats are for sale at Minnesota Street Market and The House Food & Tap.",
             "https://www.instagram.com/p/Dfde7-gjf99/", nil),
            ("The Wandering Cow", "Flight Friday", "Four scoops for $5 at Wandering Cow on Fridays.",
             "https://www.instagram.com/p/Deki5CwgiQG/", "ChIJFfdMxRVZtFIR77H-NqLzUTc/logo-7225f2ed.webp"),
            ("City of St. Joseph", "Life Saving Awards", "St. Joseph police, fire and Mayo Ambulance members received Life Saving Awards at the Oct 19 council meeting.",
             "https://www.facebook.com/CityofStJosephMN/", "city-of-st-joseph/logo-009e4537f4.webp"),
            ("White Peony Boutique", "Layer Up drop tonight", "White Peony's Layer Up collection of fall jackets and layers goes on sale tonight at 7 PM, in store and online.",
             "https://www.instagram.com/p/DezQTPEjSr0/", "stjoe-white-peony-boutique/logo-65fd9c1b.webp"),
            ("Neighbors Route 75", "Taco Tuesday", "Taco Tuesday at Neighbors Route 75, with a drink purchase, dine in only.",
             "https://www.facebook.com/NeighborsEateryandSaloon/", "ChIJz-W_cL1ZtFIRnuug5NtJwqA/logo-ffdc8eb9.webp"),
            ("Stearns County", "Early voting opens", "Early voting locations open Friday, October 16, with extended hours before Election Day.",
             "https://www.stearnscountymn.gov/", nil),
        ]
        return samples.enumerated().map { i, s in
            let news = TownNews(id: "n\(i + 1)", place: s.0, words: s.2, post: URL(string: s.3)!,
                                picture: s.4.flatMap { URL(string: logos + $0) }.map { PlacePicture(url: $0, kind: .logo) },
                                leavesAt: now.addingTimeInterval(7 * 86_400),
                                published: now.addingTimeInterval(-Double(i * 22 + 2) * 3600), title: s.1,
                                interest: i == 1 ? "dining" : nil,
                                // You hearted The Wandering Cow's (inside-cards 22): red on its card and in Liked.
                                hearted: i == 1, heartCount: i == 1 ? 1 : 0,
                                photo: i == 0 ? URL(string: logos + "news/news-866b1517a3.webp") : nil,
                                photoAspect: i == 0 ? 720.0 / 960.0 : nil)
            return TownFeedEntry(item: .news(news), leavesAt: news.leavesAt)
        }
    }

    /// `-town-games`: four games first, as `get_town_feed` sends them (game-card 02): SJU vs
    /// Gustavus to come, the ticket's real finals SJU 33-23 Concordia and Sartell 6-0 Sauk
    /// Rapids-Rice, and Sartell's 2-2 tie with Anoka, with the schools' saved logos and colors
    /// (`Resources/Fixtures/town-games.json`: their colors are data, as the feed's are). With
    /// `-town-volleyball`, CSB vs Carleton's volleyball takes SJU vs Gustavus's place, with `-town-soccer`
    /// SJU vs Augsburg's soccer, with `-town-basketball` CSB vs Loras's basketball, with `-town-hockey` SJU vs St. Olaf's
    /// hockey (game-card 09), and with `-town-shootout` Saint Ben's 1-1 Macalester, won 5-4 on penalties (game-card 15).
    private static func gameSamples(now: Date) -> [TownFeedEntry] {
        struct Sample: Decodable {
            let id, title, host, place, day: String
            let time: String?
            let hoursUntil: Double
            let went: Int
            let game: Game
        }
        guard let url = Bundle.main.url(forResource: "town-games", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let all = try? JSONDecoder().decode([Sample].self, from: data) else { return [] }
        let first = LaunchFlags.has(.townVolleyball) ? "v1" : LaunchFlags.has(.townSoccer) ? "s1"
            : LaunchFlags.has(.townBasketball) ? "b1" : LaunchFlags.has(.townHockey) ? "h1" : LaunchFlags.has(.townShootout) ? "p1"
            : LaunchFlags.has(.townLevel) ? "l1" : "g1"
        let samples = all.filter { !["v1", "s1", "b1", "h1", "g1", "p1", "l1"].contains($0.id) || $0.id == first }
        // `-town-live`: the first game started an hour ago today; TownFeed plays its score (game-card 03).
        let live = LaunchFlags.has(.townLive)
        let today = Self.townClock("yyyy-MM-dd", now)
        return samples.enumerated().map { i, g in
            let started = live && i == 0
            let entry = event(id: g.id, title: g.title, host: g.host, hostAvatar: false, chip: "", meta: g.place,
                              photo: false, hoursUntil: started ? -1 : g.hoursUntil, going: g.went, now: now)
            guard var card = entry.card else { return entry }
            card.eventDate = started ? today : g.day
            card.startTime = started ? Self.townClock("h:mm a", now.addingTimeInterval(-3600)) : g.time
            card.location = g.place
            // A game replaying starts with no score: `-town-shootout`'s sample is its final.
            card.game = started ? g.game.with(final: nil, live: nil, plays: []) : g.game
            // You's Going lists the game on (`liveGameGoing`): its card says Going too.
            card.isJoined = started
            return TownFeedEntry(card: card, leavesAt: entry.leavesAt)
        }
    }

    /// `-town-live`'s game as You's Going read sends it (BP app codebase-health-2 08): the Town feed's
    /// first game, started an hour ago today, with its teams, so its Event page opens from You too.
    static func liveGameGoing(now: Date) -> UpcomingEvent? {
        guard LaunchFlags.has(.townGames), LaunchFlags.has(.townLive),
              let card = gameSamples(now: now).first?.card, let day = card.eventDate else { return nil }
        var event = UpcomingEvent(id: card.id, title: card.title, eventDate: day, startTime: card.startTime,
                                  location: card.location, goingCount: card.goingCount, createdAt: "", rsvpd: true)
        event.game = card.game
        return event
    }

    /// A date in St. Joseph's time, as the feed writes it ("2026-10-31", "1:05 PM").
    private static func townClock(_ format: String, _ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = Town.timeZone
        f.dateFormat = format
        return f.string(from: date)
    }

    private static func sampleEvents(now: Date) -> [TownFeedEntry] {
        [
            event(
                id: "e1", title: "Music in Millstream Park",
                host: "St. Joseph Parks & Rec", hostAvatar: true,
                chip: "TONIGHT", meta: "7pm · Millstream Park",
                photo: true, hoursUntil: 6, going: 41,
                category: .musicArts,
                // Long on purpose: it runs past the event page's 4-line clamp.
                description: "Bring a blanket or a lawn chair and find a spot on the grass by the river. This week it's a local bluegrass trio playing two sets, with a short break in between so the kids can run around. The lemonade stand will be going, and a food truck or two usually parks by the lot. If it rains, check back here before you head over. Leashed dogs are welcome. Please pack out what you pack in.",
                reason: "interest", reasonName: "live_music",
                // Two of the sample friends (`Neighbor.samples`) Going (town-feed 28).
                friends: [("Sam", "centennial-park"), ("Marlene", "memorial-park")],
                now: now
            ),
            event(
                id: "e2", title: "Farmers Market",
                host: "Resurrection Lutheran", hostAvatar: true,
                chip: "SAT", meta: "8am · Resurrection Lutheran",
                photo: true, hoursUntil: 40, going: 128,
                category: .food,
                description: "Produce, eggs, honey and bread in the church parking lot.",
                friends: [("Dale", nil)],
                // A photo Block Party saved of the place, so its credit and Report photo show
                // on fixed data (BP app backlog 03).
                credit: "Resurrection Lutheran",
                now: now
            ),
            event(
                id: "e3", title: "Trail cleanup morning",
                host: "Wobegon Trail Association", hostAvatar: false,
                chip: "SUN", meta: "9am · Lake Wobegon Trailhead",
                photo: false, hoursUntil: 64, going: 12,
                category: .service,
                description: "Meet at the trailhead. We'll have gloves, bags, grabbers and coffee. Wear shoes you don't mind getting muddy.",
                // The longest age, so the white card's time line shows it whole on fixed data (inside-cards 30).
                ages: "Ages 12 and under",
                now: now
            ),
            event(
                id: "e4", title: "Abbey organ recital",
                host: "Saint John's Abbey", hostAvatar: true,
                chip: "NEXT MONTH", meta: "4pm · Saint John's Abbey",
                photo: true, hoursUntil: 24 * 27, going: 63,
                category: .musicArts,
                description: "An hour of Bach and a few newer pieces on the Abbey church organ. Open to everyone.",
                // A price, so the Event page's price line shows on fixed data (inside-cards 14).
                price: "Free, donations welcome",
                now: now
            ),
            // No description and no category (none fits a council meeting), so the
            // event page's About and category rows hide. Nobody going yet, so its card
            // shows RSVP alone (rsvp-and-groups 01). No photo, only the City's logo: the short
            // white card (BP app references/no-photo-cards), as e3 is with no logo at all.
            event(
                id: "e5", title: "City Council — regular meeting",
                host: "City of St. Joseph", hostAvatar: false,
                chip: "TUE", meta: "6pm · City Hall",
                photo: false, hoursUntil: 20, going: 0,
                logo: "city-of-st-joseph/logo-009e4537f4.webp",
                now: now
            ),
            event(
                id: "e6", title: "Saint Ben's spring choral concert",
                host: "College of Saint Benedict", hostAvatar: true,
                chip: "FINISHED", meta: "7pm · Sacred Heart Chapel",
                photo: true, hoursUntil: -30, going: 210,
                category: .musicArts,
                description: "The college choirs sing their spring program in Sacred Heart Chapel.",
                now: now
            ),
            // A long title on purpose: three lines and more at the event page's
            // title size, the way a real listing written out in full wraps.
            event(
                id: "e7", title: "Fire Department pancake breakfast and open house at the St. Joseph fire hall",
                host: "St. Joseph Fire Department", hostAvatar: false,
                chip: "SAT", meta: "7am · St. Joseph Fire Hall",
                photo: true, hoursUntil: 44, going: 57,
                category: .food,
                description: "Pancakes, sausage and coffee, then a look inside the trucks. Free will offering.",
                now: now
            ),
        ]
    }

    /// `-town-spots`: where the samples are on the map (inside-cards 19), off the places table: the park concert today,
    /// the market in two days, the organ recital next week, the trail cleanup at Sauk Centre's trailhead 50 km out, the
    /// choral concert that's over; the council meeting Online, at no one place; the pancake breakfast with no spot yet.
    static let spots: [String: EventSpot] = [
        "e1": .at(CLLocationCoordinate2D(latitude: 45.57007, longitude: -94.32874)),   // Millstream Park
        "e2": .at(CLLocationCoordinate2D(latitude: 45.57133, longitude: -94.31736)),   // Resurrection Lutheran
        "e3": .at(CLLocationCoordinate2D(latitude: 45.73690, longitude: -94.95190)),   // Lake Wobegon Trail, Sauk Centre
        "e4": .at(CLLocationCoordinate2D(latitude: 45.58003, longitude: -94.39229)),   // Saint John's Abbey
        "e5": .noPlace,
        "e6": .at(CLLocationCoordinate2D(latitude: 45.56060, longitude: -94.31950)),   // Sacred Heart Chapel
    ]

    // MARK: - Builders

    private static func posting(
        id: String, author: String, avatar: Bool, hoursAgo: Double, photo: Bool,
        caption: String, likes: Int, comments: Int,
        followed: Bool, now: Date
    ) -> PostingItem {
        PostingItem(
            id: id,
            authorName: author,
            authorAvatar: avatar ? Self.avatarURL(id) : nil,
            createdAt: now.addingTimeInterval(-hoursAgo * 3600),
            image: photo ? Self.photoURL(id) : .fallback,
            caption: caption,
            likeCount: likes,
            commentCount: comments,
            isLiked: false,
            isFollowed: followed
        )
    }

    /// What each sample is, as the morning tagger writes it (event-card 05). Most titles here already
    /// say it, so only the park concert's and the trail cleanup's cards show theirs.
    private static let whats = ["e1": "Concert", "e2": "Market", "e3": "Volunteer day", "e4": "Recital",
                                "e5": "Council meeting", "e6": "Concert", "e7": "Pancake breakfast"]

    private static func event(
        id: String, title: String, host: String, hostAvatar: Bool,
        chip: String, meta: String, photo: Bool,
        hoursUntil: Double, going: Int,
        category: EventCategory? = nil, description: String? = nil, price: String? = nil, ages: String? = nil,
        reason: String? = nil, reasonName: String? = nil,
        friends: [(name: String, photo: String?)] = [], credit: String? = nil,
        logo: String? = nil,
        now: Date
    ) -> TownFeedEntry {
        let placeLogo = logo.flatMap { URL(string: Self.logos + $0) }
            .map { FeedCardImageSource.placeLogo(PlacePicture(url: $0, kind: .logo, hue: 35)) }
        var item = FeedCardItem(
            id: id,
            title: title,
            dateChip: chip,
            metaLine: meta,
            // `-town-photo <url>`: the first card wears that photo, for a pale or busy one no sample has
            // (BP app inside-cards 26: the time under the title on Nov 6's pale gallery photo).
            image: (id == "e1" ? Self.wholeFlyer ?? Self.townPhoto : nil) ?? (photo ? Self.photoURL(id, credit: credit) : placeLogo ?? .fallback),
            recurrence: nil,
            hostName: host,
            hostAvatar: hostAvatar ? Self.avatarURL(id) : nil,
            goingCount: going,
            goingAvatars: [],
            likeCount: 0,
            isLiked: false,
            isJoined: false,
            // `-town-no-about`: no sample has an About, for a short Event page (inside-cards 19's small map, review).
            description: LaunchFlags.has(.townNoAbout) ? nil : description,
            price: price,
            ages: ages,
            category: category
        )
        // Why each is in the feed, as `get_town_feed` would say it by default: the day.
        let day = reason ?? (hoursUntil < 18 ? "today" : hoursUntil < 42 ? "tomorrow" : "soon")
        item.why = FeedCardMenu.line(reason: day, name: reasonName)
        item.what = whats[id]
        item.whole = id == "e1" && Self.wholeFlyer != nil
        item.friendsGoing = friends.map { friend in
            FeedFriend(name: friend.name,
                       photo: friend.photo.flatMap { Bundle.main.url(forResource: $0, withExtension: "jpg") })
        }
        // `-town-cancelled`: the first card and the photo-less council meeting are called
        // off, for the red Canceled pill on a card and an Event page with a photo and with none.
        item.cancelled = ["e1", "e5"].contains(id) && LaunchFlags.has(.townCancelled)
        // `-town-now`: the same two started an hour ago, so a photo card and a white card both say Now
        // under their titles (BP app inside-cards 26).
        if ["e1", "e5"].contains(id), LaunchFlags.has(.townNow) {
            let start = now.addingTimeInterval(-3600)
            // Its place first: with a start time of its own the meta line no longer gives it.
            item.location = item.whereLine
            item.eventDate = townClock("yyyy-MM-dd", start)
            item.startTime = townClock("h:mm a", start)
        }
        // `-town-spots`: each sample on its own day with its place line, the organ recital next week and the council
        // meeting Online, so the map and the Event page's small map show them (inside-cards 19). Their spots: `spots`,
        // on the card as the server's card carries them.
        if LaunchFlags.has(.townSpots), item.eventDate == nil {
            item.spot = spots[id]
            item.location = id == "e5" ? "Online" : item.whereLine
            item.startTime = item.shareTime
            item.eventDate = townClock("yyyy-MM-dd", now.addingTimeInterval((id == "e4" ? 24 * 7 : hoursUntil) * 3600))
        }
        // `-town-collab`: the first card is The House Food and Tap's, made with Milk & Honey Ciders (town-feed 58), both
        // places' real ids and saved logos, so the card's two marks, its menu and the Event page's two hosts show.
        if id == "e1" && LaunchFlags.has(.townCollab) {
            item.hostName = "The House Food and Tap"
            item.hostAvatar = nil
            item.hostPicture = URL(string: Self.logos + "ChIJy9h63EtZtFIRYVJtkqYK2zQ/logo-8c6a222a.webp")
                .map { PlacePicture(url: $0, kind: .logo) }
            item.collabs = [EventCollab(id: "796f4577-dd1a-49f6-aac5-49d3f8632ecb", entryId: "milk-and-honey-ciders",
                                        name: "Milk & Honey Ciders",
                                        picture: URL(string: Self.logos + "stjoe-milk-honey-ciders/logo-5d9d05fa.webp")
                                            .map { PlacePicture(url: $0, kind: .logo) })]
        }
        // `-town-group`: the first card is the St. Joe Rod and Gun Club's, the real group's id, so
        // its Join and the club's Group page in Search are one (rsvp-and-groups 07).
        if id == "e1" && LaunchFlags.has(.townGroup) {
            item.hostName = "St. Joe Rod and Gun Club"
            item.hostAvatar = nil
            item.groupID = "2e8db1f0-2090-407d-885f-b9fb7e8e01b4"
        }
        return TownFeedEntry(card: item, leavesAt: now.addingTimeInterval((hoursUntil + 2) * 3600))
    }

    /// Real bundled photos of the real town, so the fixtures render with no network
    /// at all. The loader downsamples a file URL the same way it does a remote one.
    ///
    /// Assigned by a stable index, NOT `hashValue` — Swift seeds string hashing per
    /// process, so a hash-picked photo would change between launches and every
    /// screenshot comparison would be noise.
    private static let photoNames = [
        "downtown", "wobegon-trail", "sacred-heart-chapel", "saint-johns-abbey",
        "memorial-park", "farmers-market", "saint-bens", "the-local-blend",
        "millstream-arts-festival", "centennial-park", "bad-habit-brewing",
        "rivers-bend-park",
    ]

    /// `-whole-flyer <url>#<width over height>`: the first card wears that flyer whole (BP app town-feed 57), as
    /// the Block Party tab's samples do; square with no shape after the #.
    static var wholeFlyer: FeedCardImageSource? {
        LaunchFlags.value(.wholeFlyer).flatMap { URL(string: $0) }
            .map { .placePhoto($0, credit: nil, aspect: $0.fragment.flatMap(Double.init)) }
    }

    /// `-town-photo <url>`'s photo, as the Event's own.
    static var townPhoto: FeedCardImageSource? {
        LaunchFlags.value(.townPhoto).flatMap { URL(string: $0) }.map { .eventPhoto($0) }
    }

    /// With a credit, the photo is one Block Party saved of the place, not the event's own.
    private static func photoURL(_ seed: String, credit: String? = nil) -> FeedCardImageSource {
        // "p7" / "e3" → 7 / 3. Stable, readable, and a missing suffix lands on 0.
        // Events start halfway down the list so a posting and an event never open
        // the feed showing the same photograph.
        let index = (Int(seed.dropFirst()) ?? 0) + (seed.hasPrefix("e") ? 6 : 0)
        let name = photoNames[index % photoNames.count]
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg") else {
            return .fallback
        }
        return credit.map { .placePhoto(url, credit: $0) } ?? .eventPhoto(url)
    }

    /// Reuses the same bundled set for faces. There are no portrait assets in the
    /// app and inventing one is not worth a file — what this has to exercise is the
    /// avatar-present branch versus the glyph fallback, and a photo does that.
    private static func avatarURL(_ seed: String) -> URL? {
        let index = Int(seed.dropFirst()) ?? 0
        return Bundle.main.url(
            forResource: photoNames[(index + 5) % photoNames.count],
            withExtension: "jpg"
        )
    }
}
#endif
