//
//  VenuePhoto.swift
//  Hygge — resolves + renders a confidence-gated Google Places photo for a
//  free-text venue name (event, club, or trail), with the ToS attribution
//  overlay. Renders `blank()` while unresolved and whenever no confident
//  match exists — never a generic stock photo, never a gray placeholder box.
//
//  See GooglePlacesService.confidentPhoto(forFreeText:hint:) for the Rule A
//  confidence gate (a KnownVenues curated anchor is required).
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
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: GooglePlacesService.shared.photoURL(name: cp.photoName, maxWidth: maxWidth)) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: blank()
                        }
                    }
                    if !cp.attributions.isEmpty {
                        Text(cp.attributions.joined(separator: ", "))
                            .font(.sans(9)).foregroundStyle(.white.opacity(0.95)).lineLimit(1)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.black.opacity(0.4), in: Capsule())
                            .padding(8)
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

    /// Re-run the lookup only when what determines the *match* changes (name +
    /// anchor). `maxWidth` only affects the media URL, not which photo resolves.
    private var resolveKey: String {
        if let c = coordinate { return "\(venueName)|\(c.latitude),\(c.longitude)" }
        return "\(venueName)|\(hint ?? "")"
    }
}
