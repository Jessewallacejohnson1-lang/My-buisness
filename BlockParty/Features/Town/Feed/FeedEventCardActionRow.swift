//
//  FeedEventCardActionRow.swift
//  Block Party — local-only social action controls and tap choreography.
//

import SwiftUI

/// Which controls a card's action row offers.
///
/// Both kinds take a heart: a heart is not agreement, it is "this is good, I want
/// more of it", which is as true of an event as of a neighbour's photo (Jesse,
/// 2026-09-19). What still separates them is the reply — a posting is somebody
/// talking, so it takes comments; an event is a fact about the town, so it does not.
enum FeedActionKind {
    case posting
    case event
}

struct FeedEventCardActionRow: View {
    var kind: FeedActionKind = .posting
    /// Shown inside the comment pill. 0 hides it.
    var commentCount: Int = 0
    /// The heart and its count. Off while the person can't act yet (no account), as
    /// Join is (Jesse, 2026-10-11).
    var showsHeart = true
    /// Each failed heart turned back while the card was open (`RealLifeActions`) shakes
    /// the heart once.
    var heartFailures = 0
    @Binding var state: FeedCardActionState
    let reduceMotion: Bool
    let autoplayStep: Int
    let onLike: ((Bool) -> Void)?
    let onComment: () -> Void
    let onShare: (() -> Void)?
    /// The Town card's •••, after the send (found-posts).
    var onMenu: (() -> Void)? = nil

    @State private var heartScale: CGFloat = 1
    @State private var heartGeneration = 0
    /// `heartFailures` at the last tap: a tap mid-shake stills it and acts at once.
    @State private var heartTappedAt = 0

    /// Nextdoor's row in Tabler's thick icons (BP app like-comment-share, set C): each control
    /// is a grey pill with its count inside, heart and comment together on the left, share
    /// on the right. Sizes are the approved mock's.
    private enum Metric {
        static let glyph: CGFloat = 22
        static let pillHeight: CGFloat = 40
        static let pillMinWidth: CGFloat = 48
        static let pillPadding: CGFloat = 14
        static let pillSpacing: CGFloat = 8
        static let countGap: CGFloat = 6
        static let rowHeight: CGFloat = 44
    }

    var body: some View {
        HStack(spacing: Metric.pillSpacing) {
            if showsHeart {
                heartPill
            }
            if kind == .posting {
                pill(action: onComment) {
                    icon("Tabler/message-circle")
                    if commentCount > 0 { countText(commentCount) }
                }
                .accessibilityLabel(commentCount > 0 ? "Comment, \(commentCount)" : "Comment")
            }

            Spacer(minLength: 12)

            pill(action: { onShare?() }) { icon("Tabler/share-3") }
                .accessibilityLabel("Share")
            if let onMenu {
                pill(action: onMenu) { icon("Lucide/ellipsis") }
                    .accessibilityLabel("More options")
            }
        }
        .frame(height: Metric.rowHeight)
        .onChange(of: autoplayStep) { _, step in
            switch step {
            case 1, 4: performHeartTap()
            default: break
            }
        }
    }

    private var heartPill: some View {
        pill(action: performHeartTap) {
            ZStack {
                icon("Tabler/heart")
                    .opacity(state.isLiked ? 0 : 1)
                // Red only when it is yours; the outline stays ink.
                icon("Tabler/heart-filled", tint: Hue.heart)
                    .opacity(state.isLiked ? 1 : 0)
            }
            .scaleEffect(reduceMotion ? 1 : heartScale)
            if state.likeCount > 0 {
                heartCount
            }
        }
        .turnBackShake(failures: heartFailures, shakes: !reduceMotion && heartTappedAt != heartFailures)
        .accessibilityLabel("Like, \(state.likeCount) likes")
        .accessibilityValue(state.isLiked ? "Liked" : "Not liked")
        .accessibilityAddTraits(state.isLiked ? .isSelected : [])
    }

    @ViewBuilder
    private var heartCount: some View {
        if reduceMotion {
            countText(state.likeCount).contentTransition(.opacity)
        } else {
            countText(state.likeCount).contentTransition(.numericText())
        }
    }

    private func countText(_ value: Int) -> some View {
        Text(Self.shortCount(value))
            .font(.sansSemibold(15))
            .monospacedDigit()
            .foregroundStyle(Hue.ink)
            .animation(
                reduceMotion
                    ? .easeInOut(duration: 0.15)
                    : .spring(response: 0.3, dampingFraction: 0.5),
                value: state.likeCount
            )
            .accessibilityHidden(true)
    }

    /// One grey capsule, its count inside it as Nextdoor draws it; it squishes on touch-down.
    private func pill<Label: View>(action: @escaping () -> Void, @ViewBuilder label: () -> Label) -> some View {
        Button(action: action) {
            HStack(spacing: Metric.countGap) { label() }
                .padding(.horizontal, Metric.pillPadding)
                .frame(minWidth: Metric.pillMinWidth, minHeight: Metric.pillHeight)
                .background(Hue.actionPill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.press(.squish))
    }

    /// A Tabler mark from the asset catalog (template), ink unless `tint` says otherwise.
    private func icon(_ name: String, tint: Color = Hue.ink) -> some View {
        Image(name)
            .resizable()
            .frame(width: Metric.glyph, height: Metric.glyph)
            .foregroundStyle(tint)
    }

    /// Instagram's counts: in full with a comma under 10,000 ("3,778"), then "12.4K",
    /// then "1.2M", with a trailing ".0" dropped ("220K"). VoiceOver gets the full
    /// number from the button's label, not this.
    static func shortCount(_ value: Int) -> String {
        func short(_ scaled: Double, _ suffix: String) -> String {
            let tenths = (scaled * 10).rounded(.down) / 10
            let text = tenths == tenths.rounded(.down)
                ? String(Int(tenths))
                : String(format: "%.1f", tenths)
            return text + suffix
        }
        switch value {
        case ..<10_000: return value.formatted(.number.locale(Locale(identifier: "en_US")))
        case ..<1_000_000: return short(Double(value) / 1_000, "K")
        default: return short(Double(value) / 1_000_000, "M")
        }
    }

    private func performHeartTap() {
        heartTappedAt = heartFailures
        heartGeneration += 1
        let generation = heartGeneration

        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.15)) {
                _ = state.toggleLike()
            }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                _ = state.toggleLike()
                heartScale = 1.3
            }

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard generation == heartGeneration else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    heartScale = 1
                }
            }
        }

        onLike?(state.isLiked)
    }
}
