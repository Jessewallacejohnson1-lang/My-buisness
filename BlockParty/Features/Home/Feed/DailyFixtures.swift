//
//  DailyFixtures.swift
//  Block Party — invented content for the Daily feed while there is no backend.
//
//  INVENTED, not real. Names, captions and events here are made up; only the town
//  is real (St. Joseph, Minnesota — Millstream Park, Saint Ben's, Saint John's
//  Abbey, the Lake Wobegon Trail), so string lengths and place names wrap the way
//  the shipped feed will.
//
//  The spread is the point. Every row below is chosen to break a different piece of
//  layout: a caption that runs past two lines, a caption of one word, none at all;
//  a missing avatar; a missing photo; counts at 0, at 4 and at 312 so the monospaced
//  tally changes width; a stranger with heavy social proof sitting beside a friend
//  with none; and an event in each of the three time buckets the ranker cares about.
//

#if DEBUG
import Foundation

enum DailyFixtures {
    /// Everything, unranked and in no meaningful order — `DailyRanker` does the
    /// sorting, and handing it a tidy list would hide whether it works.
    static func all(now: Date = Date()) -> [DailyFeedItem] {
        postings(now: now).map { .posting($0) } + events(now: now)
    }

    /// How many neighbours "you" follow. The denominator for social proof.
    private static let followedCount = 24

    // MARK: - Postings

    static func postings(now: Date = Date()) -> [PostingItem] {
        [
            posting(
                id: "p1", author: "Marlene Ostendorf", avatar: true,
                hoursAgo: 2, photo: true,
                caption: "Somebody left a very good dog tied up outside the co-op for about twenty minutes this morning and I want everyone to know he handled it with more grace than I would have.",
                likes: 41, comments: 12, followed: true, friend: true,
                followedLikers: 9, now: now
            ),
            posting(
                id: "p2", author: "Dale Brunner", avatar: true,
                hoursAgo: 5, photo: true,
                caption: "Ice out on the pond.",
                likes: 312, comments: 48, followed: false, friend: false,
                followedLikers: 21, now: now
            ),
            posting(
                id: "p3", author: "Kesia Vue", avatar: false,
                hoursAgo: 1, photo: true,
                caption: "",
                likes: 0, comments: 0, followed: false, friend: false,
                followedLikers: 0, now: now
            ),
            posting(
                id: "p4", author: "Fr. Thomas Ryan", avatar: true,
                hoursAgo: 9, photo: false,
                caption: "Bells are back. The tower crew finished Thursday and you can hear them from the trailhead again.",
                likes: 88, comments: 7, followed: true, friend: false,
                followedLikers: 14, now: now
            ),
            posting(
                id: "p5", author: "Annika Sørensen", avatar: true,
                hoursAgo: 26, photo: true,
                caption: "Three years in St. Joe today. Thank you for the casseroles, the jumper cables, the plow at 6am, and for telling me which road floods.",
                likes: 156, comments: 31, followed: true, friend: true,
                followedLikers: 18, now: now
            ),
            posting(
                id: "p6", author: "Marcus Whitefeather", avatar: false,
                hoursAgo: 4, photo: true,
                caption: "Anybody know whose gray cat keeps sitting on the hood of my truck? He is welcome. I would just like to know his name.",
                likes: 4, comments: 2, followed: false, friend: false,
                followedLikers: 1, now: now
            ),
            posting(
                id: "p7", author: "Bea Lindgren", avatar: true,
                hoursAgo: 73, photo: true,
                caption: "Rhubarb.",
                likes: 22, comments: 5, followed: true, friend: false,
                followedLikers: 0, now: now
            ),
            posting(
                id: "p8", author: "Owen Delacroix-Martinez", avatar: true,
                hoursAgo: 14, photo: false,
                caption: "Reminder that the county recycling trailer is at the fairgrounds lot until Sunday and they take paint, batteries, and the bin of electronics you have been carrying between apartments since 2019.",
                likes: 63, comments: 9, followed: false, friend: false,
                followedLikers: 2, now: now
            ),
            posting(
                id: "p9", author: "Junie Okonkwo", avatar: true,
                hoursAgo: 0, photo: true,
                caption: "first tomato",
                likes: 7, comments: 1, followed: true, friend: true,
                followedLikers: 3, now: now
            ),
            posting(
                id: "p10", author: "Hal Pedersen", avatar: false,
                hoursAgo: 190, photo: true,
                caption: "Found a wallet on the Wobegon between the trestle and the gravel crossing. Describe it and it is yours.",
                likes: 94, comments: 16, followed: false, friend: false,
                followedLikers: 11, now: now
            ),
        ]
    }

    // MARK: - Events

    static func events(now: Date = Date()) -> [DailyFeedItem] {
        [
            event(
                id: "e1", title: "Music in Millstream Park",
                host: "St. Joseph Parks & Rec", hostAvatar: true,
                chip: "TONIGHT", meta: "7pm · Millstream Park",
                photo: true, hoursUntil: 6, postedHoursAgo: 8, going: 41,
                followed: true, friend: false, followedLikers: 12, now: now
            ),
            event(
                id: "e2", title: "Farmers Market",
                host: "Resurrection Lutheran", hostAvatar: true,
                chip: "SAT", meta: "8am · Resurrection Lutheran",
                photo: true, hoursUntil: 40, postedHoursAgo: 30, going: 128,
                followed: true, friend: false, followedLikers: 6, now: now
            ),
            event(
                id: "e3", title: "Trail cleanup morning",
                host: "Wobegon Trail Association", hostAvatar: false,
                chip: "SUN", meta: "9am · Lake Wobegon Trailhead",
                photo: false, hoursUntil: 64, postedHoursAgo: 52, going: 12,
                followed: false, friend: false, followedLikers: 0, now: now
            ),
            event(
                id: "e4", title: "Abbey organ recital",
                host: "Saint John's Abbey", hostAvatar: true,
                chip: "NEXT MONTH", meta: "4pm · Saint John's Abbey",
                photo: true, hoursUntil: 24 * 27, postedHoursAgo: 96, going: 63,
                followed: true, friend: false, followedLikers: 4, now: now
            ),
            event(
                id: "e5", title: "City Council — regular meeting",
                host: "City of St. Joseph", hostAvatar: false,
                chip: "TUE", meta: "6pm · City Hall",
                photo: false, hoursUntil: 20, postedHoursAgo: 12, going: 3,
                followed: false, friend: false, followedLikers: 0, now: now
            ),
            event(
                id: "e6", title: "Saint Ben's spring choral concert",
                host: "College of Saint Benedict", hostAvatar: true,
                chip: "FINISHED", meta: "7pm · Sacred Heart Chapel",
                photo: true, hoursUntil: -30, postedHoursAgo: 120, going: 210,
                followed: true, friend: true, followedLikers: 20, now: now
            ),
        ]
    }

    // MARK: - Builders

    private static func posting(
        id: String, author: String, avatar: Bool, hoursAgo: Double, photo: Bool,
        caption: String, likes: Int, comments: Int,
        followed: Bool, friend: Bool, followedLikers: Int, now: Date
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
            isSaved: false,
            signals: FeedSignals(
                isFollowed: followed,
                isFriend: friend,
                followedLikerCount: followedLikers,
                followedCount: followedCount,
                saveCount: likes / 8
            )
        )
    }

    private static func event(
        id: String, title: String, host: String, hostAvatar: Bool,
        chip: String, meta: String, photo: Bool,
        hoursUntil: Double, postedHoursAgo: Double, going: Int,
        followed: Bool, friend: Bool, followedLikers: Int, now: Date
    ) -> DailyFeedItem {
        let item = FeedCardItem(
            id: id,
            title: title,
            dateChip: chip,
            metaLine: meta,
            image: photo ? Self.photoURL(id) : .fallback,
            recurrence: nil,
            hostName: host,
            hostAvatar: hostAvatar ? Self.avatarURL(id) : nil,
            goingCount: going,
            goingAvatars: [],
            goingSummary: going == 1 ? "1 neighbor is going" : "\(going) neighbors are going",
            likeCount: 0,
            isLiked: false,
            isSaved: false,
            isJoined: false
        )
        // Stated, not derived from the start time. Deriving it put every event more
        // than a day out in the FUTURE, which pinned its recency term at the maximum
        // and let next month's recital rank like it was posted this second.
        let signals = FeedSignals(
            isFollowed: followed,
            isFriend: friend,
            followedLikerCount: followedLikers,
            followedCount: followedCount,
            saveCount: going / 10,
            createdAt: now.addingTimeInterval(-postedHoursAgo * 3600),
            likeCount: going,
            startsAt: now.addingTimeInterval(hoursUntil * 3600)
        )
        return .event(item, signals: signals)
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

    private static func photoURL(_ seed: String) -> FeedCardImageSource {
        // "p7" / "e3" → 7 / 3. Stable, readable, and a missing suffix lands on 0.
        // Events start halfway down the list so a posting and an event never open
        // the feed showing the same photograph.
        let index = (Int(seed.dropFirst()) ?? 0) + (seed.hasPrefix("e") ? 6 : 0)
        let name = photoNames[index % photoNames.count]
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg") else {
            return .fallback
        }
        return .eventPhoto(url)
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
