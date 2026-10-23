//
//  BlockPartyColor.swift
//  Block Party — design tokens (colors)
//
//  Monochrome ink-on-paper system (July 2026): one warm page ground, white cards,
//  charcoal ink, and a compact neutral ramp with no accent colour.
//
//  DARK MODE (Aug 2026). Every token below is DYNAMIC: one light value, one dark
//  value, resolved by the system through a `UIColor` trait provider. Nothing in the
//  app asks which appearance it is in — a view that used `Hue.paper` before still
//  uses `Hue.paper`, and the whole app follows.
//
//  The dark ramp is the light one inverted around the same warmth, not a generic
//  grey scale: the cream page becomes #141412 and cards #1D1D1A, so a card still
//  reads as a lighter object sitting on the page rather than as a hairline box.
//
//  THE EXCEPTIONS ARE THE TWO FIXED-LIGHT GROUNDS. Mapbox renders LIGHT
//  cartography in both appearances (`BasemapPalette`), so ink drawn ON the map
//  canvas must stay ink or a pin badge turns white-on-white; and since round 2
//  Phase D the pin card's status wash (`statusTint`) is the same light grey in
//  both appearances, so its content pins to the light ramp too
//  (`PinDetailSheet.CardInk`). Those call sites resolve their tokens through
//  `onLightCanvas` below rather than following the system. That is scoping, not
//  an opt-out: neither canvas actually changes.
//

import SwiftUI
import UIKit

extension Color {
    /// Build a Color from a 0xRRGGBB hex literal.
    ///
    /// `nonisolated` because the module defaults to MainActor isolation and a
    /// palette is not main-actor state: the pure
    /// `nonisolated` token tables build their colours here, and an isolated
    /// initializer would trip the 0-warning bar at every one of those call sites.
    /// See the MainActor-default gotcha in CLAUDE.md.
    nonisolated init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    /// A token with two values: what it is on paper, and what it is in the dark.
    ///
    /// Built through `UIColor`'s trait provider rather than through SwiftUI's
    /// `@Environment(\.colorScheme)` because a token has to resolve where there is
    /// no view — `Color.hexString` hands values to Mapbox's runtime style setters,
    /// and a `ShapeStyle` is read far from any environment.
    nonisolated init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traits in
            UIColor(bp: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// This token as it renders in LIGHT appearance, whatever the device is set to.
    ///
    /// For anything drawn over a ground that does NOT follow the system appearance.
    /// Two such grounds exist: the Mapbox basemap (light cartography in both modes)
    /// and the pin-detail status card's fixed pale `statusTint` wash. Ink over
    /// either keeps its light-mode value or it disappears (a dark-mode near-white
    /// `ink` measured ~1.1:1 on the wash — round 2 Phase D).
    var onLightCanvas: Color {
        Color(UIColor(self).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)))
    }

    /// The reverse of `init(hex:)` — a `"#RRGGBB"` string, for APIs (like Mapbox's
    /// runtime style setters) that want a hex string rather than a `Color`. Lets a
    /// call site reuse a `Hue` token instead of duplicating its hex as a literal.
    var hexString: String {
        let c = UIColor(self).cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                  intent: .defaultIntent, options: nil) ?? UIColor(self).cgColor
        let comps = c.components ?? [0, 0, 0, 1]
        let r = Int((comps[0] * 255).rounded()), g = Int((comps[1] * 255).rounded()), b = Int((comps[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

extension UIColor {
    /// The `Color(hex:)` ramp, one level down, so the dynamic provider above can
    /// build its two ends without bouncing through SwiftUI.
    fileprivate nonisolated convenience init(bp hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Block Party palette. One namespace so call sites read `Hue.paper`, `Hue.ink`, etc.
///
/// Every token carries both appearances. The dark column is measured, not guessed:
/// `ink` on `paper` is 16.3:1 and `inkSecondary` on `surface` 6.0:1.
///
/// `nonisolated` (the module defaults to MainActor): a palette is not main-actor
/// state, and the pure token tables that build on it — `YourDayRailPalette`,
/// are themselves `nonisolated`. See the MainActor-default
/// gotcha in CLAUDE.md.
nonisolated enum Hue {
    // primary text, buttons, FABs, active states, pins
    static let ink           = Color(light: 0x111111, dark: 0xF2F1EC)
    // app background (warm white → warm near-black, same warmth)
    static let paper         = Color(light: 0xFAFAF7, dark: 0x141412)
    // cards — a step ABOVE the page in both modes, so a card is still an object
    static let surface       = Color(light: 0xFFFFFF, dark: 0x1D1D1A)
    // secondary text, captions, inactive
    static let inkSecondary  = Color(light: 0x6E6E6E, dark: 0x9C9A93)
    // borders, dividers
    static let hairline      = Color(light: 0xE7E7E4, dark: 0x33332E)
    // inert fills, placeholders, skeletons
    static let fill          = Color(light: 0xF1F1EF, dark: 0x23231F)

    /// A border that has to be SEEN rather than merely felt — a dashed edge, a
    /// stronger rule. One step darker than `hairline`; it was #D8D6CE written out
    /// twice (the day sheet's checkbox and the rail's suggested card) before it was
    /// a token, which is exactly the drift `BlockPartyColor` exists to prevent.
    static let edge          = Color(light: 0xD8D6CE, dark: 0x45443D)

    /// The outline of an interactive control that is currently EMPTY — an unchecked
    /// box. WCAG 1.4.11 asks 3:1 of any non-text control boundary, and the old
    /// #D8D6CE measured 1.46:1 on a white card, so an unchecked box read as an
    /// absence rather than as something to press. This warm grey measures 3.46:1 on
    /// white and 4.89:1 on the dark card, so one value serves both appearances.
    static let control       = Color(hex: 0x8C8A82)

    /// The pin-detail sheet's status-card wash: a plain light grey, the light `fill`
    /// value. It is the same in BOTH appearances, so the card's content pins to the light
    /// ramp via `onLightCanvas` (`PinDetailSheet.CardInk`). The header dot is ink, and
    /// `now` green while live.
    static let statusTint    = Color(hex: 0xF1F1EF)

    /// The like state, and nothing else. A heart that stays ink reads as a shape;
    /// a heart that turns red reads as something you did — which is the whole job of
    /// this control (Jesse, 2026-09-19). Same value in both appearances: it is a
    /// small filled glyph, not text, so it does not need the dark ramp's lift.
    ///
    /// This is the one red in the app. It is state, not chrome: never a border, never
    /// a background, never an error colour.
    static let heart         = Color(hex: 0xFF3040)

    /// **The brand yellow.** The logo's field colour, sampled from the master
    /// (`docs/brand/source-logo-1254.png`): the modal pixel across the field, not an
    /// eyeballed approximation. This is the app's ONE accent (Jesse, 2026-09-18) and
    /// every yellow in the UI derives from it — never a second yellow, never a
    /// call-site hex.
    ///
    /// Re-sampled 2026-09-19 for the wordmark logo: 0xF2B800 (the retired
    /// wave-figure icon's arcs) → 0xFCE804. The rule did not change, the artwork did.
    ///
    /// Accents are small by rule: the Town bar's map disc and every saved bookmark's
    /// fill today, and whatever else Jesse scopes in later. The app's ground stays
    /// white/paper, except the top of the Daily page (Jesse, 2026-10-01).
    nonisolated static let brandYellowHex: UInt32 = 0xFCE804

    /// The brand yellow at FULL strength, solid. Four uses: the Town bar's map disc
    /// (2026-09-24), the fill of every saved bookmark, `BookmarkGlyph` (Jesse,
    /// 2026-09-26/27), the yellow ground at the top of the Daily page (Jesse,
    /// 2026-10-01), and the date on the Town's Event of the day poster, as DICE prints
    /// its own (Jesse, 2026-10-19, BP app event-card 03). The selected tab-bar icon was
    /// yellow from 2026-09-25 until the Instagram bar made it ink (Jesse, 2026-09-27). It
    /// was the tab bar's Create disc until Create was removed on 2026-09-24, which is why
    /// it is a disc token rather than a map one. The map disc used to be glass tinted with the yellow at 68%
    /// (`mapWash`, deleted 2026-09-24): a tint is not the brand yellow, and it went
    /// mustard over photos.
    ///
    /// DESIGN.md's "accents are small by rule" still holds: the map disc, the saved
    /// bookmark, Daily's top and the poster's date are the four, each scoped in by Jesse.
    /// A fifth is his call, not an agent's.
    static let brandDisc     = Color(hex: brandYellowHex)

    /// Ink drawn ON `brandDisc`, pinned to the LIGHT ramp.
    ///
    /// The disc is the same yellow in both appearances, so it is a fixed canvas in
    /// exactly the sense `Color.onLightCanvas` exists for. Following the system here
    /// would put the dark ramp's near-white `ink` (#F2F1EC) on #FCE804 at **1.11:1**
    /// — the glyph would vanish in Dark Mode. The light ink measures **15.0:1** on it.
    ///
    /// White on this yellow is 1.26:1, so a white glyph is never an option here.
    ///
    /// Written as the hex rather than `ink.onLightCanvas`, which is what the map's
    /// fixed-canvas tokens use: `Hue` is `nonisolated` and `onLightCanvas` is a
    /// MainActor-isolated property, so routing through it here is a warning, and
    /// this file holds the zero-warning bar. `BrandDiscContrastTests` pins the two
    /// together so the restated value cannot drift from `ink`'s light column.
    nonisolated static let onBrandDiscHex: UInt32 = 0x111111
    static let onBrandDisc   = Color(hex: onBrandDiscHex)

    // MARK: The Meetup pill (RSVP and Invite; Jesse picked Meetup's black, 2026-10-17)

    /// The pill's fill, lit from above, measured off Meetup's iOS pills at 3x down a column
    /// clear of the word (Figma "Meetup depth"): lighter at the top edge, darkest a quarter
    /// of the way down, a little lighter at the bottom. Charcoal, not `ink`: pure ink hides
    /// both the light and the shadow. The same in both appearances while dark mode waits
    /// (iOS MEMORY.md, 2026-09-24); they get dark values when it returns.
    static let pillTop       = Color(hex: 0x3A3A3C)
    static let pillDeep      = Color(hex: 0x29292B)
    static let pillBottom    = Color(hex: 0x353439)
    /// The 1 pt line of light along the pill's inside top: white at 8%.
    static let pillRim       = Color(hex: 0xFFFFFF, alpha: 0.08)
    /// A called-off Event's pill, which says "Canceled" (Jesse, 2026-10-17): Apple's own red.
    /// The second red after `heart`, and for this one pill only.
    static let canceled      = Color(uiColor: .systemRed)
    /// "Report photo" in a Town card's ••• sheet (BP app place-photos 06): Apple's own red, as
    /// Instagram draws its Report and Apple's menu draws the same row on a page's photo.
    static let report        = Color(uiColor: .systemRed)
    /// The dot before "Now" on a Town card whose event is on (Jesse, 2026-10-20: "use the word
    /// now with green dot"): Apple's own green. A game's "Live" keeps Apple's red.
    static let now           = Color(uiColor: .systemGreen)
    /// The Town's Event of the day poster, DICE's dark card (the approved Round 3 page, BP app
    /// event-card 03), which its photo fades into. The same in both appearances: a poster.
    static let poster        = Color(hex: 0x1A1A1A)

    // MARK: Search (the tab's Reference: Jesse's mockup v7 and its Figma frames, 2026-10-02)

    /// The search field's grey: iOS's own search-field fill, #767680 at 12%.
    static let searchField   = Color(hex: 0x767680, alpha: 0.12)
    /// The field's magnifier and its "Search" prompt.
    static let searchFaint   = Color(hex: 0x8A8A8E)
    /// The round clear button inside the field.
    static let searchClear   = Color(hex: 0xA3A3A8)
    /// An unselected filter pill's outline.
    static let searchChipEdge = Color(light: 0xDCDCD8, dark: 0x3A3A35)
    /// The warm brown of the floor under a logo: the backdrop darkens toward it at the
    /// bottom (5% to 10%), so the logo stands on something.
    static let searchFloor   = Color(hex: 0x46321E)
    /// The light a logo catches as the phone tilts (`LogoShine`): white, faded by the band.
    static let logoShine     = Color(hex: 0xFFFFFF)
    /// A place's name over its photo (`PlaceNameArt`): white on a dark photo, ink on a light one,
    /// in either theme, as the photo decides; and the soft shadow under each.
    static let nameOnDark    = Color(hex: 0xFFFFFF)
    static let nameOnLight   = Color(hex: 0x111111)
    static let nameShadow    = Color(hex: 0x000000)
    /// The map's ground, buildings and greens, Uber's (`BasemapPalette`; Jesse, 2026-10-23).
    /// One value each: the map is light cartography in both appearances.
    static let mapLand       = Color(hex: 0xECECF4)
    static let mapBuilding   = Color(hex: 0xE0E0E4)
    static let mapPark       = Color(hex: 0xACE0B8)
    /// The map's top and bottom edge washes: the land in light mode, so the edges
    /// fade into the ground instead of a lighter band; the dark page in dark mode.
    static let mapEdge       = Color(light: 0xECECF4, dark: 0x141412)
    /// The logo wall's one studio backdrop, and the hue the cast shadows take on it.
    nonisolated static let searchStudioHue: Double = 34

    /// A colour from hue (degrees), saturation and lightness (0–100), as CSS writes it.
    /// Search's photo-shoot backdrops and cast shadows are computed from each logo's
    /// own hue, so they can't be listed here one by one; this is where they turn into
    /// colours.
    nonisolated static func hsl(_ h: Double, _ s: Double, _ l: Double) -> Color {
        let (r, g, b) = hslToRGB(h, s, l)
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    nonisolated static func hslToRGB(_ h: Double, _ s: Double, _ l: Double) -> (Double, Double, Double) {
        let s = s / 100, l = l / 100
        let a = s * min(l, 1 - l)
        func f(_ n: Double) -> Double {
            let k = (n + h / 30).truncatingRemainder(dividingBy: 12)
            return l - a * max(-1, min(k - 3, 9 - k, 1))
        }
        return (f(0), f(8), f(4))
    }
}
