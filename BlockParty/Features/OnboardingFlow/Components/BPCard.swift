//
//  BPCard.swift
//  Block Party — the big option card (S17–S19).
//
//  Signature mechanic #5.
//
//  Same physical recipe as `BPRow` — 2pt border, 4pt bottom edge, face travels down on
//  press — but taller, stacked, and carrying a title over a grey subtitle. S19's cards
//  add a leading glyph; S17/S19's recommended card adds a pill tag that straddles the
//  card's top edge.
//
//  The selected recipe is deliberately identical to `BPRow`'s so the whole flow has one
//  selection language: tint ground, accent border, darker-accent label.
//

import SwiftUI

struct BPCard: View {
    let title: String
    let subtitle: String
    var icon: BPGlyph?
    /// Renders the `BP.teal` RECOMMENDED tag straddling the card's top edge.
    var recommended: Bool = false
    var selected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                if let icon {
                    BPIconChip(glyph: icon, tint: selected ? BP.tealText : BP.ink)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.sansBold(17))
                        .foregroundStyle(selected ? BP.tealText : BP.ink)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.sans(14))
                        .foregroundStyle(selected ? BP.tealText.opacity(0.75) : BP.gray)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(BPCardStyle(selected: selected))
        .overlay(alignment: .topTrailing) {
            if recommended {
                BPRecommendedPill()
                    .offset(x: -12, y: -10)
            }
        }
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(recommended ? "\(title), recommended. \(subtitle)" : "\(title). \(subtitle)")
    }
}

/// The small teal tag that sits on a recommended card's top edge.
struct BPRecommendedPill: View {
    var body: some View {
        Text("RECOMMENDED")
            .font(.sansBold(10))
            .tracking(0.6)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(BP.teal, in: RoundedRectangle(cornerRadius: 6, style: BP.Metric.cornerStyle))
            .accessibilityHidden(true)   // folded into the card's own label
    }
}

// MARK: - Press + selected recipe

private struct BPCardStyle: ButtonStyle {
    let selected: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let border = selected ? BP.teal : BP.hairline

        // The card sizes to its content, so the edge is expressed as bottom padding on
        // the face's container rather than a fixed-height plate behind it.
        return configuration.label
            .background {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: BP.Metric.cardRadius, style: BP.Metric.cornerStyle)
                        .fill(border)
                        .padding(.top, BP.Metric.cardEdge)

                    RoundedRectangle(cornerRadius: BP.Metric.cardRadius, style: BP.Metric.cornerStyle)
                        .fill(selected ? BP.tealTint : Hue.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: BP.Metric.cardRadius, style: BP.Metric.cornerStyle)
                                .strokeBorder(border, lineWidth: BP.Metric.cardBorder)
                        }
                        .padding(.bottom, BP.Metric.cardEdge)
                }
            }
            .offset(y: pressed ? BP.Metric.cardEdge : 0)
            .padding(.bottom, BP.Metric.cardEdge)
            .contentShape(Rectangle())
            .animation(reduceMotion ? .linear(duration: 0.08) : BP.Motion.press, value: pressed)
            .animation(BP.Motion.select, value: selected)
            .onChange(of: configuration.isPressed) { _, isDown in
                if isDown { Haptics.light() }
            }
    }
}
