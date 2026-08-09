//
//  SignOffModule.swift
//  Block Party — closes the finite edition with one plain town-time sentence.
//

import Combine
import SwiftUI

@MainActor
final class SignOffModule: @MainActor FeedModule {
    let objectWillChange = ObservableObjectPublisher()
    let id: FeedModuleID = .signOff
    let order = 7
    let ownsFetch = false

    private let briefing: BriefingModel

    init(briefing: BriefingModel) {
        self.briefing = briefing
    }

    var phase: FeedPhase {
        briefing.payload == nil ? .empty : .ready
    }

    func isVisible(_ ctx: FeedModuleContext) -> Bool { true }
    func load(_ ctx: FeedModuleContext) async {}

    func makeView(_ ctx: FeedModuleContext) -> AnyView {
        guard phase == .ready, let payload = ctx.briefing.payload else {
            return AnyView(EmptyView())
        }

        return AnyView(
            CaughtUpFooter(
                caughtUp: payload.caughtUp,
                briefingDateLabel: BriefingDate.eyebrow(for: payload.briefingDate) ?? "",
                briefingDate: payload.briefingDate
            )
            .padding(.horizontal, 18)
            .padding(.top, 34)
            .dwell(seconds: 1) {
                ctx.analytics.recordOnce(
                    BriefingEventName.caughtUpReached,
                    key: payload.briefingDate,
                    auth: ctx.auth
                )
            }
        )
    }
}
