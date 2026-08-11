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

    /// The clock, injected. A module that needs to know what time it is reads
    /// `ctx.dates.now` rather than calling `Date()`, so a test can pin the day and
    /// ask real questions of it ("is this event over yet?"). Defaults to the
    /// device clock, so every existing call site is unchanged.
    let dates: any DateProviding

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
        refreshReplay: Int = 0,
        dates: (any DateProviding)? = nil
    ) {
        self.auth = auth
        self.briefing = briefing
        self.displayName = displayName
        self.navigate = navigate
        self.analytics = analytics ?? .shared
        // Resolved in the body, not as a default argument: a MainActor default
        // argument expression is the CLAUDE.md isolation trap.
        self.dates = dates ?? SystemDateProvider()
        self.revealed = revealed
        self.contentRevealed = contentRevealed
        self.revealAnimated = revealAnimated
        self.refreshReplay = refreshReplay
    }
}
