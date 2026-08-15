//
//  BasemapPalette.swift
//  Block Party — the map's ONE static cartography palette.
//
//  THE MAP IS CONTENT, NOT CHROME. The app's UI is monochrome ink-on-paper and
//  photographs carry the colour; the map is the same kind of thing — a picture of
//  the town — so its NATURAL features keep their real colours, and they keep them
//  generously. Round 2 (2026-08-14, Jesse's Subway store-finder reference) widened
//  this from a muted watercolor to a genuinely colorful town map: lively leaf-green
//  vegetation wherever green exists, a clear confident blue river, and warm
//  tan patches over campus/institutional ground — the reference's College-Terrace
//  read, which here is St. Ben's. Friendly and saturated-but-soft, like a printed
//  neighborhood map; never neon, never a traffic app.
//
//  This palette REPLACED a fully grayscale ramp that made land, parks and water sit
//  within ~6% luminance of each other. It was elegant and it did not work: the Sauk
//  River and the parks were both faint grey shapes, so the one screen whose
//  BACKGROUND is the content lost its landmarks. Do not make the basemap grayscale.
//
//  Built form stays neutral on purpose. Buildings and roads take app tokens, so
//  colour is spent only on ground that carries meaning, and ink markers still
//  dominate everything. Labels share the app's secondary ink and keep light-v11's
//  white halos. Raw hexes live here only where no Hue token fits — this file plus
//  BlockPartyColor.swift are the only two allowed to hold them.
//
//  There is deliberately NO time/season/weather modulation. The base map looks the
//  same at every hour, by design — one calm base layer. (The old "Living Basemap"
//  that shifted the palette by time-of-day · season · weather was retired here —
//  see MAP_BUILD_LOG.md. Its summer·noon·clear anchor preserved the ROUND-1 muted
//  palette; the values below are the round-2 colorful palette and are now the
//  regression anchor. If a screenshot ever renders paler than these, the recolor
//  didn't land — see the race note on `recolor`.)
//

import Foundation
import MapboxMaps

enum BasemapPalette {
    // MARK: Ground
    // Land stays the app's paper so the map reads as continuous with the app.
    static let land     = Hue.paper.onLightCanvas.hexString   // app background continues into the map
    static let building = Hue.fill.onLightCanvas.hexString    // built form stays neutral, on token

    // MARK: Vegetation — one leaf-green family, tiered by how "kept" the ground is
    // Parks are the loudest, lawns lighter, farm fields a whisper — so green coverage
    // reads everywhere green exists without the whole townscape going monotone.
    static let park      = "#A9D584"   // parks, gardens, playgrounds — the headline green
    static let pitch     = "#B9DB8F"   // ball fields / courts — kin to park, one step lighter
    static let wood      = "#B0D291"   // woods & scrub — softer, slightly muted canopy
    static let grass     = "#C3DFA2"   // open lawns — light tint of the same family
    static let farmland  = "#DFEAC5"   // agriculture — big-area soft green, a real tint not a whisper
    static let cemetery  = "#CBDCB4"   // kept lawn with trees — quiet natural, not park-bright

    // MARK: Warm patches — the reference's campus/institution tan
    static let campus   = "#F3E3C8"   // school · university · hospital — St. Ben's warm field
    static let commerce = "#F6E0C4"   // commercial districts — a peach step off campus tan
    static let sand     = "#F0E3C0"   // beaches / sand — warm natural

    // MARK: Water — clear and confident; the Sauk River must read instantly
    static let water    = "#7FBFE8"
    static let riverInk = "#6FB6E2"   // waterway strokes — thin lines render optically lighter,
                                      // so the line family sits one step deeper than the fill

    // MARK: Road network
    // light-v11 consolidates every road class (motorway → residential) into ONE
    // line layer (`road-simple`), differentiated only by width, not color — verified
    // against the style's actual JSON (`GET styles/v1/mapbox/light-v11`), not assumed
    // from Mapbox Streets' richer per-class layer set. So there's one road color, not
    // a fill/casing/motorway hierarchy. Quiet white roads read as light channels and
    // let the greens/tans carry the scene.
    static let road = Hue.surface.onLightCanvas.hexString

    // MARK: Labels — shared with the app's own ink ramp (not map-only)
    // Call sites use `Hue.inkSecondary.hexString`; light-v11 keeps its white halos.

    /// Apply the shared static palette to light-v11. Call once from each map's
    /// style-load callback; individual setters stay best-effort across style updates.
    static func recolor(_ map: MapboxMap?) {
        guard let map else { return }
        try? map.setLayerProperty(for: "land", property: "background-color", value: land)

        // The `landuse` fill layer carries EVERY ground class in one layer, gated by a
        // class match + a sizerank-vs-zoom stagger (all verified against the live style
        // JSON — layer ids and class lists are never guessed, a wrong id fails silently).
        // Two stock gates fought the colorful read and are re-cut here:
        //  1. The class match ADMITTED only agriculture/wood/grass/scrub/park/airport/
        //     glacier/pitch/sand — school, hospital, cemetery and commercial ground were
        //     filtered out entirely, so no filter widening = no warm campus patch, ever.
        //     Tilequery ground truth: the CSB campus is one big `school` (college,
        //     sizerank 1) polygon; St. Joe also carries cemetery/pitch/grass polygons.
        //  2. The sizerank stagger hid sizerank-14+ polygons (lawns, pitches,
        //     playgrounds) until ~z16.5 — which is why round 1's green looked sparse at
        //     town zoom no matter its hue. Dropped: the map lives at z11–15, and vector
        //     tiles already generalize away what's too small for a given zoom.
        // Residential keeps its stock step (visible only below z12) but recolors to the
        // land cream, so the low-zoom town wash warms instead of graying.
        let classFilter: [Any] = [
            "all",
            [">=", ["to-number", ["get", "sizerank"]], 0],
            [
                "match", ["get", "class"],
                ["agriculture", "wood", "grass", "scrub", "park", "pitch", "sand",
                 "glacier", "airport", "school", "hospital", "cemetery", "commercial_area"], true,
                "residential", ["step", ["zoom"], true, 12.0, false],
                false,
            ],
        ]
        let classFill: [Any] = [
            "match", ["get", "class"],
            "park", park,
            "pitch", pitch,
            ["wood", "scrub"], wood,
            "grass", grass,
            "agriculture", farmland,
            ["school", "hospital"], campus,
            "commercial_area", commerce,
            "cemetery", cemetery,
            "sand", sand,
            land,   // residential, airport, glacier — melt into the ground
        ]
        try? map.setLayerProperty(for: "landuse", property: "filter", value: classFilter)
        try? map.setLayerProperty(for: "landuse", property: "fill-color", value: classFill)

        // The `national-park` overlay (state forests/parks) ships at 0.2 opacity at
        // town zoom — a big reason round 1 read pale. Same park green, real presence.
        try? map.setLayerProperty(for: "national-park", property: "fill-color", value: park)
        try? map.setLayerProperty(
            for: "national-park", property: "fill-opacity",
            value: ["interpolate", ["linear"], ["zoom"], 5.0, 0.0, 6.0, 0.55, 12.0, 0.4]
        )

        try? map.setLayerProperty(for: "water",    property: "fill-color", value: water)
        try? map.setLayerProperty(for: "waterway", property: "line-color", value: riverInk)
        // The Sauk is a landmark, and light-v11 draws rivers at under 1pt until deep
        // street zoom (stock: exponential 1.3, z9 river 0.1 → z20 river 8) — at the
        // town zooms this map lives at, the river was a hairline that vanished into
        // the cream. Same curve shape, lifted so the river reads at z11–15 without
        // going cartoon-wide at z18+. Streams/ditches (the non-river match arm) keep
        // a thinner profile.
        try? map.setLayerProperty(
            for: "waterway", property: "line-width",
            value: [
                "interpolate", ["exponential", 1.3], ["zoom"],
                9.0,  ["match", ["get", "class"], ["canal", "river"], 0.6, 0.2],
                13.0, ["match", ["get", "class"], ["canal", "river"], 2.2, 1.0],
                20.0, ["match", ["get", "class"], ["canal", "river"], 10.0, 4.0],
            ]
        )
        try? map.setLayerProperty(for: "building", property: "fill-color",         value: building)
        try? map.setLayerProperty(for: "building", property: "fill-outline-color", value: building)
        try? map.setLayerProperty(for: "road-simple", property: "line-color", value: road)

        let labelInk = Hue.inkSecondary.onLightCanvas.hexString
        for id in ["road-label-simple", "settlement-major-label", "settlement-minor-label", "settlement-subdivision-label"] {
            try? map.setLayerProperty(for: id, property: "text-color", value: labelInk)
        }

        // Hide the basemap's OWN business labels. light-v11 ships a `poi-label` symbol layer
        // (source-layer `poi_label`) that names cafés, shops and B&Bs — the exact venues we
        // already draw ourselves from the `places` table, with our own badge + halo'd label.
        // Left on, every POI's name prints TWICE: our bold ink label and Mapbox's italic grey
        // one, overlapping. At mid zoom that doubled text sits under our badges and reads as
        // two stacked, untappable pins — which is how this was first reported.
        //
        // Mapbox's own label collision can't help: our markers are SwiftUI view annotations
        // drawn above the map canvas, so the style never sees them and cannot yield to them.
        // Hiding the layer is the fix; `POICluster.labelledPOIs` already de-conflicts OUR
        // labels against each other, the civic pins, the cluster bubbles and the app chrome.
        //
        // Trade-off, accepted deliberately: this also drops basemap labels for venues we do
        // NOT carry. That is the correct side to err on — a name we render is tappable and
        // opens a real detail sheet, while a basemap name is inert text that looks tappable.
        try? map.setLayerProperty(for: "poi-label", property: "visibility", value: "none")

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
