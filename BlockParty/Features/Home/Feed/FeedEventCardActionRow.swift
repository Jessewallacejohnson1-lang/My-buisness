//
//  FeedEventCardActionRow.swift
//  Block Party — local-only social action controls and tap choreography.
//

import SwiftUI

struct FeedEventCardActionRow: View {
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

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                likeControl
                iconButton("bubble.right", action: onComment)
                    .accessibilityLabel("Comment")
                iconButton("square.and.arrow.up") { onShare?() }
                    .accessibilityLabel("Share")
            }

            Spacer(minLength: 12)

            saveButton
        }
        .frame(height: 44)
        .onChange(of: autoplayStep) { _, step in
            switch step {
            case 1, 4: performLikeTap()
            case 3: performSaveTap()
            default: break
            }
        }
    }

    private var likeControl: some View {
        HStack(spacing: 5) {
            Button(action: performLikeTap) {
                ZStack {
                    actionIcon("heart", active: false)
                        .opacity(state.isLiked ? 0 : 1)
                    actionIcon("heart.fill", active: true)
                        .opacity(state.isLiked ? 1 : 0)
                }
                .scaleEffect(reduceMotion ? 1 : heartScale)
                .frame(width: 44, height: 44)
                .contentShape(actionShape)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Like, \(state.likeCount) likes")
            .accessibilityValue(state.isLiked ? "Liked" : "Not liked")
            .accessibilityAddTraits(state.isLiked ? .isSelected : [])

            if state.likeCount > 0 {
                likeCount
            }
        }
    }

    @ViewBuilder
    private var likeCount: some View {
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

    private func performLikeTap() {
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
