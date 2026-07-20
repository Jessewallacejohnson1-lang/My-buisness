//
//  POILayer.swift
//  Block Party — the Mapbox style-layer stack that renders the town's food & business POIs.
//
//  Unlike the six curated civic pins (SwiftUI MapViewAnnotations, which render ABOVE
//  all style layers, so they always win over POIs), the POIs are a data-driven Mapbox
//  layer so they can cluster and de-conflict at scale:
//
//    • a clustered GeoJSONSource (cluster: true) — Mapbox does the clustering, no
//      custom cluster manager;
//    • poi-dot   CircleLayer  — the family-coloured marker. Its radius interpolates
//      with zoom: a small ~6pt REST dot below the 14.5 threshold, a ~24pt AWAKE disc
//      at/above it (reusing MapModel.pinExpandZoom — the same value the civic pins use);
//    • poi-glyph SymbolLayer  — the white SDF SF-Symbol glyph + the name label, both
//      revealed by a zoom `step` at 14.5 (glyph hidden on the rest dot);
//    • poi-cluster CircleLayer + poi-cluster-count SymbolLayer — the count bubbles.
//
//  Families are told apart by GLYPH; each family shares one tint (amber food, indigo
//  business — PlaceFamily.tint, reusing shipped tokens, distinct from the live-coral).
//

import MapboxMaps
import UIKit
import SwiftUI

enum POILayer {

    // Source + layer ids (single namespace so install is idempotent across restyles).
    static let sourceID       = "blockparty-poi-src"
    static let dotLayerID      = "blockparty-poi-dot"
    static let glyphLayerID    = "blockparty-poi-glyph"
    static let clusterLayerID  = "blockparty-poi-cluster"
    static let countLayerID    = "blockparty-poi-cluster-count"

    /// The zoom at/above which a rest dot becomes a full glyph marker + label — the
    /// SAME value the civic pins use (MapModel.pinExpandZoom), expressed here as a
    /// Mapbox zoom `step`/`interpolate` since these are style layers, not SwiftUI.
    private static let awakeZoom = MapModel.pinExpandZoom   // 14.5

    // MARK: - Install (once, on style load) + update (on pois change)

    /// Register glyph images, add the clustered source, and add the layers. Idempotent:
    /// safe to call again after a restyle (guards on *Exists).
    static func install(on map: MapboxMap, pois: [POI]) {
        registerGlyphImages(on: map, pois: pois)
        addSource(on: map, pois: pois)
        addLayers(on: map)
    }

    /// Push new POI data into the existing source (called when `model.pois` loads).
    static func update(on map: MapboxMap, pois: [POI]) {
        registerGlyphImages(on: map, pois: pois)
        guard map.sourceExists(withId: sourceID) else { install(on: map, pois: pois); return }
        map.updateGeoJSONSource(withId: sourceID, geoJSON: .featureCollection(featureCollection(pois)))
    }

    // MARK: - Source

    private static func addSource(on map: MapboxMap, pois: [POI]) {
        guard !map.sourceExists(withId: sourceID) else {
            map.updateGeoJSONSource(withId: sourceID, geoJSON: .featureCollection(featureCollection(pois)))
            return
        }
        var src = GeoJSONSource(id: sourceID)
        src.data = .featureCollection(featureCollection(pois))
        src.cluster = true
        src.clusterRadius = 44
        // Cluster only when zoomed out past the town view; individual rest dots appear
        // by ~z13.5 (the default camera), glyphs/labels at 14.5.
        src.clusterMaxZoom = 13
        attempt("addSource") { try map.addSource(src) }
    }

    private static func featureCollection(_ pois: [POI]) -> FeatureCollection {
        FeatureCollection(features: pois.map { p in
            var f = Feature(geometry: .point(Point(p.coordinate)))
            f.properties = [
                "id":     .string(p.id),   // used to resolve a tapped feature back to its POI
                "family": .string(p.family.rawValue),
                "glyph":  .string(p.glyph),
                "name":   .string(p.name),
            ]
            return f
        })
    }

    // MARK: - Glyph images (white SDF SF Symbols; recoloured by icon-color)

    private static func registerGlyphImages(on map: MapboxMap, pois: [POI]) {
        for name in Set(pois.map(\.glyph)) where !map.imageExists(withId: name) {
            // Fall back to a guaranteed symbol so a bad glyph name can never leave the
            // SymbolLayer referencing an unregistered image (icon-image = get "glyph").
            guard let img = sdfGlyph(named: name) ?? sdfGlyph(named: "mappin.circle.fill") else { continue }
            attempt("addImage(\(name))") { try map.addImage(img, id: name, sdf: true) }
        }
    }

    /// Rasterize an SF Symbol into a white, padded bitmap suitable for a Mapbox SDF
    /// icon (Mapbox reads the alpha channel; icon-color then tints it).
    private static func sdfGlyph(named systemName: String) -> UIImage? {
        let cfg = UIImage.SymbolConfiguration(pointSize: 34, weight: .semibold)
        guard let base = UIImage(systemName: systemName, withConfiguration: cfg)?
            .withTintColor(.white, renderingMode: .alwaysOriginal) else { return nil }
        let pad: CGFloat = 8
        let size = CGSize(width: base.size.width + pad * 2, height: base.size.height + pad * 2)
        let renderer = UIGraphicsImageRenderer(size: size, format: {
            let f = UIGraphicsImageRendererFormat.preferred(); f.opaque = false; return f
        }())
        return renderer.image { _ in
            base.draw(in: CGRect(x: pad, y: pad, width: base.size.width, height: base.size.height))
        }
    }

    // MARK: - Layers

    private static func addLayers(on map: MapboxMap) {
        let notCluster = Exp(.not) { Exp(.has) { "point_count" } }
        let isCluster  = Exp(.has) { "point_count" }

        // 1. The family-coloured marker: small rest dot → larger awake disc.
        if !map.layerExists(withId: dotLayerID) {
            var dot = CircleLayer(id: dotLayerID, source: sourceID)
            dot.filter = notCluster
            dot.circleColor = .expression(familyColorExp())
            dot.circleRadius = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.zoom)
                12.0; 2.5          // far out: a faint dot
                14.0; 3.0          // town view: a ~6pt rest dot
                awakeZoom; 10.0    // 14.5: pops to a ~20pt Apple-sized disc
                17.0; 11.0
            })
            dot.circleStrokeColor = .constant(StyleColor(.white))
            dot.circleStrokeWidth = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.zoom)
                14.0; 0.5
                awakeZoom; 1.5
            })
            dot.circlePitchAlignment = .constant(.map)
            attempt("addLayer(\(dotLayerID))") { try map.addLayer(dot) }
        }

        // 2. The white glyph + the name label — both revealed at the awake zoom.
        if !map.layerExists(withId: glyphLayerID) {
            var sym = SymbolLayer(id: glyphLayerID, source: sourceID)
            sym.filter = notCluster
            sym.iconImage = .expression(Exp(.get) { "glyph" })
            sym.iconColor = .constant(StyleColor(.white))
            sym.iconSize = .constant(0.42)
            sym.iconOpacity = .expression(revealAtAwake())
            // Fade the glyph in over 0.20s (never a hard pop) — spec §3/§6. The zoom
            // band below does the zoom-linked fade; this smooths any non-zoom change.
            sym.iconOpacityTransition = StyleTransition(duration: 0.20, delay: 0)
            sym.iconAllowOverlap = .constant(true)      // the glyph must stay with its dot
            sym.iconAnchor = .constant(.center)
            sym.textField = .expression(Exp(.get) { "name" })
            sym.textSize = .constant(12)                 // spec §9: 12pt marker label
            // Closest available to SF Pro semibold in the basemap tileset's fontstack —
            // the app bundles no map font, so a name label leans on DIN Medium here.
            sym.textFont = .constant(["DIN Offc Pro Medium", "Arial Unicode MS Regular"])
            sym.textColor = .constant(StyleColor(UIColor(Hue.ink)))
            sym.textHaloColor = .constant(StyleColor(.white))
            sym.textHaloWidth = .constant(1.0)           // spec §9: white 1pt halo
            sym.textOpacity = .expression(revealAtAwake())
            sym.textOpacityTransition = StyleTransition(duration: 0.25, delay: 0)  // label fade 0.25s
            sym.textAnchor = .constant(.top)
            sym.textOffset = .constant([0, 0.8])         // label sits under the marker
            sym.textAllowOverlap = .constant(false)      // labels de-conflict…
            sym.textOptional = .constant(true)           // …dropping the label, never the icon
            // Keep POI labels calm: below the civic/basemap labels in the collision order.
            sym.symbolSortKey = .constant(2)
            attempt("addLayer(\(glyphLayerID))") { try map.addLayer(sym) }
        }

        // 3. Cluster bubble (neutral ink — clusters mix families, so no family colour).
        if !map.layerExists(withId: clusterLayerID) {
            var cluster = CircleLayer(id: clusterLayerID, source: sourceID)
            cluster.filter = isCluster
            cluster.circleColor = .constant(StyleColor(UIColor(Hue.ink)))
            cluster.circleOpacity = .constant(0.9)
            cluster.circleStrokeColor = .constant(StyleColor(.white))
            cluster.circleStrokeWidth = .constant(1.5)
            // Discrete count-bucket sizes (spec §7): 1–9 → 28pt, 10–24 → 34pt, 25+ → 40pt
            // (radii 14 / 17 / 20). A step, not a smooth interpolate — the old linear ramp
            // overshot to ~48pt at 25+ and never rested on a clean size.
            cluster.circleRadius = .expression(Exp(.step) {
                Exp(.get) { "point_count" }
                14.0            // 1–9   → 28pt
                10.0; 17.0      // 10–24 → 34pt
                25.0; 20.0      // 25+   → 40pt
            })
            cluster.circleRadiusTransition = StyleTransition(duration: 0.20, delay: 0)
            attempt("addLayer(\(clusterLayerID))") { try map.addLayer(cluster) }
        }

        // 4. Cluster count — 13pt semibold white (spec §7/§9).
        if !map.layerExists(withId: countLayerID) {
            var count = SymbolLayer(id: countLayerID, source: sourceID)
            count.filter = isCluster
            count.textField = .expression(Exp(.get) { "point_count_abbreviated" })
            count.textSize = .constant(13)
            count.textFont = .constant(["DIN Offc Pro Bold", "Arial Unicode MS Bold"])
            count.textColor = .constant(StyleColor(.white))
            count.textAllowOverlap = .constant(true)
            count.textIgnorePlacement = .constant(true)
            attempt("addLayer(\(countLayerID))") { try map.addLayer(count) }
        }
    }

    /// Run a style mutation, logging (not swallowing) a genuine failure under DEBUG so
    /// style-schema drift is detectable — while keeping the idempotent re-install
    /// semantics (the *Exists guards mean this only runs for a missing object).
    private static func attempt(_ what: String, _ op: () throws -> Void) {
        do {
            try op()
        } catch {
            #if DEBUG
            print("[POILayer] \(what) failed: \(error)")
            #endif
        }
    }

    // MARK: - Expressions

    /// circle-color by family — reuses PlaceFamily.tint hex strings (no duplicated hexes).
    private static func familyColorExp() -> Exp {
        Exp(.match) {
            Exp(.get) { "family" }
            PlaceFamily.food.rawValue;     PlaceFamily.food.tint.hexString
            PlaceFamily.business.rawValue; PlaceFamily.business.tint.hexString
            Hue.ink.hexString   // default (should never hit — family is always set)
        }
    }

    /// Glyph & label reveal: a real zoom-linked cross-fade across a narrow band around
    /// the awake threshold (14.5), so a pinch fades them in over ~0.25s and never *pops*
    /// them (spec §3 / acceptance §12.4). Below 14.25 → dots only; fully in by 14.55.
    private static func revealAtAwake() -> Exp {
        Exp(.interpolate) {
            Exp(.linear); Exp(.zoom)
            awakeZoom - 0.25; 0.0
            awakeZoom + 0.05; 1.0
        }
    }
}
