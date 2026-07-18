//
//  SJMapView+POIClustering.swift
//  Hygge — the client-side POI clustering that SJMapView drives: the recompute trigger,
//  the recompute itself, the bubble appear/dissolve lifecycle, and the DEBUG autozoom
//  demo. Split out of SJMapView.swift to keep that file cohesive; the @State it reads
//  (poiAssignments / renderedClusters / lastClusterZoom / viewport …) lives on the main
//  struct — extensions can't add stored properties.
//

import SwiftUI
import CoreLocation
import MapboxMaps

extension SJMapView {

    // MARK: Recompute trigger + reclustering

    /// Recompute driven from camera changes. A zoom STEP recomputes immediately (so a
    /// continuous zoom glides through intermediate cluster states); a short debounce
    /// recomputes once the camera settles (so the idle layout is exact). Both hop to the
    /// next runloop so we never mutate @State inside the camera callback.
    func scheduleClusterRecompute(zoom: Double, map: MapboxMap?) {
        if lastClusterZoom.isNaN || abs(zoom - lastClusterZoom) >= Self.clusterZoomStep {
            lastClusterZoom = zoom
            DispatchQueue.main.async { recomputeClusters(map) }
        }
        clusterSettle?.cancel()
        let work = DispatchWorkItem {
            lastClusterZoom = zoom
            recomputeClusters(map)
        }
        clusterSettle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13, execute: work)
    }

    /// Cluster the current POIs at the live projection and fold the result into the
    /// rendered layout. Writing `poiAssignments` / `renderedClusters` (container @State)
    /// is safe: each marker/bubble animates from its OWN leaf state, so this write can't
    /// cancel an in-flight glide.
    func recomputeClusters(_ map: MapboxMap?) {
        guard let map else { return }
        let pois = model.pois
        guard !pois.isEmpty else {
            poiAssignments = [:]
            renderedClusters = deactivating(renderedClusters)
            return
        }
        // Radius follows the LIVE zoom: big/calm clusters zoomed out, mostly individuals at
        // street level. The bubble diameter is capped to `maxBubble` (< radius) so two seeds
        // — always > radius apart — can never host overlapping bubbles at any zoom.
        let radius = POICluster.clusterRadius(zoom: map.cameraState.zoom)
        let maxBubble = POICluster.bubbleMaxDiameter(radius: radius)
        let output = POICluster.compute(pois: pois, radius: radius) { map.point(for: $0) }
        poiAssignments = output.assignments
        renderedClusters = merge(existing: renderedClusters, incoming: output.bubbles, maxDiameter: maxBubble)
    }

    // MARK: Bubble lifecycle (stable ids → persist / roll / fade-out)

    /// Reconcile the previous bubble set with the new one, keeping stable ids so each
    /// bubble persists (count rolls) and dissolving ones fade out before removal.
    private func merge(existing: [POIClusterRender],
                       incoming: [POIClusterBubble],
                       maxDiameter: CGFloat) -> [POIClusterRender] {
        let incomingByID = Dictionary(incoming.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var result: [POIClusterRender] = []
        var handled = Set<String>()

        for current in existing {
            if let bubble = incomingByID[current.id] {
                // Still a cluster (or a dissolving one reformed) → active, updated count + cap.
                result.append(POIClusterRender(id: bubble.id, coordinate: bubble.coordinate,
                                               count: bubble.count, active: true, maxDiameter: maxDiameter))
                handled.insert(current.id)
            } else if current.active {
                // Just dissolved → keep it a beat, fading out, then prune.
                result.append(POIClusterRender(id: current.id, coordinate: current.coordinate,
                                               count: current.count, active: false, maxDiameter: current.maxDiameter))
                schedulePrune(current.id)
            } else {
                result.append(current)   // already fading — leave the prune to fire
            }
        }
        for bubble in incoming where !handled.contains(bubble.id) {
            result.append(POIClusterRender(id: bubble.id, coordinate: bubble.coordinate,
                                           count: bubble.count, active: true, maxDiameter: maxDiameter))
        }
        return result
    }

    /// Flip every active bubble to dissolving (used when POIs vanish entirely).
    private func deactivating(_ clusters: [POIClusterRender]) -> [POIClusterRender] {
        clusters.map { c in
            guard c.active else { return c }
            schedulePrune(c.id)
            return POIClusterRender(id: c.id, coordinate: c.coordinate, count: c.count,
                                    active: false, maxDiameter: c.maxDiameter)
        }
    }

    /// Remove a dissolved bubble once its fade-out has played — unless it reformed
    /// (`active` again) in the meantime.
    private func schedulePrune(_ id: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            renderedClusters.removeAll { $0.id == id && !$0.active }
        }
    }

    // MARK: DEBUG autozoom demo

    #if DEBUG
    /// `-map-autozoom` eases the camera zoom 15 → 11 → 15 over ~6s once the POIs exist, so
    /// a full merge + split can be frame-sampled headlessly. It LOOPS the sweep so the
    /// motion can be captured regardless of when the (network-loaded) POIs land. DEBUG-only;
    /// no effect in release / without the flag.
    func startAutozoomIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-map-autozoom"), !autozoomStarted else { return }
        autozoomStarted = true
        let center = MapSpots.center
        viewport = .camera(center: center, zoom: 15)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { autozoomCycle(center: center) }
    }

    /// One 15 → 11 → 15 sweep (~6s), looping so a headless capture always catches a
    /// merge + split in flight.
    private func autozoomCycle(center: CLLocationCoordinate2D) {
        guard autozoomStarted else { return }
        withViewportAnimation(.easeInOut(duration: 3), body: {
            viewport = .camera(center: center, zoom: 11)
        }, completion: { _ in
            withViewportAnimation(.easeInOut(duration: 3), body: {
                viewport = .camera(center: center, zoom: 15)
            }, completion: { _ in
                autozoomCycle(center: center)
            })
        })
    }
    #endif
}
