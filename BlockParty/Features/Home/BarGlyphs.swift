//
//  BarGlyphs.swift
//  Block Party — the Today bar's two traced marks: the search magnifier and the
//  notifications bell.
//
//  Both are drawn rather than taken from SF Symbols, for the same reason `MapPinGlyph`
//  next door is: the reference's marks and Apple's are different SILHOUETTES, not the
//  same shape at a different weight. Measured against the reference
//  (`refs/chrome/REFERENCE-SPEC.md`, scanned at native 3x):
//
//    • `magnifyingglass` @regular carries no inner arc at all, and its stroke is
//      0.264 of the lens radius against the reference's 0.176 — half again as heavy.
//    • `bell` @regular has a crown nub the reference lacks, and its skirt FLARES
//      continuously (half-width 54.5 → 68.2 px over 20 px of descent) where the
//      reference's wall is dead vertical at 19.87 px until it splays in the last
//      fifth.
//
//  No symbol weight or scale turns one into the other, which is exactly the test the
//  `MapPinShape` comment applies.
//
//  Both follow that shape's idiom too: every proportion is expressed in ONE
//  normalising unit, so the mark holds its shape and its stroke ratio at any size,
//  and every subpath belongs to a single `Path` so one stroke renders them all at
//  identical weight.
//

import SwiftUI

// MARK: - Magnifier

/// The search mark: a lens ring, a concentric reflection arc inside it, and a handle
/// at 45°.
///
/// The arc is the detail that rules SF out, and it is genuinely part of the mark —
/// it appears at identical geometry in two independent reference frames, so it is not
/// a transient "searching" state.
struct MagnifierGlyph: View {
    var size: CGFloat = 20

    var body: some View {
        MagnifierShape()
            .stroke(style: StrokeStyle(
                lineWidth: size * MagnifierShape.strokeFraction,
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The magnifier, traced 1:1 off the reference. Unit: the lens ring's CENTRELINE
/// radius `r` (24.19 px = 8.06 pt on the reference).
///
/// The arc's angles are derived rather than read off, because round caps make the
/// rendered ink wider than the path. The scanner reports ink from 357.5° to 103.0°
/// of clock angle; a cap adds `atan((stroke/2) / arcRadius)` = 8.35° at each end, so
/// the path itself runs 5.85° → 94.65°. Authored as 5° → 95°, which reproduces the
/// measured ink to within 0.9°.
nonisolated struct MagnifierShape: Shape {
    /// Stroke weight, in lens radii.
    private static let stroke: CGFloat = 0.176
    /// The reflection arc's radius, in lens radii.
    private static let arcRadius: CGFloat = 0.600
    /// The arc's sweep, as CLOCK angles — 0° is 12 o'clock, increasing clockwise.
    private static let arcStart: CGFloat = 5
    private static let arcEnd: CGFloat = 95
    /// How far the handle's far cap sits from the lens centre, in lens radii, and the
    /// angle it leaves on. 44.80° measured; 45° is what was meant.
    private static let handleReach: CGFloat = 1.874
    private static let handleAngle: CGFloat = 45

    /// Extent from the lens centre toward the handle (including its round cap), and
    /// away from it (the ring's far side).
    private static let extentOut = handleReach * cos(handleAngle * .pi / 180) + stroke / 2
    private static let extentIn = 1 + stroke / 2
    /// Total extent in lens radii. Square, as the reference's ink box is.
    private static let span = extentIn + extentOut

    /// Stroke weight as a fraction of the glyph's box, for the caller.
    static let strokeFraction: CGFloat = stroke / span

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width / Self.span, rect.height / Self.span)
        // The lens sits OFF the box centre: the handle reaches further down-right
        // than the ring reaches up-left.
        let offset = (Self.extentOut - Self.extentIn) / 2
        let centre = CGPoint(x: rect.midX - offset * r, y: rect.midY - offset * r)

        /// A clock angle (0° = 12 o'clock, clockwise) as the angle `addArc` wants.
        /// The view's y runs DOWN, so an increasing angle already travels clockwise
        /// on screen — the same convention `MapPinShape` relies on.
        func clock(_ degrees: CGFloat) -> Angle { .degrees(Double(degrees) - 90) }

        func point(_ clockDegrees: CGFloat, _ radius: CGFloat) -> CGPoint {
            let a = (Double(clockDegrees) - 90) * .pi / 180
            return CGPoint(x: centre.x + CGFloat(cos(a)) * radius * r,
                           y: centre.y + CGFloat(sin(a)) * radius * r)
        }

        var path = Path()
        // The lens ring.
        path.addEllipse(in: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2))

        // The reflection arc, concentric inside it.
        path.move(to: point(Self.arcStart, Self.arcRadius))
        path.addArc(center: centre,
                    radius: Self.arcRadius * r,
                    startAngle: clock(Self.arcStart),
                    endAngle: clock(Self.arcEnd),
                    clockwise: false)

        // The handle. It starts ON the ring's centreline rather than at its outer
        // edge, so the join is buried under the ring instead of leaving a notch
        // where the two strokes meet.
        path.move(to: point(Self.handleAngle + 90, 1))
        path.addLine(to: point(Self.handleAngle + 90, Self.handleReach))
        return path
    }
}

// MARK: - Bell

/// The notifications mark: a domed body on vertical walls that splay into a base bar,
/// with a clapper hanging under it.
///
/// **No badge.** The reference carries none — a colour census over the mark returns
/// only black, white and their antialias neighbours, in both frames — and the app has
/// no notifications feature to badge honestly. A permanently-lit dot over nothing is
/// the "fabricated counts" DESIGN.md bans.
struct BellGlyph: View {
    var size: CGFloat = 21

    var body: some View {
        BellShape()
            .stroke(style: StrokeStyle(
                lineWidth: size * BellShape.strokeFraction,
                lineCap: .round,
                lineJoin: .round
            ))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The bell, traced 1:1 off the reference. Unit: the body's half-width `b`
/// (19.87 px = 6.62 pt on the reference).
///
/// Unusually for a traced glyph there are no eyeballed control points here — five
/// measurements describe the whole outline, and the one curve in it is an exact
/// semicircle. Fit a semicircle of radius `b` centred at the reference's y = 222.47
/// and it predicts the measured outer edge to 0.06 px at y = 215 and 0.10 px at
/// y = 210.
///
/// The one place the first pass got it wrong: the walls do NOT run straight to a base
/// bar that overshoots them. They are vertical to y = 239.8 and then SPLAY outward —
/// centreline half-width 19.87 → 19.98 → 20.84 → 21.87 at y = 238 / 240 / 242 / 244,
/// a clean 0.4725 px per px — meeting the bar at 24.0. The bar's visible "flick" past
/// the wall is the end of that splay, not a separate overhang.
nonisolated struct BellShape: Shape {
    /// Stroke weight, in body half-widths.
    private static let stroke: CGFloat = 0.194
    /// Where the vertical wall stops and the splay begins, below the dome's centre.
    private static let wallLength: CGFloat = 0.871
    /// The base bar's depth below the dome's centre, and its half-length.
    private static let baseY: CGFloat = 1.294
    private static let baseHalf: CGFloat = 1.208
    /// The clapper's radius. A semicircle, centred on the bar.
    private static let clapperRadius: CGFloat = 0.473

    /// Total extents in body half-widths. Taller than it is wide, so HEIGHT binds.
    private static let width = 2 * baseHalf + stroke
    private static let height = 1 + baseY + clapperRadius + stroke

    /// Stroke weight as a fraction of the glyph's SQUARE box — height is what binds,
    /// the same convention `MapPinShape` uses for its own taller-than-wide mark.
    static let strokeFraction: CGFloat = stroke / height

    func path(in rect: CGRect) -> Path {
        let b = min(rect.width / Self.width, rect.height / Self.height)
        // Origin: the dome's centre — the point every other measurement is relative
        // to. It sits one radius plus half a stroke below the ink's top edge.
        let dome = CGPoint(
            x: rect.midX,
            y: rect.midY - Self.height * b / 2 + (1 + Self.stroke / 2) * b
        )
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dome.x + x * b, y: dome.y + y * b)
        }

        var path = Path()
        // Up the left wall, over the dome, down the right wall, out along both splays
        // and back across the bar. One closed subpath — the bar IS the outline's
        // bottom edge, not a separate stroke laid across it.
        path.move(to: point(-1, Self.wallLength))
        path.addLine(to: point(-1, 0))
        path.addArc(center: dome,
                    radius: b,
                    startAngle: .degrees(180),
                    endAngle: .degrees(360),
                    clockwise: false)
        path.addLine(to: point(1, Self.wallLength))
        path.addLine(to: point(Self.baseHalf, Self.baseY))
        path.addLine(to: point(-Self.baseHalf, Self.baseY))
        path.closeSubpath()

        // The clapper: the BOTTOM half of a circle on the bar's centreline. Angles
        // decrease through 90°, which in this y-down space is the bottom.
        path.move(to: point(-Self.clapperRadius, Self.baseY))
        path.addArc(center: point(0, Self.baseY),
                    radius: Self.clapperRadius * b,
                    startAngle: .degrees(180),
                    endAngle: .degrees(0),
                    clockwise: true)
        return path
    }
}

#Preview {
    ZStack {
        Hue.paper.ignoresSafeArea()
        HStack(spacing: 28) {
            MagnifierGlyph(size: 20)
            BellGlyph(size: 21)
            MapPinGlyph(size: 24)
        }
        .foregroundStyle(Hue.ink)
    }
}
