//
//  MonoMarkerPalette.swift
//  Hygge — the monochrome ("ink-on-paper") marker skin, previewed here so the
//  treatment can be approved BEFORE it is ported into the Block Party rebrand.
//
//  WHY THIS FILE EXISTS
//  The rebrand (`rebrand/block-party`, Phase 2 "monochrome ink-on-paper design
//  tokens" + Phase 3b "grayscale basemap") ships SIX tokens and no accent at all:
//
//      ink #111111 · paper #FAFAF7 · surface #FFFFFF
//      inkSecondary #6E6E6E · hairline #E7E7E4 · fill #F1F1EF
//
//  Phase C of the map overhaul, by contrast, encodes nearly everything in HUE:
//  civic category tint (map green / honey600 / sky600), POI family tint
//  (terracotta food / slate business), and the sacred live-coral #FF6B57. Port
//  Phase C as-is and it re-introduces exactly the colour the rebrand spent three
//  commits removing. So the encoding has to move off hue and onto something the
//  monochrome system still has: VALUE (how dark the fill is), SHAPE, and MOTION.
//
//  THE VALUE LADDER
//  Three tiers, darkest = most important, which also fixes a defect the colour
//  version carries. `PlaceFamily.tint` already documents that the saturated POI
//  dots "visually OUTRANKED the civic landmarks they are supposed to defer to",
//  and it papered over that by desaturating the POI tints toward the civic band.
//  In monochrome the fix is structural instead of a hue tweak:
//
//    1. POI (food / business) — surface fill, hairline stroke, ink glyph.
//       LIGHTEST. A business defers to a landmark by construction, not by luck.
//    2. Civic (curated landmarks) — ink fill, surface glyph. DARKEST static tier.
//    3. Live — ink fill + a pulsing ink halo + an always-visible name label.
//       MOTION carries liveness, not hue.
//
//  Category is still told apart by GLYPH, which costs nothing here: PlaceCategoryMap
//  already maps ~40 Google primaryTypes onto distinct SF Symbols, and every
//  SpotCategory has a `filledSymbol`. That was already the stated rule for the two
//  POI families ("differentiated by GLYPH, not colour") — monochrome just extends
//  the same rule across civic as well.
//
//  A note on what this GAINS. Encoding rank in value rather than hue survives
//  greyscale printing, colour-blindness, and a dimmed screen in sunlight. The
//  colour version's green/honey/sky civic trio sits at near-identical luminance,
//  so it was never distinguishable to a deuteranope in the first place; this
//  treatment is strictly more legible, not merely "the rebrand's constraint".
//
//  HOW TO COMPARE: launch with `-mono-markers` for this skin, without it for the
//  existing colour skin. Same build, so the two screenshots differ ONLY in skin.
//
//  PORTING: the raw hexes below are the Block Party tokens verbatim. In the
//  rebrand these become `BlockPartyColor.ink` / `.surface` / `.hairline` /
//  `.inkSecondary` — a one-line swap per role, no re-derivation. That is the whole
//  point of routing every marker colour through the semantic roles in `MarkerSkin`
//  rather than through raw hexes at the call sites.
//

import SwiftUI

// MARK: - Skin selection

/// Which marker colour system the map renders. Selected once per launch.
///
/// This is a preview seam, NOT a permanent setting: once the monochrome treatment
/// is approved and ported, the rebrand keeps only `.mono` and Hygge keeps only
/// `.warm`. Neither app ships a runtime toggle.
enum MarkerSkin {
    /// The existing Hygge colour system — civic category tints, POI family tints, live coral.
    case warm
    /// Block Party ink-on-paper — rank by value, category by glyph, liveness by motion.
    case mono

    /// DEBUG-only: `-mono-markers` selects the monochrome skin so both treatments
    /// can be screenshotted from ONE build. Release always renders `.warm` here;
    /// the rebrand will hard-select `.mono` at the token layer instead.
    static let current: MarkerSkin = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-mono-markers") ? .mono : .warm
        #else
        return .warm
        #endif
    }()

    var isMono: Bool { self == .mono }
}

// MARK: - Block Party tokens (verbatim)

/// The rebrand's six monochrome tokens, copied exactly from
/// `rebrand/block-party:BlockParty/Theme/BlockPartyColor.swift`.
///
/// Hardcoded hexes are normally banned (CLAUDE.md), and these are NOT claiming the
/// map-cartography carve-out — they are a deliberate, temporary mirror of another
/// branch's tokens so this preview matches the real target exactly. They are
/// replaced by `BlockPartyColor.*` at port time and this enum is deleted.
enum BPToken {
    static let ink          = Color(hex: 0x111111)
    static let paper        = Color(hex: 0xFAFAF7)
    static let surface      = Color(hex: 0xFFFFFF)
    static let inkSecondary = Color(hex: 0x6E6E6E)
    static let hairline     = Color(hex: 0xE7E7E4)
    static let fill         = Color(hex: 0xF1F1EF)
}

// MARK: - Semantic marker roles

/// Every colour a map marker needs, named by ROLE rather than by hue.
///
/// Both skins answer the same questions, so the renderers (`MapPinBadge`,
/// `POIBadge`, `POIClusterBubbleView`) contain no `if mono` branching — they ask
/// for a role and get whichever skin is active. That is what keeps the port
/// mechanical: swap the values behind these roles, touch no view code.
enum MarkerRole {

    // — Civic (curated landmark) pins —

    /// Fill of a civic pin at rest. Warm: the category tint. Mono: ink (top static tier).
    static func civicFill(_ category: SpotCategory) -> Color {
        MarkerSkin.current.isMono ? BPToken.ink : category.tint
    }

    /// The glyph drawn inside a civic pin — always the value that reads on `civicFill`.
    static var civicGlyph: Color {
        MarkerSkin.current.isMono ? BPToken.surface : .white
    }

    // — POI (food / business) pins —

    /// Fill of a POI pin. Warm: the family tint. Mono: surface when the badge is
    /// EXPANDED, inkSecondary when it is compact.
    ///
    /// The split is not decoration — it fixes a defect caught by screenshot at zoom
    /// 13.4. A compact badge drops its glyph (there is no room at 12pt), so a
    /// surface-filled compact dot is a white circle, on #FAFAF7 land, edged only by a
    /// #E7E7E4 hairline: it effectively disappeared, while civic dots and clusters
    /// stayed crisp. The light tier only earns its lightness while it is CARRYING a
    /// dark glyph — that pairing is what makes it read. With the glyph gone the same
    /// fill is just missing contrast, so the dot inverts to the mid grey it shares
    /// with clusters (size and the absent count still tell the two apart).
    ///
    /// Warm never had this problem: a saturated terracotta/slate dot carries its own
    /// contrast at any size, which is exactly the crutch monochrome removes.
    static func poiFill(_ family: PlaceFamily, expanded: Bool) -> Color {
        guard MarkerSkin.current.isMono else { return family.tint }
        return expanded ? BPToken.surface : BPToken.inkSecondary
    }

    /// The glyph inside a POI pin. Mono inverts to ink, since the fill is now light.
    static var poiGlyph: Color {
        MarkerSkin.current.isMono ? BPToken.ink : .white
    }

    /// The ring around a pin. Warm uses a white keyline to lift the saturated fill
    /// off the basemap; mono uses a hairline on light POI pins (which need a real
    /// edge to read against paper) and keeps the white keyline on ink-filled pins.
    static func pinStroke(isLightFill: Bool) -> Color {
        guard MarkerSkin.current.isMono else { return Hue.surface }
        return isLightFill ? BPToken.hairline : BPToken.surface
    }

    // — Live —

    /// Fill of a live pin. Warm: the sacred coral. Mono: ink — liveness is carried
    /// by the pulse + the always-on label, not by hue.
    ///
    /// The warm value is passed in because `LIVE_COLOR` is file-private to
    /// SJMapView.swift, and its "one-line rebrand" comment means it to stay the single
    /// place coral is named. Widening it to reach it from here would break that.
    static func liveFill(warm: Color) -> Color {
        MarkerSkin.current.isMono ? BPToken.ink : warm
    }

    /// The expanding halo behind a live pin — the primary liveness signal in mono.
    static func liveRing(warm: Color) -> Color {
        MarkerSkin.current.isMono ? BPToken.ink : warm
    }

    // — Clusters —

    /// Cluster disc fill. The warm value repeats `POIClusterBubbleView.bubbleBase`
    /// (#FBFAF5) because that constant is private to the view; the renderer passes
    /// its own base in rather than this role reaching across the boundary.
    ///
    /// Mono uses inkSecondary — a MID grey — which is the fix for a defect the first
    /// cut shipped: with clusters on surface and POI pins on surface, both were white
    /// discs with a hairline ring and differed only by digit-vs-glyph. Two different
    /// object classes read as one. The three classes now separate by value alone:
    ///
    ///     POI (one place)      surface   — lightest
    ///     cluster (many)       inkSecondary — mid
    ///     civic (landmark)     ink       — darkest
    ///
    /// which also keeps the rank honest: a clump of businesses still defers to a
    /// curated landmark, exactly as in the colour skin.
    static func clusterFill(warmBase: Color) -> Color {
        MarkerSkin.current.isMono ? BPToken.inkSecondary : warmBase
    }

    /// Cluster border. Warm tinted it by family; mono drops the ring to `.clear` —
    /// the mid-grey disc is now its own edge, and a hairline on top of it only
    /// muddied the silhouette. This also kills the periwinkle cast the tinted
    /// border gave the bubbles.
    static func clusterStroke(_ family: PlaceFamily) -> Color {
        MarkerSkin.current.isMono ? .clear : family.tint.opacity(0.9)
    }

    /// The cluster's count. Mono flips it to surface because the disc is now a
    /// mid-grey (see `clusterFill`) rather than a light one.
    static var clusterText: Color {
        MarkerSkin.current.isMono ? BPToken.surface : Hue.mapInk
    }

    // — Live, static —

    /// A concentric ring drawn OUTSIDE a live badge, and mono-only.
    ///
    /// The first cut of this skin carried liveness on the pulse alone, and that was
    /// wrong: coral was a STATIC signal that the pulse merely amplified, so dropping
    /// to motion-only made "live" invisible in any still frame — and to anyone who
    /// glances rather than watches. Verified by screenshot: a forced-live Downtown was
    /// indistinguishable from every other civic pin. This ring restores a static cue;
    /// the pulse rides on top of it as amplification, the same division of labour the
    /// colour skin had.
    static var liveStaticRing: Color? {
        MarkerSkin.current.isMono ? BPToken.ink : nil
    }

    // — Labels —

    /// A pin's name label. Mono drops to ink so labels never carry category meaning
    /// (they can't, without hue) — the glyph is the only category channel.
    static func label(base: Color) -> Color {
        MarkerSkin.current.isMono ? BPToken.ink : base
    }
}
