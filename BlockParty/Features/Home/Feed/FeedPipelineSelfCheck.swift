#if DEBUG
import Foundation

/// Focused assertions for the pure Phase 4a feed pipeline. Run by the
/// auth-bypassing Today feed preview before it renders.
enum FeedPipelineSelfCheck {
    static func run() {
        recurrenceChecks()
        sectioningChecks()
        mappingChecks()
    }

    private static func recurrenceChecks() {
        let postings = [
            posting("weekly-nearest", title: "  Trail Walk  ", date: "2026-07-24"),
            posting("weekly-second", title: "trail walk", date: "2026-07-31"),
            posting("daily-first", title: "Morning Pages", date: "2026-07-22"),
            posting("daily-second", title: "morning pages", date: "2026-07-23"),
            posting("fortnight-first", title: "Book Club", date: "2026-07-25"),
            posting("fortnight-second", title: "book club", date: "2026-08-08"),
            posting("irregular-first", title: "Town Social", date: "2026-07-23"),
            posting("irregular-second", title: "town social", date: "2026-07-28"),
            posting("single", title: "Potluck", date: "2026-07-26")
        ]

        let result = dedupeRecurring(postings, today: "2026-07-21")
        assert(result.map(\.posting.id) == [
            "weekly-nearest",
            "daily-first",
            "fortnight-first",
            "irregular-first",
            "irregular-second",
            "single"
        ])
        assert(result.first(where: { $0.posting.id == "weekly-nearest" })?.recurrence == "WEEKLY · FRI")
        assert(result.first(where: { $0.posting.id == "daily-first" })?.recurrence == "DAILY")
        assert(result.first(where: { $0.posting.id == "fortnight-first" })?.recurrence == "EVERY OTHER SAT")
        assert(result.first(where: { $0.posting.id == "single" })?.recurrence == nil)
    }

    private static func sectioningChecks() {
        let postings: [FeedRecurringPosting] = [
            (posting("today", title: "Today", date: "2026-07-21", time: "6pm"), nil),
            (posting("day-one", title: "Tomorrow", date: "2026-07-22", time: "8pm"), nil),
            (posting("day-seven", title: "Boundary", date: "2026-07-28", time: "7am"), nil),
            (posting("day-eight", title: "Later", date: "2026-07-29"), nil),
            (posting("undated", title: "Someday", date: nil), nil)
        ]

        let sections = FeedSectioning.sections(for: postings, today: "2026-07-21")
        assert(sections.map(\.kind) == [.today, .thisWeek, .later])
        assert(sections[0].postings.map(\.posting.id) == ["today"])
        assert(sections[1].postings.map(\.posting.id) == ["day-one", "day-seven"])
        assert(sections[2].postings.map(\.posting.id) == ["day-eight", "undated"])
    }

    private static func mappingChecks() {
        var source = posting(
            "mapped",
            title: "Friday Night",
            date: "2026-07-24",
            time: "around 6",
            location: "Memorial Park",
            imageURL: "https://example.com/photo.jpg",
            going: 0
        )
        source.likeCount = 4
        source.liked = true
        source.rsvpd = true

        let item = FeedCardItem(from: source, recurrence: "WEEKLY · FRI")
        assert(item.title == "Friday Night")
        assert(item.dateChip == "FRI JUL 24")
        assert(item.metaLine == "around 6 · Memorial Park")
        assert(item.recurrence == "WEEKLY · FRI")
        assert(item.likeCount == 4 && item.isLiked)
        assert(item.goingCount == 0 && item.isJoined)
        assert(item.goingSummary == "Nobody's going yet — be first.")
        assert(item.goingAvatars.isEmpty)
        if case .eventPhoto = item.image {} else { assertionFailure("Expected an event photo") }

        let timeOnly = FeedCardItem(
            from: posting("time", title: "Time", date: "2026-07-24", time: "noon"),
            recurrence: nil
        )
        assert(timeOnly.metaLine == "noon")

        let locationOnly = FeedCardItem(
            from: posting("place", title: "Place", date: "2026-07-24", location: "Library"),
            recurrence: nil
        )
        assert(locationOnly.metaLine == "Library")
        if case .fallback = locationOnly.image {} else { assertionFailure("Expected fallback artwork") }

        let avatarURLs = [
            URL(string: "https://example.com/sam.jpg")!,
            URL(string: "https://example.com/maya.jpg")!,
            URL(string: "https://example.com/alex.jpg")!,
            URL(string: "https://example.com/lee.jpg")!
        ]
        let preview = GoingPreview(
            names: ["Sam Rivera", "Maya Chen", "Alex Kim"],
            avatars: avatarURLs
        )

        let oneGoing = FeedCardItem(
            from: posting("one", title: "One", date: "2026-07-24", going: 1),
            recurrence: nil,
            goingPreview: preview
        )
        assert(oneGoing.goingSummary == "Sam is going")

        let twoGoing = FeedCardItem(
            from: posting("two", title: "Two", date: "2026-07-24", going: 2),
            recurrence: nil,
            goingPreview: preview
        )
        assert(twoGoing.goingSummary == "Sam and 1 other are going")

        let manyGoing = FeedCardItem(
            from: posting("many", title: "Many", date: "2026-07-24", going: 4),
            recurrence: nil,
            goingPreview: preview
        )
        assert(manyGoing.goingSummary == "Sam and 3 others are going")
        assert(manyGoing.goingAvatars == Array(avatarURLs.prefix(3)))

        let unnamedGoing = FeedCardItem(
            from: posting("unnamed", title: "Unnamed", date: "2026-07-24", going: 3),
            recurrence: nil
        )
        assert(unnamedGoing.goingSummary == "3 going")
    }

    private static func posting(
        _ id: String,
        title: String,
        date: String?,
        time: String? = nil,
        location: String? = nil,
        imageURL: String? = nil,
        going: Int = 2
    ) -> FeedPosting {
        FeedPosting(
            id: id,
            title: title,
            eventDate: date,
            startTime: time,
            location: location,
            imageUrl: imageURL,
            createdAt: Date(timeIntervalSinceReferenceDate: 0),
            posterName: "Neighbor",
            posterAvatar: nil,
            posterTarget: FollowTarget(type: .profile, id: "poster"),
            followerCount: 0,
            likeCount: 0,
            commentCount: 0,
            goingCount: going,
            liked: false,
            following: false,
            rsvpd: false
        )
    }
}
#endif
