//
//  BlockPartyFont.swift
//  Block Party — design tokens (typography)
//
//  The app uses the platform system font (SF Pro) everywhere — weight carries the
//  hierarchy, so these helpers map straight onto `.system(size:weight:)`. There is
//  exactly ONE custom face: the logo, Atkinson Hyperlegible Bold, used only by
//  BlockPartyLogoBadge (`Font.logo`). Numbers keep tabular figures by pairing the mono
//  helpers with `.monospacedDigit()` at the call site.
//
//  (History: the app once bundled Spectral / DM Sans / Geist Mono; the coral
//  rebrand moved everything to the system font. The call sites — `Font.display(…)`,
//  `Font.sansSemibold(…)`, etc. — are unchanged, so nothing else had to move.)
//

import SwiftUI
import CoreText

/// PostScript names of bundled faces. Only `logo` is live now — everything else is
/// the system font. The legacy names are kept inert so any stray direct
/// `.custom(Face.…)` still compiles; those faces are no longer bundled, so such a
/// call simply falls back to the system font (which is the intended reset anyway).
enum Face {
    static let logo = "AtkinsonHyperlegible-Bold"   // the wordmark badge — the app's only custom face

    // Legacy — no longer bundled; prefer the `Font.*` system helpers below.
    static let display      = "Spectral-Bold"
    static let displaySemi  = "Spectral-SemiBold"
    static let sans         = "DMSans-Regular"
    static let sansMedium   = "DMSans-Medium"
    static let sansSemibold = "DMSans-SemiBold"
    static let sansBold     = "DMSans-Bold"
    static let mono         = "GeistMono-Regular"
    static let monoMedium   = "GeistMono-Medium"
}

/// Register every bundled .ttf so the logo's PostScript name resolves. Idempotent.
/// The only bundled face now is Atkinson (the logo); everything else is the system font.
func registerBlockPartyFonts() {
    guard let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) else { return }
    for url in urls {
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

extension Font {
    // Display / headings — system, bold weights (was Spectral).
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .bold) }
    static func displaySemi(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }

    // UI / body — system (was DM Sans).
    static func sans(_ size: CGFloat) -> Font { .system(size: size, weight: .regular) }
    static func sansMedium(_ size: CGFloat) -> Font { .system(size: size, weight: .medium) }
    static func sansSemibold(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
    static func sansBold(_ size: CGFloat) -> Font { .system(size: size, weight: .bold) }

    // Data — system, paired with `.monospacedDigit()` at the call site for tabular
    // figures (was Geist Mono).
    static func mono(_ size: CGFloat) -> Font { .system(size: size, weight: .regular) }
    static func monoMedium(_ size: CGFloat) -> Font { .system(size: size, weight: .medium) }

    // Logo — Atkinson Hyperlegible Bold. The ONE custom face; used only by
    // BlockPartyLogoBadge. Fixed size — a logo never scales with Dynamic Type.
    static func logo(_ size: CGFloat) -> Font { .custom(Face.logo, size: size) }
}
