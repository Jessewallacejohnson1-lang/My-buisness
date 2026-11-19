//
//  BlockPartyFont.swift
//  Block Party — design tokens (typography)
//
//  Two bundled faces and Apple's. Inter Tight is the header and button-word face (`display`,
//  `displaySemi`; Jesse, 2026-11-02: "all headers besides events"); BP Event Heading is scoped
//  to the one role it was drawn for, the event headline (`eventDisplay`); everything else is SF
//  Pro, Apple's face, through the sans, mono and apple helpers and `glyph` for symbols. BP Body,
//  Fraunces and Jost left the app on 2026-11-18 (Jesse: "cut bp body frauces and jost", BP app
//  backlog 35). Numbers keep tabular figures by pairing the mono helpers with
//  `.monospacedDigit()` at the call site.
//
//  EVERY helper here scales with Dynamic Type except `glyph`, which says, in its
//  own doc comment, why it must not. That is the whole point of this file, and
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

/// Verified PostScript names of the bundled faces.
enum Face {
    /// Inter Tight (OFL, `InterTight-OFL.txt`), static SemiBold and Bold cut from the Google
    /// Fonts variable font with fontTools' instancer: headers and button words.
    static let displaySemi    = "InterTight-SemiBold"
    static let displayBold    = "InterTight-Bold"

    /// BP Event Heading — the event headline, and nothing else.
    static let eventHeadline  = "BPEventHeading-Regular"
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
    /// Display faces keep their exact size and use this only as the rate at which
    /// they grow. The body helpers land on the step instead — `sans(14)` renders
    /// at 15 — because SF Pro can only name a style.
    ///
    /// ponytail: the app currently spends 22 distinct sizes across these 10 steps,
    /// so the argument is closer to a hint than a measurement. Collapsing the call
    /// sites onto five named roles is the real cleanup and it
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

    // MARK: - Headers and button words — Inter Tight

    /// Inter Tight Bold at an exact size, scaling against the nearest text style: headers.
    ///
    /// The size survives verbatim here — a custom face can do what the system face
    /// cannot — so pass `relativeTo:` only when a heading should grow at a rate its
    /// own size does not imply.
    static func display(_ size: CGFloat, relativeTo style: TextStyle? = nil) -> Font {
        .custom(Face.displayBold, size: size, relativeTo: style ?? nearestTextStyle(to: size))
    }

    /// Inter Tight SemiBold at an exact size, scaling against the nearest text style: button
    /// words and the smaller headers.
    static func displaySemi(_ size: CGFloat, relativeTo style: TextStyle? = nil) -> Font {
        .custom(Face.displaySemi, size: size, relativeTo: style ?? nearestTextStyle(to: size))
    }

    /// Event headline face — BP Event Heading, the app's own.
    ///
    /// Scoped on purpose: the headline that sits ON an event photograph, and the same headline
    /// on the event's detail page. Neither of the faces already here was right for it
    /// — SF Pro Bold and Jost SemiBold both read light over a picture — and neither
    /// was a released typeface the reference could be matched to. Measured, the
    /// reference runs about 15% wider per letter than any grotesque on hand, so this
    /// one is drawn rather than licensed.
    ///
    /// It is built from `scripts/event-font/alphabet-sheet.png`; that folder's README
    /// is how to rebuild it and, more usefully, what it still lacks. The short version
    /// for anyone reading a crash or a screenshot: accented characters are NOT in the
    /// font, so a title containing one falls back to the system face for that
    /// character alone.
    static func eventDisplay(_ size: CGFloat, relativeTo style: TextStyle? = nil) -> Font {
        .custom(Face.eventHeadline, size: size, relativeTo: style ?? nearestTextStyle(to: size))
    }

    // MARK: - UI / body — SF Pro

    /// SF Pro at the nearest text style, scaling with it: body, labels and data (BP Body until
    /// 2026-11-18, at the same sizes and weights). `sansLight` stays Regular, as it always drew.
    static func sansLight(_ size: CGFloat) -> Font { apple(size) }
    static func sans(_ size: CGFloat) -> Font { apple(size) }
    static func sansMedium(_ size: CGFloat) -> Font { apple(size, weight: .medium) }
    static func sansSemibold(_ size: CGFloat) -> Font { apple(size, weight: .semibold) }
    static func sansBold(_ size: CGFloat) -> Font { apple(size, weight: .bold) }

    /// SF Pro at the nearest text style, scaling with it: Profile's text under the name (Jesse,
    /// 2026-10-25: "use same font as group page", the Group page's SF Pro before BP Body; BP app
    /// taste/you.md). The pills' words moved to Inter Tight (2026-11-02).
    /// Onboarding uses it for every word on a step of Apple's ladder (Luma's look, BP app onboarding 34);
    /// a size between steps takes `appleFont` below.
    static func apple(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .system(nearestTextStyle(to: size), weight: weight)
    }

    // Data — paired with `.monospacedDigit()` at the call site for tabular figures
    // (was Geist Mono). Same metrics as the sans helpers by design; the separate
    // name records the intent at the call site.
    static func mono(_ size: CGFloat) -> Font { sans(size) }
    static func monoMedium(_ size: CGFloat) -> Font { sansMedium(size) }

    // MARK: - The one that must not scale

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

extension View {
    /// Apple's font at an exact size between the ladder's steps (onboarding's 24 pt question),
    /// growing with Dynamic Type at its nearest text style's rate, as the
    /// display faces do. A modifier, not a `Font`: SwiftUI has no scaling system font at a set size,
    /// so the size is a `@ScaledMetric` that follows the text size live.
    func appleFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(AppleExactFont(size: size, weight: weight))
    }
}

private struct AppleExactFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: Font.nearestTextStyle(to: size))
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight))
    }
}
