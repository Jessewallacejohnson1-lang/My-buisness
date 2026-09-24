//
//  FeedActionGlyphs.swift
//  Block Party — the Town feed's heart, comment and send marks.
//
//  Drawn rather than taken from SF Symbols, like `BarGlyphs`: Jesse's reference set
//  (2026-09-24) is a round-capped monoline family — a full-circle bubble with a
//  short tail, and a folded paper plane pointing down — and no SF symbol is either
//  silhouette. All three are authored on one 24-unit grid with one stroke weight,
//  traced off the reference at 0.1 unit per px, so they read as one family.
//

import SwiftUI

enum FeedActionGlyph {
    case heart
    case comment
    case send

    /// Stroke weight as a fraction of the glyph's box (2.2 of 24 units).
    static let strokeFraction: CGFloat = 2.2 / 24
}

struct FeedActionGlyphView: View {
    let glyph: FeedActionGlyph
    var size: CGFloat = 24
    /// Fills the shape as well as stroking it — the liked heart.
    var filled = false

    var body: some View {
        let shape = FeedActionGlyphShape(glyph: glyph)
        ZStack {
            if filled { shape.fill() }
            shape.stroke(style: StrokeStyle(
                lineWidth: size * FeedActionGlyph.strokeFraction,
                lineCap: .round,
                lineJoin: .round
            ))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

nonisolated struct FeedActionGlyphShape: Shape {
    let glyph: FeedActionGlyph

    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 24
        let origin = CGPoint(
            x: rect.midX - 12 * unit,
            y: rect.midY - 12 * unit
        )
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * unit, y: origin.y + y * unit)
        }

        var path = Path()
        switch glyph {
        case .heart:
            // Two lobe arcs meeting in a cusp at the notch, straight flanks to a
            // point. Angles are y-down, so increasing runs visually clockwise.
            path.move(to: p(12, 21))
            path.addLine(to: p(3.1, 12.6))
            path.addArc(center: p(6.8, 8.4), radius: 5.6 * unit,
                        startAngle: .degrees(131), endAngle: .degrees(337), clockwise: false)
            path.addArc(center: p(17.2, 8.4), radius: 5.6 * unit,
                        startAngle: .degrees(203), endAngle: .degrees(409), clockwise: false)
            path.closeSubpath()

        case .comment:
            // A near-full circle, its gap bridged by a tail out to the lower right.
            path.addArc(center: p(11.7, 11.5), radius: 10.2 * unit,
                        startAngle: .degrees(59), endAngle: .degrees(391), clockwise: false)
            path.addLine(to: p(22.2, 22.4))
            path.closeSubpath()

        case .send:
            // A downward paper plane: rounded triangle, its left edge folded in at
            // the kink, with the fold line running up toward the far corner. Its
            // corners overshoot the ink box because the rounding pulls acute
            // corners well inward — this is what matches the heart's width.
            let kink = p(7.2, 11.4)
            let topLeft = p(0.8, 2.6)
            let topRight = p(23.4, 2.6)
            let bottom = p(11.4, 22.6)
            let corner = 1.4 * unit
            path.move(to: p(16.8, 6.2))
            path.addLine(to: kink)
            path.addArc(tangent1End: topLeft, tangent2End: topRight, radius: corner)
            path.addArc(tangent1End: topRight, tangent2End: bottom, radius: corner)
            path.addArc(tangent1End: bottom, tangent2End: kink, radius: corner)
            path.addLine(to: kink)
        }
        return path
    }
}
