//
//  MonoMarkerPalette.swift
//  Block Party — every map-marker colour, named by ROLE rather than by hue.
//
//  WHY ROLES AND NOT TOKENS AT THE CALL SITE
//  The map overhaul (Phases A–C, ported from `feat/map-poi-markers`) encoded almost
//  everything in HUE: civic category tint, POI family tint, and the live coral. This
//  app has no accent — six tokens, all greys — so that encoding had to move onto
//  what monochrome still has: VALUE, SHAPE and MOTION. Routing every marker colour
//  through one role table is what let that swap happen without touching a single
//  renderer, and it is what will let the next rebrand happen the same way.
//
//  THE VALUE LADDER — darkest is most important
//
//    1. POI (food / business)  surface / inkSecondary   lightest
//    2. cluster (many places)  inkSecondary             mid
//    3. civic (landmark)       ink                      darkest
//    4. live                   ink + a STATIC ring + the pulse
//
//  This also repaired a defect the colour version shipped with: its own comments
//  recorded that the saturated POI dots "visually OUTRANKED the civic landmarks they
//  are supposed to defer to", and it treated that by desaturating the POI tints toward
//  the civic band. Here the fix is structural — a business is lighter than a landmark
//  by construction, not by tuning.
//
//  Category is told apart by GLYPH, which costs nothing: PlaceCategoryMap already maps
//  ~40 Google primaryTypes onto distinct SF Symbols and every SpotCategory has a
//  `filledSymbol`. "Differentiated by glyph, not colour" was already the stated rule
//  for the two POI families; monochrome just extends it across civic as well.
//
//  WHAT THIS GAINS, beyond satisfying the brand constraint: rank encoded in value
//  survives greyscale, colour-blindness, and a dimmed screen outdoors. The old
//  green/honey/sky civic trio sat at near-identical luminance, so it was never
//  distinguishable to a deuteranope in the first place.
//
//  THREE DEFECTS FOUND BY SCREENSHOT (each invisible in code review — keep them fixed):
//   1. Clusters and POI pins were both light discs with a hairline ring, so two
//      different object classes read as one. Clusters took the mid-grey tier.
//   2. Liveness carried by the pulse ALONE vanished in a still frame. Coral had been a
//      STATIC signal that the pulse merely amplified; `liveStaticRing` restores that,
//      with the pulse riding on top. Motion must never be the ONLY channel.
//   3. A compact POI dot drops its glyph at 12pt, and a surface-filled dot on
//      near-white land then has no contrast at all. The light tier only earns its
//      lightness WHILE carrying a dark glyph, so compact dots invert to mid grey.
//

import SwiftUI

/// Every colour a map marker needs, named by role.
///
/// Renderers (`MapPinBadge`, `POIBadge`, `POIClusterBubbleView`) ask for a role and
/// never branch on the design system — that indirection is the whole point.
enum MarkerRole {

    // — Civic (curated landmark) pins —

    /// Fill of a civic pin at rest: the top static tier.
    ///
    /// Takes the category for signature parity with the colour system it replaced — a
    /// future skin could differentiate landmarks again without touching a call site.
    static func civicFill(_ category: SpotCategory) -> Color { Hue.ink }

    /// The glyph inside a civic pin — the value that reads on `civicFill`.
    static var civicGlyph: Color { Hue.surface }

    // — POI (food / business) pins —

    /// Fill of a POI pin: surface when EXPANDED, inkSecondary when compact.
    ///
    /// See defect 3 in the header — this split is a fix, not decoration. Do not
    /// collapse it back to one value without re-checking a compact-zoom screenshot.
    static func poiFill(_ family: PlaceFamily, expanded: Bool) -> Color {
        expanded ? Hue.surface : Hue.inkSecondary
    }

    /// The glyph inside an expanded POI pin, which sits on a light fill.
    static var poiGlyph: Color { Hue.ink }

    /// A pin's keyline. A light-filled pin needs a real hairline edge to read against
    /// paper; a dark-filled one takes the white lift that separates it from the map.
    static func pinStroke(isLightFill: Bool) -> Color {
        isLightFill ? Hue.hairline : Hue.surface
    }

    // — Live —

    /// Fill of a live pin. Liveness is carried by the ring + pulse, not by the fill,
    /// so this matches the civic tier rather than introducing a fourth value.
    static var liveFill: Color { Hue.ink }

    /// The expanding halo behind a live pin — the motion half of the live signal.
    static var liveRing: Color { Hue.ink }

    /// A STATIC concentric ring outside a live badge — the half of the live signal that
    /// survives a still frame. See defect 2; do not remove without replacing the cue.
    static var liveStaticRing: Color { Hue.ink }

    // — Clusters —

    /// The cluster disc: the mid tier, which is what separates a cluster from the
    /// lighter POI pins it stands for (defect 1).
    static var clusterFill: Color { Hue.inkSecondary }

    /// Cluster border. The mid-grey disc is its own edge; a ring on top only muddied
    /// the silhouette, and a tinted one was the periwinkle cast the colour skin fought.
    static func clusterStroke(_ family: PlaceFamily) -> Color { .clear }

    /// The count, which sits on the mid-grey disc.
    static var clusterText: Color { Hue.surface }

    // — Labels —

    /// A pin's name label. Always ink: labels can't carry category meaning without hue,
    /// so the glyph is the only category channel and the text just has to be readable.
    static func label(base: Color) -> Color { Hue.ink }
}
