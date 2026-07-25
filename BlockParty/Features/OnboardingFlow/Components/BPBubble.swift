//
//  BPBubble.swift
//  Block Party — the typing speech bubble.
//
//  Signature mechanic #3.
//
//  A rounded rect with a thin grey border and a small tail pointing at the mascot.
//  The outline is ONE closed path including the tail, so the border strokes continuously
//  around the notch — an overlaid triangle would leave a seam where it meets the edge.
//
//  Two tail positions, both present in the reference:
//   • `.leading`  — question screens (S05, S08, S12…): small mascot at the left, bubble
//                   beside it, tail pointing left.
//   • `.bottom`   — talking screens (S03, S04, S11…): bubble on top, mascot below it,
//                   tail pointing down.
//
//  Text types on at ~30ms/char via the app's existing `TypewriterText`, which already
//  reserves the final layout so the bubble never reflows mid-write, and already rests a
//  beat at punctuation. Bold/coloured spans ride in as an `AttributedString`.
//
//  Reduce Motion: `TypewriterText` is never driven — the caller's state resolves to
//  `.shown` and the full line renders at once.
//
//  TODO(Jesse): the spec asks for "a soft tick" under the typing. The app ships no
//  audio infrastructure and no sound asset, so `onTick` is wired but left unbound —
//  raising it at the Phase 0 gate rather than inventing a sound.
//

import SwiftUI

enum BPBubbleTail: Equatable {
    /// Tail on the left edge, at a fraction of the bubble's height.
    case leading(CGFloat)
    /// Tail on the bottom edge, at a fraction of the bubble's width.
    case bottom(CGFloat)

    static let leading = BPBubbleTail.leading(0.5)
    static let bottom = BPBubbleTail.bottom(0.28)
}

struct BPBubble: View {
    let content: AttributedString
    var tail: BPBubbleTail = .leading
    /// Drive the type-on. Pass `false` for an already-settled bubble.
    var typing: Bool = true
    var onFinished: (() -> Void)?
    /// Fires per revealed character, for the soft tick. Unbound today — see file note.
    var onTick: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The bubble HUGS ITS TEXT — it does not fill the available width. Measured:
    /// S03's one-liner is 180.7pt wide, S05's two-liner 221.7pt (text column 181.7pt).
    /// Filling the width was the single most visible miss across S03–S08 in the first
    /// diff pass, so this cap is the text column, not the bubble's outer width.
    var maxWidth: CGFloat = BP.Metric.bubbleTextWidth

    var body: some View {
        TypewriterText(
            content: content,
            mode: .character,
            state: state,
            perUnit: BP.Motion.typePerChar,
            onFinished: onFinished
        )
        .font(.sans(BP.Metric.bubbleFont))
        .foregroundStyle(BP.ink)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: maxWidth, alignment: .leading)
        .padding(.horizontal, BP.Metric.bubblePadH)
        .padding(.vertical, BP.Metric.bubblePadV)
        .background {
            BPBubbleShape(tail: tail)
                .fill(Hue.surface)
        }
        .overlay {
            BPBubbleShape(tail: tail)
                .strokeBorder(BP.hairline, lineWidth: BP.Metric.bubbleBorder)
        }
        // A reacting bubble swaps its whole line — animate the swap, and re-type.
        .id(String(content.characters))
        .transition(.opacity.combined(with: .offset(y: 4)))
        .accessibilityElement()
        .accessibilityLabel(String(content.characters))
    }

    private var state: TypewriterState {
        if reduceMotion || !typing { return .shown }
        return .writing
    }
}

// MARK: - Outline

/// A rounded rect with a triangular tail, drawn as one closed path so a stroke runs
/// continuously around the notch.
struct BPBubbleShape: InsettableShape {
    var tail: BPBubbleTail = .leading
    var radius: CGFloat = BP.Metric.bubbleRadius
    var tailSize: CGFloat = BP.Metric.bubbleTail
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> BPBubbleShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let rad = min(radius, min(r.width, r.height) / 2)
        let t = tailSize
        var p = Path()

        // Half-width of the tail's base along the edge it sits on.
        let base = t * 0.75

        switch tail {
        case .leading(let frac):
            let mid = r.minY + r.height * min(max(frac, 0), 1)
            let top = min(max(mid - base, r.minY + rad), r.maxY - rad - base * 2)
            let bot = top + base * 2

            p.move(to: CGPoint(x: r.minX + rad, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - rad, y: r.minY))
            p.addArc(center: CGPoint(x: r.maxX - rad, y: r.minY + rad), radius: rad,
                     startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - rad))
            p.addArc(center: CGPoint(x: r.maxX - rad, y: r.maxY - rad), radius: rad,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            p.addLine(to: CGPoint(x: r.minX + rad, y: r.maxY))
            p.addArc(center: CGPoint(x: r.minX + rad, y: r.maxY - rad), radius: rad,
                     startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            // Up the left edge, out through the tail, and on up.
            p.addLine(to: CGPoint(x: r.minX, y: bot))
            p.addLine(to: CGPoint(x: r.minX - t, y: (top + bot) / 2))
            p.addLine(to: CGPoint(x: r.minX, y: top))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + rad))
            p.addArc(center: CGPoint(x: r.minX + rad, y: r.minY + rad), radius: rad,
                     startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)

        case .bottom(let frac):
            let mid = r.minX + r.width * min(max(frac, 0), 1)
            let left = min(max(mid - base, r.minX + rad), r.maxX - rad - base * 2)
            let right = left + base * 2

            p.move(to: CGPoint(x: r.minX + rad, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - rad, y: r.minY))
            p.addArc(center: CGPoint(x: r.maxX - rad, y: r.minY + rad), radius: rad,
                     startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - rad))
            p.addArc(center: CGPoint(x: r.maxX - rad, y: r.maxY - rad), radius: rad,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            // Along the bottom edge, down through the tail, and on.
            p.addLine(to: CGPoint(x: right, y: r.maxY))
            p.addLine(to: CGPoint(x: (left + right) / 2, y: r.maxY + t))
            p.addLine(to: CGPoint(x: left, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX + rad, y: r.maxY))
            p.addArc(center: CGPoint(x: r.minX + rad, y: r.maxY - rad), radius: rad,
                     startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + rad))
            p.addArc(center: CGPoint(x: r.minX + rad, y: r.minY + rad), radius: rad,
                     startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }

        p.closeSubpath()
        return p
    }
}
