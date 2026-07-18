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
/// seed POI id), the coordinate it's pinned at (the seed's), and the member count.
struct POIClusterBubble: Identifiable, Equatable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let count: Int

    static func == (l: POIClusterBubble, r: POIClusterBubble) -> Bool {
        l.id == r.id && l.count == r.count
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
    var active: Bool
    /// Overlap guard: the bubble caps its on-screen diameter to this, so two seeds — always
    /// > radius apart — can never host bubbles that reach each other (see `bubbleMaxDiameter`).
    var maxDiameter: CGFloat

    static func == (l: POIClusterRender, r: POIClusterRender) -> Bool {
        l.id == r.id && l.count == r.count && l.active == r.active && l.maxDiameter == r.maxDiameter
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
    /// reach each other. The floor (36pt) is above the smallest bubble (34pt across); the
    /// high-zoom end never produces the big 40–46pt bubbles (those need big clusters, which
    /// only exist zoomed out where the radius is 52pt). So no two bubbles overlap at rest.
    static func clusterRadius(zoom: Double) -> CGFloat {
        let far: CGFloat = 52   // z ≤ 13 — calm, big clusters (covers the 46pt bubble + margin)
        let near: CGFloat = 36  // z ≥ 15 — mostly individuals (still ≥ the 34pt small bubble)
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
                                                count: members.count))
            }
        }

        return POIClusterOutput(assignments: assignments, bubbles: bubbles)
    }
}
