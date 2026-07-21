#if DEBUG
//
//  FeedCardGallery.swift
//  Block Party — deterministic full-screen gallery for headless card verification.
//

import SwiftUI

struct FeedCardGallery: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 28) {
                ForEach(Self.samples) { item in
                    FeedEventCard(item: item)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 28)
        }
        .background(Hue.paper.ignoresSafeArea())
    }

    private static let samples: [FeedCardItem] = {
        let memorialPark = bundledPhoto("memorial-park")
        let wobegonTrail = bundledPhoto("wobegon-trail")
        let farmersMarket = bundledPhoto("farmers-market")
        let localBlend = bundledPhoto("the-local-blend")
        let riversBend = bundledPhoto("rivers-bend-park")

        return [
            FeedCardItem(
                id: "gallery-event-photo",
                title: "Friday Night in Memorial Park",
                dateChip: "FRI JUL 24",
                metaLine: "6 PM · Memorial Park",
                image: .eventPhoto(memorialPark),
                recurrence: nil,
                goingCount: 4,
                goingAvatars: [memorialPark, localBlend, farmersMarket],
                goingSummary: "Sam and 3 others are going",
                likeCount: 12,
                isLiked: true,
                isSaved: false,
                isJoined: false
            ),
            FeedCardItem(
                id: "gallery-places-photo",
                title: "Sunset Picnic by the River",
                dateChip: "SAT JUL 25",
                metaLine: "7 PM · Rivers Bend Park",
                image: .placesPhoto(riversBend, attribution: "Photo: Jane D."),
                recurrence: nil,
                goingCount: 3,
                goingAvatars: [riversBend],
                goingSummary: "Maya and 2 others are going",
                likeCount: 5,
                isLiked: false,
                isSaved: true,
                isJoined: false
            ),
            FeedCardItem(
                id: "gallery-fallback",
                title: "Neighborhood Book Swap",
                dateChip: "SUN JUL 26",
                metaLine: "10 AM · College Avenue",
                image: .fallback,
                recurrence: nil,
                goingCount: 2,
                goingAvatars: [localBlend],
                goingSummary: "Alex and 1 other are going",
                likeCount: 0,
                isLiked: false,
                isSaved: false,
                isJoined: false
            ),
            FeedCardItem(
                id: "gallery-recurring",
                title: "Lake Wobegon Trail Walk",
                dateChip: "FRI JUL 31",
                metaLine: "3 PM · Lake Wobegon Trailhead",
                image: .eventPhoto(wobegonTrail),
                recurrence: "WEEKLY · FRI",
                goingCount: 3,
                goingAvatars: [wobegonTrail, memorialPark],
                goingSummary: "Lee and 2 others are going",
                likeCount: 8,
                isLiked: false,
                isSaved: false,
                isJoined: true
            ),
            FeedCardItem(
                id: "gallery-no-going",
                title: "Morning at the Farmers Market",
                dateChip: "SAT AUG 1",
                metaLine: "9 AM · Downtown St. Joseph",
                image: .eventPhoto(farmersMarket),
                recurrence: nil,
                goingCount: 0,
                goingAvatars: [],
                goingSummary: "No neighbors are going yet",
                likeCount: 0,
                isLiked: false,
                isSaved: false,
                isJoined: false
            )
        ]
    }()

    private static func bundledPhoto(_ name: String) -> URL {
        Bundle.main.url(forResource: name, withExtension: "jpg")
            ?? URL(fileURLWithPath: "/\(name).jpg")
    }
}
#endif
