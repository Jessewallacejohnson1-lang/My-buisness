//
//  BPButton.swift
//  Block Party — the chunky 3D press.
//
//  Signature mechanic #1. This one component carries most of the "feels like
//  Duolingo" effect, so the physics matter more than the paint.
//
//  MEASURED off the reference (S02, x=590 vertical scan): the button is 48pt tall
//  overall — a 44pt face sitting on a 4pt darker edge. The edge colour is 19% darker
//  than the face (#5ACD05 → #5CA600). Side margins are 16pt.
//
//  The press is NOT a scale. The face TRANSLATES DOWN over its edge until the edge is
//  fully covered, which is why it reads as a physical key rather than a shrinking
//  rectangle — the button's outer bounds never change, only the face's offset. On
//  release it springs back and fires.
//
//  Press feedback rides `ButtonStyle.isPressed`, never a `LongPressGesture`. A
//  pan-competing gesture on a tappable surface out-competes an enclosing ScrollView's
//  vertical pan and silently kills scrolling — that shipped as a real bug once
//  (see CLAUDE.md, "Never attach a pan-competing gesture to a scrollable feed cell").
//
//  Reduce Motion: the translation is the affordance, not decoration, so it is kept —
//  but the spring is flattened to a linear settle so nothing overshoots.
//

import SwiftUI

enum BPButtonVariant {
    /// Filled orange with the darker edge. The screen's one primary action.
    case primary
    /// White face, thin grey border, orange label. S02's "I ALREADY HAVE AN ACCOUNT".
    case secondary
    /// Borderless text button. S15's "NOT NOW".
    case quiet
}

struct BPButton: View {
    let title: String
    var variant: BPButtonVariant = .primary
    var enabled: Bool = true
    /// DEBUG-only: drives the press visual with no touch.
    ///
    /// `ButtonStyle.isPressed` cannot be synthesised, and this simulator setup exposes no
    /// tap automation, so the press physics would otherwise be unverifiable — the one
    /// mechanic the spec calls most important. This feeds the SAME `pressed` state the
    /// real touch does, so what gets measured is the shipping animation, not a mock of it.
    var debugPressed: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.sansBold(15))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .buttonStyle(BPButtonStyle(variant: variant, enabled: enabled, forcePressed: debugPressed))
        .disabled(!enabled)
        .animation(BP.Motion.select, value: enabled)
    }

    private var labelColor: Color {
        guard enabled else { return BP.gray }
        switch variant {
        case .primary:   return .white
        case .secondary: return BP.orange
        case .quiet:     return BP.gray
        }
    }
}

// MARK: - The press

private struct BPButtonStyle: ButtonStyle {
    let variant: BPButtonVariant
    let enabled: Bool
    /// See `BPButton.debugPressed`. Always false in normal use.
    var forcePressed: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = (configuration.isPressed || forcePressed) && enabled

        return Group {
            if variant == .quiet {
                configuration.label
                    .frame(maxWidth: .infinity)
                    .frame(height: BP.Metric.buttonHeight)
                    .contentShape(Rectangle())
                    .opacity(pressed ? 0.55 : 1)
            } else {
                ZStack(alignment: .top) {
                    // The edge — full height, so it peeks out below the face at rest
                    // and is fully covered when the face travels down onto it.
                    RoundedRectangle(cornerRadius: BP.Metric.buttonRadius, style: BP.Metric.cornerStyle)
                        .fill(edgeColor)
                        .frame(height: BP.Metric.buttonHeight)

                    // The face.
                    RoundedRectangle(cornerRadius: BP.Metric.buttonRadius, style: BP.Metric.cornerStyle)
                        .fill(faceColor)
                        .overlay {
                            if variant == .secondary && enabled {
                                RoundedRectangle(cornerRadius: BP.Metric.buttonRadius, style: BP.Metric.cornerStyle)
                                    .strokeBorder(BP.hairline, lineWidth: 2)
                            }
                        }
                        .frame(height: BP.Metric.buttonFace)
                        .overlay { configuration.label }
                        .offset(y: pressed ? BP.Metric.buttonEdge : 0)
                }
                .frame(maxWidth: .infinity)
                .frame(height: BP.Metric.buttonHeight)
                .contentShape(Rectangle())
            }
        }
        .animation(reduceMotion ? .linear(duration: 0.08) : BP.Motion.press, value: pressed)
        .onChange(of: configuration.isPressed) { _, isDown in
            // Tick on the press-DOWN edge, the moment the key travels — matching the
            // reference, where the haptic lands with the movement rather than the fire.
            if isDown && enabled { Haptics.light() }
        }
    }

    private var faceColor: Color {
        guard enabled else { return BP.chip }
        switch variant {
        case .primary:   return BP.orange
        case .secondary: return Hue.surface
        case .quiet:     return .clear
        }
    }

    /// Disabled and secondary buttons have no visible edge — the edge colour simply
    /// matches the face, so the component keeps its 48pt footprint and the layout
    /// never shifts when a Continue button enables.
    private var edgeColor: Color {
        guard enabled else { return BP.chip }
        switch variant {
        case .primary:   return BP.orangeEdge
        case .secondary: return BP.hairline
        case .quiet:     return .clear
        }
    }
}
