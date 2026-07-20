//
//  ActivitiesSkeleton.swift
//  Block Party — the "rendering" placeholder for the Explore/Activities tab, shown while
//  its data loads. Replaces a bare centered spinner (which gave no sense of the
//  page filling in) with shimmering blocks the shape of the real discovery layout:
//  a full-width featured hero + page dots, then two horizontal shelves. The header
//  and category tiles above render immediately, so the skeleton stands in only for
//  the load-gated body — and its shapes match, so nothing shifts when data lands.
//

import SwiftUI

struct ActivitiesSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            featuredHero
            shelf
            shelf
        }
        .padding(.top, 4)
        .shimmering()
        // The whole page is loading; VoiceOver hears one "Loading" rather than a
        // dozen meaningless blocks.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading activities")
    }

    // Full-width 210pt hero + three page dots (mirrors FeaturedCarousel).
    private var featuredHero: some View {
        VStack(spacing: 12) {
            SkeletonBlock(cornerRadius: Radius.card)
                .frame(height: 210)
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in SkeletonCircle(diameter: 6) }
            }
        }
        .padding(.horizontal, 18)
    }

    // Section header (title + "see all" pill) over a row of shelf cards.
    private var shelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SkeletonLine(widthFraction: 0.5, height: 18)
                Spacer(minLength: 24)
                SkeletonBlock(cornerRadius: 12).frame(width: 64, height: 24)
            }
            .padding(.horizontal, 18)

            HStack(spacing: 14) {
                shelfCard
                shelfCard
                shelfCard
            }
            .padding(.horizontal, 18)
        }
        .clipped()
    }

    // A 232×132 photo block with a title + meta line beneath (mirrors EventShelfCard).
    private var shelfCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonBlock(cornerRadius: Radius.card)
                .frame(width: 232, height: 132)
            SkeletonLine(widthFraction: 0.85, height: 12)
            SkeletonLine(widthFraction: 0.55, height: 10)
        }
        .frame(width: 232, alignment: .leading)
    }
}

#if DEBUG
#Preview("Activities skeleton") {
    ScrollView { ActivitiesSkeleton() }
        .background(Hue.paper)
}
#endif
