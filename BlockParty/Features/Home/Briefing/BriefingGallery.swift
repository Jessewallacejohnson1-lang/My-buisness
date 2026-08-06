//
//  BriefingGallery.swift
//  Block Party — DEBUG-only visual coverage for every daily briefing state.
//

import SwiftUI

#if DEBUG
struct BriefingGallery: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 30) {
                galleryState("3 EVENTS") {
                    HappeningSoonSection(
                        events: sampleEvents,
                        fallback: nil,
                        onOpen: { _ in },
                        onRsvp: { _, _ in }
                    )
                }

                galleryState("1 EVENT") {
                    HappeningSoonSection(
                        events: [sampleEvents[0]],
                        fallback: nil,
                        onOpen: { _ in },
                        onRsvp: { _, _ in }
                    )
                }

                galleryState("0 EVENTS + FALLBACK") {
                    HappeningSoonSection(
                        events: [],
                        fallback: sampleFallback
                    )
                }

                galleryState("POLL · UNVOTED") {
                    DailyTouchCard(touch: unvotedPoll, onVote: { _ in })
                }

                galleryState("POLL · VOTED") {
                    DailyTouchCard(touch: votedPoll)
                }

                galleryState("HISTORY TOUCH") {
                    DailyTouchCard(touch: historyTouch)
                }

                galleryState("SPOTLIGHT") {
                    SpotlightCard(spotlight: sampleSpotlight, onOpen: {})
                }

                galleryState("CAUGHT UP") {
                    CaughtUpFooter(
                        caughtUp: sampleCaughtUp,
                        briefingDateLabel: "Wednesday, August 5"
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 24)
        }
        .background(Hue.paper)
    }

    /// `-gallery-state POLL` renders only the matching states. There is no
    /// scroll/gesture automation in this simulator setup, so a state below the
    /// fold cannot be reached — selecting one is the only way to screenshot it
    /// headlessly. (Distinct from `-briefing-state`, which names a whole canned
    /// payload for the real Today composition.)
    private var only: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-gallery-state"), i + 1 < args.count else { return nil }
        return args[i + 1].uppercased()
    }

    @ViewBuilder
    private func galleryState<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if let only, !label.contains(only) {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(label)
                    .font(.monoMedium(10))
                    .tracking(1)
                    .monospacedDigit()
                    .foregroundStyle(Hue.inkSecondary)

                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sampleEvents: [BriefingEvent] {
        [
            BriefingEvent(
                rank: 1,
                id: "gallery-market",
                title: "Evening market on College Avenue",
                eventDate: "2026-08-05",
                startTime: "5:30 PM",
                location: "College Avenue",
                imageUrl: nil,
                clubName: "St. Joe Local",
                category: "Community",
                goingCount: 28,
                goingAvatars: [],
                likeCount: 14,
                commentCount: 3,
                rsvpd: true,
                saved: false,
                liked: false
            ),
            BriefingEvent(
                rank: 2,
                id: "gallery-music",
                title: "Music in the park",
                eventDate: "2026-08-05",
                startTime: "7 PM",
                location: "Millstream Park",
                imageUrl: "https://images.unsplash.com/photo-1506157786151-b8491531f063?auto=format&fit=crop&w=1200&q=80",
                clubName: "City of St. Joseph",
                category: "Music",
                goingCount: 46,
                goingAvatars: [],
                likeCount: 21,
                commentCount: 5,
                rsvpd: false,
                saved: true,
                liked: true
            ),
            BriefingEvent(
                rank: 3,
                id: "gallery-run",
                title: "Wobegon Trail social run",
                eventDate: "2026-08-05",
                startTime: "6:15 PM",
                location: "Wobegon Trailhead",
                imageUrl: "https://images.unsplash.com/photo-1552674605-db6ffd4facb5?auto=format&fit=crop&w=1200&q=80",
                clubName: "St. Joe Run Club",
                category: "Outdoors",
                goingCount: 12,
                goingAvatars: [],
                likeCount: 8,
                commentCount: 2,
                rsvpd: false,
                saved: false,
                liked: false
            )
        ]
    }

    private var sampleFallback: BriefingFallback {
        BriefingFallback(
            kind: "quiet_day",
            title: "A quieter afternoon",
            body: "Nothing featured is starting soon. Browse Activities for more ways to spend time around town.",
            deeplink: "activities"
        )
    }

    private var unvotedPoll: BriefingTouch {
        BriefingTouch(
            id: "gallery-poll-open",
            kind: .poll,
            prompt: "Which summer tradition should return next year?",
            options: ["Porch concerts", "Community picnic", "Outdoor movie"],
            body: nil,
            voteCounts: [0, 0, 0],
            totalVotes: 0,
            myVote: nil
        )
    }

    private var votedPoll: BriefingTouch {
        BriefingTouch(
            id: "gallery-poll-voted",
            kind: .poll,
            prompt: "Which summer tradition should return next year?",
            options: ["Porch concerts", "Community picnic", "Outdoor movie"],
            body: nil,
            voteCounts: [42, 31, 19],
            totalVotes: 92,
            myVote: 0
        )
    }

    private var historyTouch: BriefingTouch {
        BriefingTouch(
            id: "gallery-history",
            kind: .history,
            prompt: "The bell that called neighbors together",
            options: nil,
            body: "In the early 1900s, a bell near the center of town marked fires, celebrations, and moments when neighbors were needed. Its sound carried well beyond College Avenue.",
            voteCounts: [],
            totalVotes: 0,
            myVote: nil
        )
    }

    private var sampleSpotlight: BriefingSpotlight {
        BriefingSpotlight(
            id: "gallery-spotlight",
            slug: "wobegon-trailhead",
            title: "Wobegon Trailhead",
            blurb: "A shady starting point for an easy evening ride, with downtown coffee and a quiet bench only a few blocks away.",
            imageUrl: "https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=1400&q=80",
            placeId: "wobegon"
        )
    }

    private var sampleCaughtUp: BriefingCaughtUp {
        BriefingCaughtUp(
            nextBriefingAt: Date(timeIntervalSince1970: 1_786_003_200),
            label: "New briefing at 6 AM"
        )
    }
}
#endif
