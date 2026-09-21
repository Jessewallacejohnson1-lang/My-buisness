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
    /// Shown beside the comment glyph, the way Instagram shows it. 0 hides it.
    var commentCount: Int = 0
    @Binding var state: FeedCardActionState
    let reduceMotion: Bool
    let autoplayStep: Int
    let onLike: ((Bool) -> Void)?
    let onSave: ((Bool) -> Void)?
    let onComment: () -> Void
    let onShare: (() -> Void)?

    @State private var heartScale: CGFloat = 1
    @State private var bookmarkOffset: CGFloat = 0
    @State private var heartGeneration = 0
    @State private var bookmarkGeneration = 0

    /// Instagram's feed action row, measured off a capture (Jesse, 2026-09-20):
    /// a 24pt glyph, its count right beside it, and 16pt of air between one control
    /// and the next. The 28pt-wide target plus `groupSpacing` is what adds up to
    /// that 16 — the glyph does not fill its box.
    private enum Metric {
        static let glyph: CGFloat = 24
        static let tapWidth: CGFloat = 28
        static let groupSpacing: CGFloat = 12
        static let countGap: CGFloat = 6
        static let rowHeight: CGFloat = 44
    }

    var body: some View {
        // Instagram's split: everything that acts on the post sits leading, in one
        // cluster with its counts; the bookmark — the only control that files this
        // away somewhere else — sits alone at the trailing edge.
        HStack(spacing: 0) {
            HStack(spacing: Metric.groupSpacing) {
                heartControl
                if kind == .posting {
                    countedControl(
                        "bubble.right",
                        count: commentCount,
                        label: "Comment",
                        action: onComment
                    )
                }
                shareButton
            }

            Spacer(minLength: 12)

            saveButton
        }
        .frame(height: Metric.rowHeight)
        .onChange(of: autoplayStep) { _, step in
            switch step {
            case 1, 4: performHeartTap()
            case 3: performSaveTap()
            default: break
            }
        }
    }

    private var heartControl: some View {
        HStack(spacing: Metric.countGap) {
            Button(action: performHeartTap) {
                ZStack {
                    actionIcon("heart", active: false)
                        .opacity(state.isLiked ? 0 : 1)
                    // Red only when it is yours. The outline stays ink, so the row
                    // reads as one family until you act on it.
                    //
                    // The colour is passed IN rather than applied to the returned
                    // view: `actionIcon` sets `foregroundStyle` itself, closer to the
                    // Image, and the inner style wins. Wrapping it from outside
                    // silently did nothing (caught on the recording — no red).
                    actionIcon("heart.fill", active: true, tint: Hue.heart)
                        .opacity(state.isLiked ? 1 : 0)
                }
                .scaleEffect(reduceMotion ? 1 : heartScale)
                .frame(width: Metric.tapWidth, height: Metric.rowHeight)
                .contentShape(actionShape)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Like, \(state.likeCount) likes")
            .accessibilityValue(state.isLiked ? "Liked" : "Not liked")
            .accessibilityAddTraits(state.isLiked ? .isSelected : [])

            if state.likeCount > 0 {
                heartCount
            }
        }
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
        Text("\(value)")
            .font(.mono(13))
            .monospacedDigit()
            .foregroundStyle(Hue.ink.opacity(0.45))
            .animation(
                reduceMotion
                    ? .easeInOut(duration: 0.15)
                    : .spring(response: 0.3, dampingFraction: 0.5),
                value: state.likeCount
            )
            .accessibilityHidden(true)
    }

    private var saveButton: some View {
        Button(action: performSaveTap) {
            ZStack {
                actionIcon("bookmark", active: false)
                    .opacity(state.isSaved ? 0 : 1)
                actionIcon("bookmark.fill", active: true)
                    .opacity(state.isSaved ? 1 : 0)
            }
            .offset(y: reduceMotion ? 0 : bookmarkOffset)
            .frame(width: Metric.tapWidth, height: Metric.rowHeight)
            .contentShape(actionShape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.isSaved ? "Saved" : "Save")
        .accessibilityAddTraits(state.isSaved ? .isSelected : [])
    }

    private var shareButton: some View {
        iconButton("square.and.arrow.up") { onShare?() }
            .accessibilityLabel("Share")
    }

    /// A glyph with its count beside it, Instagram's pairing. The count is not part
    /// of the button: tapping a number by accident is how you un-like a post.
    private func countedControl(
        _ symbol: String,
        count: Int,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Metric.countGap) {
            iconButton(symbol, action: action)
                .accessibilityLabel(count > 0 ? "\(label), \(count)" : label)

            if count > 0 {
                countText(count)
            }
        }
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionIcon(symbol, active: false)
                .frame(width: Metric.tapWidth, height: Metric.rowHeight)
                .contentShape(actionShape)
        }
        .buttonStyle(.plain)
    }

    /// One icon in the row. `tint` overrides the ink ramp for the one control that
    /// carries colour — the liked heart — and must be passed here rather than layered
    /// on the result, because this `foregroundStyle` sits closer to the Image and
    /// would win.
    private func actionIcon(_ symbol: String, active: Bool, tint: Color? = nil) -> some View {
        // SF Symbols does not expose a 1.75pt stroke; regular approximates the spec.
        Image(systemName: symbol)
            .font(.sans(Metric.glyph))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(tint ?? Hue.ink.opacity(active ? 1 : 0.45))
    }

    private var actionShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
    }

    private func performHeartTap() {
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

    private func performSaveTap() {
        bookmarkGeneration += 1
        let generation = bookmarkGeneration

        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.15)) {
                _ = state.toggleSave()
            }
        } else {
            withAnimation(.easeOut(duration: 0.08)) {
                _ = state.toggleSave()
                bookmarkOffset = 4
            }

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                guard generation == bookmarkGeneration else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    bookmarkOffset = 0
                }
            }
        }

        onSave?(state.isSaved)
    }
}
