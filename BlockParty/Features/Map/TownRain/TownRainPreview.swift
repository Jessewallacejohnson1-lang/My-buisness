//
//  TownRainPreview.swift
//  Block Party — DEBUG-only headless surface for the town-rain drop.
//
//  `-town-rain-preview` renders the field full-screen over paper, bypassing the auth
//  gate, and fires a burst on a loop. That exists because the drop's trigger is a real
//  touch on the town pill and this setup has NO tap automation — without a gate the
//  animation cannot be recorded, and its timing is the whole point of the feature.
//
//  It stands in ONLY for the `places` rows, never for the marks: the logo URLs are
//  rebuilt from the real roster uuids against the public `place-logos` bucket — the
//  exact objects production loads — so the preview rains the REAL businesses' logos
//  through the real `POILogoCache` path, with no auth (the bucket is public read).
//  Add `-poi-logo-stub` for a deterministic offline run when measuring the PHYSICS,
//  where network timing and mark shapes would only add noise.
//
//  Measure a recording with `scripts/track_rain.swift` and compare against
//  `docs/town-rain-reference-measurements.md`.
//

#if DEBUG
import CoreLocation
import SwiftUI

struct TownRainPreview: View {

    @State private var trigger = 0
    @State private var pois: [POI] = TownRainPreview.syntheticPlaces()

    /// Long enough for a whole burst (2.9 s of spawning + ~2 s of flight) to land and
    /// clear before the next one starts, so a recording always holds a clean cycle.
    private static let burstPeriod: TimeInterval = 8

    var body: some View {
        ZStack {
            Hue.paper.ignoresSafeArea()

            // The floor the balls bounce on is the map sheet's peek edge; draw that
            // edge so a recording shows the contact plane the numbers refer to.
            VStack {
                Spacer()
                Rectangle()
                    .fill(Hue.hairline)
                    .frame(height: 1)
                Rectangle()
                    .fill(Hue.fill)
                    .frame(height: TownRainPhysics.floorInset)
            }
            .ignoresSafeArea()

            TownRainField(trigger: trigger, pois: pois)
                .ignoresSafeArea()
        }
        .onAppear {
            POILogoCache.shared.prefetch(pois.compactMap(\.logoURL))
            fire()
        }
    }

    private func fire() {
        trigger += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.burstPeriod) { fire() }
    }

    /// Stand-ins for `places` rows, one per roster slot, so `TownRainRoster.eligible`
    /// resolves a full pool without a signed-in session. The uuids are the REAL roster
    /// ids and the URLs are the REAL bucket objects (`place-logos/{uuid}.png`, public
    /// read — the same convention `upload_place_logos.py` writes and the same column
    /// value `places.logo_url` holds), so this exercises production's lookup and fetch
    /// path rather than a mock of it. Only `name`/`lat`/`lon` are stand-ins: the drop
    /// itself reads none of them, though `-poi-logo-stub` DOES read `name` and `id` to
    /// draw its monogram, so the marks in an offline run are stand-ins as well.
    private static func syntheticPlaces() -> [POI] {
        TownRainRoster.placeIDs.enumerated().map { index, id in
            POI(id: id,
                placeId: nil,
                name: "Place \(index + 1)",
                lat: MapSpots.center.latitude,
                lon: MapSpots.center.longitude,
                family: .business,
                primaryType: nil,
                types: [],
                address: nil,
                logoUrl: SupabaseConfig.storageURL
                    .appendingPathComponent("object/public/place-logos/\(id).png")
                    .absoluteString)
        }
    }
}
#endif
