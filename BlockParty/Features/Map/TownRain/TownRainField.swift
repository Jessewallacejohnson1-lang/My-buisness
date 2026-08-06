//
//  TownRainField.swift
//  Block Party — the town-rain overlay: real local brand marks drop past the map.
//
//  Pressing the "Saint Joseph" town pill (or the recenter control — both call
//  `flyHome()`) drops ONE of the town's own business logos into the screen. It falls
//  under the measured gravity and bounces around the field — off the side walls, and
//  off the map sheet's live top edge — until it settles and fades.
//  `TownRainPhysics` owns every number and every rule; this file is only the display
//  link and the drawing.
//
//  WHY A CANVAS: the field re-renders every frame at up to 120 Hz. One `Canvas` is one
//  draw pass, and it stays one draw pass if the burst ever grows past a single ball.
//  The driver is held here as `@StateObject` for the same
//  reason `MapCompass` holds its heading as `@State` — the per-frame publish must not
//  escape into `SJMapView`'s body, or the map re-renders at 120 Hz with it.
//
//  Accessibility: the field is decorative and non-interactive — it never takes a
//  touch (`allowsHitTesting(false)`) and is hidden from VoiceOver. Under Reduce
//  Motion nothing falls at all (house §11), and the press keeps its own haptic +
//  camera fly, so no information is carried by the rain alone.
//

import Combine
import SwiftUI
import UIKit

struct TownRainField: View {

    /// Bumped by the parent on each press. Any change starts a fresh burst.
    let trigger: Int
    /// The map's loaded places; the roster picks which of them may fall.
    let pois: [POI]
    /// The map sheet's live top edge — the surface a ball lands on. `.infinity` before
    /// the sheet has published, which the driver reads as "use the resting floor".
    var floorY: CGFloat = .infinity

    @StateObject private var driver = TownRainDriver()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // NOT `@ObservedObject POILogoCache.shared`: the cache publishes once per arriving
    // logo (~77 times during the map's prefetch) and this view's render path reads
    // none of it — the burst snapshots its marks at press time. Observing it would buy
    // nothing and cost a re-render per logo. It is read directly in `resolvedLogos()`.

    var body: some View {
        GeometryReader { geo in
            Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
                draw(driver.balls, logos: driver.logos, in: context)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: trigger) { _, _ in
                guard !reduceMotion else { return }          // §11: nothing falls
                driver.start(bounds: geo.size, logos: resolvedLogos())
            }
            // The floor follows the sheet frame by frame, so dragging the sheet under a
            // ball in flight changes where it lands — and a ball already resting on it
            // rides up with it.
            .onChange(of: floorY, initial: true) { _, top in driver.floorY = top }
            .onChange(of: reduceMotion) { _, isOn in
                if isOn { driver.stop() }       // §11: honor it mid-burst, not just at press
            }
            .onDisappear { driver.stop() }
        }
        .allowsHitTesting(false)
    }

    /// The roster's marks that have actually loaded, in roster order.
    ///
    /// `TownRainRoster.eligible` only knows whether a place HAS a logo URL, not whether
    /// that image arrived — so a roster whose own marks all failed to fetch would rain
    /// nothing even with plenty of other resolved marks on the map. Hence the second
    /// fallback here, on resolved images rather than URLs. A genuinely cold map still
    /// resolves to nothing and simply doesn't rain, which beats a burst of blank discs.
    private func resolvedLogos() -> [UIImage] {
        let cache = POILogoCache.shared
        let ranked = TownRainRoster.eligible(from: pois).compactMap { cache.resolvedImage(for: $0) }
        if !ranked.isEmpty { return ranked }
        return pois.compactMap { cache.resolvedImage(for: $0) }
    }

    // MARK: Drawing

    /// A ball is the same object the map pin shows, at ball size: the mark filling a
    /// circle, clipped to it so a non-square mark cannot bleed past the edge, over a
    /// white fill (for marks with transparency) and under a hairline keyline.
    private func draw(_ balls: [TownRainBall], logos: [UIImage], in context: GraphicsContext) {
        guard !logos.isEmpty else { return }
        for ball in balls {
            guard let image = logos[safe: ball.logoIndex] else { continue }
            let resolved = context.resolve(Image(uiImage: image))
            var layer = context
            layer.translateBy(x: ball.x, y: ball.y)
            layer.rotate(by: .degrees(ball.angle))

            let radius = ball.size / 2
            let box = CGRect(x: -radius, y: -radius, width: ball.size, height: ball.size)
            let circle = Path(ellipseIn: box)
            // A settled ball fades out where it lies — with walls closing the field it
            // has no edge to leave by.
            layer.opacity = TownRainPhysics.opacity(ball)

            // Drop shadow belongs to the disc, not the mark — filtering the image too
            // would smear a dark halo through any logo with transparency.
            layer.addFilter(.shadow(color: Self.shadowColor, radius: Self.shadowRadius, x: 0, y: Self.shadowY))
            layer.fill(circle, with: .color(Hue.surface))
            layer.addFilter(.shadow(color: .clear, radius: 0))

            // Full-bleed, exactly like `POILogoCircle` on the pins: the curated PNGs
            // are already 256×256 white-padded squares, so filling the circle gives
            // the mark its intended optical size. Insetting it inside a second white
            // ring shrinks it to unreadable at 36 pt and reads as a badge-in-a-badge.
            // The mark is clipped on its OWN copy of the context so the keyline that
            // follows keeps its full width (a stroke inside the clip loses its outer
            // half) — the same relationship `POILogoCircle`'s `.overlay` has.
            var marked = layer
            marked.clip(to: circle)
            marked.draw(resolved, in: box)
            layer.stroke(circle, with: .color(Hue.hairline), lineWidth: Self.edgeWidth)
        }
    }

    private static let edgeWidth: CGFloat = 1

    // A ball IS a map marker, so it takes the marker elevation from `mapMarkerShadow`
    // (spec §8 — black 12%, blur 4, y 1) rather than inventing a fourth shadow. The
    // values are restated rather than called because `GraphicsContext` takes a filter,
    // not a SwiftUI view modifier.
    private static let shadowColor = Color.black.opacity(0.12)
    private static let shadowRadius: CGFloat = 4
    private static let shadowY: CGFloat = 1
}

// MARK: - The display link

/// Steps the emitter once per screen refresh and republishes the balls. One burst per
/// `start(...)`; the link is torn down the moment the last ball leaves so an idle map
/// costs nothing.
@MainActor
final class TownRainDriver: NSObject, ObservableObject {

    @Published private(set) var balls: [TownRainBall] = []
    /// The marks this burst is falling, snapshotted at press time so the set can't
    /// shift under a burst that is already in the air.
    private(set) var logos: [UIImage] = []

    /// The map sheet's live top edge; `.infinity` until it publishes one.
    var floorY: CGFloat = .infinity

    private var emitter: TownRainEmitter?
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var seed: UInt64 = 0

    /// Guards against a hitch (or a backgrounded app) integrating one enormous step
    /// and teleporting every ball through the floor.
    private static let maxStep: CGFloat = 1.0 / 30.0

    func start(bounds: CGSize, logos: [UIImage]) {
        guard bounds.width > 0, bounds.height > 0, !logos.isEmpty else { return }
        seed &+= 1
        self.logos = logos
        emitter = TownRainEmitter(seed: seed, logoCount: logos.count, bounds: bounds)
        balls = []
        lastTimestamp = 0
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        emitter = nil
        balls = []
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard var emitter else { stop(); return }
        let dt: CGFloat
        if lastTimestamp == 0 {
            dt = CGFloat(link.duration)
        } else {
            dt = min(CGFloat(link.timestamp - lastTimestamp), Self.maxStep)
        }
        lastTimestamp = link.timestamp

        emitter = emitter.advanced(by: dt, floorY: floorY.isFinite ? floorY : nil)
        self.emitter = emitter
        balls = emitter.balls

        if emitter.isFinished { stop() }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
