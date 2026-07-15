//
//  POILayer.swift
//  Hygge — the Mapbox style-layer stack that renders the town's food & business POIs.
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
    static let sourceID       = "hygge-poi-src"
    static let dotLayerID      = "hygge-poi-dot"
    static let glyphLayerID    = "hygge-poi-glyph"
    static let clusterLayerID  = "hygge-poi-cluster"
    static let countLayerID    = "hygge-poi-cluster-count"

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
            sym.iconAllowOverlap = .constant(true)      // the glyph must stay with its dot
            sym.iconAnchor = .constant(.center)
            sym.textField = .expression(Exp(.get) { "name" })
            sym.textSize = .constant(11)
            sym.textColor = .constant(StyleColor(UIColor(Hue.ink)))
            sym.textHaloColor = .constant(StyleColor(.white))
            sym.textHaloWidth = .constant(1.2)
            sym.textOpacity = .expression(revealAtAwake())
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
            cluster.circleColor = .constant(StyleColor(UIColor(Hue.mapInk)))
            cluster.circleOpacity = .constant(0.9)
            cluster.circleStrokeColor = .constant(StyleColor(.white))
            cluster.circleStrokeWidth = .constant(1.5)
            cluster.circleRadius = .expression(Exp(.interpolate) {
                Exp(.linear); Exp(.get) { "point_count" }
                2.0; 13.0
                10.0; 18.0
                25.0; 24.0
            })
            attempt("addLayer(\(clusterLayerID))") { try map.addLayer(cluster) }
        }

        // 4. Cluster count.
        if !map.layerExists(withId: countLayerID) {
            var count = SymbolLayer(id: countLayerID, source: sourceID)
            count.filter = isCluster
            count.textField = .expression(Exp(.get) { "point_count_abbreviated" })
            count.textSize = .constant(12)
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
            Hue.mapInk.hexString   // default (should never hit — family is always set)
        }
    }

    /// 0 below the awake zoom, 1 at/above it — the glyph & label reveal, reusing 14.5.
    private static func revealAtAwake() -> Exp {
        Exp(.step) {
            Exp(.zoom)
            0.0
            awakeZoom; 1.0
        }
    }
}
