//
//  TownRainPreview.swift
//  Block Party — DEBUG-only headless surface for the town-rain drop.
//
//  `-town-rain-preview` renders the field full-screen over paper, bypassing the auth
//  gate, and fires a burst on a loop. That exists because the drop's trigger is a real
//  touch on the town pill and this setup has NO tap automation — without a gate the
//  animation cannot be recorded, and its timing is the whole point of the feature.
//
//  It reads the real `places` rows (anon read, no sign-in), so the preview rains the REAL
//  businesses' map-pin logos through the real `POILogoCache` path. Add `-poi-logo-stub`
//  for a deterministic offline run when measuring the PHYSICS, where network timing and
//  mark shapes would only add noise: it rains code-drawn marks on stand-in rows.
//
//  Measure a recording with `scripts/track_rain.swift` and compare against
//  `docs/town-rain-reference-measurements.md`.
//

#if DEBUG
import CoreLocation
import SwiftUI

struct TownRainPreview: View {

    @State private var trigger = 0
    @State private var pois: [POI] = POILogoCache.stubEnabled ? TownRainPreview.syntheticPlaces() : []

    /// Presses come in runs: several a beat apart, so a recording shows marks
    /// ACCUMULATING (the thing that changed), then a gap long enough for the field to
    /// clear before the next run.
    private static let pressGap: TimeInterval = 0.9
    private static let pressesPerRun = 5
    private static let runGap: TimeInterval = 6

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
        .task {
            if !POILogoCache.stubEnabled, let real = try? await CommunityAPI(auth: AuthStore.shared).getPlaces() {
                pois = real
            }
            POILogoCache.shared.prefetch(pois.compactMap(\.logoURL))
            fire()
        }
    }

    /// One press, then either the next press in this run or the start of the next run.
    private func fire(pressesLeft: Int = TownRainPreview.pressesPerRun) {
        trigger += 1
        let remaining = pressesLeft - 1
        let delay = remaining > 0 ? Self.pressGap : Self.runGap
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            fire(pressesLeft: remaining > 0 ? remaining : Self.pressesPerRun)
        }
    }

    /// Stand-ins for `places` rows for the offline `-poi-logo-stub` run, one per roster
    /// slot, so `TownRainRoster.eligible` resolves a full pool. The uuids are the real
    /// roster ids; the stub draws each mark from `name` and `id`, so the URL only has to
    /// be present, never fetched.
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
                logoUrl: "stub://\(id)")
        }
    }
}
#endif
