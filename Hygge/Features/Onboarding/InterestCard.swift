//
//  InterestCard.swift
//  Hygge — a photo interest card (reference-faithful): image, bottom scrim +
//  label, and a top-right selection circle. Selecting rings it coral, checks it,
//  and zooms the photo a touch. Full Reduce-Motion path (no zoom when set).
//

import SwiftUI

struct InterestCard: View {
    let interest: Interest
    let selected: Bool
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: { Haptics.selection(); onTap() }) {
            ZStack(alignment: .bottomLeading) {
                photo
                scrim
                label
                checkCircle
            }
            .frame(height: 130)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .stroke(selected ? Hue.accent : Hue.hairline, lineWidth: selected ? 3 : 1)
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selected)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement()
        .accessibilityLabel(interest.label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private var photo: some View {
        if let img = InterestImage.image(for: interest.id) {
            img.resizable().scaledToFill()
                .scaleEffect(selected && !reduceMotion ? 1.05 : 1)
        } else {
            // Calm tinted fallback (no gradient slop) until a photo is present.
            Rectangle().fill(Hue.paper200)
                .overlay(Image(systemName: "photo")
                    .font(.system(size: 22)).foregroundStyle(Hue.ink3))
        }
    }

    private var scrim: some View {
        LinearGradient(colors: [.clear, .black.opacity(0.55)],
                       startPoint: .center, endPoint: .bottom)
    }

    private var label: some View {
        Text(interest.label)
            .font(.sansSemibold(15))
            .foregroundStyle(.white)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            .padding(12)
    }

    private var checkCircle: some View {
        ZStack {
            Circle()
                .fill(selected ? Hue.accent : .black.opacity(0.25))
                .overlay(Circle().stroke(.white.opacity(selected ? 0 : 0.9), lineWidth: 1.5))
                .frame(width: 26, height: 26)
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(10)
    }
}

/// Press feedback for the photo cards — a soft scale-in on touch.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
