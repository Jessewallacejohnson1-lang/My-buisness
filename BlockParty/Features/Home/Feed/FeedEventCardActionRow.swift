//
//  FeedEventCardActionRow.swift
//  Block Party — local-only social action controls and tap choreography.
//

import SwiftUI

/// Which controls a card's action row offers.
///
/// A posting is somebody talking, so it takes a reaction and a reply. An event is
/// a fact about the town — there is nothing to agree or disagree with, so it only
/// offers the two verbs that do something for you later: keep it, or pass it on.
enum FeedActionKind {
    case posting
    case event
}

struct FeedEventCardActionRow: View {
    var kind: FeedActionKind = .posting
    @Binding var state: FeedCardActionState
    let reduceMotion: Bool
    let autoplayStep: Int
    let onLike: ((Bool) -> Void)?
    let onSave: ((Bool) -> Void)?
    let onComment: () -> Void
    let onShare: (() -> Void)?

    @State private var thumbScale: CGFloat = 1
    @State private var bookmarkOffset: CGFloat = 0
    @State private var thumbGeneration = 0
    @State private var bookmarkGeneration = 0

    var body: some View {
        // Share sits alone past the spacer, hard against the trailing edge. It is the
        // only control here that leaves the app, so it does not belong in the same
        // cluster as the three that act on the card in place.
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                if kind == .posting {
                    thumbControl
                    iconButton("bubble.right", action: onComment)
                        .accessibilityLabel("Comment")
                }
                saveButton
            }

            Spacer(minLength: 12)

            shareButton
        }
        .frame(height: 44)
        .onChange(of: autoplayStep) { _, step in
            switch step {
            case 1, 4: if kind == .posting { performThumbTap() }
            case 3: performSaveTap()
            default: break
            }
        }
    }

    private var thumbControl: some View {
        HStack(spacing: 5) {
            Button(action: performThumbTap) {
                ZStack {
                    actionIcon("hand.thumbsup", active: false)
                        .opacity(state.isLiked ? 0 : 1)
                    actionIcon("hand.thumbsup.fill", active: true)
                        .opacity(state.isLiked ? 1 : 0)
                }
                .scaleEffect(reduceMotion ? 1 : thumbScale)
                .frame(width: 44, height: 44)
                .contentShape(actionShape)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Thumbs up, \(state.likeCount) thumbs up")
            .accessibilityValue(state.isLiked ? "Given" : "Not given")
            .accessibilityAddTraits(state.isLiked ? .isSelected : [])

            if state.likeCount > 0 {
                thumbCount
            }
        }
    }

    @ViewBuilder
    private var thumbCount: some View {
        if reduceMotion {
            countText.contentTransition(.opacity)
        } else {
            countText.contentTransition(.numericText())
        }
    }

    private var countText: some View {
        Text("\(state.likeCount)")
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
            .frame(width: 44, height: 44)
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

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionIcon(symbol, active: false)
                .frame(width: 44, height: 44)
                .contentShape(actionShape)
        }
        .buttonStyle(.plain)
    }

    private func actionIcon(_ symbol: String, active: Bool) -> some View {
        // SF Symbols does not expose a 1.75pt stroke; regular approximates the spec.
        Image(systemName: symbol)
            .font(.system(size: 22, weight: .regular))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Hue.ink.opacity(active ? 1 : 0.45))
    }

    private var actionShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
    }

    private func performThumbTap() {
        thumbGeneration += 1
        let generation = thumbGeneration

        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.15)) {
                _ = state.toggleLike()
            }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                _ = state.toggleLike()
                thumbScale = 1.3
            }

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard generation == thumbGeneration else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    thumbScale = 1
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
