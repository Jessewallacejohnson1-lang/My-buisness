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
        // `weak map`, matching `schedulePrune`: this fires 0.13s late and the map tab can be
        // torn down inside that window — a strong capture would keep a `MapboxMap` alive past
        // its `MapView` and then project against it.
        let work = DispatchWorkItem { [weak map] in
            guard let map else { return }
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
            renderedClusters = deactivating(renderedClusters, map)
            labelledPOIs = []   // one recompute owns ALL the layout state it writes
            return
        }
        // Radius follows the LIVE zoom: big/calm clusters zoomed out, mostly individuals at
        // street level. The bubble diameter is capped to `maxBubble` (< radius) so two seeds
        // — always > radius apart — can never host overlapping bubbles at any zoom.
        let radius = POICluster.clusterRadius(zoom: map.cameraState.zoom)
        let maxBubble = POICluster.bubbleMaxDiameter(radius: radius)
        let output = POICluster.compute(pois: pois, radius: radius) { map.point(for: $0) }
        poiAssignments = output.assignments
        let rendered = merge(existing: renderedClusters, incoming: output.bubbles, maxDiameter: maxBubble, map: map)
        renderedClusters = rendered
        // Which POI names have room to draw at this layout. Only matters once pins are
        // expanded (labels are hidden below the awake zoom anyway), but it's computed off
        // the same projection pass, so there's nothing to gain by gating it.
        //
        // Reserve against the RENDERED bubbles, not `output.bubbles`: a just-split bubble is
        // absent from the fresh output but stays on screen for its 0.55s fade, and a label
        // granted through it would draw over visible chrome.
        labelledPOIs = POICluster.labelledPOIs(
            pois: pois,
            assignments: output.assignments,
            bubbles: rendered,
            civicSpots: filteredSpots.map { ($0.coordinate, $0.name) },
            chrome: chromeRects(mapSize: mapSize),
            // Incumbency: labels already on screen keep their grant, so a pinch can't strobe
            // them on and off at a collision boundary.
            previous: labelledPOIs,
            project: { map.point(for: $0) }
        )
    }

    /// Screen boxes the app's own floating chrome occupies, so the label pass never grants a
    /// name that would draw underneath it. These are SwiftUI overlays sitting above the whole
    /// annotation layer, so a label there isn't merely crowded — it is invisible.
    ///
    /// Approximated as bands rather than measured: the chrome is at fixed insets, and over-
    /// reserving the very top and bottom of the map costs little (few POIs sit there, and the
    /// ones that do keep their badge — only the text is withheld).
    func chromeRects(mapSize: CGSize) -> [CGRect] {
        let W = mapSize.width, H = mapSize.height
        guard W > 0, H > 0 else { return [] }
        // Top row: filter chip · town pill · compose "+" — safe area + padding + a 44pt control.
        let topBand = CGRect(x: 0, y: 0, width: W, height: 118)
        // The collapsed sheet (peek) plus the tab bar it rests on.
        let sheetTop = H - (MapSheet.tabBarReserve + MapSheet.peekHeight)
        let bottomBand = CGRect(x: 0, y: sheetTop, width: W, height: max(0, H - sheetTop))
        // The ? and locate circles, which float above the sheet.
        let controlsY = sheetTop - 96 - 44
        let help = CGRect(x: 16, y: controlsY, width: 44, height: 44)
        let recenter = CGRect(x: W - 60, y: controlsY, width: 44, height: 44)
        return [topBand, bottomBand, help, recenter]
    }

    // MARK: Bubble lifecycle (stable ids → persist / roll / fade-out)

    /// Reconcile the previous bubble set with the new one, keeping stable ids so each
    /// bubble persists (count rolls) and dissolving ones fade out before removal.
    private func merge(existing: [POIClusterRender],
                       incoming: [POIClusterBubble],
                       maxDiameter: CGFloat,
                       map: MapboxMap) -> [POIClusterRender] {
        let incomingByID = Dictionary(incoming.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var result: [POIClusterRender] = []
        var handled = Set<String>()

        for current in existing {
            if let bubble = incomingByID[current.id] {
                // Still a cluster (or a dissolving one reformed) → active, updated count + cap.
                result.append(POIClusterRender(id: bubble.id, coordinate: bubble.coordinate,
                                               count: bubble.count, dominantFamily: bubble.dominantFamily,
                                               active: true, maxDiameter: maxDiameter))
                handled.insert(current.id)
            } else if current.active {
                // Just dissolved → keep it a beat, fading out, then prune.
                result.append(POIClusterRender(id: current.id, coordinate: current.coordinate,
                                               count: current.count, dominantFamily: current.dominantFamily,
                                               active: false, maxDiameter: current.maxDiameter))
                schedulePrune(current.id, map)
            } else {
                result.append(current)   // already fading — leave the prune to fire
            }
        }
        for bubble in incoming where !handled.contains(bubble.id) {
            result.append(POIClusterRender(id: bubble.id, coordinate: bubble.coordinate,
                                           count: bubble.count, dominantFamily: bubble.dominantFamily,
                                           active: true, maxDiameter: maxDiameter))
        }
        return result
    }

    /// Flip every active bubble to dissolving (used when POIs vanish entirely).
    private func deactivating(_ clusters: [POIClusterRender], _ map: MapboxMap) -> [POIClusterRender] {
        clusters.map { c in
            guard c.active else { return c }
            schedulePrune(c.id, map)
            return POIClusterRender(id: c.id, coordinate: c.coordinate, count: c.count,
                                    dominantFamily: c.dominantFamily,
                                    active: false, maxDiameter: c.maxDiameter)
        }
    }

    /// Remove a dissolved bubble once its fade-out has played — unless it reformed
    /// (`active` again) in the meantime.
    ///
    /// Recomputes afterwards so the label pass gives back the space the bubble was holding.
    /// Without it a label suppressed by a dissolving bubble would stay hidden until the next
    /// camera move, since pruning writes `renderedClusters` without rerunning the pass.
    /// Terminates: the pruned bubble is in neither `existing` nor `incoming` on the next pass,
    /// so it schedules nothing further.
    ///
    /// `weak map`: this fires 0.55s late, and the map tab can be torn down inside that window —
    /// a strong capture would keep a `MapboxMap` alive past its `MapView` and then project
    /// against it. And the recompute only runs if the bubble ACTUALLY went away: a bubble that
    /// reformed (active again) is still holding its space, so nothing was freed and a full
    /// cluster + label pass would be pure waste.
    private func schedulePrune(_ id: String, _ map: MapboxMap) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak map] in
            let before = renderedClusters.count
            renderedClusters.removeAll { $0.id == id && !$0.active }
            guard renderedClusters.count != before, let map else { return }
            recomputeClusters(map)
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
