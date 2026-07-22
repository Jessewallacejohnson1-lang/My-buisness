//
//  VenuePhoto.swift
//  Block Party — resolves + renders a confidence-gated Google Places photo for a
//  free-text venue name (event, club, or trail), with the ToS attribution
//  overlay. Renders `blank()` while unresolved and whenever no confident
//  match exists — never a generic stock photo, never a gray placeholder box.
//
//  See GooglePlacesService.confidentPhoto(forFreeText:hint:) for the Rule A
//  confidence gate (a KnownVenues curated anchor is required). Activities callers
//  should hand it a resolved `coordinate` via `ActivityVenue` rather than relying on
//  the free-text path.
//

import SwiftUI
import CoreLocation

struct VenuePhoto<Blank: View>: View {
    /// The best-known actual venue name — e.g. a trail's title, or an event/club's
    /// `location` (NOT its own title/name, which is usually about what's happening,
    /// not where). This is what gets searched AND checked for a confident match.
    let venueName: String
    /// Extra free text (an event/club's own title, a trail's location) that only
    /// helps the KnownVenues lookup — never used in the confidence name-check.
    var hint: String? = nil
    /// A curated, human-verified coordinate for `venueName` (e.g. a city park's own
    /// pin). When supplied we anchor Rule A's confidence check directly against it,
    /// instead of routing `venueName` through the free-text KnownVenues lookup —
    /// which lets fixed civic places (parks) resolve a photo without a KnownVenues
    /// entry. nil → the free-text path.
    var coordinate: CLLocationCoordinate2D? = nil
    /// Requested pixel width, sized to the caller's render box (a 320pt hero wants
    /// ~1600; a small shelf card ~700). Google Photo media is billed per request,
    /// not per pixel, so a larger ask costs nothing extra.
    var maxWidth: Int = 800
    @ViewBuilder var blank: () -> Blank

    @State private var photo: ConfidentPhoto?

    var body: some View {
        Group {
            if let cp = photo {
                AsyncImage(url: GooglePlacesService.shared.photoURL(name: cp.photoName, maxWidth: maxWidth)) { phase in
                    switch phase {
                    case .success(let img): filled(img, credit: cp.attributions)
                    default: blank()
                    }
                }
            } else {
                blank()
            }
        }
        .task(id: resolveKey) {
            // Clear first so a reused view identity (same card id, changed venue)
            // shows the blank() fallback immediately instead of the previous
            // venue's photo + attribution while the new lookup is in flight.
            photo = nil
            if let coordinate {
                photo = await GooglePlacesService.shared.confidentPhoto(name: venueName, coordinate: coordinate)
            } else {
                photo = await GooglePlacesService.shared.confidentPhoto(forFreeText: venueName, hint: hint)
            }
        }
    }

    /// The loaded photo filling the caller's box, with the required author credit
    /// pinned to its corner. The credit sits on the CLEAR container rather than on
    /// the image itself: `scaledToFill` renders a bitmap larger than the box, so an
    /// overlay anchored to the image would land outside the caller's clip.
    ///
    /// Attribution is attached to this branch only — a photo that is still loading,
    /// or that failed to load, draws `blank()` and must not carry a credit for an
    /// image nobody can see.
    private func filled(_ img: Image, credit names: [String]) -> some View {
        Color.clear
            .overlay { img.resizable().scaledToFill() }
            .clipped()
            .overlay(alignment: .bottomTrailing) { PhotoCredit(names: names) }
    }

    /// Re-run the lookup only when what determines the *match* changes (name +
    /// anchor). `maxWidth` only affects the media URL, not which photo resolves.
    private var resolveKey: String {
        if let c = coordinate { return "\(venueName)|\(c.latitude),\(c.longitude)" }
        return "\(venueName)|\(hint ?? "")"
    }
}

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
/// case; if the photo is on screen, so is its credit.
private struct PhotoCredit: View {
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
