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
    /// Granted by the clusterer's label de-confliction pass — false when this POI's name
    /// would collide with a civic landmark, a cluster bubble, another badge, or a label
    /// that was granted first. The badge always draws; only the text is withheld.
    let showsLabel: Bool
    /// Read live each transition to project the true coord + the cluster seed to screen.
    let proxy: MapProxy
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 = solo (rests at its true coord), 1 = fully merged (sits on the cluster seed,
    /// invisible). This leaf's OWN state — isolation is what lets the spring survive the
    /// map's camera callbacks.
    @State private var t: Double = 0

    var body: some View {
        POIBadge(poi: poi, expanded: expanded, showsLabel: showsLabel)
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
/// name label beside it, mirroring the civic MapPinBadge. The label additionally needs a
/// de-confliction grant (`showsLabel`) so dense blocks don't turn into overlapping text.
private struct POIBadge: View {
    let poi: POI
    let expanded: Bool
    let showsLabel: Bool

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
                .opacity(expanded && showsLabel ? 1 : 0)
        }
        // Fade a label in/out as the de-confliction pass grants or withdraws it (a zoom
        // step can free up room), so text never pops.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: showsLabel)
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

/// A LIGHT disc: a translucent (but NOT appearance-adaptive — see the fill) surface + a
/// dominant-category tint wash + a thin category ring + a soft shadow for depth, with the
/// count in map ink. It replaces the old
/// flat charcoal disc, which read as a heavy black blob dropped on a pale map and shared no
/// visual language with the pins it stands for. Now a cluster reads as the same family as
/// the pins inside it — same category palette, same surface ring, same float shadow — just
/// aggregated.
///
/// Scales up + fades in as members merge (`active`), scales down + fades out when the
/// cluster dissolves (`active` false — the container keeps it mounted a beat so the split
/// fades, not pops). The count ROLLS on change (numericText), never a hard cut.
struct POIClusterBubbleView: View {
    let count: Int
    let active: Bool
    /// Tints the wash + ring, so a bubble hints at what's inside it.
    let family: PlaceFamily
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

    init(count: Int, active: Bool, family: PlaceFamily, maxDiameter: CGFloat, onTap: @escaping () -> Void) {
        self.count = count
        self.active = active
        self.family = family
        self.maxDiameter = maxDiameter
        self.onTap = onTap
        _displayCount = State(initialValue: count)
    }

    /// Size-by-count, clamped to the clusterer's overlap cap. Defined in `POICluster` so the
    /// label de-confliction pass reserves the exact box this draws.
    private var diameter: CGFloat {
        POICluster.bubbleDiameter(count: displayCount, maxDiameter: maxDiameter)
    }

    var body: some View {
        ZStack {
            Circle()
                // Translucent light fill — the basemap reads faintly through it, so the
                // bubble sits ON the map rather than punching a hole in it.
                //
                // NOT `.regularMaterial`: that is appearance-adaptive, and this app is
                // light-only by construction (every Hue token is a fixed light hex, the
                // basemap is light-v11 recoloured to a fixed cream palette, and nothing sets
                // preferredColorScheme). Under iOS Dark Mode a material would resolve DARK,
                // putting near-black `mapInk` digits on a near-black disc over a cream map —
                // the count, which is the bubble's whole payload, would vanish. A fixed
                // surface fill is scheme-independent, like the charcoal disc it replaces.
                // 0.95, not 0.90: at 0.90 the POI badges stacked underneath GHOSTED through a
                // big bubble as a pale disc-inside-a-disc smudge. Still translucent enough to
                // sit on the map rather than punch a hole in it.
                .fill(Hue.surface.opacity(0.95))
                // Dominant-category wash — a whisper. The ring, not the fill, carries the
                // category; a heavier wash turns the disc into a colour chip (indigo washed
                // over cream reads lavender) instead of a light disc with a coloured edge.
                .overlay(Circle().fill(family.tint.opacity(0.07)))
                // Category ring — the bubble's category signal, and what makes it read as
                // Apple-style cluster chrome. 1.8pt rather than 1.5: a ring is a FIXED width
                // on a disc whose size varies 22→44pt, so the thinnest-looking bubble is the
                // smallest one — and a 22pt "2" was measurably QUIETER than a single solid
                // rest dot beside it. The extra weight lands hardest where it was needed.
                .overlay(Circle().strokeBorder(family.tint.opacity(0.9), lineWidth: 1.8))
                // Deeper than the pins' float shadow ON PURPOSE: a bubble stands for many
                // places, so it must sit ABOVE the individual rest dots around it. With the
                // pale fill and the pins' lighter shadow it read as the quieter element —
                // an inverted hierarchy.
                .shadow(color: Hue.mapInk.opacity(0.22), radius: 5, x: 0, y: 2)
            Text("\(displayCount)")
                // Scale the digits to the (possibly capped) disc, with an 11pt floor so the
                // SMALLEST bubble — the most common one at street zoom — stays legible.
                .font(.system(size: max(11, min(17, diameter * 0.46)), weight: .bold))
                .monospacedDigit()
                // Ink, not white — the disc is light now. ~13:1 against the surface fill.
                .foregroundStyle(Hue.mapInk)
                .contentTransition(.numericText())
        }
        // The dominant family can flip (amber ⇄ indigo) when membership shifts across a
        // near-tie, so the wash + ring must CROSS-FADE, not cut. Phase A's whole thesis is
        // "nothing snaps"; MapPinBadge animates its own tint changes for the same reason.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: family)
        .frame(width: diameter, height: diameter)
        .animation(reduceMotion ? nil : CLUSTER_SPRING, value: diameter)
        .scaleEffect(shown ? 1 : 0.3)
        .opacity(shown ? 1 : 0)
        .contentShape(Circle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        // Just the count: `family` is the DOMINANT family, which on an exact tie falls back
        // to the seed's — so "mostly Food & Drink" would be a claim the data doesn't support.
        // The tint is a visual hint; the spoken label stays factual.
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
