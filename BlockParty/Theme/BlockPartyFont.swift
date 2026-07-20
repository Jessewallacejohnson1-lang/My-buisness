//
//  BlockPartyFont.swift
//  Block Party — design tokens (typography)
//
//  Two-face system: Jost is the display, headline, and wordmark face; SF Pro stays
//  the body, UI, and data face through the system helpers. Atkinson Hyperlegible
//  Bold remains bundled but is no longer referenced. Numbers keep tabular figures
//  by pairing the mono helpers with `.monospacedDigit()` at the call site.
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
    // Display / headings — Jost.
    static func display(_ size: CGFloat) -> Font { .custom(Face.displayBold, size: size) }
    static func displaySemi(_ size: CGFloat) -> Font { .custom(Face.displaySemi, size: size) }

    // UI / body — system (was DM Sans).
    static func sans(_ size: CGFloat) -> Font { .system(size: size, weight: .regular) }
    static func sansMedium(_ size: CGFloat) -> Font { .system(size: size, weight: .medium) }
    static func sansSemibold(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
    static func sansBold(_ size: CGFloat) -> Font { .system(size: size, weight: .bold) }

    // Data — system, paired with `.monospacedDigit()` at the call site for tabular
    // figures (was Geist Mono).
    static func mono(_ size: CGFloat) -> Font { .system(size: size, weight: .regular) }
    static func monoMedium(_ size: CGFloat) -> Font { .system(size: size, weight: .medium) }

    // Logo — Jost SemiBold. Fixed size — a logo never scales with Dynamic Type.
    static func logo(_ size: CGFloat) -> Font { .custom(Face.logo, size: size) }
}
