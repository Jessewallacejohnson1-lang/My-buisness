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
    // MARK: Monochrome preview (see MonoMarkerPalette.swift)
    //
    // Judging the mono MARKERS against this warm cream/green/blue ground would be
    // misleading — the rebrand pairs them with a grayscale basemap (Phase 3b,
    // `rebrand/block-party` commit 23c31a5). These are that commit's values verbatim,
    // not an invented desaturation, so the preview shows the real end state:
    // near-white throughout, with roads the LIGHTEST element and water the darkest.
    //
    // Note what this ground implies for the markers: land is #FAFAF7 and roads are
    // pure white, so a surface-filled POI pin has almost no contrast of its own and
    // leans entirely on its keyline. That is why the POI tier keeps a real stroke
    // rather than relying on fill alone.
    private static var mono: Bool { MarkerSkin.current.isMono }

    // MARK: Ground & natural features
    static var land: String { mono ? "#FAFAF7" : "#F4F3EC" }   // warm cream ground
    // Parks, landcover, woods. Nudged up from the original sage #D6E8C4, which read as
    // "barely there" against the cream ground — parks all but vanished at town zoom.
    // Tuned to Apple Maps' light-mode park green (≈#C7E5B0): enough chroma that green reads
    // as GREEN at a glance, but it still RECEDES as terrain rather than advancing as a flat
    // card. An earlier pass at #B8E6A0 (S58 L76) overshot — large park masses became the
    // loudest thing on screen, and, because the bottom sheet is Liquid Glass, the excess
    // chroma bloomed THROUGH it and tinted the tab bar green at the default zoom.
    static var green: String    { mono ? "#EFEFEC" : "#C2E6AC" }   // parks: one value step below land
    static var water: String    { mono ? "#E4E4E0" : "#9EDAF3" }   // water: darker again, without hue
    static var building: String { mono ? "#F1F1EF" : "#EDEBE1" }   // inert built-form fill

    // MARK: Road network
    // light-v11 consolidates every road class (motorway → residential) into ONE
    // line layer (`road-simple`), differentiated only by width, not color — verified
    // against the style's actual JSON (`GET styles/v1/mapbox/light-v11`), not assumed
    // from Mapbox Streets' richer per-class layer set. So there's one road color, not
    // a fill/casing/motorway hierarchy — near-white, warm-tinted to sit quietly on
    // the cream ground (this is what the reference's residential streets look like;
    // light-v11 has no separate layer to give the highway a darker treatment).
    static var road: String { mono ? "#FFFFFF" : "#FBFAF6" }

    // MARK: Labels — shared with the app's own ink ramp (not map-only)
    // Neighborhood / road labels: #555553 sampled off the reference ≈ Hue.ink2 (#5E5D56).
    // Call sites should use `Hue.ink2.hexString`, not duplicate this hex.
}
