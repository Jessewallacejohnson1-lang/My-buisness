//
//  BriefingSkeletons.swift
//  Block Party — first-load placeholders for the briefing modules.
//
//  These exist so nothing jumps when the real payload lands: each placeholder
//  matches the height of the module it stands in for. They only ever show on a
//  genuinely cold start — once a briefing has been cached, the cache renders
//  instantly and these are skipped entirely.
//
//  Shimmer is applied once at the root of each skeleton, per the house
//  convention in Skeleton.swift.
//

import SwiftUI

/// Matches the full-width hero variant, which is the shape a cold start most
/// often resolves to given how few events are usually in the window.
struct HappeningSoonSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonLine(widthFraction: 0.34, height: 9)
            SkeletonBlock(cornerRadius: Radius.card)
                .aspectRatio(5.0 / 4.0, contentMode: .fit)
        }
        .shimmering()
        .accessibilityLabel("Loading what's happening soon")
    }
}

/// Prompt plus four option rows — the shape of every poll in the v1 bank.
struct DailyTouchSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SkeletonLine(widthFraction: 0.82, height: 17)
            VStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonBlock(cornerRadius: Radius.button)
                        .frame(height: 52)
                }
            }
        }
        .blockPartyCard(padding: 18)
        .shimmering()
        .accessibilityLabel("Loading today's question")
    }
}

struct SpotlightSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SkeletonLine(widthFraction: 0.28, height: 9)
            SkeletonLine(widthFraction: 0.56, height: 18)
            SkeletonLine(widthFraction: 1.0, height: 12)
            SkeletonLine(widthFraction: 0.74, height: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .blockPartyCard(padding: 18)
        .shimmering()
        .accessibilityLabel("Loading around town")
    }
}
