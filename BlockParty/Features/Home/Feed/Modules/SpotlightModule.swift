//
//  SpotlightModule.swift
//  Block Party — mounts SpotlightCard unchanged behind FeedModule.
//

import Combine
import SwiftUI

@MainActor
final class SpotlightModule: @MainActor FeedModule {
    let objectWillChange = ObservableObjectPublisher()
    let id: FeedModuleID = .spotlight
    let order = 6
    let ownsFetch = false

    private let briefing: BriefingModel

    init(briefing: BriefingModel) {
        self.briefing = briefing
    }

    var phase: FeedPhase {
        if briefing.payload?.spotlight != nil { return .ready }
        if briefing.payload == nil && !briefing.loadFailed { return .loading }
        return .empty
    }

    func isVisible(_ ctx: FeedModuleContext) -> Bool { true }
    func load(_ ctx: FeedModuleContext) async {}

    func makeView(_ ctx: FeedModuleContext) -> AnyView {
        switch phase {
        case .loading:
            return AnyView(
                SpotlightSkeleton()
                    .padding(.horizontal, 18)
                    .padding(.top, 22)
            )

        case .ready:
            guard let spotlight = ctx.briefing.payload?.spotlight else {
                return AnyView(EmptyView())
            }
            return AnyView(
                SpotlightCard(spotlight: spotlight)
                    .padding(.horizontal, 18)
                    .padding(.top, 22)
                    .springReveal(
                        3,
                        revealed: ctx.contentRevealed,
                        animated: ctx.revealAnimated
                    )
            )

        case .empty, .failed:
            return AnyView(EmptyView())
        }
    }
}
