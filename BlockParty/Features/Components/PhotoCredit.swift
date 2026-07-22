//
//  PhotoCredit.swift
//  Block Party — the ONE Google-required photographer credit treatment, shared by
//  every place a Places photo is rendered (VenuePhoto, the feed hero, VenueInfoView).
//
//  It lives in one file on purpose: the credit is a ToS obligation, not decoration, so
//  it must never fork into a second, weaker treatment. It previously had — a 9pt
//  white-on-40%-black chip shipped on the feed hero while this component was being
//  rewritten to abandon exactly that chip as illegible; promoting it here closes that
//  gap so there is only one credit in the app.
//

import SwiftUI

/// The Google-required photographer credit, sized to be READ rather than merely
/// present. It has to survive the smallest photo box in the app — the 232x132
/// "Happening this week" shelf card — where the previous 9pt white-on-40%-black
/// chip scanned as a smudge in the corner.
///
/// What makes it deliberate at that size: 10pt medium (the smallest weight/size pair
/// in the type scale that still holds a serif-free name), a hair of tracking, a
/// darker and slightly taller capsule so it reads as a caption chip instead of a
/// stray mark, and a soft drop shadow so it separates from a busy photograph rather
/// than dissolving into one. It is never suppressed — Google's terms require the
/// attribution wherever the image appears, so there is no "too small to bother"
/// case; if the photo is on screen, so is its credit. Callers must therefore only
/// place it over a photo that is actually shown (a `.success` phase), never over a
/// loading/failed placeholder.
struct PhotoCredit: View {
    let names: [String]

    /// Type + chip metrics, kept together so the credit stays one considered object.
    private static let fontSize: CGFloat = 10
    private static let tracking: CGFloat = 0.2
    private static let insetH: CGFloat = 7
    private static let insetV: CGFloat = 4
    private static let edgeInset: CGFloat = 9
    private static let scrimOpacity: Double = 0.46

    private var credit: String { names.joined(separator: ", ") }

    var body: some View {
        if names.isEmpty {
            EmptyView()
        } else {
            Text(credit)
                .font(.sansMedium(Self.fontSize))
                .tracking(Self.tracking)
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, Self.insetH)
                .padding(.vertical, Self.insetV)
                .background(.black.opacity(Self.scrimOpacity), in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
                .padding(Self.edgeInset)
                .allowsHitTesting(false)
                .accessibilityLabel("Photo by \(credit)")
        }
    }
}
