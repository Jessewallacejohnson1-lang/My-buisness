//
//  BasemapPalette.swift
//  Block Party — the map's ONE static cartography palette.
//
//  A neutral grayscale ramp continuous with the app's ink-on-paper system. Land,
//  parks, water, buildings, and roads stay separable by value alone; labels share
//  the app's secondary ink and retain the light-v11 style's white halos. Raw hexes
//  live here only where the app palette has no matching Hue token.
//
//  There is deliberately NO time/season/weather modulation. The base map looks the
//  same at every hour, by design — one calm base layer. (The old "Living Basemap"
//  that shifted the palette by time-of-day · season · weather was retired here —
//  see MAP_BUILD_LOG.md.)
//

import Foundation
import MapboxMaps

enum BasemapPalette {
    // MARK: Ground & natural features
    static let land     = Hue.paper.hexString   // app background continues into the map
    static let green    = "#EFEFEC"             // parks: one value step below land
    static let water    = "#E4E4E0"             // water: darker again, without hue
    static let building = Hue.fill.hexString    // inert built-form fill

    // MARK: Road network
    // light-v11 consolidates every road class (motorway → residential) into ONE
    // line layer (`road-simple`), differentiated only by width, not color — verified
    // against the style's actual JSON (`GET styles/v1/mapbox/light-v11`), not assumed
    // from Mapbox Streets' richer per-class layer set. So there's one road color, not
    // a fill/casing/motorway hierarchy. Surface white makes roads read as light
    // channels against the paper ground.
    static let road = Hue.surface.hexString

    // MARK: Labels — shared with the app's own ink ramp (not map-only)
    // Call sites use `Hue.inkSecondary.hexString`; light-v11 keeps its white halos.

    /// Apply the shared static palette to light-v11. Call once from each map's
    /// style-load callback; individual setters stay best-effort across style updates.
    static func recolor(_ map: MapboxMap?) {
        guard let map else { return }
        try? map.setLayerProperty(for: "land", property: "background-color", value: land)
        // Parks / grass / woods (fill layers) — light-v11 only has these two.
        for id in ["landuse", "national-park"] {
            try? map.setLayerProperty(for: id, property: "fill-color", value: green)
        }
        try? map.setLayerProperty(for: "water",    property: "fill-color", value: water)
        try? map.setLayerProperty(for: "waterway", property: "line-color", value: water)
        try? map.setLayerProperty(for: "building", property: "fill-color",         value: building)
        try? map.setLayerProperty(for: "building", property: "fill-outline-color", value: building)
        try? map.setLayerProperty(for: "road-simple", property: "line-color", value: road)

        let labelInk = Hue.inkSecondary.hexString
        for id in ["road-label-simple", "settlement-major-label", "settlement-minor-label", "settlement-subdivision-label"] {
            try? map.setLayerProperty(for: id, property: "text-color", value: labelInk)
        }
    }
}
