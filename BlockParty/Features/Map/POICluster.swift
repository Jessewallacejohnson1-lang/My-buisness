//
//  POICluster.swift
//  Hygge — the client-side, deterministic clusterer that replaces Mapbox's built-in
//  GeoJSON clustering for the town's POIs and curated civic landmarks.
//
//  Why client-side: Mapbox's GeoJSON clustering SNAPS pins between the clustered and
//  unclustered layouts at zoom steps (and occasionally leaves a straggler dot beside a
//  bubble). Rendering the POIs as SwiftUI view annotations instead lets each pin GLIDE
//  (spring) as it merges into / splits out of a cluster — but that needs a layout we
//  own. This is that layout.
//
//  Algorithm — greedy, screen-space, deterministic (the town data set is tiny):
//  project every marker to its current screen point, then, iterating in a STABLE id order,
//  seed a cluster and absorb every unassigned marker within `radius`. Below the expand
//  threshold, remaining singletons join their nearest real group, so every non-selected
//  projectable marker is counted exactly once. The seed is the cluster's stable anchor
//  coordinate AND its id, so a persistent bubble can crossfade its count without jitter.
//

import CoreLocation
import CoreGraphics

// MARK: - Shared marker input

/// Namespaces the two marker catalogs before they enter one cluster pass. Civic ids are
/// short slugs while POI ids are UUIDs today, but making that accidental distinction part
/// of correctness would be brittle.
enum ClusterMarkerID: Hashable, Comparable {
    case poi(String)
    case civic(String)

    private var sortKey: String {
        switch self {
        case .poi(let id):   return "poi:\(id)"
        case .civic(let id): return "civic:\(id)"
        }
    }

    static func < (lhs: ClusterMarkerID, rhs: ClusterMarkerID) -> Bool {
        lhs.sortKey < rhs.sortKey
    }
}

/// The common geometry the clusterer needs from a POI or curated civic landmark.
/// `family` remains optional because a civic marker has no food/business family; the
/// cluster's monochrome role does not invent one just to absorb a landmark.
struct ClusterMarkerInput {
    let id: ClusterMarkerID
    let coordinate: CLLocationCoordinate2D
    let family: PlaceFamily?
    let isLive: Bool
}

// MARK: - Per-marker assignment

/// Where a single marker should sit after clustering: the coordinate it flies
/// toward (its cluster's seed anchor, or its own coord when solo) and whether it is a
/// member of a multi-marker cluster. Drives the fade / scale / screen-offset in the leaf
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

/// One multi-marker cluster the renderer should draw a count bubble for: a stable id (its
/// seed marker id), the coordinate it's pinned at (the seed's), the member count, and the
/// family that most of its members belong to (which tints the bubble, so a cluster hints
/// at what's inside it rather than reading as an anonymous blob).
struct POIClusterBubble: Identifiable, Equatable {
    let id: ClusterMarkerID
    let coordinate: CLLocationCoordinate2D
    let count: Int
    let dominantFamily: PlaceFamily
    let containsLive: Bool

    static func == (l: POIClusterBubble, r: POIClusterBubble) -> Bool {
        l.id == r.id && l.count == r.count && l.dominantFamily == r.dominantFamily
            && l.containsLive == r.containsLive
            && l.coordinate.latitude == r.coordinate.latitude
            && l.coordinate.longitude == r.coordinate.longitude
    }
}

// MARK: - Cluster bubble (render state)

/// A bubble as the map actually renders it: the engine's bubble plus an `active` flag.
/// When a cluster dissolves (a split) the container keeps its bubble mounted a beat with
/// `active == false` so it can FADE OUT rather than pop — the members fading in cover the
/// same spot in the meantime. Stable id ⇒ SwiftUI reuses the annotation, so appear /
/// dissolve / count-crossfade all animate on one persistent view.
struct POIClusterRender: Identifiable, Equatable {
    let id: ClusterMarkerID
    let coordinate: CLLocationCoordinate2D
    let count: Int
    /// Largest count this stable bubble has crossfaded through. Collision geometry
    /// stays conservative while the displayed count/diameter is between old and new.
    let collisionCount: Int
    let dominantFamily: PlaceFamily
    let containsLive: Bool
    var active: Bool
    /// Overlap guard: the bubble caps its on-screen diameter to this, so two seeds — always
    /// > radius apart — can never host bubbles that reach each other (see `bubbleMaxDiameter`).
    var maxDiameter: CGFloat

    static func == (l: POIClusterRender, r: POIClusterRender) -> Bool {
        l.id == r.id && l.count == r.count && l.collisionCount == r.collisionCount
            && l.active == r.active && l.maxDiameter == r.maxDiameter
            && l.dominantFamily == r.dominantFamily && l.containsLive == r.containsLive
            && l.coordinate.latitude == r.coordinate.latitude
            && l.coordinate.longitude == r.coordinate.longitude
    }
}

// MARK: - Engine output

struct POIClusterOutput {
    /// Every marker id → its assignment (solo pins included, so the renderer always has one).
    let assignments: [ClusterMarkerID: POIAssignment]
    /// One entry per multi-marker cluster.
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
    ///
    /// Below the label/expand threshold, `forceAllIntoClusters` is true. The radius pass
    /// first creates the calm local groups the map already used, then any remaining
    /// singleton joins its nearest real group. That second pass is the collapsed-map
    /// "zero orphans" invariant: every projectable, non-selected marker is counted by
    /// exactly one bubble rather than lingering as a loose dot beside it.
    static func compute(markers: [ClusterMarkerInput],
                        radius: CGFloat,
                        forceAllIntoClusters: Bool,
                        project: (CLLocationCoordinate2D) -> CGPoint) -> POIClusterOutput {
        // Stable order → deterministic seeds → stable cluster ids across recomputes.
        let ordered = markers.sorted { $0.id < $1.id }
        let points = ordered.map { project($0.coordinate) }
        let radius2 = radius * radius

        var assigned = [Bool](repeating: false, count: ordered.count)
        var groups: [(seed: Int, members: [Int])] = []
        groups.reserveCapacity(ordered.count)

        for i in ordered.indices where !assigned[i] {
            assigned[i] = true
            let seedPoint = points[i]

            // A seed that can't be projected (behind the camera) just renders solo at its
            // own coordinate — it can't sensibly gather neighbours.
            guard seedPoint.x.isFinite, seedPoint.y.isFinite else {
                groups.append((seed: i, members: [i]))
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
            groups.append((seed: i, members: members))
        }

        if forceAllIntoClusters, ordered.count > 1 {
            var clusterIndices = groups.indices.filter { groups[$0].members.count >= 2 }

            // Defensive fallback for a sparse/filtered data set: establish one real group
            // from all finite markers, then the normal nearest-group rule still holds.
            if clusterIndices.isEmpty,
               let first = groups.indices.first(where: {
                   let p = points[groups[$0].seed]
                   return p.x.isFinite && p.y.isFinite
               }) {
                for i in groups.indices where i != first {
                    let p = points[groups[i].seed]
                    guard p.x.isFinite, p.y.isFinite else { continue }
                    groups[first].members.append(contentsOf: groups[i].members)
                    groups[i].members.removeAll()
                }
                clusterIndices = [first]
            }

            for i in groups.indices where groups[i].members.count == 1 {
                let p = points[groups[i].seed]
                guard p.x.isFinite, p.y.isFinite,
                      let nearest = clusterIndices.min(by: { l, r in
                          squaredDistance(from: p, to: points[groups[l].seed])
                              < squaredDistance(from: p, to: points[groups[r].seed])
                      }),
                      nearest != i else { continue }
                groups[nearest].members.append(contentsOf: groups[i].members)
                groups[i].members.removeAll()
            }
        }

        var assignments: [ClusterMarkerID: POIAssignment] = [:]
        assignments.reserveCapacity(ordered.count)
        var bubbles: [POIClusterBubble] = []

        for group in groups where !group.members.isEmpty {
            let seed = ordered[group.seed]
            let clustered = group.members.count >= 2
            for member in group.members {
                assignments[ordered[member].id] = POIAssignment(
                    anchor: seed.coordinate,
                    clustered: clustered
                )
            }
            if clustered {
                bubbles.append(POIClusterBubble(
                    id: seed.id,
                    coordinate: seed.coordinate,
                    count: group.members.count,
                    dominantFamily: dominantFamily(of: group.members, in: ordered),
                    containsLive: group.members.contains { ordered[$0].isLive }
                ))
            }
        }
        return POIClusterOutput(assignments: assignments, bubbles: bubbles)
    }

    private static func squaredDistance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return dx * dx + dy * dy
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
        /// The exact `.frame(width: 100)` cap on the label and its two-line ceiling.
        /// Reserving the maximum is intentionally conservative: this pass promises no
        /// overlap, so it cannot rely on an average character-width estimate.
        static let maxWidth: CGFloat = 100
        static let lineHeight: CGFloat = 16
        static let halo: CGFloat = 1

        static func text(at p: CGPoint, gap: CGFloat) -> CGRect {
            let height = lineHeight * 2
            return CGRect(
                x: p.x + gap - halo,
                y: p.y - height / 2 - halo,
                width: maxWidth + halo * 2,
                height: height + halo * 2
            )
        }
        static func badge(at p: CGPoint, radius: CGFloat) -> CGRect {
            CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
        }
    }

    /// Which POI and civic markers may draw their name label, so a dense street-level
    /// view reads as a clean map instead of a pile of overlapping text.
    ///
    /// Mapbox's own symbol-collision engine can't help here: these markers are SwiftUI view
    /// annotations drawn ABOVE the map canvas, so the style never sees them. This is the
    /// same greedy screen-space pass the clusterer itself uses — reserve the boxes that must
    /// stay clear, then walk candidates in priority order and grant a label only when its
    /// text box is still free.
    ///
    /// Reservation priority (highest first): cluster bubbles; every visible marker badge;
    /// selected label; then remaining labels by distance to the camera focus. This is the
    /// hierarchy the renderer uses too: cluster > selected pin > nearer pin. Reserving every
    /// badge before granting any text is what makes "a label never covers another marker"
    /// true for both catalogs rather than just within the POI layer.
    ///
    /// Among non-selected candidates, `previous` wins before camera-focus distance. That
    /// incumbency keeps an already-visible label sticky while every projected box translates
    /// together during a pan; distance still chooses between NEW labels when space opens.
    ///
    /// Clustered markers are not candidates — they're mid-merge and invisible.
    ///
    /// `bubbles` is the RENDERED set, not the engine's fresh output: a bubble that just split
    /// stays mounted (`active: false`) for the length of its fade, so it is still on screen and
    /// must still hold its space. Reserving off the fresh output instead would grant labels
    /// straight through a dissolving bubble for the whole 0.55s fade. Each render carries the
    /// cap it was built with, so a dissolving one keeps its own diameter rather than borrowing
    /// the current zoom's.
    static func labelledMarkers(
        pois: [POI],
        assignments: [ClusterMarkerID: POIAssignment],
        bubbles: [POIClusterRender],
        civicSpots: [(id: String, coordinate: CLLocationCoordinate2D)],
        selected: ClusterMarkerID?,
        previous: Set<ClusterMarkerID>,
        chrome: [CGRect],
        focus: CGPoint,
        project: (CLLocationCoordinate2D) -> CGPoint
    ) -> Set<ClusterMarkerID> {
        struct Candidate {
            let id: ClusterMarkerID
            let point: CGPoint
            let badgeRadius: CGFloat
            let labelGap: CGFloat
            let distanceToFocus: CGFloat
        }

        // The app's OWN floating chrome outranks everything — it is drawn above the whole
        // annotation layer, so a label granted underneath it doesn't compete, it just
        // disappears behind the filter chip / compose "+" / bottom sheet.
        var reserved: [CGRect] = chrome

        // Bubbles win their space over every label, including a selected one.
        for bubble in bubbles {
            let p = project(bubble.coordinate)
            guard p.x.isFinite, p.y.isFinite else { continue }
            let d = bubbleDiameter(count: bubble.collisionCount, maxDiameter: bubble.maxDiameter)
            reserved.append(LabelBox.badge(at: p, radius: d / 2))
        }

        var candidates: [Candidate] = []
        candidates.reserveCapacity(pois.count + civicSpots.count)

        for poi in pois {
            let id = ClusterMarkerID.poi(poi.id)
            guard assignments[id]?.clustered == false else { continue }
            let p = project(poi.coordinate)
            guard p.x.isFinite, p.y.isFinite else { continue }
            let isSelected = id == selected
            // The selected POI overlay carries a 54pt halo, so its label starts beyond
            // that halo rather than printing through its own selection treatment.
            let radius: CGFloat = isSelected ? 28 : LabelBox.poiRadius
            let gap: CGFloat = isSelected ? 30 : LabelBox.poiLeadingGap
            let distance = squaredDistance(from: p, to: focus)
            candidates.append(Candidate(
                id: id,
                point: p,
                badgeRadius: radius,
                labelGap: gap,
                distanceToFocus: distance.isFinite ? distance : .infinity
            ))
        }

        for spot in civicSpots {
            let id = ClusterMarkerID.civic(spot.id)
            guard assignments[id]?.clustered == false else { continue }
            let p = project(spot.coordinate)
            guard p.x.isFinite, p.y.isFinite else { continue }
            let distance = squaredDistance(from: p, to: focus)
            candidates.append(Candidate(
                id: id,
                point: p,
                badgeRadius: LabelBox.civicRadius,
                labelGap: LabelBox.civicLeadingGap,
                distanceToFocus: distance.isFinite ? distance : .infinity
            ))
        }

        // Every visible badge draws, so reserve all of them before considering any label.
        // This prevents a high-priority label from solving its own collision by covering a
        // lower-priority marker.
        for candidate in candidates {
            reserved.append(LabelBox.badge(at: candidate.point, radius: candidate.badgeRadius))
        }

        candidates.sort { lhs, rhs in
            let lhsSelected = lhs.id == selected
            let rhsSelected = rhs.id == selected
            if lhsSelected != rhsSelected { return lhsSelected }
            if !lhsSelected {
                let lhsIncumbent = previous.contains(lhs.id)
                let rhsIncumbent = previous.contains(rhs.id)
                if lhsIncumbent != rhsIncumbent { return lhsIncumbent }
            }
            if lhs.distanceToFocus != rhs.distanceToFocus {
                return lhs.distanceToFocus < rhs.distanceToFocus
            }
            return lhs.id < rhs.id
        }

        var labelled = Set<ClusterMarkerID>()
        for candidate in candidates {
            let box = LabelBox.text(at: candidate.point, gap: candidate.labelGap)
            guard !reserved.contains(where: { $0.intersects(box) }) else { continue }
            reserved.append(box)
            labelled.insert(candidate.id)
        }
        return labelled
    }

    /// The family most of a cluster's POI members belong to — the bubble's legacy styling
    /// hint. Civic members do not vote; ties hold the first POI member's family.
    ///
    /// That makes any SINGLE evaluation deterministic, but it is not hysteresis: a cluster
    /// balanced near a tie (say 3 food / 4 business) flips tint when one member drifts across
    /// the radius on a zoom step, and flips back when it drifts in. The bubble cross-fades
    /// the change rather than cutting (see `POIClusterBubbleView`), so the flip reads as a
    /// soft settle rather than a snap. True stability would need the previous tint carried
    /// across recomputes — worth doing only if the cross-fade proves visible in practice.
    private static func dominantFamily(of members: [Int],
                                       in ordered: [ClusterMarkerInput]) -> PlaceFamily {
        var tally: [PlaceFamily: Int] = [:]
        for m in members {
            if let family = ordered[m].family { tally[family, default: 0] += 1 }
        }
        guard let baseline = members.compactMap({ ordered[$0].family }).first else {
            // Civic-only bubbles are monochrome, so this fallback never invents a visible
            // category signal. It simply satisfies the legacy bubble styling interface.
            return .business
        }
        let seedCount = tally[baseline] ?? 0
        let challengers = tally
            .filter { $0.value > seedCount }
            .sorted { l, r in
                l.value != r.value ? l.value > r.value : l.key.rawValue < r.key.rawValue
            }
        return challengers.first?.key ?? baseline
    }
}
