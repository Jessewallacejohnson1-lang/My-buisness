//
//  SJMapView+POIClustering.swift
//  Hygge — the client-side POI clustering that SJMapView drives: the recompute trigger,
//  the recompute itself, the bubble appear/dissolve lifecycle, and the DEBUG autozoom
//  demo. Split out of SJMapView.swift to keep that file cohesive; the @State it reads
//  (markerAssignments / renderedClusters / lastClusterZoom / viewport …) lives on the main
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

    /// Cluster current POIs plus eligible civic landmarks at the live projection and fold
    /// the result into the rendered layout. Writing `markerAssignments` / `renderedClusters`
    /// (container @State)
    /// is safe: each marker/bubble animates from its OWN leaf state, so this write can't
    /// cancel an in-flight glide.
    func recomputeClusters(_ map: MapboxMap?) {
        guard let map else { return }
        let zoom = map.cameraState.zoom
        // The chip row's filtered set — the same set SJMapView mounts, so the
        // bubbles recount to what is actually visible (map polish Phase 4).
        let pois = filteredPOIs
        let selected = selectedClusterMarkerID

        // A selected marker is never counted by an aggregate. Civic landmarks participate
        // only below the shared expand threshold, so crossing 14.5 gives each one a solo
        // assignment and the same retained-anchor leaf animates it home.
        var inputs = pois.compactMap { poi -> ClusterMarkerInput? in
            let id = ClusterMarkerID.poi(poi.id)
            guard id != selected else { return nil }
            return ClusterMarkerInput(
                id: id,
                coordinate: poi.coordinate,
                family: poi.family,
                isLive: false
            )
        }
        if zoom < MapModel.pinExpandZoom {
            inputs.append(contentsOf: filteredSpots.compactMap { spot -> ClusterMarkerInput? in
                let id = ClusterMarkerID.civic(spot.id)
                guard id != selected else { return nil }
                return ClusterMarkerInput(
                    id: id,
                    coordinate: spot.coordinate,
                    family: nil,
                    isLive: isLive(spot)
                )
            })
        }

        // Radius follows the LIVE zoom: big/calm clusters zoomed out, mostly individuals at
        // street level. The bubble diameter is capped to `maxBubble` (< radius) so two seeds
        // — always > radius apart — can never host overlapping bubbles at any zoom.
        let radius = POICluster.clusterRadius(zoom: zoom)
        let maxBubble = POICluster.bubbleMaxDiameter(radius: radius)
        let output = POICluster.compute(
            markers: inputs,
            radius: radius,
            forceAllIntoClusters: zoom < MapModel.pinExpandZoom,
            project: { map.point(for: $0) }
        )

        var assignments = output.assignments
        // Markers excluded from `inputs` still need explicit solo assignments: selected
        // POIs at any zoom, selected civics, and every civic at/above pinExpandZoom.
        for poi in pois {
            let id = ClusterMarkerID.poi(poi.id)
            if assignments[id] == nil {
                assignments[id] = POIAssignment(anchor: poi.coordinate, clustered: false)
            }
        }
        for spot in filteredSpots {
            let id = ClusterMarkerID.civic(spot.id)
            if assignments[id] == nil {
                assignments[id] = POIAssignment(anchor: spot.coordinate, clustered: false)
            }
        }
        markerAssignments = assignments

        let rendered = merge(existing: renderedClusters, incoming: output.bubbles, maxDiameter: maxBubble, map: map)
        renderedClusters = rendered
        // Which POI/civic names have room to draw at this layout. Only matters once pins
        // are expanded (labels are hidden below the threshold), but computing in the same
        // projection pass keeps the first expanded frame correct.
        //
        // Reserve against the RENDERED bubbles, not `output.bubbles`: a just-split bubble is
        // absent from the fresh output but stays on screen for its 0.55s fade, and a label
        // granted through it would draw over visible chrome.
        labelledMarkers = POICluster.labelledMarkers(
            pois: pois,
            assignments: assignments,
            bubbles: rendered,
            civicSpots: filteredSpots.map { ($0.id, $0.coordinate) },
            selected: selected,
            previous: labelledMarkers,
            chrome: chromeRects(mapSize: mapSize),
            focus: map.point(for: map.cameraState.center),
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
        // Top chrome: the pill row plus the filter chip row at rest, or the
        // expanded search field + results panel while active. Both states are
        // measured live off the chrome itself (`searchChromeBottom`, the whole
        // top-chrome VStack's maxY in the container's named space), so pin
        // labels never draw under whatever the band currently holds. The 118
        // floor covers the first frames before the measurement lands.
        let topHeight = max(118, searchChromeBottom + 8)
        let topBand = CGRect(x: 0, y: 0, width: W, height: topHeight)
        // The collapsed sheet (peek) plus the tab bar it rests on.
        let sheetTop = H - (MapSheet.tabBarReserve + MapSheet.peekHeight)
        let bottomBand = CGRect(x: 0, y: sheetTop, width: W, height: max(0, H - sheetTop))
        // The ?, + and locate circles, which float above the sheet ("+" sits 56pt
        // above recenter — 44pt circle + the stack's 12pt spacing).
        let controlsY = sheetTop - 96 - 44
        let help = CGRect(x: 16, y: controlsY, width: 44, height: 44)
        let recenter = CGRect(x: W - 60, y: controlsY, width: 44, height: 44)
        let compose = CGRect(x: W - 60, y: controlsY - 56, width: 44, height: 44)
        return [topBand, bottomBand, help, recenter, compose]
    }

    // MARK: Bubble lifecycle (stable ids → persist / crossfade / fade-out)

    /// Reconcile the previous bubble set with the new one, keeping stable ids so each
    /// bubble persists (count crossfades) and dissolving ones fade out before removal.
    private func merge(existing: [POIClusterRender],
                       incoming: [POIClusterBubble],
                       maxDiameter: CGFloat,
                       map: MapboxMap) -> [POIClusterRender] {
        let incomingByID = Dictionary(incoming.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var result: [POIClusterRender] = []
        var handled = Set<ClusterMarkerID>()

        for current in existing {
            if let bubble = incomingByID[current.id] {
                // Still a cluster (or a dissolving one reformed) → active, updated count + cap.
                result.append(POIClusterRender(id: bubble.id, coordinate: bubble.coordinate,
                                               count: bubble.count,
                                               collisionCount: max(current.collisionCount, bubble.count),
                                               dominantFamily: bubble.dominantFamily,
                                               containsLive: bubble.containsLive,
                                               active: true, maxDiameter: maxDiameter))
                handled.insert(current.id)
            } else if current.active {
                // Just dissolved → keep it a beat, fading out, then prune.
                result.append(POIClusterRender(id: current.id, coordinate: current.coordinate,
                                               count: current.count, collisionCount: current.collisionCount,
                                               dominantFamily: current.dominantFamily,
                                               containsLive: current.containsLive,
                                               active: false, maxDiameter: current.maxDiameter))
                schedulePrune(current.id, map)
            } else {
                result.append(current)   // already fading — leave the prune to fire
            }
        }
        for bubble in incoming where !handled.contains(bubble.id) {
            result.append(POIClusterRender(id: bubble.id, coordinate: bubble.coordinate,
                                           count: bubble.count, collisionCount: bubble.count,
                                           dominantFamily: bubble.dominantFamily,
                                           containsLive: bubble.containsLive,
                                           active: true, maxDiameter: maxDiameter))
        }
        return result
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
    private func schedulePrune(_ id: ClusterMarkerID, _ map: MapboxMap) {
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
