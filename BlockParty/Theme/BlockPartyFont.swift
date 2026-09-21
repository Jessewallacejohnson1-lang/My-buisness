//
//  BlockPartyFont.swift
//  Block Party — design tokens (typography)
//
//  Jost is the display, headline, and wordmark face; SF Pro stays the body, UI, and
//  data face through the system helpers; SF Pro Rounded Heavy is scoped to the one
//  role that earned it, the event headline over a photograph (`roundedDisplay`).
//  Atkinson Hyperlegible Bold remains bundled but is no longer referenced. Numbers
//  keep tabular figures by pairing the mono helpers with `.monospacedDigit()` at the
//  call site.
//
//  EVERY helper here scales with Dynamic Type except the three that say, in their
//  own doc comment, why they must not. That is the whole point of this file, and
//  `TypographyScalingGuardTests` is what keeps it true: no other file in the app
//  may name a raw point size, because the two ways of naming one behave oppositely
//  and mixing them is what broke text scaling app-wide.
//
//      Font.system(size:)   FROZEN. Never grows, whatever the user has set.
//      Font.custom(_:size:) Scales, with NO ceiling and no relationship to the
//                           system face beside it.
//
//  Measured before this file was fixed: at AX5 a 22pt Jost title reached ~55pt
//  inside a 208pt column and truncated mid-word, while the 13pt SF body beside it
//  did not move at all. Both faces now scale against a shared text style, so they
//  move together.
//

import SwiftUI
import CoreText

/// Verified PostScript names of the bundled Jost variable font instances.
enum Face {
    static let displayRegular = "Jost-Regular"
    static let displayMedium  = "JostRoman-Medium"
    static let displaySemi    = "JostRoman-SemiBold"
    static let displayBold    = "JostRoman-Bold"
    static let logo           = "JostRoman-SemiBold"
}

/// Register every bundled .ttf so its PostScript name resolves. Idempotent.
func registerBlockPartyFonts() {
    guard let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) else { return }
    for url in urls {
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

extension Font {

    // MARK: - The ladder

    /// The system text style nearest a given point size — the scaling reference
    /// every helper below is measured against.
    ///
    /// The steps are Apple's own at the default content size (caption2 11, caption
    /// 12, footnote 13, subheadline 15, callout 16, body 17, title3 20, title2 22,
    /// title 28, largeTitle 34). Ties round UP, because this file exists to serve
    /// the user who asked for larger text and the cost of a point too big is lower
    /// than the cost of a point too small.
    ///
    /// Custom faces keep their exact size and use this only as the rate at which
    /// they grow. The SF helpers cannot: SwiftUI has no `system(size:relativeTo:)`,
    /// so a system font either names a frozen size or names a style. They name a
    /// style, which means a size that is not one of the ten steps lands on its
    /// neighbour — `sans(14)` renders at 15.
    ///
    /// ponytail: the app currently spends 22 distinct sizes across these 10 steps,
    /// so the argument is closer to a hint than a measurement. Collapsing the call
    /// sites onto the five named roles in `DayTypeScale` is the real cleanup and it
    /// needs a design eye on screenshots, not a rule in a token file.
    static func nearestTextStyle(to size: CGFloat) -> TextStyle {
        switch size {
        case ..<11.5:   .caption2     // 11
        case ..<12.5:   .caption      // 12
        case ..<13.5:   .footnote     // 13
        case ..<15.5:   .subheadline  // 15
        case ..<16.5:   .callout      // 16
        case ..<18.5:   .body         // 17
        case ..<21.0:   .title3       // 20
        case ..<24.0:   .title2       // 22
        case ..<31.0:   .title        // 28
        default:        .largeTitle   // 34
        }
    }

    // MARK: - Display / headings — Jost

    /// Jost Bold at an exact size, scaling against the nearest text style.
    ///
    /// The size survives verbatim here — a custom face can do what the system face
    /// cannot — so pass `relativeTo:` only when a heading should grow at a rate its
    /// own size does not imply.
    static func display(_ size: CGFloat, relativeTo style: TextStyle? = nil) -> Font {
        .custom(Face.displayBold, size: size, relativeTo: style ?? nearestTextStyle(to: size))
    }

    /// Jost SemiBold at an exact size, scaling against the nearest text style.
    static func displaySemi(_ size: CGFloat, relativeTo style: TextStyle? = nil) -> Font {
        .custom(Face.displaySemi, size: size, relativeTo: style ?? nearestTextStyle(to: size))
    }

    /// Event headline face — SF Pro Rounded at Heavy.
    ///
    /// The third face in a file whose header says there are two, so it is scoped on
    /// purpose: the headline that sits ON an event photograph, and the same headline
    /// on the event's detail page. Both were lighter than the job — SF Pro Bold on the
    /// card, Jost SemiBold on the detail page — and a headline over a photograph needs
    /// weight before it needs personality. Heavy at a large x-height with closed
    /// apertures is what holds white type against a picture.
    ///
    /// It is a system face, so there is no file to bundle, no licence to carry, and
    /// it inherits Dynamic Type from the text style like every other helper here.
    ///
    /// Not a match for the reference this was chosen from. That reference is a
    /// geometric sans in the Circular mould — taller x-height, shorter ascenders,
    /// a diagonally cut `t`, flat-cut terminals rather than rounded ones. Rounded
    /// Heavy is the free approximation, and switching to the real thing means
    /// bundling a licensed file and changing the one line below.
    static func roundedDisplay(_ size: CGFloat, relativeTo style: TextStyle? = nil) -> Font {
        .system(style ?? nearestTextStyle(to: size), design: .rounded).weight(.heavy)
    }

    // MARK: - UI / body — system

    static func sansLight(_ size: CGFloat) -> Font { .system(nearestTextStyle(to: size)).weight(.light) }
    static func sans(_ size: CGFloat) -> Font { .system(nearestTextStyle(to: size)) }
    static func sansMedium(_ size: CGFloat) -> Font { .system(nearestTextStyle(to: size)).weight(.medium) }
    static func sansSemibold(_ size: CGFloat) -> Font { .system(nearestTextStyle(to: size)).weight(.semibold) }
    static func sansBold(_ size: CGFloat) -> Font { .system(nearestTextStyle(to: size)).weight(.bold) }

    // Data — system, paired with `.monospacedDigit()` at the call site for tabular
    // figures (was Geist Mono). Same metrics as the sans helpers by design; the
    // separate name records the intent at the call site.
    static func mono(_ size: CGFloat) -> Font { .system(nearestTextStyle(to: size)) }
    static func monoMedium(_ size: CGFloat) -> Font { .system(nearestTextStyle(to: size)).weight(.medium) }

    // MARK: - The three that must not scale

    /// Logo — Jost SemiBold, frozen. A logo is a mark, not text: it holds its
    /// proportions against the artwork beside it at every content size.
    static func logo(_ size: CGFloat) -> Font { .custom(Face.logo, fixedSize: size) }

    /// A glyph drawn at a fixed size because it is ARTWORK, not text.
    ///
    /// Reach for this only when growing the thing would break what it is drawn
    /// inside — a symbol centred in a fixed-diameter map marker, a decorative burst
    /// over a photo, a placeholder inside a circular avatar. It is deliberately the
    /// ugly-sounding name in this file: text that reaches for it is a bug.
    ///
    /// Anything using this owes the reader an alternative — `accessibilityHidden`
    /// if it is decorative, a label if it carries meaning, and on map chrome an
    /// `.accessibilityShowsLargeContentViewer()` so a long press still enlarges it.
    static func glyph(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}
