//
//  BasemapPalette.swift
//  Block Party — the map's ONE static cartography palette.
//
//  Pixel-sampled from the Life360/Mobbin reference (Bukit Batok, Singapore):
//  a warm cream ground, sage parks, sky-blue water, and neutral-grey roads with
//  a charcoal label ink shared with the app's own Hue.inkSecondary. These are the only
//  raw hexes the map is allowed — it owns cartography.
//
//  There is deliberately NO time/season/weather modulation. The base map looks the
//  same at every hour, by design — one calm base layer. (The old "Living Basemap"
//  that shifted the palette by time-of-day · season · weather was retired here —
//  see MAP_BUILD_LOG.md.) Pure Foundation.
//

import Foundation

enum BasemapPalette {
    // MARK: Ground & natural features
    static let land     = "#F4F3EC"   // warm cream ground
    static let green    = "#D6E8C4"   // sage — parks, landcover, woods
    static let water    = "#9EDAF3"   // sky blue
    static let building = "#EDEBE1"   // barely lifts off the land

    // MARK: Road network
    // light-v11 consolidates every road class (motorway → residential) into ONE
    // line layer (`road-simple`), differentiated only by width, not color — verified
    // against the style's actual JSON (`GET styles/v1/mapbox/light-v11`), not assumed
    // from Mapbox Streets' richer per-class layer set. So there's one road color, not
    // a fill/casing/motorway hierarchy — near-white, warm-tinted to sit quietly on
    // the cream ground (this is what the reference's residential streets look like;
    // light-v11 has no separate layer to give the highway a darker treatment).
    static let road = "#FBFAF6"

    // MARK: Labels — shared with the app's own ink ramp (not map-only)
    // Neighborhood / road labels: #555553 sampled off the reference ≈ Hue.inkSecondary (#6E6E6E).
    // Call sites should use `Hue.inkSecondary.hexString`, not duplicate this hex.
}
