//
//  LoaderGarbageTruckIcon.swift
//  Block Party — the one launch icon with no clean SF Symbol: a garbage truck.
//
//  A flat side-view silhouette (facing left) matching the reference icon's chunky
//  style: low cab up front, tall body, three vertical slats, a slanted rear hopper,
//  and two wheels. Drawn in a Canvas over a 0–100 design grid so it scales to any
//  size, with the window / slats / hubs punched as true transparency (destinationOut)
//  so it reads correctly whatever sits behind it.
//

import SwiftUI

struct GarbageTruckIcon: View {
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let s = size.width
            func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x / 100 * s, y: y / 100 * s) }
            func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
                Path(roundedRect: CGRect(x: x / 100 * s, y: y / 100 * s, width: w / 100 * s, height: h / 100 * s),
                     cornerRadius: r / 100 * s, style: .continuous)
            }

            // --- solid silhouette (color) ---
            var solid = Path()
            solid.addPath(R(29, 24, 52, 46, 7))     // tall body / container
            solid.addPath(R(7, 43, 28, 27, 6))      // low cab up front (left)
            // rear hopper — a slanted block jutting off the back (right)
            var hopper = Path()
            hopper.move(to: P(78, 38)); hopper.addLine(to: P(94, 45))
            hopper.addLine(to: P(91, 74)); hopper.addLine(to: P(76, 70)); hopper.closeSubpath()
            solid.addPath(hopper)
            ctx.fill(solid, with: .color(color))

            // wheels — discs sitting below the chassis
            let wheels = Path { p in
                p.addEllipse(in: CGRect(x: 15 / 100 * s, y: 63 / 100 * s, width: 22 / 100 * s, height: 22 / 100 * s))
                p.addEllipse(in: CGRect(x: 50 / 100 * s, y: 63 / 100 * s, width: 22 / 100 * s, height: 22 / 100 * s))
            }
            ctx.fill(wheels, with: .color(color))

            // --- cutouts (true transparency) ---
            ctx.blendMode = .destinationOut

            // windshield — a raked quad in the cab
            var glass = Path()
            glass.move(to: P(12, 48)); glass.addLine(to: P(26, 48))
            glass.addLine(to: P(23, 60)); glass.addLine(to: P(12, 60)); glass.closeSubpath()
            ctx.fill(glass, with: .color(.black))

            // three vertical slats on the body
            var slats = Path()
            for x in [CGFloat(40), 51, 62] { slats.addPath(R(x, 31, 5, 30, 2.4)) }
            ctx.fill(slats, with: .color(.black))

            // wheel hubs
            let hubs = Path { p in
                p.addEllipse(in: CGRect(x: 22 / 100 * s, y: 70 / 100 * s, width: 8 / 100 * s, height: 8 / 100 * s))
                p.addEllipse(in: CGRect(x: 57 / 100 * s, y: 70 / 100 * s, width: 8 / 100 * s, height: 8 / 100 * s))
            }
            ctx.fill(hubs, with: .color(.black))
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    ZStack {
        Hue.paper.ignoresSafeArea()
        GarbageTruckIcon(color: Color(red: 0.937, green: 0.325, blue: 0.314))
            .frame(width: 200, height: 200)
    }
}
