#if DEBUG
import SwiftUI

struct TodayFeedPreview: View {
    private let arguments = ProcessInfo.processInfo.arguments

    var body: some View {
        ScrollView(showsIndicators: false) {
            TodayFeedView(
                sections: Self.sections(emptyToday: arguments.contains("-today-feed-empty")),
                isLoading: arguments.contains("-today-feed-skeleton")
            )
            Color.clear.frame(height: 48)
        }
        .background(Hue.paper.ignoresSafeArea())
        .onAppear { FeedPipelineSelfCheck.run() }
    }

    private static func sections(emptyToday: Bool) -> [FeedCardSection] {
        let today = DateHelpers.localDate()
        let source = postings.filter { !emptyToday || $0.eventDate != today }
        let deduped = dedupeRecurring(source)
        assert(deduped.filter { $0.posting.title == "Friday Trail Walk" }.count == 1)
        assert(deduped.first { $0.posting.title == "Friday Trail Walk" }?.recurrence?.hasPrefix("WEEKLY") == true)
        return FeedSectioning.sections(for: deduped).map {
            $0.mapped(goingPreviews: goingPreviews)
        }
    }

    private static let postings: [FeedPosting] = {
        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        let friday = 6
        let rawFridayOffset = (friday - weekday + 7) % 7
        let nextFridayOffset = rawFridayOffset == 0 ? 7 : rawFridayOffset
        let photoOne = bundledPhoto("memorial-park")

        return [
            posting(
                "preview-today",
                title: "Music in Memorial Park",
                daysFromToday: 0,
                time: "6 PM",
                location: "Memorial Park",
                imageURL: photoOne,
                going: 4,
                likes: 12
            ),
            posting(
                "preview-week",
                title: "Neighborhood Book Swap",
                daysFromToday: 1,
                time: "10 AM",
                location: "College Avenue",
                imageURL: nil,
                going: 0,
                likes: 2
            ),
            // No imageURL, on purpose: every real club_events row has image_url NULL,
            // so this is the production path — a lazy venue lookup against a real
            // St. Joe venue. Lets the resolved Places photo + its ToS attribution be
            // verified headlessly, without auth (see FeedCardVenuePhoto).
            posting(
                "preview-recurring-nearest",
                title: "Friday Trail Walk",
                daysFromToday: nextFridayOffset,
                time: "3 PM",
                location: "Lake Wobegon Trailhead",
                imageURL: nil,
                going: 3,
                likes: 8,
                joined: true
            ),
            posting(
                "preview-recurring-next",
                title: "Friday Trail Walk",
                daysFromToday: nextFridayOffset + 7,
                time: "3 PM",
                location: "Lake Wobegon Trailhead",
                imageURL: nil,
                going: 2,
                likes: 3
            ),
            posting(
                "preview-later",
                title: "Riverside Potluck",
                daysFromToday: 10,
                time: "5:30 PM",
                location: "Rivers Bend Park",
                imageURL: nil,
                going: 1,
                likes: 5
            )
        ]
    }()

    private static let goingPreviews: [String: GoingPreview] = [
        "preview-today": GoingPreview(
            names: ["Sam Rivera", "Maya Chen", "Alex Kim"],
            avatars: ["the-local-blend", "farmers-market", "rivers-bend-park"]
                .compactMap(bundledPhotoURL)
        )
    ]

    private static func posting(
        _ id: String,
        title: String,
        daysFromToday: Int,
        time: String,
        location: String,
        imageURL: String?,
        going: Int,
        likes: Int,
        joined: Bool = false
    ) -> FeedPosting {
        let date = Calendar.current.date(byAdding: .day, value: daysFromToday, to: Date()) ?? Date()
        return FeedPosting(
            id: id,
            title: title,
            eventDate: DateHelpers.localDate(date),
            startTime: time,
            location: location,
            imageUrl: imageURL,
            createdAt: Date(),
            posterName: "Neighbor",
            posterAvatar: nil,
            posterTarget: FollowTarget(type: .profile, id: "preview-neighbor"),
            followerCount: 0,
            likeCount: likes,
            commentCount: 0,
            goingCount: going,
            liked: false,
            following: false,
            rsvpd: joined
        )
    }

    private static func bundledPhoto(_ name: String) -> String? {
        bundledPhotoURL(name)?.absoluteString
    }

    private nonisolated static func bundledPhotoURL(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "jpg")
    }
}
#endif
