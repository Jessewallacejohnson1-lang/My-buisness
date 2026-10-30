import Foundation

/// The DEBUG launch arguments (`docs/debug-flags.md`), read in this one place. A Release build
/// reads none: every flag is off and every value nil, whatever the launch passed.
nonisolated enum LaunchFlags {
    /// Every flag the app reads. `LaunchFlagsTests` holds this list and the doc to each other.
    nonisolated enum Flag: String, CaseIterable {
        case anonData = "-anon-data"
        case appearance = "-appearance"
        case appearanceDemo = "-appearance-demo"
        case dailyFeedPreview = "-daily-feed-preview"
        case dailyFeedState = "-daily-feed-state"
        case dailyHour = "-daily-hour"
        case dailySamples = "-daily-samples"
        case eventPageTwoPhotos = "-event-page-two-photos"
        case feedBarBack = "-feed-bar-back"
        case feedCardAutoplay = "-feed-card-autoplay"
        case feedCardGallery = "-feed-card-gallery"
        case feedRenderLog = "-feed-render-log"
        case feedScrollSweep = "-feed-scroll-sweep"
        case feedScrolled = "-feed-scrolled"
        case feedScrolledY = "-feed-scrolled-y"
        case frameGapLog = "-frame-gap-log"
        case friendsFail = "-friends-fail"
        case friendsLimit = "-friends-limit"
        case friendsWords = "-friends-words"
        case headerCollapsed = "-header-collapsed"
        case helloDrop = "-hello-drop"
        case helloDropHold = "-hello-drop-hold"
        case helloFinal = "-hello-final"
        case helloJoined = "-hello-joined"
        case helloLater = "-hello-later"
        case helloMoment = "-hello-moment"
        case helloSeenDays = "-hello-seen-days"
        case helloWelcome = "-hello-welcome"
        case mapAutozoom = "-map-autozoom"
        case mapBearing = "-map-bearing"
        case mapCenter = "-map-center"
        case mapDetailExpanded = "-map-detail-expanded"
        case mapDetent = "-map-detent"
        case mapFilter = "-map-filter"
        case mapForceLive = "-map-force-live"
        case mapNow = "-map-now"
        case mapOpen = "-map-open"
        case mapOpenPoi = "-map-open-poi"
        case mapPitch = "-map-pitch"
        case mapSave = "-map-save"
        case mapSearch = "-map-search"
        case mapSearchCommitted = "-map-search-committed"
        case mapSearchOpen = "-map-search-open"
        case mapSheet = "-map-sheet"
        case mapZoom = "-map-zoom"
        case noticeSamples = "-notice-samples"
        case onboarding = "-onboarding"
        case onboardingNotYet = "-onboarding-not-yet"
        case openBusiness = "-open-business"
        case openEvent = "-open-event"
        case openFriends = "-open-friends"
        case openFriendsChat = "-open-friends-chat"
        case openMap = "-open-map"
        case openNotifications = "-open-notifications"
        case openPage = "-open-page"
        case openProfile = "-open-profile"
        case openTab = "-open-tab"
        case openTeam = "-open-team"
        case poiLogoStub = "-poi-logo-stub"
        case profileAutoclose = "-profile-autoclose"
        case profileBottom = "-profile-bottom"
        case profileEdit = "-profile-edit"
        case profileEditInterests = "-profile-edit-interests"
        case profileModeration = "-profile-moderation"
        case profileSettings = "-profile-settings"
        case reviewQueueFail = "-review-queue-fail"
        case reviewQueuePreview = "-review-queue-preview"
        case scrollLog = "-scroll-log"
        case searchChip = "-search-chip"
        case searchFocus = "-search-focus"
        case searchWords = "-search-words"
        case seedPlaces = "-seed-places"
        case shareDemo = "-share-demo"
        case showHome = "-show-home"
        case showMapIntro = "-show-map-intro"
        case showSkeletons = "-show-skeletons"
        case tabCycle = "-tab-cycle"
        case tilt = "-tilt"
        case townCancelled = "-town-cancelled"
        case townGames = "-town-games"
        case townGroup = "-town-group"
        case townLive = "-town-live"
        case townMenuOpen = "-town-menu-open"
        case townNews = "-town-news"
        case townOffline = "-town-offline"
        case townRain = "-town-rain"
        case townRainPreview = "-town-rain-preview"
        case townRefuse = "-town-refuse"
        case townSamples = "-town-samples"
        case uiTests = "-ui-tests"
        case youFreeToday = "-you-free-today"
    }

    /// Whether the launch passed the flag.
    static func has(_ flag: Flag) -> Bool { arguments.contains(flag.rawValue) }

    /// The argument after the flag (`-open-tab you` gives "you"), or nil without it.
    static func value(_ flag: Flag) -> String? { values(flag).first }

    /// The argument after each time the flag is passed, for the repeatable ones (`-map-save`).
    static func values(_ flag: Flag) -> [String] { values(flag, in: arguments) }

    static func values(_ flag: Flag, in arguments: [String]) -> [String] {
        zip(arguments, arguments.dropFirst()).filter { $0.0 == flag.rawValue }.map(\.1)
    }

    /// Whether the launch passed any flag at all (a screenshot or a UI test run).
    static var any: Bool { arguments.dropFirst().contains { $0.hasPrefix("-") } }

    /// Where Join, hearts, saves and the other writes go: `-town-offline` beats `-town-samples`
    /// on every screen, since offline is the samples kept from a last visit with every read failing.
    static var backend: RealLifeActions.Backend { backend(for: arguments) }

    static func backend(for arguments: [String]) -> RealLifeActions.Backend {
        #if DEBUG
        if arguments.contains(Flag.townOffline.rawValue) { return .offline }
        if arguments.contains(Flag.townSamples.rawValue) { return .samples }
        #endif
        return .live
    }

    private static let arguments: [String] = {
        #if DEBUG
        ProcessInfo.processInfo.arguments
        #else
        []
        #endif
    }()
}
