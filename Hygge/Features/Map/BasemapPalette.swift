//
//  BasemapPalette.swift
//  Hygge — the map's ONE static cartography palette.
//
//  Pixel-sampled from the Life360/Mobbin reference (Bukit Batok, Singapore):
//  a warm cream ground, sage parks, sky-blue water, and neutral-grey roads with
//  a charcoal label ink shared with the app's own Hue.ink2. These are the only
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
    // Parks, landcover, woods. Nudged up from the original sage #D6E8C4, which read as
    // "barely there" against the cream ground — parks all but vanished at town zoom.
    // Tuned to Apple Maps' light-mode park green (≈#C7E5B0): enough chroma that green reads
    // as GREEN at a glance, but it still RECEDES as terrain rather than advancing as a flat
    // card. An earlier pass at #B8E6A0 (S58 L76) overshot — large park masses became the
    // loudest thing on screen, and, because the bottom sheet is Liquid Glass, the excess
    // chroma bloomed THROUGH it and tinted the tab bar green at the default zoom.
    static let green    = "#C2E6AC"   // fresh park green
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
    // Neighborhood / road labels: #555553 sampled off the reference ≈ Hue.ink2 (#5E5D56).
    // Call sites should use `Hue.ink2.hexString`, not duplicate this hex.
}
