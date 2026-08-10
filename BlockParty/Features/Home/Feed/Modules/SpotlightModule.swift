//
//  SpotlightModule.swift
//  Block Party — mounts the town-time weekly spotlight behind FeedModule.
//

import Combine
import SwiftUI
import UIKit

@MainActor
final class SpotlightModule: @MainActor FeedModule {
    let objectWillChange = ObservableObjectPublisher()
    let id: FeedModuleID = .spotlight
    let order = 5
    let ownsFetch = false

    private let briefing: BriefingModel

    init(briefing: BriefingModel) {
        self.briefing = briefing
    }

    var phase: FeedPhase {
        SpotlightPhaseRule.phase(
            hasSpotlight: briefing.payload?.spotlight != nil,
            hasPayload: briefing.payload != nil,
            loadFailed: briefing.loadFailed
        )
    }

    func isVisible(_ ctx: FeedModuleContext) -> Bool {
        #if DEBUG
        return !FeedDebugFocus.isHidden(id)
        #else
        return true
        #endif
    }

    func load(_ ctx: FeedModuleContext) async {}

    func makeView(_ ctx: FeedModuleContext) -> AnyView {
        switch phase {
        case .loading:
            return AnyView(
                SpotlightCardSkeleton()
                    .padding(.horizontal, 18)
                    .padding(.top, 22)
            )

        case .failed:
            // The spotlight is the last briefing-backed card in the column, so it
            // carries the cold-start failure for the payload it reads. The sign-off
            // stays quiet instead of duplicating this — see SignOffModule.
            return AnyView(
                FeedUnavailableCard(title: FeedLowerStateCopy.spotlightUnavailable) {
                    Task { await ctx.briefing.refresh(BriefingAPI(auth: ctx.auth)) }
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)
            )

        case .ready:
            guard let spotlight = ctx.briefing.payload?.spotlight else {
                return AnyView(EmptyView())
            }
            let coordinate = KnownVenues.coordinate(for: spotlight.title)
            let mapURL = SpotlightMapLink.url(
                placeID: spotlight.placeId,
                title: spotlight.title,
                coordinate: coordinate
            )
            let openMap: (() -> Void)? = mapURL.map { url in
                { UIApplication.shared.open(url) }
            }
            return AnyView(
                SpotlightCard(
                    spotlight: spotlight,
                    weekLabel: SpotlightWeekLabel.label(
                        forBriefingDate: ctx.briefing.payload?.briefingDate ?? ""
                    ),
                    onOpen: openMap
                )
                    .padding(.horizontal, 18)
                    .padding(.top, 22)
                    .springReveal(
                        3,
                        revealed: ctx.contentRevealed,
                        animated: ctx.revealAnimated
                    )
            )

        case .empty:
            return AnyView(EmptyView())
        }
    }
}
