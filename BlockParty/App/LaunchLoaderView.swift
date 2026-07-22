//
//  LaunchLoaderView.swift
//  Block Party — the launch loader (a single bloom, ported from a Pinterest reference).
//
//  A centred app mark grows while five little icons EMANATE from behind it — they
//  travel centre→peak, grow, fade in, and TURN, settling into place together. Then
//  it holds. One pop, not a heartbeat.
//
//  v1 looped this on a ~0.8 s cycle, faithfully reproducing the reference's
//  rise→hold→fall. On a real cold launch that read as the loader "popping twice"
//  before the app appeared, so v2 keeps only the RISE and holds at full. The fall
//  phase is deliberately gone — not commented out, gone; git has it if we ever want
//  the heartbeat back.
//
//  MEASURED FROM THE REFERENCE (504×1050 @ ~57 fps; trough 249 ms → peak 663 ms):
//   - rise = 414 ms, which is `bloomDuration` below. Every other timing here is a
//     fraction of that rise, so the internal ratios are the reference's exactly.
//   - the mark reaches full scale at 0.48 of the rise — noticeably before the icons,
//     which is what makes the mark feel like the source the icons come out of.
//   - icons: they SHOOT out to position (exponential settle) while growing on a
//     slower ease-out cubic — two different curves, see `travel`.
//   - icons ROTATE ~48° into place (see `spinDeg`). This was missing from v1 and is
//     the detail that makes the bloom read as thrown rather than faded-in.
//
//  ROTATION — measured, and where we knowingly diverge:
//  Rotation was recovered by mask template-matching each frame against the icon at
//  the bloom peak (PCA is useless here — the icons are near-isotropic, elongation
//  ~1.04, so their principal axis is undefined). Fits were IoU 0.92–1.00. Every icon
//  emerges rotated ~42–49° counter-clockwise and turns clockwise into its upright
//  orientation at the peak — the same direction and nearly the same amount for all
//  five, so this is one shared gesture, not per-icon confetti.
//  In the reference the turn follows an ease-IN (≈ u³: barely moving early, fastest
//  at the peak) and then keeps going into the fall — it never stops, so it can afford
//  to be at full speed. Ours stops. Reproducing u³ literally would slam the rotation
//  to a halt at full angular velocity. So `settle` below keeps the reference's
//  signature — the turn LAGS the travel — while arriving at zero velocity.
//

import SwiftUI

// MARK: - Tunable model

/// Everything the ss-loop tunes lives here — timings as fractions of the bloom
/// (0 = launch, 1 = full), positions/sizes as fractions of the screen.
private enum Loader {
    /// The reference's rise, measured trough→peak (249 ms → 663 ms).
    static let bloomDuration: Double = 0.414

    /// A held beat before the bloom starts.
    ///
    /// iOS cross-fades the app in over its launch screen, measured here at ~160 ms
    /// (2740→2900 ms in a cold-launch capture). Without this delay the bloom runs
    /// underneath that fade: the icons have already shot most of the way out by the
    /// time the screen is fully opaque, so the emanation — the whole point — is spent
    /// on an invisible frame. Holding at p=0 shows a still, small mark through the
    /// fade and starts the bloom once the app is actually on screen.
    static let startDelay: Double = 0.32

    // Centre mark — the app icon (see LoaderBlockPartyMark).
    /// Measured centre of the reference logo, not the screen centre — it sits a hair
    /// right of and below dead centre.
    static let markCenter = UnitPoint(x: 0.505, y: 0.492)  // frac of screen
    /// Frac of screen WIDTH for the icon PLATE — sized so the INK inside it matches the
    /// reference logo's extent.
    ///
    /// The reference logo spans 0.252·W (127 px of 504, and the earlier measurement pass
    /// recorded the same figure). What the eye compares is the ink, not the white plate
    /// it sits on, and `LaunchMark`'s ink occupies 0.751 of the asset — so the plate has
    /// to be 0.252/0.751 to land the ink on the reference. At the previous 0.30 the ink
    /// measured 0.225·W in a screenshot: an 11% under-size against the target.
    static let markSide: CGFloat = 0.252 / BlockPartyMark.inkFraction
    static let markScaleStart: Double = 0.61               // starts here, grows to 1
    static let markFullAt: Double = 0.48                   // full scale at 0.48 of the bloom

    // Icon envelope (shared by all five; they bloom together).
    static let iconBaseSize: CGFloat = 0.115               // frac of screen WIDTH

    /// The five icons at their settled position (fractions of the screen), mapped from
    /// the reference layout to the nearest-colour position so the palette lands where
    /// the eye expects it. `spinDeg` is the measured angle each emerges at, in degrees
    /// counter-clockwise from its settled orientation.
    ///
    /// Peaks are the measured centroids of each reference shape, not the rounded figures
    /// carried over from v1 — the clover in particular sat 0.015·W left of where it
    /// belongs. Recovered by classifying pixels on their deviation-from-white DIRECTION,
    /// which is opacity-invariant (compositing over white scales that vector uniformly,
    /// so anti-aliased edge pixels keep their hue and a fading shape does not drift).
    static let icons: [LoaderIcon] = [
        LoaderIcon(kind: .run,    color: .orange, peak: UnitPoint(x: 0.417, y: 0.215), sizeMul: 1.00, spinDeg: 45), // top
        LoaderIcon(kind: .book,   color: .green,  peak: UnitPoint(x: 0.655, y: 0.251), sizeMul: 1.00, spinDeg: 43), // top-right
        LoaderIcon(kind: .yoga,   color: .purple, peak: UnitPoint(x: 0.248, y: 0.317), sizeMul: 1.02, spinDeg: 42), // left
        LoaderIcon(kind: .truck,  color: .red,    peak: UnitPoint(x: 0.495, y: 0.332), sizeMul: 1.15, spinDeg: 49), // centre
        LoaderIcon(kind: .market, color: .yellow, peak: UnitPoint(x: 0.818, y: 0.343), sizeMul: 1.02, spinDeg: 43), // right
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
    /// Degrees counter-clockwise from settled that this icon emerges at.
    let spinDeg: Double
}

// MARK: - The view

/// Holds the moment the loader was first actually drawn.
///
/// A plain `let start = Date()` anchors to view *init*, which on a cold launch runs
/// well before the first frame reaches the screen — measured ~80 ms early here. The
/// bloom then burns that time invisibly and the user joins it already in progress.
/// A reference type lets the first timeline tick record itself without invalidating
/// the view the way writing to @State from `body` would.
private final class BloomClock { var firstFrame: Date? }

struct LaunchLoaderView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Animation anchor, set by the first rendered frame. Date() is fine in app code
    /// (only Workflow scripts ban it).
    @State private var clock = BloomClock()
    /// Once the bloom has landed there is nothing left to animate, so the timeline is
    /// paused rather than left ticking behind a still image for the rest of the wait.
    @State private var bloomDone = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Hue.paper   // warm-white — the on-brand equal of the reference's white

                if reduceMotion {
                    // Reduce Motion gets the landed frame: no growth, no travel, no spin.
                    content(p: 1, size: size)
                } else {
                    TimelineView(.animation(minimumInterval: nil, paused: bloomDone)) { tl in
                        content(p: progress(at: tl.date), size: size)
                    }
                    .task {
                        // Pausing must never truncate the bloom, so the deadline is
                        // derived from the clock's real anchor rather than from when
                        // this task happened to start — on a slow launch (exactly when
                        // this loader matters most) those can be far apart. Sleep the
                        // nominal span, then top up with whatever the anchor says is
                        // still owed. Converges: after the first sleep it is anchored.
                        var remaining = Loader.startDelay + Loader.bloomDuration + 0.05
                        while remaining > 0 {
                            try? await Task.sleep(for: .seconds(remaining))
                            guard let anchor = clock.firstFrame else { break }
                            remaining = anchor
                                .addingTimeInterval(Loader.startDelay + Loader.bloomDuration + 0.05)
                                .timeIntervalSinceNow
                        }
                        bloomDone = true
                    }
                }
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }

    /// 0 → 1 across the bloom, then pinned at 1. No wrap: this is a one-shot.
    ///
    /// Held at 0 for `startDelay` first, so the bloom does not play underneath the
    /// system's launch cross-fade (see `Loader.startDelay`).
    private func progress(at date: Date) -> Double {
        let anchor = clock.firstFrame ?? date
        if clock.firstFrame == nil { clock.firstFrame = date }
        let elapsed = date.timeIntervalSince(anchor) - Loader.startDelay
        return clamp01(elapsed / Loader.bloomDuration)
    }

    @ViewBuilder
    private func content(p: Double, size: CGSize) -> some View {
        let W = size.width, H = size.height
        let center = CGPoint(x: Loader.markCenter.x * W, y: Loader.markCenter.y * H)

        ZStack {
            // Icons first so the mark covers them where they overlap early on — they
            // must read as coming out from BEHIND the mark.
            ForEach(Loader.icons) { icon in
                let f = LoaderMotion.iconFrame(peak: point(icon.peak, W, H),
                                               center: center, spinDeg: icon.spinDeg, p: p)
                iconView(icon, side: Loader.iconBaseSize * W * icon.sizeMul)
                    .rotationEffect(.degrees(f.rotation))
                    .scaleEffect(f.scale)
                    .position(f.pos)
            }

            BlockPartyMark(side: Loader.markSide * W)
                .scaleEffect(LoaderMotion.markFrame(p: p).scale)
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

private struct ElemFrame {
    var pos: CGPoint = .zero
    var scale: Double = 1
    var rotation: Double = 0
}

private enum LoaderMotion {
    /// NOTHING IN THIS BLOOM FADES. Both the icons and the mark hold full opacity the
    /// whole way through, which is measured, not assumed: sampling the reference's
    /// darkest core pixel and inverting the composite-over-white equation puts the
    /// pushpin at 96% opacity on its very FIRST visible frame, and the logo at 100%
    /// from the trough onward.
    ///
    /// The earlier model described the icons as fading in over the first ~46% of the
    /// rise. That was reading occlusion as transparency — the icons start behind the
    /// mark and are simply hidden until they clear it. The arithmetic agrees: the
    /// truck's peak sits 0.069 screen-heights above the mark's top edge, which
    /// `travel` crosses at u = 0.082 — the same u where the reference's pushpin first
    /// appears. Fading them in on top of that made them ghostly through the exact part
    /// of the bloom where the reference is already solid.
    static func iconFrame(peak: CGPoint, center: CGPoint, spinDeg: Double, p: Double) -> ElemFrame {
        // Travel and growth are NOT the same curve — see `travel` vs `easeOutCubic`.
        let pos = CGPoint(x: lerp(center.x, peak.x, travel(p)),
                          y: lerp(center.y, peak.y, travel(p)))
        // Negative = counter-clockwise, unwinding to 0 as the icon lands.
        let rotation = -spinDeg * (1 - settle(p))
        return ElemFrame(pos: pos, scale: easeOutCubic(p), rotation: rotation)
    }

    static func markFrame(p: Double) -> ElemFrame {
        // Gradual ease-in-out growth (not front-loaded) so the mark swells like the
        // reference logo rather than snapping to full early.
        let s = lerp(Loader.markScaleStart, 1, smoothstep(0, 1, clamp01(p / Loader.markFullAt)))
        return ElemFrame(scale: s)
    }

    /// How far an icon has travelled centre→peak.
    ///
    /// This is deliberately NOT the same curve as its growth. Measured on the
    /// reference, the icons are ~44% of the way out at 8% of the rise and ~88% out by
    /// 28%, while their scale over the same span only reaches 29% and 69%. So they
    /// SHOOT to position and then keep swelling in place — that mismatch is what makes
    /// the bloom read as thrown rather than zoomed. v1 drove both off one ease-out
    /// cubic, which left the travel visibly lagging (22% vs 44% at u=0.08).
    ///
    /// An exponential settle fits the measurements to within ~2 points across the rise
    /// (k = 7.2, i.e. τ ≈ 58 ms). Normalised so it lands exactly on the peak, since a
    /// raw exponential never quite arrives.
    private static func travel(_ u: Double) -> Double {
        let k = 7.2
        return (1 - exp(-k * u)) / (1 - exp(-k))
    }

    /// The rotation curve: slow to start (so the turn LAGS the travel, as the
    /// reference does), then arriving at zero angular velocity so the hold is still.
    /// Squaring before the smoothstep is what buys the lag; the smoothstep is what
    /// buys the soft landing.
    private static func settle(_ u: Double) -> Double { smoothstep(0, 1, u * u) }
}

private func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }
private func easeOutCubic(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
private func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
    let t = clamp01((x - e0) / (e1 - e0))
    return t * t * (3 - 2 * t)
}

// MARK: - Previews

#Preview("Loader") { LaunchLoaderView() }
