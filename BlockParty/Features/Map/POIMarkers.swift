//
//  POIMarkers.swift
//  Hygge — the SwiftUI view-annotation markers that replace the retired POILayer's
//  Mapbox style layers. Two leaf views, each owning its OWN animation state so a camera
//  callback writing sibling @State on the map container can never cancel an in-flight
//  spring (the same isolation PulseRing uses in SJMapView):
//
//   • POIClusterMarker — one always-mounted marker per POI, anchored at its TRUE coord.
//     Glides in screen space toward its cluster's seed as it merges, fading + shrinking.
//   • POIClusterBubbleView — the count bubble for a cluster; appears / dissolves / crossfades
//     its count.
//
//  Positioning mechanism (proven by _SpikeClusterView's "Mechanism B"): a MapViewAnnotation
//  coordinate is NOT SwiftUI-animatable, so we anchor at the true coord and move the inner
//  view with a screen-space `.offset` = (seedScreen − trueScreen) · t, animating t (0 solo
//  → 1 merged) with a spring. Scale + opacity ride the same t. Under Reduce Motion the
//  spatial move is removed and the leaf/bubble relationship crossfades.
//

import SwiftUI
import CoreLocation
import MapboxMaps

/// Lively, gentle overshoot (~0.4s) — the spring the spike settled on for merge/split.
/// Shared by POI leaves, civic leaves, and bubbles; never recreate it at a call site.
let CLUSTER_SPRING = Animation.spring(response: 0.42, dampingFraction: 0.72)

// MARK: - Shared marker motion (leaf; owns its merge/split animation)

/// Keeps every POI/civic annotation mounted at its true coordinate and animates only the
/// inner content in screen space. Holding `mergeAnchor` locally is important on split:
/// the incoming solo assignment already points at the marker's own coordinate, so reading
/// that value directly would erase the return path and make the pin pop home in one frame.
struct ClusteredMarkerMotion<Content: View>: View {
    let coordinate: CLLocationCoordinate2D
    let assignment: POIAssignment
    let proxy: MapProxy
    let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 = at the true coordinate, 1 = at the retained cluster anchor.
    @State private var progress: Double = 0
    @State private var visibility: Double = 1
    @State private var mergeAnchor: CLLocationCoordinate2D?

    init(
        coordinate: CLLocationCoordinate2D,
        assignment: POIAssignment,
        proxy: MapProxy,
        @ViewBuilder content: () -> Content
    ) {
        self.coordinate = coordinate
        self.assignment = assignment
        self.proxy = proxy
        self.content = content()
    }

    var body: some View {
        content
            .scaleEffect(reduceMotion ? 1 : 1 - 0.7 * progress)
            .opacity(visibility)
            .offset(reduceMotion ? .zero : mergeOffset)
            // A merged/merging marker is invisible and stacked under the bubble — don't
            // let its 44pt hit target eat the bubble's (or a neighbour's) tap.
            .allowsHitTesting(!assignment.clustered && visibility > 0.5)
            .onAppear {
                mergeAnchor = assignment.anchor
                progress = assignment.clustered ? 1 : 0
                visibility = assignment.clustered ? 0 : 1
            }
            .onChange(of: assignment) { old, new in
                if new.clustered {
                    // On merge, install the destination while the pin is still at progress 0.
                    // On clustered→clustered reassignment the marker is already invisible.
                    mergeAnchor = new.anchor
                } else if !old.clustered {
                    mergeAnchor = new.anchor
                }

                let targetProgress: Double = new.clustered ? 1 : 0
                let targetVisibility: Double = new.clustered ? 0 : 1
                if reduceMotion {
                    // No spatial travel or scaling under Reduce Motion; meaning is retained
                    // as a cross-fade between leaf and bubble.
                    progress = targetProgress
                    withAnimation(Motion.smooth) { visibility = targetVisibility }
                } else {
                    withAnimation(CLUSTER_SPRING) {
                        progress = targetProgress
                        visibility = targetVisibility
                    }
                }
            }
    }

    /// Screen vector from the marker's true point to its retained cluster seed, scaled
    /// by `progress`. On split the old seed is intentionally retained until progress is 0.
    private var mergeOffset: CGSize {
        guard progress > 0, let anchor = mergeAnchor, let map = proxy.map else { return .zero }
        let base = map.point(for: coordinate)
        let target = map.point(for: anchor)
        guard base.x.isFinite, base.y.isFinite, target.x.isFinite, target.y.isFinite else { return .zero }
        return CGSize(width: (target.x - base.x) * progress,
                      height: (target.y - base.y) * progress)
    }
}

// MARK: - POI marker

struct POIClusterMarker: View {
    let poi: POI
    let assignment: POIAssignment
    let expanded: Bool
    let selected: Bool
    /// Granted by the clusterer's label de-confliction pass — false when this POI's name
    /// would collide with a civic landmark, a cluster bubble, another badge, or a label
    /// that was granted first. The badge always draws; only the text is withheld.
    let showsLabel: Bool
    /// Read live each transition to project the true coord + the cluster seed to screen.
    let proxy: MapProxy
    let onTap: () -> Void

    var body: some View {
        ClusteredMarkerMotion(
            coordinate: poi.coordinate,
            assignment: assignment,
            proxy: proxy
        ) {
            POIBadge(poi: poi, expanded: expanded, selected: selected, showsLabel: showsLabel)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
        }
    }
}

// MARK: - Civic marker

/// Civic counterpart to `POIClusterMarker`. The visual badge remains the existing
/// `MapPinBadge`; only the shared outer leaf owns cluster travel/fade state.
struct CivicClusterMarker<Content: View>: View {
    let coordinate: CLLocationCoordinate2D
    let assignment: POIAssignment
    let proxy: MapProxy
    let content: Content

    init(
        coordinate: CLLocationCoordinate2D,
        assignment: POIAssignment,
        proxy: MapProxy,
        @ViewBuilder content: () -> Content
    ) {
        self.coordinate = coordinate
        self.assignment = assignment
        self.proxy = proxy
        self.content = content()
    }

    var body: some View {
        ClusteredMarkerMotion(
            coordinate: coordinate,
            assignment: assignment,
            proxy: proxy
        ) {
            content
        }
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
    let selected: Bool
    let showsLabel: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let expandedDiameter: CGFloat = 26
    private static let compactDiameter: CGFloat = 12
    private var diameter: CGFloat { expanded ? Self.expandedDiameter : Self.compactDiameter }
    private var labelLeadingPadding: CGFloat {
        // The selected overlay's halo is 54pt wide. Its label starts just beyond that
        // geometry so the selected marker does not cover its own name.
        selected ? 43 : Self.expandedDiameter + 5
    }
    private var labelVisible: Bool { expanded && showsLabel }

    var body: some View {
        ZStack {
            Circle()
                .fill(MarkerRole.poiFill(poi.family, expanded: expanded))
                .frame(width: diameter, height: diameter)
                // Mono fills an EXPANDED POI pin with surface — the lightest tier — so it
                // needs a real hairline edge to read against paper, where the warm skin's
                // saturated fill only needed a white lift. A compact dot inverts to mid
                // grey and takes the white keyline instead. See MonoMarkerPalette.swift.
                .overlay(Circle().stroke(MarkerRole.pinStroke(isLightFill: expanded), lineWidth: 1.5))
                .mapFloatShadow()
            Image(systemName: poi.glyph)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MarkerRole.poiGlyph)
                .opacity(expanded ? 1 : 0)   // too cramped on the compact dot
            // Brand logo covers the glyph when resolved; inset so the hairline keyline
            // stays the outer edge. Hidden on the compact dot with the glyph.
            POILogoCircle(poi: poi, diameter: diameter - 3)
                .opacity(expanded ? 1 : 0)
        }
        .frame(width: diameter, height: diameter)
        // Shrink/expand as a spring so a pinch settles like one physical move.
        .animation(reduceMotion ? Motion.smooth : Motion.card, value: expanded)
        .overlay(alignment: .leading) {
            // NOT `poiFill` — in mono that is surface, i.e. white text on paper. A label
            // must stay readable, so it takes the ink role while the DOT goes light.
            HaloText(poi.name, color: MarkerRole.label(base: poi.family.tint))
                .frame(width: 100, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, labelLeadingPadding)
                .allowsHitTesting(false)
                .scaleEffect(reduceMotion ? 1 : (labelVisible ? 1 : 0.9), anchor: .leading)
                .opacity(labelVisible ? 1 : 0)
        }
        // Fade a label in/out as the de-confliction pass grants or withdraws it (a zoom
        // step can free up room), so text never pops.
        .animation(Motion.smooth, value: showsLabel)
        .animation(Motion.smooth, value: selected)
        // Consistent ≥44pt tap target regardless of the current visual size, centered on
        // the badge so the annotation's coordinate anchor doesn't move.
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(poi.name), \(poi.family.label)")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Cluster count bubble (leaf; owns appear / dissolve / count crossfade)

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
/// fades, not pops). The count crossfades on change, never a hard cut.
struct POIClusterBubbleView: View {
    let count: Int
    let active: Bool
    /// True when at least one absorbed civic landmark has a live happening. Liveness
    /// survives aggregation as a static inset ring, so motion is never its only channel.
    let containsLive: Bool
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
    /// The number actually on screen — lags `count` by one transition so the digit
    /// change crossfades rather than cutting.
    @State private var displayCount: Int

    init(
        count: Int,
        active: Bool,
        containsLive: Bool,
        family: PlaceFamily,
        maxDiameter: CGFloat,
        onTap: @escaping () -> Void
    ) {
        self.count = count
        self.active = active
        self.containsLive = containsLive
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
                .fill(MarkerRole.clusterFill.opacity(0.95))
                // Category ring — the bubble's category signal, and what makes it read as
                // Apple-style cluster chrome. 1.8pt rather than 1.5: a ring is a FIXED width
                // on a disc whose size varies 22→44pt, so the thinnest-looking bubble is the
                // smallest one — and a 22pt "2" was measurably QUIETER than a single solid
                // rest dot beside it. The extra weight lands hardest where it was needed.
                .overlay(Circle().strokeBorder(MarkerRole.clusterStroke(family), lineWidth: 1.8))
                // A live civic pin is absorbed like every other non-selected marker. Its
                // static signal moves onto the aggregate instead of surviving as an orphan.
                .overlay {
                    if containsLive {
                        Circle()
                            .strokeBorder(MarkerRole.liveStaticRing, lineWidth: 2)
                            .padding(2)
                    }
                }
                // Deeper than the pins' float shadow ON PURPOSE: a bubble stands for many
                // places, so it must sit ABOVE the individual rest dots around it. With the
                // pale fill and the pins' lighter shadow it read as the quieter element —
                // an inverted hierarchy.
                .shadow(color: MarkerRole.clusterShadow, radius: 5, x: 0, y: 2)
            Text("\(displayCount)")
                // Scale the digits to the (possibly capped) disc, with an 11pt floor so the
                // SMALLEST bubble — the most common one at street zoom — stays legible.
                .font(.system(size: max(11, min(17, diameter * 0.46)), weight: .bold))
                .monospacedDigit()
                // Ink, not white — the disc is light now. ~13:1 against the surface fill.
                .foregroundStyle(MarkerRole.clusterText)
                .contentTransition(.opacity)
        }
        // The dominant family can flip (amber ⇄ indigo) when membership shifts across a
        // near-tie, so the wash + ring must CROSS-FADE, not cut. Phase A's whole thesis is
        // "nothing snaps"; MapPinBadge animates its own tint changes for the same reason.
        .animation(Motion.smooth, value: family)
        .animation(Motion.smooth, value: containsLive)
        .frame(width: diameter, height: diameter)
        .animation(reduceMotion ? nil : CLUSTER_SPRING, value: diameter)
        .scaleEffect(reduceMotion ? 1 : (shown ? 1 : 0.3))
        .opacity(shown ? 1 : 0)
        .contentShape(Circle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        // Just the count: `family` is the DOMINANT family, which on an exact tie falls back
        // to the seed's — so "mostly Food & Drink" would be a claim the data doesn't support.
        // The tint is a visual hint; the spoken label stays factual.
        .accessibilityLabel(
            containsLive
                ? "Cluster of \(displayCount) places, happening now"
                : "Cluster of \(displayCount) places"
        )
        .accessibilityAddTraits(.isButton)
        .onAppear {
            withAnimation(reduceMotion ? Motion.smooth : CLUSTER_SPRING) { shown = active }
        }
        .onChange(of: active) { _, isActive in
            withAnimation(reduceMotion ? Motion.smooth : CLUSTER_SPRING) { shown = isActive }
        }
        .onChange(of: count) { _, newCount in
            withAnimation(Motion.smooth) { displayCount = newCount }
        }
    }
}
