//
//  POIMarkers.swift
//  Hygge — the SwiftUI view-annotation markers that replace the retired POILayer's
//  Mapbox style layers. Two leaf views, each owning its OWN animation state so a camera
//  callback writing sibling @State on the map container can never cancel an in-flight
//  spring (the same isolation PulseRing uses in SJMapView):
//
//   • POIClusterMarker — one always-mounted marker per POI, anchored at its TRUE coord.
//     Glides in screen space toward its cluster's seed as it merges, fading + shrinking.
//   • POIClusterBubbleView — the count bubble for a cluster; appears / dissolves / rolls
//     its count.
//
//  Positioning mechanism (proven by _SpikeClusterView's "Mechanism B"): a MapViewAnnotation
//  coordinate is NOT SwiftUI-animatable, so we anchor at the true coord and move the inner
//  view with a screen-space `.offset` = (seedScreen − trueScreen) · t, animating t (0 solo
//  → 1 merged) with a spring. Scale + opacity ride the same t. Under Reduce Motion the
//  transition is instant (opacity/scale only), no glide.
//

import SwiftUI
import CoreLocation
import MapboxMaps

/// Lively, gentle overshoot (~0.4s) — the spring the spike settled on for merge/split.
private let CLUSTER_SPRING = Animation.spring(response: 0.42, dampingFraction: 0.72)

// MARK: - POI marker (leaf; owns its merge/split animation)

struct POIClusterMarker: View {
    let poi: POI
    let assignment: POIAssignment
    let expanded: Bool
    /// Read live each transition to project the true coord + the cluster seed to screen.
    let proxy: MapProxy
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 = solo (rests at its true coord), 1 = fully merged (sits on the cluster seed,
    /// invisible). This leaf's OWN state — isolation is what lets the spring survive the
    /// map's camera callbacks.
    @State private var t: Double = 0

    var body: some View {
        POIBadge(poi: poi, expanded: expanded)
            .scaleEffect(1 - 0.7 * t)
            .opacity(1 - t)
            .offset(mergeOffset)
            // A merged/merging marker is invisible and stacked under the bubble — don't
            // let its 44pt hit target eat the bubble's (or a neighbour's) tap.
            .allowsHitTesting(t < 0.5)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            // First mount reflects the current assignment with NO animation (no fly-in on a
            // cold launch); only later assignment flips glide.
            .onAppear { t = assignment.clustered ? 1 : 0 }
            .onChange(of: assignment.clustered) { _, clustered in
                let target: Double = clustered ? 1 : 0
                if reduceMotion { t = target }
                else { withAnimation(CLUSTER_SPRING) { t = target } }
            }
    }

    /// Screen vector from the POI's true point to its cluster seed, scaled by `t`.
    /// Resolved off the LIVE projection at each transition; the endpoints are exact
    /// (t=0 ⇒ .zero ⇒ Mapbox-pinned true coord; t=1 ⇒ the seed) so a split always lands
    /// on the real pin and a merge always lands on the bubble.
    private var mergeOffset: CGSize {
        guard t > 0, let map = proxy.map else { return .zero }
        let base = map.point(for: poi.coordinate)
        let target = map.point(for: assignment.anchor)
        guard base.x.isFinite, base.y.isFinite, target.x.isFinite, target.y.isFinite else { return .zero }
        return CGSize(width: (target.x - base.x) * t, height: (target.y - base.y) * t)
    }
}

// MARK: - POI badge (visual only — kept close to the retired renderer for Phase A)

/// Family tint (amber food / indigo business) + white glyph. Compact = a small tint dot
/// when zoomed out; expanded (at/above the awake zoom) = a larger disc + glyph + a halo'd
/// name label beside it, mirroring the civic MapPinBadge. Final polish is Phase C.
private struct POIBadge: View {
    let poi: POI
    let expanded: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let expandedDiameter: CGFloat = 26
    private static let compactDiameter: CGFloat = 12
    private var diameter: CGFloat { expanded ? Self.expandedDiameter : Self.compactDiameter }

    var body: some View {
        ZStack {
            Circle()
                .fill(poi.family.tint)
                .frame(width: diameter, height: diameter)
                .overlay(Circle().stroke(Hue.surface, lineWidth: 1.5))
                .mapFloatShadow()
            Image(systemName: poi.glyph)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .opacity(expanded ? 1 : 0)   // too cramped on the compact dot
        }
        .frame(width: diameter, height: diameter)
        // Shrink/expand as a spring so a pinch settles like one physical move.
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.8),
                   value: expanded)
        .overlay(alignment: .leading) {
            HaloText(poi.name, color: poi.family.tint)
                .frame(width: 100, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, Self.expandedDiameter + 5)
                .allowsHitTesting(false)
                .scaleEffect(expanded ? 1 : 0.9, anchor: .leading)
                .opacity(expanded ? 1 : 0)
        }
        // Consistent ≥44pt tap target regardless of the current visual size, centered on
        // the badge so the annotation's coordinate anchor doesn't move.
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(poi.name), \(poi.family.label)")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Cluster count bubble (leaf; owns appear / dissolve / count-roll)

/// Charcoal disc + white count, close to the retired renderer. Scales up + fades in as
/// members merge (`active`), scales down + fades out when the cluster dissolves (`active`
/// false — the container keeps it mounted a beat so the split fades, not pops). The count
/// ROLLS on change (numericText), never a hard cut. Size steps up gently with the count.
struct POIClusterBubbleView: View {
    let count: Int
    let active: Bool
    /// Overlap cap from the clusterer — the disc never draws larger than this, so two
    /// seeds (always > radius apart) can't host bubbles that reach each other.
    let maxDiameter: CGFloat
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Whether the disc is at full scale/opacity. Own state → the appear/dissolve spring
    /// survives the map's camera callbacks.
    @State private var shown = false
    /// The number actually on screen — lags `count` by one animated roll so the digit
    /// change reads as a roll, not a cut.
    @State private var displayCount: Int

    init(count: Int, active: Bool, maxDiameter: CGFloat, onTap: @escaping () -> Void) {
        self.count = count
        self.active = active
        self.maxDiameter = maxDiameter
        self.onTap = onTap
        _displayCount = State(initialValue: count)
    }

    /// Size-by-count, then clamped to the clusterer's overlap cap.
    private var diameter: CGFloat {
        let byCount: CGFloat
        switch displayCount {
        case ..<10:   byCount = 34
        case 10..<25: byCount = 40
        default:      byCount = 46
        }
        return min(byCount, maxDiameter)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Hue.mapInk.opacity(0.92))
                .overlay(Circle().stroke(Hue.surface, lineWidth: 2))
                .mapFloatShadow()
            Text("\(displayCount)")
                // Scale the digits to the (possibly capped) disc so a small bubble stays legible.
                .font(.system(size: min(15, diameter * 0.46), weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .frame(width: diameter, height: diameter)
        .animation(reduceMotion ? nil : CLUSTER_SPRING, value: diameter)
        .scaleEffect(shown ? 1 : 0.3)
        .opacity(shown ? 1 : 0)
        .contentShape(Circle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cluster of \(displayCount) places")
        .accessibilityAddTraits(.isButton)
        .onAppear {
            if reduceMotion { shown = active }
            else { withAnimation(CLUSTER_SPRING) { shown = active } }
        }
        .onChange(of: active) { _, isActive in
            if reduceMotion { shown = isActive }
            else { withAnimation(CLUSTER_SPRING) { shown = isActive } }
        }
        .onChange(of: count) { _, newCount in
            if reduceMotion { displayCount = newCount }
            else { withAnimation(.easeInOut(duration: 0.28)) { displayCount = newCount } }
        }
    }
}
