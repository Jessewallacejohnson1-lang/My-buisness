//
//  TriviaModule.swift
//  Block Party — mounts DailyTouchCard unchanged behind FeedModule.
//

import Combine
import SwiftUI

@MainActor
final class TriviaModule: @MainActor FeedModule {
    let objectWillChange = ObservableObjectPublisher()
    let id: FeedModuleID = .trivia
    let order = 5
    let ownsFetch = false

    private let briefing: BriefingModel

    init(briefing: BriefingModel) {
        self.briefing = briefing
    }

    var phase: FeedPhase {
        if briefing.payload?.touch != nil { return .ready }
        if briefing.payload == nil && !briefing.loadFailed { return .loading }
        return .empty
    }

    func isVisible(_ ctx: FeedModuleContext) -> Bool { true }
    func load(_ ctx: FeedModuleContext) async {}

    func makeView(_ ctx: FeedModuleContext) -> AnyView {
        switch phase {
        case .loading:
            return AnyView(
                DailyTouchSkeleton()
                    .padding(.horizontal, 18)
                    .padding(.top, 22)
            )

        case .ready:
            guard let touch = ctx.briefing.payload?.touch else { return AnyView(EmptyView()) }
            return AnyView(
                DailyTouchCard(
                    touch: touch,
                    onVote: { index in
                        Task {
                            let api = BriefingAPI(auth: ctx.auth)
                            let landed = await ctx.briefing.vote(api, optionIndex: index)
                            guard landed else { return }
                            ctx.analytics.record(
                                BriefingEventName.touchVote,
                                payload: ["touch_id": touch.id, "option_idx": index],
                                auth: ctx.auth
                            )
                        }
                    }
                )
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .springReveal(
                    2,
                    revealed: ctx.contentRevealed,
                    animated: ctx.revealAnimated
                )
            )

        case .empty, .failed:
            return AnyView(EmptyView())
        }
    }
}
