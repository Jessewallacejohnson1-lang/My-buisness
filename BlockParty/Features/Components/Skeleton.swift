//
//  Skeleton.swift
//  Block Party — the "rendering" placeholders shown while a tab loads, so content
//  resolves in place instead of popping in over a blank screen.
//
//  Craft bar (impeccable / DESIGN.md): calm and on-brand, not flashy. Paper-tone
//  blocks the exact shape of the content they stand in for (no layout shift when
//  real data lands), with ONE soft light sweep travelling across the whole group
//  (masked to the blocks, so gaps stay quiet) — cohesive, and a single
//  TimelineView rather than one per block. GPU-only (a masked gradient offset, no
//  layout properties animate). Reduce Motion drops the sweep for a gentle opacity
//  breath. Cross-fade the skeleton→content hand-off at the call site, keyed on the
//  load flag:
//
//      ZStack {
//          if model.loaded { RealContent() } else { TabSkeleton() }
//      }
//      .animation(Motion.smooth, value: model.loaded)
//
//  with `.transition(.opacity)` on each branch.
//

import SwiftUI

// MARK: - Building blocks (static paper-tone shapes; the sweep is applied once at
// the skeleton's root via `.shimmering()`).

/// A rounded paper-tone rect the size of the content it stands in for.
struct SkeletonBlock: View {
    var cornerRadius: CGFloat = 10

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Hue.fill)
    }
}

/// A placeholder text line. `widthFraction` of the available width keeps a
/// paragraph looking like ragged text, not identical bars.
struct SkeletonLine: View {
    var widthFraction: CGFloat = 1
    var height: CGFloat = 12

    var body: some View {
        SkeletonBlock(cornerRadius: height / 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .scaleEffect(x: widthFraction, anchor: .leading)
    }
}

/// A round placeholder — avatars, dots, small icons.
struct SkeletonCircle: View {
    var diameter: CGFloat = 40

    var body: some View {
        Circle()
            .fill(Hue.fill)
            .frame(width: diameter, height: diameter)
    }
}

// MARK: - Shimmer

extension View {
    /// Apply ONCE at a skeleton's root. A soft highlight sweeps left→right across
    /// the whole group, masked to its opaque blocks so gaps stay calm.
    func shimmering() -> some View { modifier(Shimmer()) }
}

struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let period: Double = 1.4

    func body(content: Content) -> some View {
        if reduceMotion {
            content.modifier(Breathe())
        } else {
            content.overlay { sweep(over: content) }
        }
    }

    private func sweep(over content: Content) -> some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let p = t.truncatingRemainder(dividingBy: Self.period) / Self.period
                let w = geo.size.width
                let band = max(120, w * 0.5)
                LinearGradient(
                    colors: [.clear, .white.opacity(0.6), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: band)
                .offset(x: -band + p * (w + band))
                .frame(width: w, height: geo.size.height, alignment: .leading)
            }
        }
        // Clip the highlight to the blocks themselves — the gaps don't shimmer.
        .mask(content)
        .allowsHitTesting(false)
    }
}

/// Reduce-Motion substitute: a slow opacity breath instead of a travelling sweep.
private struct Breathe: ViewModifier {
    func body(content: Content) -> some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let s = 0.5 + 0.5 * cos(t.truncatingRemainder(dividingBy: 1.8) / 1.8 * 2 * .pi)
            content.opacity(0.72 + 0.28 * s)
        }
    }
}

#if DEBUG
/// Standalone gallery of the tab skeletons, shown via the `-show-skeletons` launch
/// flag (RootView gate) so the shimmer + layouts can be screenshotted without auth.
struct SkeletonGalleryPreview: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Activities").font(.displaySemi(16)).foregroundStyle(Hue.inkSecondary)
                    .padding(.horizontal, 18)
                ActivitiesSkeleton()

                // The briefing's cold-start placeholders. `TodayLoadingCard` stood
                // here until the Today tab became a briefing; it mirrored the old
                // feed's "Today + count + event rows", which no longer exists.
                Text("Happening Soon").font(.displaySemi(16)).foregroundStyle(Hue.inkSecondary)
                    .padding(.horizontal, 18)
                HappeningSoonSkeleton().padding(.horizontal, 18)

                Text("Daily touch").font(.displaySemi(16)).foregroundStyle(Hue.inkSecondary)
                    .padding(.horizontal, 18)
                DailyTouchSkeleton().padding(.horizontal, 18)

                Text("Spotlight").font(.displaySemi(16)).foregroundStyle(Hue.inkSecondary)
                    .padding(.horizontal, 18)
                SpotlightSkeleton().padding(.horizontal, 18)
            }
            .padding(.vertical, 24)
        }
        .background(Hue.paper.ignoresSafeArea())
    }
}

#Preview("Skeleton gallery") { SkeletonGalleryPreview() }
#endif
