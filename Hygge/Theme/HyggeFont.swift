//
//  HyggeFont.swift
//  Hygge — design tokens (typography)
//
//  Three strict roles, never swapped:
//    • Display  → Spectral          (wordmark, H1s, hero)
//    • UI/body  → Schibsted Grotesk (labels, body, buttons)
//    • Data     → Geist Mono        (every number, with tabular figures)
//
//  RN has no synthetic bolding, so each weight is its own family. We mirror that
//  here by addressing fonts through their PostScript names. The .ttf files live
//  in Resources/Fonts and are registered at launch (see registerHyggeFonts()).
//

import SwiftUI
import CoreText

/// PostScript names of the bundled faces (verified from each ttf's name table).
enum Face {
    static let display     = "Spectral-Bold"             // 700
    static let displaySemi = "Spectral-SemiBold"         // 600
    static let sans        = "SchibstedGrotesk-Regular"  // 400
    static let sansMedium  = "SchibstedGrotesk-Medium"   // 500
    static let sansSemibold = "SchibstedGrotesk-SemiBold" // 600
    static let sansBold    = "SchibstedGrotesk-Bold"     // 700
    static let mono        = "GeistMono-Regular"         // 400
    static let monoMedium  = "GeistMono-Medium"          // 500
}

/// Register every bundled .ttf so the PostScript names resolve. Idempotent.
func registerHyggeFonts() {
    guard let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) else { return }
    for url in urls {
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

extension Font {
    // Display — Spectral. Scales relative to a large title.
    static func display(_ size: CGFloat) -> Font { .custom(Face.display, size: size, relativeTo: .largeTitle) }
    static func displaySemi(_ size: CGFloat) -> Font { .custom(Face.displaySemi, size: size, relativeTo: .title) }

    // UI / body — Schibsted Grotesk.
    static func sans(_ size: CGFloat) -> Font { .custom(Face.sans, size: size, relativeTo: .body) }
    static func sansMedium(_ size: CGFloat) -> Font { .custom(Face.sansMedium, size: size, relativeTo: .body) }
    static func sansSemibold(_ size: CGFloat) -> Font { .custom(Face.sansSemibold, size: size, relativeTo: .headline) }
    static func sansBold(_ size: CGFloat) -> Font { .custom(Face.sansBold, size: size, relativeTo: .headline) }

    // Data — Geist Mono. Always pair with .monospacedDigit() at the call site.
    static func mono(_ size: CGFloat) -> Font { .custom(Face.mono, size: size, relativeTo: .footnote) }
    static func monoMedium(_ size: CGFloat) -> Font { .custom(Face.monoMedium, size: size, relativeTo: .footnote) }
}
