//
//  FeedEventCardJoinButton.swift
//  Block Party — join/leave morph and press choreography for the feed card.
//

import SwiftUI

struct FeedEventCardJoinButton: View {
    let isJoined: Bool
    let isFallback: Bool
    let reduceMotion: Bool
    let autoplayPressed: Bool
    let onToggle: () -> Void

    @State private var ringScale: CGFloat = 1
    @State private var ringOpacity: Double = 0
    @State private var ringGeneration = 0

    var body: some View {
        Button(action: onToggle) {
            ZStack {
                ring
                buttonFace
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(
            FeedCardJoinPressStyle(
                reduceMotion: reduceMotion,
                autoplayPressed: autoplayPressed
            )
        )
        .accessibilityLabel(isJoined ? "Joined" : "Join event")
        .accessibilityHint(isJoined ? "Double tap to leave" : "")
        .accessibilityAddTraits(isJoined ? .isSelected : [])
        .onChange(of: isJoined) { wasJoined, joined in
            guard joined, !wasJoined else { return }
            playRingBurst()
        }
    }

    private var buttonFace: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                .fill(isJoined ? Color.white : Hue.ink)
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .strokeBorder(buttonBorder, lineWidth: 1)
                }
                .animation(morphAnimation, value: isJoined)

            FeedCardPlusMark()
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .frame(width: 20, height: 20)
                .rotationEffect(
                    reduceMotion ? .zero : .degrees(isJoined ? 90 : 0)
                )
                .opacity(isJoined ? 0 : 1)
                .animation(morphAnimation, value: isJoined)

            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Hue.ink)
                .opacity(isJoined ? 1 : 0)
                .animation(morphAnimation, value: isJoined)
        }
        .frame(width: 44, height: 44)
    }

    private var ring: some View {
        ZStack {
            ringHalo

            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                .strokeBorder(Hue.ink, lineWidth: 1.75)
        }
            .scaleEffect(reduceMotion ? 1 : ringScale)
            .opacity(reduceMotion ? 0 : ringOpacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var ringHalo: some View {
        RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
            .strokeBorder(Color.white, lineWidth: 3.75)
    }

    private var buttonBorder: Color {
        if isJoined { return Hue.hairline }
        return isFallback ? Hue.hairline : .clear
    }

    private var morphAnimation: Animation {
        .easeInOut(duration: reduceMotion ? 0.15 : 0.18)
    }

    private func playRingBurst() {
        guard !reduceMotion else { return }

        ringGeneration += 1
        let generation = ringGeneration
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            ringScale = 1
            ringOpacity = 0.6
        }

        Task { @MainActor in
            await Task.yield()
            guard generation == ringGeneration else { return }
            withAnimation(.easeOut(duration: 0.35)) {
                ringScale = 1.6
                ringOpacity = 0
            }
        }
    }
}

private struct FeedCardJoinPressStyle: ButtonStyle {
    let reduceMotion: Bool
    let autoplayPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed || autoplayPressed

        configuration.label
            .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.88 : 1))
            .animation(
                reduceMotion
                    ? nil
                    : .spring(response: 0.25, dampingFraction: 0.6),
                value: isPressed
            )
    }
}

private struct FeedCardPlusMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
