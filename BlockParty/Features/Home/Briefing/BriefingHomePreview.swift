//
//  BriefingHomePreview.swift
//  Block Party — the REAL Today composition, rendered headlessly.
//
//  `-briefing-preview [-briefing-state <name>]` mounts HomeView itself, bypassing
//  the auth gate, with `BriefingModel` seeded from a canned payload and no network
//  call at all. That is the Phase 3 gate: the screen renders complete, in order,
//  from a fixture, offline.
//
//  Names come from `BriefingSample` (generated from fixtures/):
//    sample · one_event · zero_events · voted · none · degraded
//
//  This mounts the real view rather than a stand-in, so module ORDER, spacing and
//  the entrance cascade are what gets verified — the things a per-module gallery
//  cannot show.
//

#if DEBUG
import SwiftUI

struct BriefingHomePreview: View {
    @Namespace private var cardNS
    @State private var expandedPlace: Place?

    var body: some View {
        HomeView(expandedPlace: $expandedPlace, cardNS: cardNS)
            .environmentObject(AuthStore.shared)
    }
}
#endif
