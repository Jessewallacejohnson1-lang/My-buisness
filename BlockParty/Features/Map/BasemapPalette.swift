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

        // Move the SETTLEMENT (town/city) names DOWN, out from under the cluster bubbles.
        // A town's POI cluster necessarily sits on the town centroid — exactly where Mapbox
        // anchors the town name — so the biggest bubble always landed on "St. Joseph". Mapbox's
        // own label collision can't help: these bubbles are SwiftUI view annotations drawn above
        // the map canvas, so the style never sees them.
        //
        // Anchoring the text to its TOP and pushing it below the point clears the bubble while
        // keeping every name on the map. (Hiding the layers instead would kill Collegeville,
        // Saint Wendel, Five Points and St. Cloud too — the town pill only reverse-geocodes the
        // viewport CENTRE, so it can't name the towns around it, and a nameless map at z11 is
        // worse than the collision ever was.)
        //
        // The offset is in ems of the label's own text size, which light-v11 interpolates to
        // ~14–24pt by zoom and `symbolrank`. It must clear the LARGEST bubble radius — the
        // overlap cap tops out at 44pt across ⇒ 22pt — so 2.4em (≈34–58pt) clears with room.
        // 1.4em was measurably short: the z11 "69" bubble still clipped "St. Joseph".
        //
        // Both layers also carry a `text-radial-offset`, which takes precedence over
        // `text-offset` where it is non-zero. light-v11 steps it to 0 at z ≥ 8 and this map
        // lives at z11–15, so `text-offset` is the one that applies here.
        for id in ["settlement-major-label", "settlement-minor-label"] {
            try? map.setLayerProperty(for: id, property: "text-anchor", value: "top")
            try? map.setLayerProperty(for: id, property: "text-offset", value: [0.0, 2.4])
        }
        // Above z13 the town name stops earning its space: you are unambiguously INSIDE one
        // town and the top pill already names it. Capping matches what light-v11 already does
        // to `settlement-minor-label` (maxzoom 13), so majors and minors retire together.
        //
        // KNOWN LIMIT, deliberately not chased further: at z12 a civic REST DOT can still graze
        // the first glyphs of the name. The offset dodges the cluster bubble (centred on the
        // town centroid) but the civic spots trail just south of it, which is where the offset
        // puts the text. Anchoring ABOVE instead was measured and is WORSE — the label lands
        // squarely behind the bubble. The remaining options both cost more than the defect: a
        // larger offset detaches the name from its own dot, and our pins can't dodge because
        // they sit at real coordinates while the label is Mapbox's.
        try? map.setLayerProperty(for: "settlement-major-label", property: "maxzoom", value: 13.0)
    }
}
