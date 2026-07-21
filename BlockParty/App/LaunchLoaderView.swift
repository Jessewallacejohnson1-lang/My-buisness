//
//  LaunchLoaderView.swift
//  Block Party — the launch loader (Pinterest-style "breathing" bloom).
//
//  Ported frame-by-frame from a reference recording of the Pinterest app's launch
//  loader: a centred brand mark that scale-pulses while a scatter of little icons
//  BURSTS out from behind it, holds, then fades + shrinks in place — looping on a
//  ~0.8s heartbeat. We keep the motion 1:1 and swap only the two things that are
//  ours: the centre mark (the Block Party framed wordmark) and the five icons.
//
//  Measured model (source: scratchpad MODEL.md):
//   - period ~0.80s, looping
//   - trough: icons gone (collapsed to mark centre), mark at 0.61 scale + dimmed
//   - rise  (emanate): icons grow + travel centre→peak + fade in; mark 0.61→1 (fast)
//   - hold  : near full
//   - fall  (dissipate): icons fade + shrink IN PLACE (no retract); mark 1→0.61
//   Motion is asymmetric — that asymmetry is the signature, so it is preserved here.
//
//  The five icons keep their own colour — they are *content* (like photography and
//  the map basemap), the deliberate colour exception to the monochrome chrome. The
//  palette is local to this file (LoaderIconColor), never a reusable chrome token.
//

import SwiftUI

// MARK: - Tunable model

/// Everything the ss-loop tunes lives here — timings as cycle fractions (0 = trough),
/// positions/sizes as fractions of the screen. Keeping them in one place makes the
/// frame-match iteration a matter of nudging numbers, not restructuring the view.
private enum Loader {
    /// Full loop length. Troughs measured 784–833 ms apart → 0.80 s.
    static let period: Double = 0.80

    // Centre mark — the Block Party framed wordmark (analog of Pinterest's red P).
    static let markCenter = UnitPoint(x: 0.50, y: 0.49)   // frac of screen
    static let markSide: CGFloat = 0.30                    // frac of screen WIDTH (square)
    static let markScaleTrough: Double = 0.61              // shrinks to this at the trough
    static let markOpacityTrough: Double = 0.78            // dims to this at the trough
    static let markRiseEnd: Double = 0.25                  // reaches full scale by here (gradual)
    static let markFallStart: Double = 0.80                // starts shrinking here

    // Icon envelope (shared by all five; they burst together).
    static let iconRiseEnd: Double = 0.52    // peak spread + scale reached here
    static let iconHoldEnd: Double = 0.68     // fade-out begins here (reference softens early)
    static let iconOpacityInStart: Double = 0.0   // become visible from the very first beat
    static let iconOpacityInEnd: Double = 0.24
    static let iconScaleFallEnd: Double = 0.45 // shrink-in-place floor (opacity hits 0 anyway)
    static let iconBaseSize: CGFloat = 0.115   // frac of screen WIDTH

    /// The five icons at their PEAK scatter (fractions of the screen), mapped from the
    /// reference layout to the nearest-colour Pinterest position so the palette lands
    /// where the eye expects it.
    static let icons: [LoaderIcon] = [
        LoaderIcon(kind: .run,     color: .orange, peak: UnitPoint(x: 0.42, y: 0.22), sizeMul: 1.00), // top
        LoaderIcon(kind: .book,    color: .green,  peak: UnitPoint(x: 0.64, y: 0.25), sizeMul: 1.00), // top-right
        LoaderIcon(kind: .yoga,    color: .purple, peak: UnitPoint(x: 0.24, y: 0.315), sizeMul: 1.02), // left
        LoaderIcon(kind: .truck,   color: .red,    peak: UnitPoint(x: 0.49, y: 0.335), sizeMul: 1.15), // centre
        LoaderIcon(kind: .market,  color: .yellow, peak: UnitPoint(x: 0.81, y: 0.345), sizeMul: 1.02), // right
    ]
}

/// Local content palette for the launch icons — NOT chrome tokens. These are the
/// reference icon colours; the monochrome system deliberately allows colour only for
/// content (photos, the map), and the launch bloom is a one-off illustrated moment.
private enum LoaderIconColor {
    static let orange = Color(red: 0.937, green: 0.545, blue: 0.235) // runner
    static let green  = Color(red: 0.486, green: 0.667, blue: 0.235) // book
    static let red    = Color(red: 0.937, green: 0.325, blue: 0.314) // truck
    static let purple = Color(red: 0.612, green: 0.529, blue: 0.831) // yoga
    static let yellow = Color(red: 0.949, green: 0.792, blue: 0.267) // market
}

private enum IconColorKey { case orange, green, red, purple, yellow
    var color: Color {
        switch self {
        case .orange: return LoaderIconColor.orange
        case .green:  return LoaderIconColor.green
        case .red:    return LoaderIconColor.red
        case .purple: return LoaderIconColor.purple
        case .yellow: return LoaderIconColor.yellow
        }
    }
}

private enum IconKind { case run, book, yoga, truck, market }

private struct LoaderIcon: Identifiable {
    let id = UUID()
    let kind: IconKind
    let color: IconColorKey
    let peak: UnitPoint
    let sizeMul: CGFloat
}

// MARK: - The view

struct LaunchLoaderView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Animation anchor. Date() is fine in app code (only Workflow scripts ban it).
    private let start = Date()

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Hue.paper   // warm-white — the on-brand equal of the reference's white

                if reduceMotion {
                    // Static bloom — mark full, icons at rest. No heartbeat under RM.
                    content(phase: reducedMotionPhase, size: size)
                } else {
                    TimelineView(.animation) { tl in
                        content(phase: phase(at: tl.date), size: size)
                    }
                }
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }

    /// A phase that renders the icons at full spread but skips motion, for Reduce Motion.
    private var reducedMotionPhase: Double { Loader.iconRiseEnd }

    private func phase(at date: Date) -> Double {
        let elapsed = date.timeIntervalSince(start)
        let p = (elapsed / Loader.period).truncatingRemainder(dividingBy: 1)
        return p < 0 ? p + 1 : p
    }

    @ViewBuilder
    private func content(phase: Double, size: CGSize) -> some View {
        let W = size.width, H = size.height
        let center = CGPoint(x: Loader.markCenter.x * W, y: Loader.markCenter.y * H)

        ZStack {
            // Icons first so the mark sits over them where they overlap at the trough.
            ForEach(Loader.icons) { icon in
                let f = LoaderMotion.iconFrame(peak: point(icon.peak, W, H),
                                               center: center, phase: phase)
                iconView(icon, side: Loader.iconBaseSize * W * icon.sizeMul)
                    .scaleEffect(f.scale)
                    .opacity(f.opacity)
                    .position(f.pos)
            }

            let m = LoaderMotion.markFrame(phase: phase)
            BlockPartyMark(side: Loader.markSide * W)
                .scaleEffect(m.scale)
                .opacity(m.opacity)
                .position(center)
        }
        .frame(width: W, height: H)
    }

    private func point(_ u: UnitPoint, _ W: CGFloat, _ H: CGFloat) -> CGPoint {
        CGPoint(x: u.x * W, y: u.y * H)
    }

    @ViewBuilder
    private func iconView(_ icon: LoaderIcon, side: CGFloat) -> some View {
        switch icon.kind {
        case .run:    symbol("figure.run", side: side, color: icon.color.color)
        case .book:   symbol("book.fill", side: side, color: icon.color.color)
        case .yoga:   symbol("figure.mind.and.body", side: side, color: icon.color.color)
        case .market: symbol("storefront.fill", side: side, color: icon.color.color)
        case .truck:  GarbageTruckIcon(color: icon.color.color).frame(width: side, height: side)
        }
    }

    private func symbol(_ name: String, side: CGFloat, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: side, weight: .regular))
            .foregroundStyle(color)
            .frame(width: side, height: side)
    }
}

// MARK: - Motion math (pure, isolation-free)

private struct ElemFrame { var pos: CGPoint = .zero; var scale: Double = 1; var opacity: Double = 1 }

private enum LoaderMotion {
    static func iconFrame(peak: CGPoint, center: CGPoint, phase phi: Double) -> ElemFrame {
        // Position: emanate centre→peak on the rise, then hold at peak (spread clamps
        // to 1). The reset to centre at the wrap is invisible because opacity is ~0 there.
        let spread = easeOutCubic(clamp01(phi / Loader.iconRiseEnd))
        let pos = CGPoint(x: lerp(center.x, peak.x, spread),
                          y: lerp(center.y, peak.y, spread))

        // Scale: grow 0→1 on the rise, hold, then shrink in place on the fall.
        let scale: Double
        if phi <= Loader.iconRiseEnd {
            scale = easeOutCubic(clamp01(phi / Loader.iconRiseEnd))
        } else if phi <= Loader.iconHoldEnd {
            scale = 1
        } else {
            let t = (phi - Loader.iconHoldEnd) / (1 - Loader.iconHoldEnd)
            scale = lerp(1, Loader.iconScaleFallEnd, easeInCubic(clamp01(t)))
        }

        // Opacity: fade in on the rise, hold, then an accelerating fade-out.
        let opacity: Double
        if phi <= Loader.iconOpacityInEnd {
            opacity = smoothstep(Loader.iconOpacityInStart, Loader.iconOpacityInEnd, phi)
        } else if phi <= Loader.iconHoldEnd {
            opacity = 1
        } else {
            // Gentle-then-accelerating fade (easeInQuad), matching the reference's soft
            // start into a fast collapse — easeInCubic held too flat too long.
            let t = (phi - Loader.iconHoldEnd) / (1 - Loader.iconHoldEnd)
            opacity = 1 - easeInQuad(clamp01(t))
        }
        return ElemFrame(pos: pos, scale: scale, opacity: opacity)
    }

    static func markFrame(phase phi: Double) -> ElemFrame {
        let s: Double
        if phi <= Loader.markRiseEnd {
            // Gradual ease-in-out growth (not front-loaded) so the mark swells like the
            // reference logo rather than snapping to full early.
            s = lerp(Loader.markScaleTrough, 1, smoothstep(0, 1, clamp01(phi / Loader.markRiseEnd)))
        } else if phi <= Loader.markFallStart {
            s = 1
        } else {
            let t = (phi - Loader.markFallStart) / (1 - Loader.markFallStart)
            s = lerp(1, Loader.markScaleTrough, easeInCubic(clamp01(t)))
        }
        // Dim slightly with scale so the trough reads as a soft pull-back, echoing the
        // reference logo fading toward pink at its smallest.
        let norm = (s - Loader.markScaleTrough) / (1 - Loader.markScaleTrough)
        let opacity = lerp(Loader.markOpacityTrough, 1, clamp01(norm))
        return ElemFrame(scale: s, opacity: opacity)
    }
}

private func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }
private func easeOutCubic(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
private func easeInCubic(_ t: Double) -> Double { t * t * t }
private func easeInQuad(_ t: Double) -> Double { t * t }
private func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
    let t = clamp01((x - e0) / (e1 - e0))
    return t * t * (3 - 2 * t)
}

// MARK: - Previews

#Preview("Loader") { LaunchLoaderView() }
