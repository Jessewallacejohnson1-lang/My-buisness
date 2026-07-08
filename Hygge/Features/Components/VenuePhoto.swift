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

struct VenuePhoto<Blank: View>: View {
    /// The best-known actual venue name — e.g. a trail's title, or an event/club's
    /// `location` (NOT its own title/name, which is usually about what's happening,
    /// not where). This is what gets searched AND checked for a confident match.
    let venueName: String
    /// Extra free text (an event/club's own title, a trail's location) that only
    /// helps the KnownVenues lookup — never used in the confidence name-check.
    var hint: String? = nil
    @ViewBuilder var blank: () -> Blank

    @State private var photo: ConfidentPhoto?

    var body: some View {
        Group {
            if let cp = photo {
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: GooglePlacesService.shared.photoURL(name: cp.photoName, maxWidth: 500)) { phase in
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
        .task(id: "\(venueName)|\(hint ?? "")") {
            photo = await GooglePlacesService.shared.confidentPhoto(forFreeText: venueName, hint: hint)
        }
    }
}
