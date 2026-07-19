//
//  POICluster.swift
//  Hygge — the client-side, deterministic clusterer that replaces Mapbox's built-in
//  GeoJSON clustering for the town's food/business POIs (the retired POILayer).
//
//  Why client-side: Mapbox's GeoJSON clustering SNAPS pins between the clustered and
//  unclustered layouts at zoom steps (and occasionally leaves a straggler dot beside a
//  bubble). Rendering the POIs as SwiftUI view annotations instead lets each pin GLIDE
//  (spring) as it merges into / splits out of a cluster — but that needs a layout we
//  own. This is that layout.
//
//  Algorithm — greedy, screen-space, single pass (52 POIs, so no need for Supercluster):
//  project every POI to its current screen point, then, iterating in a STABLE id order,
//  seed a cluster from each not-yet-assigned POI and absorb every not-yet-assigned POI
//  within `radius` points of that seed. Membership-by-radius means every pin within
//  range of a seed joins it, so no orphan can be left sitting under the bubble — the
//  straggler fix is by construction. The seed is the cluster's stable anchor coordinate
//  AND its id, so a bubble persists (its count just rolls) as members join/leave across
//  zoom-step recomputes, and it never jitters the way a recomputed geometric centroid
//  would when membership shifts.
//

import CoreLocation
import CoreGraphics

// MARK: - Per-POI assignment

/// Where a single POI marker should sit after clustering: the coordinate it flies
/// toward (its cluster's seed anchor, or its own coord when solo) and whether it is a
/// member of a multi-POI cluster. Drives the fade / scale / screen-offset in the leaf
/// marker view. Equatable (hand-rolled — `CLLocationCoordinate2D` isn't) so a leaf can
/// `onChange` on it and animate only when its target actually flips.
struct POIAssignment: Equatable {
    let anchor: CLLocationCoordinate2D
    let clustered: Bool

    static func == (l: POIAssignment, r: POIAssignment) -> Bool {
        l.clustered == r.clustered
            && l.anchor.latitude == r.anchor.latitude
            && l.anchor.longitude == r.anchor.longitude
    }
}

// MARK: - Cluster bubble (engine output)

/// One multi-POI cluster the renderer should draw a count bubble for: a stable id (its
/// seed POI id), the coordinate it's pinned at (the seed's), the member count, and the
/// family that most of its members belong to (which tints the bubble, so a cluster hints
/// at what's inside it rather than reading as an anonymous blob).
struct POIClusterBubble: Identifiable, Equatable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let count: Int
    let dominantFamily: PlaceFamily

    static func == (l: POIClusterBubble, r: POIClusterBubble) -> Bool {
        l.id == r.id && l.count == r.count && l.dominantFamily == r.dominantFamily
            && l.coordinate.latitude == r.coordinate.latitude
            && l.coordinate.longitude == r.coordinate.longitude
    }
}

// MARK: - Cluster bubble (render state)

/// A bubble as the map actually renders it: the engine's bubble plus an `active` flag.
/// When a cluster dissolves (a split) the container keeps its bubble mounted a beat with
/// `active == false` so it can FADE OUT rather than pop — the members fading in cover the
/// same spot in the meantime. Stable id ⇒ SwiftUI reuses the annotation, so appear /
/// dissolve / count-roll all animate on one persistent view.
struct POIClusterRender: Identifiable, Equatable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let count: Int
    let dominantFamily: PlaceFamily
    var active: Bool
    /// Overlap guard: the bubble caps its on-screen diameter to this, so two seeds — always
    /// > radius apart — can never host bubbles that reach each other (see `bubbleMaxDiameter`).
    var maxDiameter: CGFloat

    static func == (l: POIClusterRender, r: POIClusterRender) -> Bool {
        l.id == r.id && l.count == r.count && l.active == r.active && l.maxDiameter == r.maxDiameter
            && l.dominantFamily == r.dominantFamily
            && l.coordinate.latitude == r.coordinate.latitude
            && l.coordinate.longitude == r.coordinate.longitude
    }
}

// MARK: - Engine output

struct POIClusterOutput {
    /// Every POI id → its assignment (solo pins included, so the renderer always has one).
    let assignments: [String: POIAssignment]
    /// One entry per multi-POI cluster.
    let bubbles: [POIClusterBubble]
}

// MARK: - Engine

enum POICluster {

    /// The grouping distance (points) at a given zoom. AGGRESSIVE when zoomed out (calm,
    /// big town clusters) and ramping DOWN as you zoom in, so street level (z15) reads as
    /// mostly individual named shops — only near-coincident pins still merge.
    ///
    /// It also fixes bubble-on-bubble overlap at the SOURCE: two distinct seeds are always
    /// > radius apart (a closer pin would have been absorbed), so as long as the radius
    /// stays ≥ the largest count bubble that can appear at that zoom, two bubbles can never
    /// reach each other. The floor (36pt) still exceeds its own cap (36 − 8 = 28pt), and the
    /// high-zoom end never produces the big 40–48pt bubbles (those need big clusters, which
    /// only exist zoomed out where the radius is 52pt). So no two bubbles overlap at rest.
    static func clusterRadius(zoom: Double) -> CGFloat {
        let far: CGFloat = 52   // z ≤ 13 — calm, big clusters (covers the 44pt capped bubble + margin)
        let near: CGFloat = 36  // z ≥ 15 — mostly individuals (still > its own 28pt bubble cap)
        switch zoom {
        case ..<13:  return far
        case 15...:  return near
        default:
            let t = CGFloat((zoom - 13) / (15 - 13))   // 0 at z13 → 1 at z15
            return far - t * (far - near)
        }
    }

    /// Guaranteed clearance (points) between any two bubbles at rest.
    static let bubbleOverlapMargin: CGFloat = 8

    // MARK: Bubble size-by-count

    /// Smallest / largest a bubble may draw before the overlap cap applies. The old three
    /// discrete steps (34/40/46) made a "2" and a "42" look nearly the same size; this is a
    /// continuous ramp over a wider range, so count reads as SIZE at a glance.
    static let minBubbleDiameter: CGFloat = 22
    static let maxBubbleDiameter: CGFloat = 48
    /// The member COUNT at which the growth ramp saturates (not a diameter — kept `Int` so
    /// retuning the diameters can't silently retune the saturation point). Set near the
    /// biggest cluster the town actually produces, so the ramp is spent on counts that
    /// occur rather than on a theoretical maximum.
    static let bubbleRampCeiling: Int = 26

    /// A bubble's on-screen diameter for a member count, on a log ramp (a 2 is clearly
    /// smaller than a 42, but a 61 doesn't dwarf the map).
    ///
    /// The ramp is scaled INTO the overlap cap rather than clamped against it. Clamping made
    /// size-by-count inert wherever the cap was low: at z ≥ 15 the cap is 36 − 8 = 28, which
    /// equalled the old 28pt floor, so a "2" and a "10" drew at exactly the same size in the
    /// zoom band where you actually read individual bubbles. Scaling keeps the full ordering
    /// at every zoom — the range just narrows as the cap tightens.
    ///
    /// One definition, shared by the bubble view and the label de-confliction pass.
    static func bubbleDiameter(count: Int, maxDiameter: CGFloat) -> CGFloat {
        let top = min(maxBubbleDiameter, maxDiameter)
        let lo = min(minBubbleDiameter, top)
        let n = max(2, CGFloat(count))
        let t = min(1, log2(n / 2) / log2(CGFloat(bubbleRampCeiling) / 2))
        return lo + t * (top - lo)
    }

    /// The cap a bubble applies to its on-screen diameter, given the current grouping
    /// radius. Two distinct seeds are always > radius apart, so if each bubble's diameter is
    /// ≤ radius − margin, two bubbles' summed radii are ≤ radius − margin < seed distance ⇒
    /// they never overlap and stay ≥ `bubbleOverlapMargin` apart. Floored so a small bubble
    /// stays legible.
    static func bubbleMaxDiameter(radius: CGFloat) -> CGFloat {
        max(24, radius - bubbleOverlapMargin)
    }

    /// Greedy screen-space clustering at the current projection. `project` maps a
    /// coordinate to its screen point (`MapboxMap.point(for:)`); `radius` is the
    /// grouping distance in points (~44). Deterministic: seeds are chosen in sorted-id
    /// order, so the same layout at the same zoom yields the same cluster ids.
    static func compute(pois: [POI],
                        radius: CGFloat,
                        project: (CLLocationCoordinate2D) -> CGPoint) -> POIClusterOutput {
        // Stable order → deterministic seeds → stable cluster ids across recomputes.
        let ordered = pois.sorted { $0.id < $1.id }
        let points = ordered.map { project($0.coordinate) }
        let radius2 = radius * radius

        var assigned = [Bool](repeating: false, count: ordered.count)
        var assignments: [String: POIAssignment] = [:]
        assignments.reserveCapacity(ordered.count)
        var bubbles: [POIClusterBubble] = []

        for i in ordered.indices where !assigned[i] {
            assigned[i] = true
            let seed = ordered[i]
            let seedPoint = points[i]

            // A seed that can't be projected (behind the camera) just renders solo at its
            // own coordinate — it can't sensibly gather neighbours.
            guard seedPoint.x.isFinite, seedPoint.y.isFinite else {
                assignments[seed.id] = POIAssignment(anchor: seed.coordinate, clustered: false)
                continue
            }

            var members = [i]
            for j in ordered.indices where !assigned[j] {
                let p = points[j]
                guard p.x.isFinite, p.y.isFinite else { continue }
                let dx = p.x - seedPoint.x
                let dy = p.y - seedPoint.y
                if dx * dx + dy * dy <= radius2 {
                    assigned[j] = true
                    members.append(j)
                }
            }

            let clustered = members.count >= 2
            for m in members {
                assignments[ordered[m].id] = POIAssignment(anchor: seed.coordinate, clustered: clustered)
            }
            if clustered {
                bubbles.append(POIClusterBubble(id: seed.id,
                                                coordinate: seed.coordinate,
                                                count: members.count,
                                                dominantFamily: dominantFamily(of: members, seed: seed, in: ordered)))
            }
        }

        return POIClusterOutput(assignments: assignments, bubbles: bubbles)
    }

    // MARK: - Label de-confliction

    /// Approximate on-screen geometry of a marker's halo'd name label, measured off
    /// `POIBadge` / `MapPinBadge`: the text sits to the RIGHT of the badge, offset by the
    /// badge's radius + gap, in a fixed-width box that may wrap to two lines.
    private enum LabelBox {
        /// POI badge (26pt) → text left edge: 26/2 + 5 padding = 18.
        static let poiLeadingGap: CGFloat = 18
        /// Civic badge is 28pt with 6pt padding ⇒ 20. Its radius also has to cover the
        /// selected pin's 1.15× scale bump (28 × 1.15 / 2 ≈ 16.1).
        static let civicLeadingGap: CGFloat = 20
        static let civicRadius: CGFloat = 18
        static let poiRadius: CGFloat = 16
        /// The `.frame(width: 100)` cap on the label, and the line box of `.sansBold(12)`.
        static let maxWidth: CGFloat = 100
        static let lineHeight: CGFloat = 16

        /// The label's box, ESTIMATED from the name rather than always reserving the full
        /// 100×34. A fixed max box over-reserved ~2.5× for a short name like "Coborn's",
        /// suppressing labels that would have fitted fine. `.sansBold(12)` averages ~6.6pt
        /// per character; over `maxWidth` the label wraps to its 2-line limit.
        static func text(_ name: String, at p: CGPoint, gap: CGFloat) -> CGRect {
            let natural = CGFloat(name.count) * 6.6
            let w = min(maxWidth, natural)
            let h = natural > maxWidth ? lineHeight * 2 : lineHeight
            return CGRect(x: p.x + gap, y: p.y - h / 2, width: w, height: h)
        }
        static func badge(at p: CGPoint, radius: CGFloat) -> CGRect {
            CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
        }
    }

    /// Which POIs may draw their name label, so a dense street-level view reads as a clean
    /// map instead of a pile of overlapping text.
    ///
    /// Mapbox's own symbol-collision engine can't help here: these markers are SwiftUI view
    /// annotations drawn ABOVE the map canvas, so the style never sees them. This is the
    /// same greedy screen-space pass the clusterer itself uses — reserve the boxes that must
    /// stay clear, then walk candidates in priority order and grant a label only when its
    /// text box is still free. The pass is translation-invariant (`pitch`/`bearing` are 0, so
    /// projection under pan is a pure translation and every box moves together), so panning
    /// at a fixed zoom can't change the outcome.
    ///
    /// Reservation priority (highest first): civic landmark badges + labels — the six curated
    /// spots are the map's anchors and must never be covered; then cluster bubbles; then every
    /// POI badge (badges always draw, so no label may sit on one); then POI labels.
    ///
    /// Among POI labels, `previous` wins first: a label already on screen keeps its grant
    /// before any newcomer competes for the space. Without that incumbency, every 0.1-zoom
    /// step re-ran an independent greedy pass, so a label sitting on a collision boundary
    /// strobed during a pinch — and worse, one label losing its box freed space that let two
    /// others in, cascading several flips per step. Ties below incumbency go to food places
    /// (this is a town map — where you'd GO ranks above a service), then alphabetically, so
    /// the surviving set is meaningful rather than an artefact of Supabase row ids.
    ///
    /// Clustered POIs are not candidates — they're mid-merge and invisible.
    ///
    /// `bubbles` is the RENDERED set, not the engine's fresh output: a bubble that just split
    /// stays mounted (`active: false`) for the length of its fade, so it is still on screen and
    /// must still hold its space. Reserving off the fresh output instead would grant labels
    /// straight through a dissolving bubble for the whole 0.55s fade. Each render carries the
    /// cap it was built with, so a dissolving one keeps its own diameter rather than borrowing
    /// the current zoom's.
    static func labelledPOIs(pois: [POI],
                             assignments: [String: POIAssignment],
                             bubbles: [POIClusterRender],
                             civicSpots: [(coordinate: CLLocationCoordinate2D, name: String)],
                             previous: Set<String>,
                             project: (CLLocationCoordinate2D) -> CGPoint) -> Set<String> {
        var reserved: [CGRect] = []

        for spot in civicSpots {
            let p = project(spot.coordinate)
            guard p.x.isFinite, p.y.isFinite else { continue }
            reserved.append(LabelBox.badge(at: p, radius: LabelBox.civicRadius))
            reserved.append(LabelBox.text(spot.name, at: p, gap: LabelBox.civicLeadingGap))
        }
        for bubble in bubbles {
            let p = project(bubble.coordinate)
            guard p.x.isFinite, p.y.isFinite else { continue }
            let d = bubbleDiameter(count: bubble.count, maxDiameter: bubble.maxDiameter)
            reserved.append(LabelBox.badge(at: p, radius: d / 2))
        }

        // Solo POIs only — a clustered one has glided into its bubble and drawn nothing.
        // Incumbents first (see the doc comment), then food, then name — fully deterministic.
        let candidates = pois
            .filter { assignments[$0.id]?.clustered == false }
            // NOTE: the family tier is a valid strict weak ordering only because PlaceFamily
            // has exactly TWO cases, so `l.family == .food` totally partitions it. Adding a
            // third case makes this non-transitive and Swift's debug `sort` can trap — rank
            // families explicitly (a `sortRank` on PlaceFamily) if one is ever added.
            .sorted { l, r in
                let li = previous.contains(l.id), ri = previous.contains(r.id)
                if li != ri { return li }
                if l.family != r.family { return l.family == .food }
                return l.name < r.name
            }

        var points: [String: CGPoint] = [:]
        for poi in candidates {
            let p = project(poi.coordinate)
            guard p.x.isFinite, p.y.isFinite else { continue }
            points[poi.id] = p
            // Every badge draws → always reserved, so no label may sit on one.
            reserved.append(LabelBox.badge(at: p, radius: LabelBox.poiRadius))
        }

        var labelled = Set<String>()
        for poi in candidates {
            guard let p = points[poi.id] else { continue }
            let box = LabelBox.text(poi.name, at: p, gap: LabelBox.poiLeadingGap)
            guard !reserved.contains(where: { $0.intersects(box) }) else { continue }
            reserved.append(box)
            labelled.insert(poi.id)
        }
        return labelled
    }

    /// The family most of a cluster's members belong to — the bubble's tint. A family only
    /// takes the tint by STRICTLY outnumbering the seed's; ties hold the seed's family, and
    /// the sort keeps the pick deterministic regardless of dictionary iteration order.
    ///
    /// That makes any SINGLE evaluation deterministic, but it is not hysteresis: a cluster
    /// balanced near a tie (say 3 food / 4 business) flips tint when one member drifts across
    /// the radius on a zoom step, and flips back when it drifts in. The bubble cross-fades
    /// the change rather than cutting (see `POIClusterBubbleView`), so the flip reads as a
    /// soft settle rather than a snap. True stability would need the previous tint carried
    /// across recomputes — worth doing only if the cross-fade proves visible in practice.
    private static func dominantFamily(of members: [Int],
                                       seed: POI,
                                       in ordered: [POI]) -> PlaceFamily {
        var tally: [PlaceFamily: Int] = [:]
        for m in members { tally[ordered[m].family, default: 0] += 1 }
        let seedCount = tally[seed.family] ?? 0
        let challengers = tally
            .filter { $0.value > seedCount }
            .sorted { l, r in
                l.value != r.value ? l.value > r.value : l.key.rawValue < r.key.rawValue
            }
        return challengers.first?.key ?? seed.family
    }
}
