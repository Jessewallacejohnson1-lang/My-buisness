//
//  YourDayModule.swift
//  Block Party — mounts HappeningSoonSection unchanged behind FeedModule.
//

import Combine
import SwiftUI

@MainActor
final class YourDayModule: @MainActor FeedModule {
    let objectWillChange = ObservableObjectPublisher()
    let id: FeedModuleID = .yourDay
    let order = 2
    let ownsFetch = false

    private let briefing: BriefingModel

    init(briefing: BriefingModel) {
        self.briefing = briefing
    }

    var phase: FeedPhase {
        guard let payload = briefing.payload else {
            return briefing.loadFailed ? .failed : .loading
        }
        return payload.featured.isEmpty && payload.featuredFallback == nil ? .empty : .ready
    }

    func isVisible(_ ctx: FeedModuleContext) -> Bool { true }
    func load(_ ctx: FeedModuleContext) async {}

    func makeView(_ ctx: FeedModuleContext) -> AnyView {
        switch phase {
        case .loading:
            return AnyView(
                HappeningSoonSkeleton()
                    .padding(.horizontal, 18)
                    .padding(.top, 22)
            )

        case .failed:
            return AnyView(
                BriefingUnavailableCard {
                    Task {
                        await ctx.briefing.refresh(BriefingAPI(auth: ctx.auth))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)
            )

        case .ready:
            guard let payload = ctx.briefing.payload else { return AnyView(EmptyView()) }
            return AnyView(
                HappeningSoonSection(
                    events: payload.featured,
                    fallback: payload.featuredFallback,
                    onRsvp: { event, going in
                        Task {
                            let api = CommunityAPI(auth: ctx.auth)
                            let landed = await ctx.briefing.setRsvp(
                                api,
                                event: event,
                                going: going
                            )
                            guard landed, going else { return }
                            ctx.analytics.record(
                                BriefingEventName.rsvpFromHome,
                                payload: ["event_id": event.id, "rank": event.rank],
                                auth: ctx.auth
                            )
                        }
                    }
                )
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .springReveal(
                    1,
                    revealed: ctx.contentRevealed,
                    animated: ctx.revealAnimated
                )
            )

        case .empty:
            return AnyView(EmptyView())
        }
    }
}
