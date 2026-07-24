//
//  BPRow.swift
//  Block Party — the answer row.
//
//  Signature mechanic #4.
//
//  MEASURED off the reference (S06, column scans at x=1000/1050): rows are 56pt tall
//  overall and sit on a 68pt pitch, so the gap between them is 12pt. Full width minus
//  16pt margins. The border is 2pt on the top and sides — and 4pt along the BOTTOM,
//  which is the same 3D edge the buttons have. That asymmetry is easy to miss and is a
//  large part of why the rows read as physical keys.
//
//  Selected recipe, sampled: fill #E1F4FF, border #1DB3FB — i.e. the accent at ~12%
//  over white, with the accent itself as the border. Here: `BP.tealTint` + `BP.teal`,
//  with `BP.tealText` on the label so it clears 4.5:1.
//
//  Press feedback rides `ButtonStyle.isPressed` — the same rule as `BPButton`, and for
//  the same reason: these rows live inside a ScrollView on the longer questions (S09
//  has seven), and a pan-competing gesture would silently kill scrolling.
//

import SwiftUI

/// What sits in the row's leading chip.
enum BPRowIcon: Equatable {
    case glyph(BPGlyph)
    case level(Int)
    case none
}

struct BPRow: View {
    let label: String
    var icon: BPRowIcon = .none
    /// Right-aligned grey label — S12's Casual / Regular / Serious / Intense.
    var trailingLabel: String?
    var selected: Bool = false
    /// Multi-select rows carry a check badge that springs in (S09/S10).
    var showsCheck: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: BP.Metric.rowChipGap) {
                switch icon {
                case .glyph(let g): BPIconChip(glyph: g, tint: selected ? BP.tealText : BP.ink)
                case .level(let n): BPLevelChip(level: n)
                case .none:         EmptyView()
                }

                Text(label)
                    .font(.sansBold(16))
                    .foregroundStyle(selected ? BP.tealText : BP.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 8)

                if let trailingLabel {
                    Text(trailingLabel)
                        .font(.sans(15))
                        .foregroundStyle(selected ? BP.tealText.opacity(0.75) : BP.gray)
                        .lineLimit(1)
                }

                if showsCheck {
                    BPCheckBadge(on: selected)
                }
            }
            .padding(.horizontal, BP.Metric.rowPadding)
        }
        .buttonStyle(BPRowStyle(selected: selected))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Press + selected recipe

private struct BPRowStyle: ButtonStyle {
    let selected: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let border = selected ? BP.teal : BP.hairline

        return ZStack(alignment: .top) {
            // The 4pt bottom edge, in the border colour.
            RoundedRectangle(cornerRadius: BP.Metric.rowRadius, style: BP.Metric.cornerStyle)
                .fill(border)
                .frame(height: BP.Metric.rowHeight)

            RoundedRectangle(cornerRadius: BP.Metric.rowRadius, style: BP.Metric.cornerStyle)
                .fill(selected ? BP.tealTint : Hue.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: BP.Metric.rowRadius, style: BP.Metric.cornerStyle)
                        .strokeBorder(border, lineWidth: BP.Metric.rowBorder)
                }
                .frame(height: BP.Metric.rowFace)
                .overlay { configuration.label }
                .offset(y: pressed ? BP.Metric.rowEdge : 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: BP.Metric.rowHeight)
        .contentShape(Rectangle())
        .animation(reduceMotion ? .linear(duration: 0.08) : BP.Motion.press, value: pressed)
        .animation(BP.Motion.select, value: selected)
        .onChange(of: configuration.isPressed) { _, isDown in
            if isDown { Haptics.light() }
        }
    }
}

// MARK: - Check badge

/// The trailing check on a multi-select row. Springs in on selection; leaves an empty
/// rounded square behind when off, exactly as the reference does (S09 unselected shows
/// the empty box, so the row's layout never shifts when it fills).
struct BPCheckBadge: View {
    let on: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: BP.Metric.cornerStyle)
                .strokeBorder(BP.hairline, lineWidth: 2)
                .frame(width: 26, height: 26)
                .opacity(on ? 0 : 1)

            RoundedRectangle(cornerRadius: 7, style: BP.Metric.cornerStyle)
                .fill(BP.teal)
                .frame(width: 26, height: 26)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .scaleEffect(on ? 1 : 0.5)
                .opacity(on ? 1 : 0)
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : BP.Motion.badge, value: on)
    }
}
