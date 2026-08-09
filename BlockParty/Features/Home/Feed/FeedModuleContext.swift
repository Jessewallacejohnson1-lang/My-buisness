//
//  FeedModuleContext.swift
//  Block Party — injected dependencies and presentation state for a feed module.
//

@MainActor
struct FeedModuleContext {
    let auth: AuthStore
    let briefing: BriefingModel
    let displayName: String?
    let navigate: (FeedRoute) -> Void
    let analytics: BriefingAnalytics

    // The existing Today reveal choreography remains screen-owned, while each
    // module applies its own index and spacing from its makeView implementation.
    let revealed: Bool
    let contentRevealed: Bool
    let revealAnimated: Bool
    let refreshReplay: Int

    init(
        auth: AuthStore,
        briefing: BriefingModel,
        displayName: String?,
        navigate: @escaping (FeedRoute) -> Void,
        analytics: BriefingAnalytics? = nil,
        revealed: Bool = false,
        contentRevealed: Bool = false,
        revealAnimated: Bool = true,
        refreshReplay: Int = 0
    ) {
        self.auth = auth
        self.briefing = briefing
        self.displayName = displayName
        self.navigate = navigate
        self.analytics = analytics ?? .shared
        self.revealed = revealed
        self.contentRevealed = contentRevealed
        self.revealAnimated = revealAnimated
        self.refreshReplay = refreshReplay
    }
}
