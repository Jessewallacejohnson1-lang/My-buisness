//
//  AlmanacModule.swift
//  Block Party — mounts the existing almanac unchanged behind FeedModule.
//

import Combine
import SwiftUI

@MainActor
final class AlmanacModule: @MainActor FeedModule {
    let objectWillChange = ObservableObjectPublisher()
    let id: FeedModuleID = .almanac
    let order = 1
    let ownsFetch = false

    /// Always `.ready`, and never `.empty`. The masthead's first two lines — the
    /// date and the greeting — are local truth that needs no fetch, so there is no
    /// module-level moment where this has nothing to render. The almanac's own
    /// loading and error states belong to the async READINGS inside
    /// `AlmanacSection`, which is where the network actually is.
    let phase: FeedPhase = .ready

    init(briefing: BriefingModel) {}

    func isVisible(_ ctx: FeedModuleContext) -> Bool {
        #if DEBUG
        if FeedDebugFocus.isHidden(id) { return false }
        #endif
        return true
    }

    func load(_ ctx: FeedModuleContext) async {}

    func makeView(_ ctx: FeedModuleContext) -> AnyView {
        AnyView(
            AlmanacSection(
                name: ctx.displayName,
                replay: ctx.refreshReplay,
                injectedLine: ctx.briefing.payload?.almanac?.line,
                townDate: ctx.briefing.payload?.briefingDate
            )
            .environmentObject(ctx.auth)
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .springReveal(0, revealed: ctx.revealed, animated: ctx.revealAnimated)
            .dwell(seconds: 3) {
                ctx.analytics.record(
                    BriefingEventName.almanacDwell,
                    payload: ["source": ctx.briefing.payload?.almanac?.source ?? "unknown"],
                    auth: ctx.auth
                )
            }
        )
    }
}
