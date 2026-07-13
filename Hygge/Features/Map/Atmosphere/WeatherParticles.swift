//
//  WeatherParticles.swift
//  Hygge — GPU-cheap precip over the map. Snow drifts, rain streaks; fog/overcast
//  get no particles (handled as haze in the palette). Capped counts, non-
//  interactive, decorative. Reduce Motion → a still frame (no TimelineView).
//

import SwiftUI

struct WeatherParticles: View {
    let atmosphere: TownAtmosphere
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Kind { case snow, rain }
    private struct Particle { let x: CGFloat; let phase: CGFloat; let scale: CGFloat; let speed: CGFloat; let sway: CGFloat }

    private var kind: Kind? {
        switch atmosphere.sky {
        case .snow:         return .snow
        case .rain, .storm: return .rain
        default:            return nil
        }
    }

    private var count: Int {
        guard let kind else { return 0 }
        let base = kind == .snow ? 44 : 72
        switch atmosphere.intensity {
        case .light: return Int(Double(base) * 0.6)
        case .heavy: return base + 20
        default:     return base
        }
    }

    // Deterministic scatter (no random at render time; stable across frames).
    private var particles: [Particle] {
        (0..<count).map { i in
            let f = CGFloat(i)
            return Particle(
                x: (f * 0.6180339).truncatingRemainder(dividingBy: 1),
                phase: (f * 0.3542).truncatingRemainder(dividingBy: 1),
                scale: 0.6 + (f * 0.271).truncatingRemainder(dividingBy: 1) * 0.8,
                speed: 0.7 + (f * 0.113).truncatingRemainder(dividingBy: 1) * 0.6,
                sway: (f * 0.197).truncatingRemainder(dividingBy: 1)
            )
        }
    }

    var body: some View {
        Group {
            if kind != nil {
                Group {
                    if reduceMotion {
                        Canvas { ctx, size in draw(ctx: ctx, size: size, t: 0.2) }
                    } else {
                        TimelineView(.animation) { tl in
                            Canvas { ctx, size in
                                draw(ctx: ctx, size: size, t: tl.date.timeIntervalSinceReferenceDate)
                            }
                        }
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .ignoresSafeArea()
                // Weather arrives, it doesn't blink on: fade the field in when the sky
                // flips to precip (Reduce Motion → instant).
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: kind != nil)
    }

    private func draw(ctx: GraphicsContext, size: CGSize, t: TimeInterval) {
        guard let kind else { return }
        let color: Color = kind == .snow
            ? Color.white.opacity(0.85)
            : Color(.sRGB, red: 0.62, green: 0.71, blue: 0.82, opacity: 0.72)  // rain: darker + more opaque so it reads over light ground
        for p in particles {
            let fall = kind == .snow ? 0.05 : 0.22
            let cycle = (CGFloat(t) * p.speed * CGFloat(fall) + p.phase).truncatingRemainder(dividingBy: 1)
            let y = cycle * (size.height + 40) - 20
            let swayX = kind == .snow ? sin((CGFloat(t) * 0.6) + p.sway * 6) * 10 : 0
            let x = p.x * size.width + swayX
            if kind == .snow {
                let r = 1.5 * p.scale
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)), with: .color(color))
            } else {
                var line = Path()
                line.move(to: CGPoint(x: x, y: y))
                line.addLine(to: CGPoint(x: x - 2.5, y: y + 18 * p.scale))   // longer, slightly steeper streak
                ctx.stroke(line, with: .color(color), lineWidth: 1.4)
            }
        }
    }
}
