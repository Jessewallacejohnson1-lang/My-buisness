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
                    weekIdentifier: SpotlightWeek.identifier(
                        for: ctx.briefing.payload?.briefingDate ?? ""
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

        case .empty, .failed:
            return AnyView(EmptyView())
        }
    }
}
