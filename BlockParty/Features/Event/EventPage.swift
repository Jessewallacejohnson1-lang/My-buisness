//
//  EventPage.swift
//  Block Party — the Event page: the single event behind a card.
//
//  Apple Invites' top (BP app docs/plans/inside-cards, ticket 17; Jesse, 2026-11-06: "copy apples invites
//  top", "copy all of it"): the picture runs from the screen's top and melts into its own colour, near-black
//  at the foot, under a big centred title and the facts in a light tint of that colour; two big round-ended
//  buttons (Map and the page it was found on), the host's row with Follow, and About in Apple's font. A
//  flyer stays whole, a logo sits on a white disc, and no picture is the exact yellow with ink words. The
//  sizes are `EventLook`'s, off Apple's screen and the approved mock. The Attend bar is Meetup's floating
//  capsule (rsvp-and-groups 02) holding friends' faces, the send and a white Attend (`EventBar`, ticket 18).
//
//  A game's page keeps its own look (ticket 21): its teams' colours (`GameMatchup`), the round white buttons
//  and the facts as Meetup's rows (`Metric`, measured off Fresha's venue page; a business page in Search
//  shares those).
//
//  Every list pushes this onto the shell's stack; the system bar stays hidden.
//
//  PRODUCT RULE: never render a zero count or a placeholder. Every row below is
//  optional and simply absent when the data is: no description, no About; no
//  place, no Map; no link, no Website; no picture, the yellow page.
//
//  Map (inside-cards 19): with a spot it opens a small map right below, pushing the page down, and a tap on that
//  raises the full map over the page, flying in to the Event's bubble and card; closing lands back here as it was.
//  With no spot known, Apple Maps at the place; at no one place (Online), no Map button. All from the card
//  (`EventMapRoute`), so Map does the same whenever it's tapped, offline too.
//

import CoreLocation
import EventKitUI
import SwiftUI

struct EventPage: View {
    let item: FeedCardItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    /// Going and Heart, shared with the card behind the page (`RealLifeActions`).
    @Environment(RealLifeActions.self) private var actions
    /// Every game's newest score, from whatever tab opened the page (codebase-health-2 08); nil in previews.
    @Environment(LiveGames.self) private var live: LiveGames?
    /// The page's hold on Live games while it's open, its own, so two pages of one Event let go one at a time.
    @State private var liveHolder = "page:" + UUID().uuidString
    /// `actions.heartFailureCount` when the heart was last tapped: equal means a tap since the
    /// last failed turn back, so its shake stops (as the RSVP pill's, `RSVPArea`).
    @State private var heartTappedAt = 0
    /// Pictures whose bitmaps are on screen. Until then the page shows the skeleton, and a photo's
    /// credit waits for its photo.
    @State private var shownPhotos: Set<URL> = []
    /// Pictures that could not be loaded. The next takes their place, so a failure never holds a
    /// skeleton on screen.
    @State private var failedPhotos: Set<URL> = []
    /// The page's colour, read from its picture once the picture is here (`EventLook.dominant`); nil until
    /// then, when the page is `Hue.gameNight` and the colour fades in. Called off, grey with the photo.
    @State private var pageColor: UInt32?
    /// A pale picture (mean brightness over 60%): its melt ends sooner.
    @State private var pale = false
    /// Each later picture's colour, when the page swipes from the Event's own photo through an exhibit's other pieces
    /// (event-photos 25) to its flyer (town-feed 59), as each lands.
    @State private var pageColors: [URL: UInt32] = [:]
    /// Those pictures that are pale: their melt ends sooner, as a pale picture's does.
    @State private var pagePales: [URL: Bool] = [:]
    /// How far the hero is swiped: 0 on its own photo, 1 on the next picture, and so on.
    @State private var heroSwipe: CGFloat = 0
    /// Which picture the hero rests on.
    @State private var heroPage: Int? = 0
    /// Two fingers have lifted the picture (`pinchToZoom`): the buttons over it step aside till it lands.
    @State private var heroLifted = false
    /// The page's width, for the picture's sizes, which scale with it. Width, never height: nothing the
    /// scroll reads back may set its own content size (swift-traps).
    @State private var width: CGFloat = EventLook.mockWidth
    /// Apple's add-to-Calendar sheet, from a game's day row, with the entry as it was at the tap: one
    /// called off or ending while the sheet is up keeps its sheet, and Cancel.
    @State private var calendarShown = false
    @State private var adding: CalendarEntry?
    /// A game's page scrolled off its top: its score slides under the clock and the round buttons, so a
    /// fade of its dark comes in behind them (game-card 08).
    @State private var scrolled = false
    /// How far down the page is, for coming back to it after a restart (`LeftOff`): its link row
    /// sits low, and that's the tap that leaves the app.
    @State private var position = ScrollPosition()
    /// Where it lands after a restart, while its height is still growing to let it.
    @State private var landAt: CGFloat?
    @Environment(\.openURL) private var openURL
    /// The small map is open under Map.
    @State private var smallMap = false
    /// The small map's still, made the first time it opens: a page whose Map is never tapped makes none.
    @State private var mapShot: UIImage?
    /// A neighbour's Event's places after the first (BP app town-feed 54), read as the page opens.
    @State private var morePlaces: [String] = []
    /// A long Event's parts (BP app happening-now 06), read as the page opens: its Schedule under Map.
    @State private var parts: [EventPart] = []
    /// A basketball game's player lines as the page read them on opening (game-card 35); a live game's realtime row
    /// brings newer ones on `game`.
    @State private var players: [Game.Box]?
    /// The small map's top, and the foot of what shows above the bar (the home bar with none), both in the page's
    /// own coordinates: whether opening it scrolls it clear of the bar.
    @State private var smallMapTop: CGFloat = 0
    @State private var visibleBottom: CGFloat = 0
    /// A game's scoring plays' top in the page's own coordinates, where "Show less" lands the page (game-card 34).
    @State private var playsTop: CGFloat = 0
    /// How far the page can scroll now, as its scroll offset counts it: "Show less" lands no lower than the shorter
    /// page can go, or the page went past its end and dropped back (game-card 34, review).
    @State private var room: CGFloat = 0
    @Environment(\.displayScale) private var displayScale
    /// What raises Block Party's map on this Event: the shell's, or the map's own when the page is on it.
    @Environment(\.viewOnMap) private var viewOnMap

    /// The Going chat's row: not on the map's own stack, which has no chat to push to.
    private let goingChat: Bool
    /// Opened from the Review queue (BP app launch-ready 07): an Event that may not be live yet, so
    /// nothing on it acts. No Attend bar, no share or save, no Going chat, and no coming back to it
    /// after a restart.
    private let reviewing: Bool

    init(item: FeedCardItem, goingChat: Bool = true, reviewing: Bool = false) {
        self.item = item
        self.goingChat = goingChat && !reviewing
        self.reviewing = reviewing
        _landAt = State(initialValue: LeftOff.reopening(item.id) ? LeftOff.current?.eventY : nil)
    }

    /// Sizes off the Reference, in points. Measured 2026-09-26 on the original PNG. A business's
    /// page in Search takes the same (`BusinessPage`, Jesse 2026-10-17: like the Event page).
    enum Metric {
        /// Screen top to the sheet's edge: 303 of 393 pt. Other widths keep the
        /// ratio, so 324 pt on a 420 pt phone (guessed).
        static let heroAspect: CGFloat = 393.0 / 303.0
        /// The sheet's top corners: a circle fitted to the Reference's corner
        /// measures 72 px, 24 pt. No token is 24 (`card` 20, `bento` 22).
        static let sheetCorner: CGFloat = 24
        /// How far the photo runs on under the sheet: the corner, so no paper
        /// shows through the curve (guessed).
        static let heroUnderlap: CGFloat = sheetCorner
        /// Content, buttons, counter, pill and the RSVP bar all sit 20 pt in from the edge.
        static let inset: CGFloat = 20
        /// The round buttons: 36 pt circles in 44 pt tap boxes, their tops 13.5 pt
        /// under the safe area. Share and save sit 44 pt apart, centre to centre.
        static let button: CGFloat = 36
        static let tapBox: CGFloat = 44
        /// The heart in its circle: half the circle, the map card's 18 pt (inside-cards 16).
        static let heart: CGFloat = 18
        static let buttonTop: CGFloat = 13.5
        /// With no photo, the sheet starts this far under the buttons (guessed).
        static let noPhotoGap: CGFloat = 16
        /// The photo counter: 43 x 27 pt, its bottom 20.5 pt above the sheet edge.
        static let counterSize = CGSize(width: 43, height: 27)
        static let counterBottom: CGFloat = 20.5
        /// The location pill: 44 pt tall; its pin a 10.7 pt box 15 pt in, the
        /// place name 35 pt in.
        static let pillHeight: CGFloat = 44
        static let pillInset: CGFloat = 15
        static let pinBox: CGFloat = 10.7
        /// The RSVP bar, Meetup's floating capsule measured off its iOS screen at 3x: 57 pt
        /// tall, 20 pt from the sides (`inset`), the words 24 pt in, the pill 5.5 pt from the end.
        /// Its bottom is 35 pt above the screen's: 1 pt above the 34 pt home-bar inset (Jesse,
        /// 2026-10-18; the Figma page's 74 pt counted Mobbin's 40 pt caption strip).
        static let barHeight: CGFloat = 57
        static let barWordsInset: CGFloat = 24
        static let barPillInset: CGFloat = 5.5
        static let barBottom: CGFloat = 1
        /// The white layer under the bar's glass (picked on the eyes sim against Meetup's
        /// frosting: the words behind show at about 5%).
        static let barWhite: Double = 0.6
        /// Meetup's fade to the page under the bar starts 115 pt above the screen's bottom,
        /// 23 pt above the capsule's top (Jesse, 2026-10-18).
        static let fadeAboveBar: CGFloat = 23

        // Vertical rhythm, tuned so the rendered baselines land on the
        // Reference's: title cap-top 28 pt under the sheet edge, 36 pt title
        // lines, title → category 30, category → when 34, when → pill top 21.6,
        // pill → About 37.3, About → body 34, body lines 22.
        static let titleTop: CGFloat = 26
        static let titleLineSpacing: CGFloat = 9
        /// A page name in Inter Tight (group, business): its line is 7 pt taller than the
        /// event face's at 28, so 9 less 7 keeps a two-line name's gap where the event title's is.
        static let nameLineSpacing: CGFloat = 2
        static let categoryTop: CGFloat = 8
        static let pillTop: CGFloat = 17.3
        static let aboutTop: CGFloat = 33
        static let pinGap: CGFloat = 8
        /// The facts under the title (event-page-formats 06), off the approved mock's CSS (Meetup's
        /// rows): 16 pt under the title, each row a 22 pt glyph 14 pt from its words, 13 pt above and
        /// below them, the second line 3 pt under the first, a 20 pt glyph at its end; a 1 pt
        /// hairline between rows, under the words only. The host card 20 pt under the rows, About
        /// (and a game's score) 30 pt under the card, the Interest 12 pt under About.
        static let rowsTop: CGFloat = 16
        static let rowGlyph: CGFloat = 22
        /// The Going chat's two bubbles, to fit that box.
        static let chatGlyph: CGFloat = 15
        static let rowGap: CGFloat = 14
        static let rowPad: CGFloat = 13
        static let rowLineGap: CGFloat = 3
        static let rowEnd: CGFloat = 20
        static let hairline: CGFloat = 1
        static let hostTop: CGFloat = 20
        static let sectionTop: CGFloat = 30
        static let interestTop: CGFloat = 12
        /// A game's page counts as scrolled this far down, and its top fade runs this far under the
        /// buttons (picked).
        static let scrolledAfter: CGFloat = 8
        static let fadeBelowButtons: CGFloat = 28
        /// Paper under the last row, above the RSVP bar (guessed): with the bar's 57 + 1 pt
        /// inset, the last line rests just above the fade.
        static let contentBottom: CGFloat = 24
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if let game {
                    GameMatchup(game: game, when: current.whenLine?.text, cancelled: item.cancelled)
                        .padding(.horizontal, Metric.inset)
                        .padding(.top, Metric.buttonTop + Metric.tapBox)
                    sheet
                } else {
                    lookHero
                    lookWords
                }
            }
            // The page's own coordinates, which don't move as it scrolls: where the small map sits.
            .coordinateSpace(.named(Self.page))
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > Metric.scrolledAfter } action: { _, now in
            scrolled = now
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in
            LeftOff.pageY[item.id] = y
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.visibleRect.maxY - $0.contentInsets.bottom } action: { _, foot in
            visibleBottom = foot
        }
        // The page's height comes in over a few layouts, and a jump past it stops at the top. As far
        // as it can each time, so a page that's shorter now ("Read more" closed) still lands low.
        .onScrollGeometryChange(for: CGFloat.self) {
            $0.contentSize.height + $0.contentInsets.top + $0.contentInsets.bottom - $0.containerSize.height
        } action: { _, room in
            self.room = room
            guard let y = landAt, room > 0 else { return }
            position.scrollTo(y: min(y, room))
            if room >= y { landAt = nil }
        }
        // A finger on the page ends the landing, and so does a second: "Read more" mustn't jump it later.
        .onScrollPhaseChange { _, phase in if phase == .tracking { landAt = nil } }
        .task {
            guard landAt != nil else { return }
            try? await Task.sleep(for: .seconds(1))
            landAt = nil
        }
        .scrollPosition($position)
        // The small map's still, the first time it opens (until then its ground and the photo show), and again once
        // the page's width is known or a try failed.
        .task(id: item.id) {
            #if DEBUG
            if let names = LaunchFlags.value(.eventMorePlaces) { morePlaces = names.split(separator: "|").map(String.init); return }
            #endif
            // Only a neighbour's own Event can have more (a found one or a game never does), and only a real id.
            guard game == nil, !item.found, UUID(uuidString: item.id) != nil else { return }
            morePlaces = await CommunityAPI(auth: AuthStore.shared).morePlaces(event: item.id)
        }
        .task(id: item.id) {
            #if DEBUG
            if LaunchFlags.has(.townPartDay) { parts = EventSchedule.oneDaySamples(.now); return }
            if LaunchFlags.has(.townPart) { parts = EventSchedule.samples(.now); return }
            #endif
            // A game never has parts; a sample's id isn't a real one.
            guard game == nil, UUID(uuidString: item.id) != nil else { return }
            parts = await CommunityAPI(auth: AuthStore.shared).parts(event: item.id)
        }
        .task(id: item.id) {
            // Only a basketball game's file has player lines; a sample's id isn't a real one.
            guard game?.isBasketball == true, game?.players == nil, UUID(uuidString: item.id) != nil else { return }
            let read = await CommunityAPI(auth: AuthStore.shared).playerStats(event: item.id)
            withAnimation(reduceMotion ? nil : Motion.smooth) { players = read }
        }
        .task(id: smallMap ? width : nil) {
            guard smallMap, mapShot == nil, case .ourMap(let at)? = EventMapRoute.route(item) else { return }
            mapShot = await SmallMapShot.make(at: at, size: CGSize(width: width - 2 * EventLook.side, height: EventLook.smallMap),
                                              scale: displayScale)
        }
        // The picture runs up under the status bar, and the yellow page lays out from the screen's top too; a
        // game's page starts below it.
        .ignoresSafeArea(edges: game == nil ? .top : [])
        // A game's page is its teams' colors from edge to edge, fixed while the page scrolls over them
        // (game-card 08); an Event's is its picture's colour, near-black at the foot, fixed the same way,
        // and with no picture the exact yellow.
        .background {
            if let game {
                GameMatchup.backdrop(game).ignoresSafeArea()
            } else if sun {
                Hue.brandDisc.ignoresSafeArea()
            } else {
                ZStack {
                    Hue.gameNight
                    if let wash {
                        LinearGradient(stops: wash.stops, startPoint: .top, endPoint: .bottom)
                            .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : Motion.smooth, value: wash)
                .ignoresSafeArea()
            }
        }
        // Outside the scroll, so the buttons stay put while the page moves under them.
        // The sort priority asks VoiceOver to read them first, as they sit, not after the
        // About. AXe's element tree does not show sort priority, so the sim can't prove it.
        // An Event's page's top colour fading in under the clock once the page scrolls, 118 pt from the
        // screen's very top (the mock's), over the picture and under the buttons. A flexible clear view
        // ignores the safe area; a fixed frame can't (swift-traps).
        .overlay(alignment: .top) {
            if game == nil {
                // Near-black until the picture's colour is here, never a grey band (review).
                let top = sun ? Hue.brandDisc : wash.map { Color(hex: $0.top) } ?? Hue.gameNight
                Color.clear
                    .overlay(alignment: .top) {
                        LinearGradient(stops: [.init(color: top, location: 0), .init(color: top, location: EventLook.topFadeSolid),
                                               .init(color: top.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom)
                            .frame(height: EventLook.topFade)
                    }
                    .ignoresSafeArea(edges: .top)
                    .opacity(scrolled ? 1 : 0)
                    .animation(reduceMotion ? nil : Motion.smooth, value: scrolled)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .top) {
            Group {
                // Removed, not hidden, while the picture is lifted: they're glass (swift-traps). They go at once,
                // before the picture's snapshot, and fade back in once it has landed.
                if game != nil { topButtons } else if !heroLifted {
                    lookButtons.transition(.asymmetric(insertion: .opacity, removal: .identity))
                }
            }
            .animation(reduceMotion ? nil : Motion.smooth, value: heroLifted)
            .accessibilityElement(children: .contain)
            .accessibilitySortPriority(1)
            // A game's dark fading in under the clock and the buttons once the page scrolls, the
            // bottom bar's fade turned over.
            .background(alignment: .top) {
                if game != nil {
                    LinearGradient(colors: [Hue.gameNight, Hue.gameNight.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .padding(.bottom, -Metric.fadeBelowButtons)
                        .ignoresSafeArea(edges: .top)
                        .opacity(scrolled ? 1 : 0)
                        .animation(reduceMotion ? nil : Motion.smooth, value: scrolled)
                        .allowsHitTesting(false)
                }
            }
        }
        .accessibilityElement(children: .contain)
        // Whether the person may act is the module's, not the card's the page was opened
        // with: on first launch the quiet account can arrive while the page is open, and
        // the bar comes up then. An inset, so the page scrolls under the capsule and its last
        // line stops clear of it. Not `.safeAreaBar`: it let iOS recolour the Town bar
        // (2026-09-24); the bar brings its own fade.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !reviewing, let words = actions.rsvp(current, bar: true, look: game == nil) {
                rsvpBar(words)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom))
            }
        }
        .animation(Motion.smooth, value: actions.canAct)
        // Light words on a game's dark and an Event's, its rows, buttons and bar with them, as a school's
        // page (TeamPage); the yellow page keeps ink.
        .environment(\.colorScheme, game != nil || !sun ? .dark : colorScheme)
        // Hidden, never `navigationBarBackButtonHidden`. Hidden here, UIKit also turns
        // the swipe back off; `SwipeBack` (RootView) turns it back on.
        .toolbar(.hidden, for: .navigationBar)
        .animation(Motion.smooth, value: photos.count)
        // A goal's scorer under the score and its play in the list move the rest of the page down together
        // (game-card 09), rather than the page jumping.
        .animation(reduceMotion ? nil : Motion.smooth, value: game?.plays.count)
        .sheet(isPresented: $calendarShown) {
            // Apple's sheet in the phone's own appearance, not the page's dark.
            if let adding { AddToCalendar(entry: adding).environment(\.colorScheme, colorScheme) }
        }
        // A failed Join or Heart shakes and buzzes only while its page is open: the buzz
        // used to land on Town after a pop. Leaving never cancels the write itself.
        .onAppear {
            actions.pageOpened(item.id)
            live?.hold(liveHolder, [item])
            if !reviewing { LeftOff.page = item.id }
        }
        .onDisappear {
            if LeftOff.page == item.id { LeftOff.page = nil }
            actions.pageClosed(item.id)
            live?.hold(liveHolder, [])
        }
    }

    /// No picture and no logo: the whole page is the exact yellow, with ink words (Jesse, 2026-11-06).
    private var sun: Bool { game == nil && !hasHero }

    /// The page's colours from its picture's colour; none until the picture is here.
    private var wash: EventLook.Wash? {
        pageColor.map { photo in
            EventLook.wash(heroColor(photo))
        }
    }

    /// The colour under the finger as the hero swipes: between the two pictures it sits between, each its own once it
    /// has landed and the first picture's until then.
    private func heroColor(_ photo: UInt32) -> UInt32 {
        let pages = heroPages
        guard pages.count > 1 else { return photo }
        let at = Self.between(heroSwipe, count: pages.count)
        let color = { (index: Int) in index == 0 ? photo : pageColors[pages[index].url] ?? photo }
        return EventLook.blend(color(at.page), color(at.page + 1), at.toward)
    }

    /// Reads the page's colour off a picture that's just landed: the most common colourful hue, or grey
    /// once it's called off, since its photo is black and white (`EventLook`, tested).
    private func takeColor(from image: CGImage) {
        let pixels = EventLook.pixels(of: image)
        pale = EventLook.brightness(pixels: pixels) > EventLook.pale
        pageColor = item.cancelled ? EventLook.grey : EventLook.dominant(pixels: pixels)
    }

    /// Where it was found: every read sends it with the Event card (BP app codebase-health-2).
    private var link: BusinessPage.LinkRow? { Self.sourceLink(item.sourceURL) }

    // MARK: A game (game-card 05)

    /// The game as it is now, its score and plays coming in; else as the page was opened.
    private var game: Game? {
        live?.game(item) ?? item.game
    }

    /// The opened Event with that game, so a final reaching the open page turns its bar to "went"
    /// and its day line to the day, as the card does.
    private var current: FeedCardItem {
        var card = item
        card.game = game
        return card
    }

    // MARK: The picture (inside-cards 15 and 17)

    /// The card's picture (`FeedCardItem.pagePhotos`): the Event's own, else its place's, saved by Block Party,
    /// so nothing is looked up; never its place's cover alone (BP app town-feed 72). One picture, so the page
    /// doesn't swipe (Jesse, 2026-11-06).
    private var photos: [FeedCardImageSource] {
        item.pagePhotos(failed: failedPhotos)
    }

    /// A place we have no photo of puts its logo where the picture goes, on a white disc: the card's own
    /// picture when that is the logo, else its place's.
    private var heroLogo: SearchLogo? {
        photos.isEmpty ? item.image.logo ?? item.place?.logo ?? item.hostPicture.map(FeedCardImageSource.init)?.logo : nil
    }

    private var hasHero: Bool { !photos.isEmpty || heroLogo != nil || !heroPages.isEmpty }

    /// The picture, when it shows as a flyer: a flyer (BP app event-photos 16), or a photo too small to fill
    /// the top without a blur, whole as a flyer is (Jesse, 2026-11-17, BP app event-photo-sharp), unless the
    /// page swipes from it to the Event's flyer or through an exhibit's pieces, whose pictures all fill the top
    /// alike (event-photos 25). One that failed to load has left the list.
    private var flyer: URL? {
        guard let first = photos.first, let url = first.url else { return nil }
        if item.whole, item.image.url == url { return url }
        guard item.flyer == nil, item.pieces.isEmpty, case .placePhoto(_, _, let aspect?, let height?) = first,
              Self.tooSmall(aspect: aspect, height: height, frame: CGSize(width: width, height: photoHeight),
                            scale: displayScale) else { return nil }
        return url
    }

    /// A photo stretched more than this to fill the top shows whole instead (Jesse, 2026-11-17: 1.10).
    static let mostStretch: CGFloat = 1.10

    /// A photo `height` pixels tall at `aspect` (width over height) would be stretched past `mostStretch` to
    /// fill `frame` points at `scale`: the Grey Face Rescue photo, 1600 x 1067, fills 402 x 410 at 3x 1.15 times.
    static func tooSmall(aspect: Double, height: Int, frame: CGSize, scale: CGFloat) -> Bool {
        guard aspect > 0, height > 0 else { return false }
        let pixels = CGSize(width: CGFloat(aspect) * CGFloat(height), height: CGFloat(height))
        return max(frame.width * scale / pixels.width, frame.height * scale / pixels.height) > mostStretch
    }

    /// A flyer's shape, width over height: as it decoded, so it never crops; before that as the database sent
    /// it, else square.
    private var flyerAspect: CGFloat {
        if let url = flyer, let image = FeedCardImageLoader.shared.largest(for: url), image.height > 0 {
            return CGFloat(image.width) / CGFloat(image.height)
        }
        if case .placePhoto(_, _, let aspect?, _) = photos.first ?? .fallback { return aspect }
        return 1
    }

    /// A photo's height at this width: edge to edge, 410 pt on the mock's phone.
    private var photoHeight: CGFloat { EventLook.photoHeight * width / EventLook.mockWidth }

    /// The picture at the top: a photo melting into the page, a flyer whole over its melt, or a logo on its
    /// disc. Town's heart sits on it, and a photo's credit beside the heart; a flyer's credit goes under it,
    /// so it never covers the flyer's words. Pulling the page down past its top stretches it from its
    /// bottom edge, as before (guessed, until Apple Invites' own motion is recorded). An Event with its own
    /// photo swipes through an exhibit's other pieces and its flyer (`heroPager`, event-photos 25, town-feed 59).
    @ViewBuilder private var lookHero: some View {
        let pages = heroPages
        if !pages.isEmpty {
            heroPager(pages)
        } else if let picture = photos.first, let url = picture.url {
            heroPicture(url: url, picture: picture, isFlyer: flyer == url, aspect: flyerAspect)
        } else if let heroLogo {
            EventLogoHero(logo: heroLogo) { takeColor(from: $0) }
                .visualEffect { content, proxy in
                    let pull = max(0, proxy.frame(in: .scrollView(axis: .vertical)).minY)
                    return content.scaleEffect(1 + pull / max(proxy.size.height, 1), anchor: .bottom)
                }
                .overlay(alignment: .bottomTrailing) {
                    if !reviewing {
                        TownCardHeart(item: item)
                            .padding(.trailing, EventLook.heartInset)
                            .padding(.bottom, EventLook.heartFlyerInset)
                    }
                }
                .transition(.opacity)
        }
    }

    /// One picture as the hero shows it, a photo melting into the page or a flyer whole, with its heart and credit.
    /// In the pager (`chrome` false) the heart and credit sit over the set instead, still as the finger drags.
    private func heroPicture(url: URL, picture: FeedCardImageSource, isFlyer: Bool, aspect: CGFloat,
                             pale: Bool? = nil, chrome: Bool = true) -> some View {
        let pale = pale ?? self.pale
        let height = isFlyer ? EventFlyerHero.height(aspect: aspect, width: width) : photoHeight
        let flyerSize = EventFlyerHero.size(aspect: aspect, width: width)
        return Group {
            if isFlyer {
                EventFlyerHero(url: url, aspect: aspect, width: width, pale: pale, cancelled: item.cancelled,
                               ready: PhotoPager.isShown(url, in: shownPhotos), onReady: { shown(url) }, onFailure: { drop(url) })
            } else {
                EventMeltHero(url: url, width: width, height: height, pale: pale, cancelled: item.cancelled,
                              ready: PhotoPager.isShown(url, in: shownPhotos), onReady: { shown(url) }, onFailure: { drop(url) })
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(picture.attribution.map { "Photo, by \($0)" } ?? "Photo")
        .accessibilityIdentifier(isFlyer && swipeFlyer == url ? "event-page-flyer" : "event-page-picture")
        // A shimmer until the bitmap lands, as the carousel had.
        .overlay(alignment: .top) {
            if !PhotoPager.isShown(url, in: shownPhotos) {
                SkeletonBlock(cornerRadius: 0).frame(height: height).shimmering().transition(.opacity)
            }
        }
        .animation(Motion.smooth, value: shownPhotos)
        .visualEffect { content, proxy in
            let pull = max(0, proxy.frame(in: .scrollView(axis: .vertical)).minY)
            return content.scaleEffect(1 + pull / max(proxy.size.height, 1), anchor: .bottom)
        }
        // Two fingers lift it where it sits, its heart and credit too (BP app photo-zoom). The melt's
        // ground is clear, so the whole picture takes the fingers.
        .contentShape(Rectangle())
        .pinchToZoom(slot: wash.map { Color(hex: $0.top) } ?? Hue.gameNight, lifted: $heroLifted)
        // After the stretch, so they stay put, unscaled.
        .overlay(alignment: .bottomTrailing) {
            if chrome, !reviewing {
                TownCardHeart(item: item)
                    .padding(.trailing, isFlyer ? (width - flyerSize.width) / 2 + EventLook.heartFlyerInset : EventLook.heartInset)
                    .padding(.bottom, isFlyer ? EventLook.flyerBottom + EventLook.heartFlyerInset
                                              : EventLook.heartAboveFoot - TownCardHeart.side)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if chrome, !isFlyer, let credit = picture.attribution, PhotoPager.isShown(url, in: shownPhotos) {
                PhotoCredit(names: [credit], report: picture.report(place: item.whereLine), spoken: false)
                    .padding(.leading, EventLook.heartInset - PhotoCredit.edgeInset)
                    .padding(.bottom, EventLook.creditAboveFoot - PhotoCredit.edgeInset)
            }
        }
        .transition(.opacity)
    }

    // MARK: Its own photo, an exhibit's other pieces, then its flyer (event-photos 25, town-feed 59)

    /// The pictures the hero swipes through: the Event's own photo while it is on show, an exhibit's other pieces, then
    /// its flyer, skipping any that failed. None when there is only one, so the page shows it alone.
    private var heroPages: [HeroPage] {
        guard !item.whole, item.image.url != nil, photos.first?.url == item.image.url || !item.pieces.isEmpty else { return [] }
        return Self.heroPages(own: item.image, pieces: item.pieces, flyer: item.flyer, failed: failedPhotos)
    }

    /// The flyer the hero ends on, when it has one.
    private var swipeFlyer: URL? {
        heroPages.last.flatMap { $0.flyer ? $0.url : nil }
    }

    /// How far the flyer has come in: 0 until the picture before it, 1 on it.
    private var flyerIn: CGFloat {
        guard swipeFlyer != nil else { return 0 }
        return min(max(heroSwipe - CGFloat(heroPages.count - 2), 0), 1)
    }

    /// The flyer's shape: as it decoded, else as the database sent it, else square.
    private var swipeAspect: CGFloat {
        if let url = item.flyer, let image = FeedCardImageLoader.shared.largest(for: url), image.height > 0 {
            return CGFloat(image.width) / CGFloat(image.height)
        }
        return item.flyerAspect.map { CGFloat($0) } ?? 1
    }

    /// The pictures side by side, a page at a time, as Instagram's photo set (Jesse, 2026-11-10: "you could swipe and
    /// then see the full list of things"; 2026-11-17: "like an Instagram carousel"). The frame grows from a photo's
    /// height to the flyer's as the finger drags, so the flyer stays its full size, and the page's colour goes from one
    /// picture's to the next with it; both turn back if the finger does. Dots level with the heart say which is on show.
    private func heroPager(_ pages: [HeroPage]) -> some View {
        let tall = EventFlyerHero.height(aspect: swipeAspect, width: width)
        let heights = pages.map { $0.flyer ? tall : photoHeight }
        // Each heart's middle, down from the frame's top.
        let dots = pages.map { $0.flyer ? tall - EventLook.flyerBottom - EventLook.heartFlyerInset - TownCardHeart.side / 2
                                        : photoHeight - EventLook.heartAboveFoot + TownCardHeart.side / 2 }
        let at = Self.between(heroSwipe, count: pages.count)
        let height = heights[at.page] + (heights[at.page + 1] - heights[at.page]) * at.toward
        let dot = dots[at.page] + (dots[at.page + 1] - dots[at.page]) * at.toward
        let swipe = min(max(heroSwipe, 0), CGFloat(pages.count - 1))
        let shown = Int(swipe.rounded())
        // One heart and one credit over the set, as Instagram's post keeps its buttons still (the approved mock): the
        // heart moves only toward a flyer's corner, and the credit fades to the name of the picture nearest the finger.
        let flyerWidth = EventFlyerHero.size(aspect: swipeAspect, width: width).width
        let hearts = pages.map { $0.flyer ? ((width - flyerWidth) / 2 + EventLook.heartFlyerInset, EventLook.flyerBottom + EventLook.heartFlyerInset)
                                          : (EventLook.heartInset, EventLook.heartAboveFoot - TownCardHeart.side) }
        let heart = (hearts[at.page].0 + (hearts[at.page + 1].0 - hearts[at.page].0) * at.toward,
                     hearts[at.page].1 + (hearts[at.page + 1].1 - hearts[at.page].1) * at.toward)
        let near = pages[shown]
        let credit = near.flyer || !PhotoPager.isShown(near.url, in: shownPhotos) ? nil : near.picture.attribution
        return ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Array(pages.enumerated()), id: \.element.url) { index, page in
                    heroPicture(url: page.url, picture: page.picture, isFlyer: page.flyer, aspect: page.flyer ? swipeAspect : 1,
                                pale: index == 0 ? nil : pagePales[page.url] ?? false, chrome: false)
                        .frame(width: width, height: height, alignment: .top)
                        .accessibilityHidden(index != shown)
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        // The photo's melt runs on below its frame into the page, as it does alone; only its sides meet the screen's.
        .scrollClipDisabled()
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $heroPage)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x / max($0.containerSize.width, 1) } action: { _, x in
            heroSwipe = x
        }
        .frame(height: height)
        .overlay(alignment: .top) {
            if !reviewing {
                EventPageDots(count: pages.count, page: swipe)
                    .offset(y: dot - EventPageDots.side / 2)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !reviewing, !heroLifted {
                TownCardHeart(item: item)
                    .padding(.trailing, heart.0)
                    .padding(.bottom, heart.1)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if !heroLifted, let credit {
                PhotoCredit(names: [credit], report: near.picture.report(place: item.whereLine), spoken: false)
                    .padding(.leading, EventLook.heartInset - PhotoCredit.edgeInset)
                    .padding(.bottom, EventLook.creditAboveFoot - PhotoCredit.edgeInset)
                    .opacity(Double(max(0, 1 - abs(swipe - CGFloat(shown)) * 2)))
                    .id(near.url)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(pages[shown].flyer ? "Flyer, \(shown + 1) of \(pages.count)" : "Photo \(shown + 1) of \(pages.count)")
        .accessibilityAdjustableAction { direction in
            let next = (heroPage ?? 0) + (direction == .increment ? 1 : -1)
            withAnimation(reduceMotion ? nil : Motion.smooth) { heroPage = min(max(next, 0), pages.count - 1) }
        }
    }

    /// The picture's bitmap is on screen: its credit can show, and the page takes its colour.
    private func shown(_ url: URL) {
        shownPhotos.insert(url)
        guard let image = FeedCardImageLoader.shared.largest(for: url) else { return }
        // Each picture to swipe to keeps its own colour, which the page goes to as it comes in (town-feed 59).
        if heroPages.dropFirst().contains(where: { $0.url == url }) {
            let pixels = EventLook.pixels(of: image)
            let pale = EventLook.brightness(pixels: pixels) > EventLook.pale
            let color = item.cancelled ? EventLook.grey : EventLook.dominant(pixels: pixels)
            withAnimation(reduceMotion ? nil : Motion.smooth) {
                pagePales[url] = pale
                pageColors[url] = color
            }
        } else {
            takeColor(from: image)
        }
    }

    /// Whose photo is on screen, once it is: nil before, and for a photo with no credit.
    private var creditName: String? {
        guard let picture = photos.first, let url = picture.url, PhotoPager.isShown(url, in: shownPhotos) else { return nil }
        return picture.attribution
    }

    // MARK: The words (inside-cards 17)

    /// The lines' colour: a light tint of the page's colour; white until the colour is here.
    private var tint: Color {
        if sun { return Hue.onBrandDisc.opacity(EventLook.sunTint) }
        return wash.map { Color(hex: $0.tint) } ?? .white
    }

    /// Under the picture: a flyer's credit, the big centred title, the date and place in the tint, the two
    /// big buttons, the host's row, the Going chat and About. The yellow page starts its title 158 pt down.
    private var lookWords: some View {
        let ink: Color = sun ? Hue.onBrandDisc : .white
        let link = self.link
        let place = Self.placeText(item)
        return VStack(spacing: 0) {
            // The flyer it swipes to has its credit there too, coming in with it (town-feed 59).
            if let second = swipeFlyer, let credit = item.flyerCredit {
                HStack {
                    Spacer(minLength: 0)
                    PhotoCredit(names: [credit], report: FeedCardImageSource.placePhoto(second, credit: credit)
                                    .report(place: item.whereLine))
                        .padding(.trailing, -PhotoCredit.edgeInset)
                }
                .frame(height: EventLook.creditLine * flyerIn)
                .opacity(Double(flyerIn))
                .clipped()
            }
            if flyer != nil, let credit = creditName, let picture = photos.first {
                HStack {
                    Spacer(minLength: 0)
                    // The picture's label already says it ("Photo, by givemn").
                    PhotoCredit(names: [credit], report: picture.report(place: item.whereLine), spoken: false)
                        .padding(.trailing, -PhotoCredit.edgeInset)
                }
                .frame(height: EventLook.creditLine)
            }
            Text(item.title)
                .font(.eventDisplay(sun ? EventLook.sunTitle : EventLook.title))
                .lineSpacing(sun ? EventLook.sunTitleSpacing : EventLook.titleSpacing)
                .multilineTextAlignment(.center)
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
                // Called off, VoiceOver says so with the title: the bar's red pill comes last.
                .accessibilityValue(item.cancelled ? "Canceled" : "")
                .padding(.top, sun ? EventLook.sunTitleTop : EventLook.titleTop)
                // Without the flyer's credit, the title still sits where it does under a flyer alone (town-feed 59).
                .padding(.top, swipeFlyer == nil || item.flyerCredit != nil ? 0 : EventLook.creditLine * flyerIn)

            let date = Self.dateLine(current)
            let price = Self.priceLine(ages: item.ages, price: item.price)
            if date != nil || place != nil || !price.isEmpty {
                VStack(spacing: EventLook.lineHeight - EventLook.lineNatural) {
                    if let date {
                        Text(date.oneLine).accessibilityLabel(date.spoken)
                    }
                    // Each place on its own line, in the order its host picked them (town-feed 54, Uber's Route order).
                    if let place {
                        ForEach(Array(([place] + morePlaces).enumerated()), id: \.offset) { _, name in
                            Text(name)
                        }
                    }
                    // The price when a source said it (inside-cards 14), led by who it's for by age like a LEGO
                    // box's "18+ | 10273 | 3231 pcs" (inside-cards 30); nothing when unknown, never a placeholder.
                    if !price.isEmpty {
                        Self.priceText(price).accessibilityLabel(price.joined(separator: ", "))
                    }
                }
                .font(.apple(EventLook.line))
                .multilineTextAlignment(.center)
                .foregroundStyle(tint)
                .animation(reduceMotion ? nil : Motion.smooth, value: pageColor)
                .animation(reduceMotion ? nil : Motion.smooth, value: morePlaces)
                .frame(maxWidth: .infinity)
                .padding(.top, EventLook.linesTop)
            }

            // Map opens the small map below with a spot, else Apple Maps at the place (inside-cards 19); the page
            // it was found on by its app's name, else Website. With no one place, Website takes the whole row.
            let map = EventMapRoute.route(item)
            if map != nil || link != nil {
                HStack(spacing: EventLook.buttonGap) {
                    if let map {
                        EventBigButton(glyph: "map", word: "Map", sun: sun, lit: smallMap) { tapMap(map) }
                            .accessibilityHint(mapHint(map))
                    }
                    if let link {
                        EventBigButton(glyph: link.glyph, word: Self.linkWord(link), sun: sun) { openURL(link.url) }
                    }
                }
                .padding(.top, EventLook.buttonsTop)
            }

            // The small map, right below the buttons, opening and closing in place.
            if case .ourMap(let at)? = map {
                EventSmallMap(item: item, shot: mapShot) { openFullMap(at) }
                    .padding(.top, EventLook.smallMapTop)
                    .frame(height: smallMap ? EventLook.smallMapTop + EventLook.smallMap : 0, alignment: .top)
                    .clipped()
                    .allowsHitTesting(smallMap)
                    .accessibilityHidden(!smallMap)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.page)).minY } action: { smallMapTop = $0 }
            }

            // A long Event's parts (happening-now 06): none, no section.
            EventScheduleSection(parts: parts, ink: ink, tint: tint, picked: sun ? Hue.brandDisc : Hue.onBrandDisc)
                .animation(reduceMotion ? nil : Motion.smooth, value: parts)

            // Who hosts it, with Instagram's Follow, in a plain row (follows 02; inside-cards 09).
            EventHostRow(item: item, top: EventLook.hostTop, plain: true, sun: sun)

            if goingChat {
                ChatRoomRow(title: "Going chat", isIn: actions.going(current).isGoing,
                            listed: { [id = current.id] in $0.chat(forEvent: id) },
                            quiet: actions.going(current).count > 0 ? "\(actions.going(current).count) going" : nil,
                            access: { [id = current.id] in try await $0.goingAccess(id) },
                            route: { [current] in .going(current, isHost: $0) })
            }

            if let about = Self.aboutText(item.description, lineup: item.lineup ? item.hostName : nil) {
                EventAbout(text: about, sun: sun)
                    .padding(.top, EventLook.aboutTop)
            }
        }
        .padding(.horizontal, EventLook.side)
        .padding(.bottom, Metric.contentBottom)
        .frame(maxWidth: .infinity)
        // The heart on the yellow page, where the picture's corner would be (the mock's spot).
        .overlay(alignment: .topTrailing) {
            if sun && !reviewing {
                TownCardHeart(item: item, onWhite: true)
                    .padding(.trailing, EventLook.sunHeartInset)
                    .padding(.top, EventLook.sunHeartTop)
            }
        }
    }

    // MARK: The map (inside-cards 19)

    /// The page's own coordinate space.
    private static let page = "eventPage"

    private func mapHint(_ map: EventMapRoute) -> String {
        switch map {
        case .appleMaps: "Opens in Maps"
        case .ourMap: smallMap ? "Hides the map" : "Shows the map below"
        }
    }

    /// Opens or closes the small map in place; opening below the bar, the page scrolls on the same spring so it ends
    /// 12 pt above it, as the mock does. A short page drops a scroll asked while it grows, so once it has grown the
    /// page finishes the way.
    private func tapMap(_ map: EventMapRoute) {
        guard case .ourMap = map else {
            if case .appleMaps(let url) = map { openURL(url) }
            return
        }
        let opening = !smallMap
        let spring = reduceMotion ? nil : EventLook.smallMapSpring
        withAnimation(spring, completionCriteria: .logicallyComplete) {
            smallMap = opening
            if opening { clearTheBar() }
        } completion: {
            if opening, smallMap { withAnimation(spring) { clearTheBar() } }
        }
    }

    /// Scrolls the page so the open small map ends 12 pt above the bar, when it would end lower: in the page's own
    /// coordinates, where the map's top and the bar's (`visibleBottom`) both are.
    private func clearTheBar() {
        let short = smallMapTop + EventLook.smallMapTop + EventLook.smallMap + EventLook.smallMapClear - visibleBottom
        if short > 0.5 { position.scrollTo(y: (LeftOff.pageY[item.id] ?? 0) + short) }
    }

    /// The full map over the page, flying in to this Event's bubble and card; without a map to raise (the Review
    /// queue), Apple Maps' directions to the spot.
    private func openFullMap(_ at: CLLocationCoordinate2D) {
        Haptics.light()
        if let viewOnMap {
            viewOnMap.show(.init(event: current, spot: at))
        } else if let url = Directions.url(to: at) {
            openURL(url)
        }
    }

    /// Back, in Apple Invites' round glass over the picture. No calendar button (Jesse, 2026-11-15: "remove calender
    /// in top right corner").
    private var lookButtons: some View {
        EventGlassButton(glyph: "arrow.left", label: "Back", sun: sun) { dismiss() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, EventLook.backInset - (MeetupPillStyle.minTarget - EventLook.glass) / 2)
            .padding(.top, EventLook.glassTop - (MeetupPillStyle.minTarget - EventLook.glass) / 2)
    }

    // MARK: Buttons

    private var topButtons: some View {
        HStack(spacing: 0) {
            Self.circleButton(
                glyph: Image(systemName: "arrow.left"),
                label: "Back",
                onColor: game != nil
            ) { dismiss() }

            Spacer(minLength: 0)

            if !reviewing {
                // The card's share reveal. 15, not the row's 17: the Reference's share
                // mark is 14 x 17 pt.
                Self.circleButton(glyph: Image(systemName: "square.and.arrow.up").font(.sansSemibold(15)), label: "Share",
                                  onColor: game != nil) {
                    ShareCenter.shared.present(.event(item))
                }

                // The heart where the bookmark was: a heart is a save now (BP app inside-cards 16), and lands
                // the Event in You's Liked. The Town card's heart, red and filled once yours, popping to 1.3.
                // A game's page keeps it here for good (inside-cards 21), red too.
                let heart = actions.heart(item)
                let failures = actions.heartFailureCount(item.id)
                Self.circleButton(
                    glyph: FeedActionGlyphView(glyph: .heart, size: Metric.heart, filled: heart.isHearted)
                        .foregroundStyle(heart.isHearted ? Hue.heart : game != nil ? .white : Hue.ink)
                        .phaseAnimator([1, 1.3], trigger: heart.isHearted) { glyph, scale in
                            glyph.scaleEffect(reduceMotion ? 1 : scale)
                        } animation: { _ in .spring(response: 0.3, dampingFraction: 0.5) },
                    label: "Like", onColor: game != nil, action: toggleHeart)
                    .turnBackShake(failures: failures, shakes: !reduceMotion && heartTappedAt != failures)
                    .accessibilityValue(heart.isHearted ? "Liked" : "Not liked")
                    .accessibilityAddTraits(heart.isHearted ? .isSelected : [])
            }
        }
        // A game's sport between the buttons, as Apple Sports names its league (the Football draft); the
        // score below says it to VoiceOver.
        .overlay {
            if let game {
                Text(game.sport)
                    .font(.sansMedium(15))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                    // "Boys Basketball · 7th Grade" still fits between the buttons, as on the white card.
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 2 * Metric.tapBox + Metric.inset)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Metric.inset - (Metric.tapBox - Metric.button) / 2)
        .padding(.top, Metric.buttonTop - (Metric.tapBox - Metric.button) / 2)
    }

    /// A heart gets the light tap (taste.md, from `RealLifeActions`); the fill springs in, as on the
    /// Town card.
    private func toggleHeart() {
        heartTappedAt = actions.heartFailureCount(item.id)
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.5)) {
            actions.toggleHeart(item)
        }
    }

    /// A white circle with an ink glyph, lifted by the map's floating-button shadow
    /// (Jesse's pick, 2026-09-26; the Reference's heart is solid white). Not Liquid Glass: glass takes
    /// its colour from what is under it and went dark with white glyphs over a dark
    /// photo, even with the scheme pinned (measured 2026-09-26), and chrome never takes
    /// its colour from what is under it (taste.md).
    /// The same circle on a business's page in Search (`BusinessPage`).
    static func circleButton(
        glyph: some View,
        label: String,
        onColor: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            glyph
                .font(.sansSemibold(17))
                .foregroundStyle(onColor ? .white : Hue.ink)
                .frame(width: Metric.button, height: Metric.button)
                // The shadow on the circle alone: on the whole button it also lands
                // under each glyph and dulled the old bookmark's yellow to #F8E404. On a game's colors
                // (`onColor`, game-card 08) the circle is see-through white, as Apple Sports' are.
                .background {
                    if onColor {
                        Circle().fill(.white.opacity(0.14)).overlay(Circle().strokeBorder(.white.opacity(0.14)))
                    } else {
                        Circle().fill(Hue.surface).mapFloatShadow()
                    }
                }
                .frame(width: Metric.tapBox, height: Metric.tapBox)
                .contentShape(Rectangle())
        }
        .buttonStyle(.press(.squish))
        .accessibilityLabel(label)
    }

    // MARK: A game's sheet

    /// A game's page under its score: its plays, then the facts as Meetup's rows, the host in a grey card,
    /// About, the Interest and where it was found. As it was before inside-cards 17 (Jesse, 2026-11-06:
    /// "game pages stay the same").
    @ViewBuilder private var sheet: some View {
        if let game {
            VStack(alignment: .leading, spacing: 0) {
                // A game's score says its title (game-card 08): its plays lead, the facts follow.
                GameScoring(game: game, top: Metric.sectionTop) { shorter in
                    // "Show less" takes the page back up to the list's top, just under the round buttons, or to
                    // the shorter page's end when that comes first (game-card 34).
                    position.scrollTo(y: max(0, min(playsTop - Metric.buttonTop - Metric.tapBox, room - shorter)))
                }
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.page)).minY } action: { playsTop = $0 }

                // Each player's line under the plays (game-card 35): fading in when the read lands after the page opened.
                if let boxes = game.players ?? players {
                    GamePlayers(game: game, boxes: boxes, top: Metric.sectionTop)
                        .transition(.opacity)
                }

                facts
                    .padding(.top, Metric.sectionTop - Metric.rowsTop)

                // Who hosts it, with Follow (follows 02), in Meetup's grey card.
                EventHostRow(item: item, top: Metric.hostTop)

                if let about = Self.aboutText(item.description) {
                    AboutSection(text: about)
                        .padding(.top, Metric.sectionTop)
                }

                // Its Interest, in grey words that open nothing (event-page-formats 05).
                if let interest = Self.categoryText(item.category) {
                    Text(interest)
                        .font(.sans(15))
                        .foregroundStyle(Hue.inkSecondary)
                        .padding(.top, Self.aboutText(item.description) != nil ? Metric.interestTop : Metric.hostTop)
                }

                // Where it was found, for the rest: the Business page's link row (Jesse, 2026-10-27).
                if let link {
                    InfoPill(glyph: link.glyph, text: link.text, url: link.url, hint: "Opens the link",
                             glyphBox: SearchMetric.bizGlyphBox, leaves: true)
                        .padding(.top, SearchMetric.bizLinksTop)
                }
            }
            .padding(.horizontal, Metric.inset)
            .padding(.bottom, Metric.contentBottom)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: The facts (event-page-formats 06)

    /// A game's day and place under its score, each its own row with Apple's glyph, as Meetup's Event page
    /// lays them out: the day adds it to the phone's calendar, the place opens Maps.
    @ViewBuilder private var facts: some View {
        let day = Self.dayLines(current)
        let place = Self.placeText(item)
        if day != nil || place != nil {
            VStack(alignment: .leading, spacing: 0) {
                if let day {
                    let entry = Self.calendarEntry(current)
                    FactRow(glyph: "calendar", lines: day, end: entry == nil ? nil : .add,
                            hint: "Adds it to your phone's calendar") {
                        adding = entry
                        calendarShown = true
                    }
                }
                if day != nil, place != nil {
                    Hue.hairline
                        .frame(height: Metric.hairline)
                        .padding(.leading, Metric.rowGlyph + Metric.rowGap)
                }
                if let place {
                    // The same search Your Day's "Directions" opens.
                    FactRow(glyph: "mappin.and.ellipse", lines: Self.placeLines(place), end: .opens,
                            hint: "Opens in Maps") { Directions.url(forPlace: place).map { openURL($0) } }
                }
                if goingChat {
                    ChatRoomRow(title: "Going chat", isIn: actions.going(current).isGoing,
                                listed: { [id = current.id] in $0.chat(forEvent: id) },
                                quiet: actions.going(current).count > 0 ? "\(actions.going(current).count) going" : nil,
                                access: { [id = current.id] in try await $0.goingAccess(id) },
                                route: { [current] in .going(current, isHost: $0) })
                }
            }
            .padding(.top, Metric.rowsTop)
        }
    }

    // MARK: The bar

    /// Meetup's capsule floating over the page: an Event's faces, send and white Attend (`EventBar`), a game's
    /// RSVP words and its team's Attend as before (`RSVPArea`, inside-cards 21). The send and Invite open what
    /// the top share did. Under it the page fades to its foot, so words never run hard into its edge or the
    /// home bar.
    private func rsvpBar(_ words: RSVPWords) -> some View {
        Group {
            if game == nil {
                EventBar(item: current, words: words, sun: sun) { ShareCenter.shared.present(.event(item)) }
            } else {
                RSVPArea(item: current, words: words, size: .page, yellow: true, tint: game.flatMap { GameMatchup.attend($0) }) {
                    ShareCenter.shared.present(.event(item))
                }
                .padding(.leading, Metric.barWordsInset)
            }
        }
            .padding(.trailing, Metric.barPillInset)
            // 57 pt at the default text size; larger text grows it rather than spilling out.
            .padding(.vertical, Metric.barPillInset)
            .frame(minHeight: Metric.barHeight)
            // The whole capsule takes a touch, so one between the words and the pill never reaches
            // the page under it (rsvp-and-groups 06 found a Group page's link opening that way).
            .contentShape(Capsule())
            // A little glass, as Meetup's (Jesse at Check-in 2): the words behind it show through
            // blurred and faint. Apple's Liquid Glass over a white layer that keeps it light,
            // the tab bar's way (TabBar), since the glass alone darkens over dark content.
            .glassEffect(.regular, in: Capsule())
            .background {
                Capsule()
                    .fill(Hue.surface.opacity(Metric.barWhite))
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, Metric.inset)
            .padding(.bottom, Metric.barBottom)
            .background {
                // A game's page and an Event's fade to their near-black foot (game-card 08); the yellow page to its yellow.
                let ground = sun ? Hue.brandDisc : Hue.gameNight
                LinearGradient(colors: [ground.opacity(0), ground], startPoint: .top, endPoint: .bottom)
                    .padding(.top, -Metric.fadeAboveBar)
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)
            }
    }

    /// Takes a picture that failed out, so the next takes its place.
    private func drop(_ url: URL) {
        failedPhotos.insert(url)
    }

    // MARK: Pure rules (EventPageTests)

    /// The hero's picture: the event's own, else the venue's first photo, alone, so the page doesn't
    /// swipe (Jesse, 2026-11-06, BP app inside-cards 15). Anything that is not a photo yet, or that
    /// `failed` to load, is skipped, so the next one takes its place.
    static func photoList(
        event: FeedCardImageSource,
        venue: [FeedCardImageSource],
        failed: Set<URL> = []
    ) -> [FeedCardImageSource] {
        ([event] + venue).first { $0.url.map { !failed.contains($0) } ?? false }.map { [$0] } ?? []
    }

    /// One picture of the hero's set: a photo, or the flyer it ends on.
    struct HeroPage {
        let url: URL
        let picture: FeedCardImageSource
        let flyer: Bool
    }

    /// The hero's set (BP app event-photos 25, town-feed 59): the Event's own photo, an exhibit's other pieces in
    /// order, then its flyer, each picture once, each that `failed` left out, so the next piece leads when the first
    /// fails. None without an own photo, or with one picture left.
    static func heroPages(own: FeedCardImageSource?, pieces: [FeedCardImageSource], flyer: URL?,
                          failed: Set<URL>) -> [HeroPage] {
        guard let own, own.url != nil else { return [] }
        var seen = failed
        let photos = ([own] + pieces).compactMap { picture in
            picture.url.flatMap { seen.insert($0).inserted ? HeroPage(url: $0, picture: picture, flyer: false) : nil }
        }
        guard !photos.isEmpty else { return [] }
        let last = flyer.flatMap { seen.insert($0).inserted ? HeroPage(url: $0, picture: .placePhoto($0, credit: nil), flyer: true) : nil }
        let pages = photos + (last.map { [$0] } ?? [])
        return pages.count > 1 ? pages : []
    }

    /// Where a swipe `x` pages across rests in a set of `count`: the picture on its left and how far toward the next,
    /// held to the set's ends, so a rubber band past either stays on it.
    static func between(_ x: CGFloat, count: Int) -> (page: Int, toward: CGFloat) {
        guard count > 1 else { return (0, 0) }
        let x = min(max(x, 0), CGFloat(count - 1))
        let page = min(Int(x), count - 2)
        return (page, x - CGFloat(page))
    }

    /// "2/3" on the second of three; nil when there is only one photo to show.
    static func counterText(page: Int, count: Int) -> String? {
        count >= 2 ? "\(page + 1)/\(count)" : nil
    }

    /// About's words: its description, led by what it is part of when its flyer lists other things too ("Part of Sal's
    /// Bar & Grill's lineup"; Jesse, 2026-11-10, BP app town-feed 59), the line alone without a description.
    static func aboutText(_ description: String?, lineup host: String? = nil) -> String? {
        let part = nonempty(host).map { "Part of \($0)\(($0.hasSuffix("s") ? "'" : "'s")) lineup" }
        let words = [part, nonempty(description)].compactMap { $0 }
        return words.isEmpty ? nil : words.joined(separator: "\n\n")
    }

    /// The price line's facts (inside-cards 30): who it's for by age first, as a LEGO box leads with "18+", then the
    /// price; each only when a source said it.
    static func priceLine(ages: String?, price: String?) -> [String] {
        [nonempty(ages), nonempty(price)].compactMap { $0 }
    }

    /// The facts with LEGO's thin rule between them, the rule a step lighter than the words.
    static func priceText(_ facts: [String]) -> Text {
        facts.dropFirst().reduce(Text(verbatim: facts.first ?? "")) { line, fact in
            Text("\(line)\(Text(verbatim: "  |  ").foregroundStyle(.secondary))\(Text(verbatim: fact))")
        }
    }

    /// The found page as the Business page draws a link: "Facebook", "Instagram", else the site's name.
    static func sourceLink(_ url: URL?) -> BusinessPage.LinkRow? {
        guard let url, let host = url.host()?.lowercased() else { return nil }
        let kind = host.hasSuffix("facebook.com") ? "facebook" : host.hasSuffix("instagram.com") ? "instagram" : "website"
        return BusinessPage.rows([PlaceLink(kind: kind, url: url.absoluteString)]).first
    }

    /// The big button's word for the page it was found on: Facebook and Instagram by name, else Website.
    static func linkWord(_ link: BusinessPage.LinkRow) -> String {
        ["Facebook", "Instagram"].contains(link.text) ? link.text : "Website"
    }

    /// A fact's two lines, as its row prints them and as VoiceOver reads them.
    struct FactLines: Equatable {
        let first: String
        var second: String? = nil

        var spoken: String {
            [first, second?.replacingOccurrences(of: " – ", with: " to ")].compactMap { $0 }.joined(separator: ", ")
        }

        /// Both on one line, as the Event page's centred date line prints them.
        var oneLine: String { [first, second].compactMap { $0 }.joined(separator: ", ") }
    }

    /// The Event page's one date line (inside-cards 17), Apple Invites' "Sat, 8 Feb, 6:00–8:00 PM" in the
    /// app's words: the short day, its hours, then how it repeats: "Thu, Nov 19, 6 – 8 PM", "Sun, Nov 8,
    /// 9 AM · Every Sunday", "Mon, Nov 16, until Wednesday, November 25". The year past six months off.
    static func dateLine(_ item: FeedCardItem, now: Date = .now) -> FactLines? {
        guard let lines = dayAndHours(item, now: now) else { return nil }
        let day = item.when.map { when in
            let withYear = abs(Town.days(from: now, to: when.start)) > 183
            return Town.format(when.start, withYear ? "EEEMMMdyyyy" : "EEEMMMd")
        } ?? lines.first
        var rest = lines.second
        if rest?.hasPrefix("Until ") == true { rest = "until " + rest!.dropFirst(6) }
        guard let repeats = nonempty(item.recurrence) else { return FactLines(first: day, second: rest) }
        return FactLines(first: day, second: [rest, repeats].compactMap { $0 }.joined(separator: " · "))
    }

    /// The day row (event-page-formats 06): the day in full over its hours, "Monday, November 30" over
    /// "4:30 – 6 PM", the start alone when the Event gives no end, "7 PM until Wednesday, December 2"
    /// when it runs over days. Untimed: "Until" its last day when it runs over days, else the time as
    /// written ("after dark"), else the day alone. The year past six months off, as the card's. A repeat
    /// follows its hours, "9 AM · Every Sunday" (BP app inside-cards 11).
    static func dayLines(_ item: FeedCardItem, now: Date = .now) -> FactLines? {
        dayAndHours(item, now: now).map { lines in
            guard let repeats = nonempty(item.recurrence) else { return lines }
            return FactLines(first: lines.first, second: [lines.second, repeats].compactMap { $0 }.joined(separator: " · "))
        }
    }

    /// The Attend bar's day over its time while nobody's going (inside-cards 18): the date line's words without its
    /// repeat, every day short so they fit beside Attend: "Thu, Nov 19" over "6 – 8 PM", "Mon, Nov 16" over
    /// "until Wed, Nov 25".
    static func barDay(_ item: FeedCardItem, now: Date = .now) -> FactLines? {
        guard var lines = dayAndHours(item, now: now, short: true) else { return nil }
        if let rest = lines.second, rest.hasPrefix("Until ") { lines.second = "until " + rest.dropFirst(6) }
        return lines
    }

    /// `short`: "Thu, Nov 19" for "Thursday, November 19".
    private static func dayAndHours(_ item: FeedCardItem, now: Date, short: Bool = false) -> FactLines? {
        guard let when = item.when else { return item.whenLine.map { FactLines(first: $0.text) } }
        let withYear = abs(Town.days(from: now, to: when.start)) > 183
        let format = short ? (withYear ? "EEEMMMdyyyy" : "EEEMMMd") : withYear ? "EEEEMMMMdyyyy" : "EEEEMMMMd"
        let day = { (date: Date) in Town.format(date, format) }
        // A game whose final is in shows its day alone, as its card (game-card 02).
        if item.game?.final != nil { return FactLines(first: day(when.start)) }
        guard when.timed else {
            let last = when.end.addingTimeInterval(-1)
            if Town.days(from: when.start, to: last) > 0 {
                return FactLines(first: day(when.start), second: "Until \(day(last))")
            }
            let written = item.allDay ? nil : nonempty(item.startTime)
            return FactLines(first: day(when.start), second: written)
        }
        guard item.endAt != nil else { return FactLines(first: day(when.start), second: Town.clock(when.start)) }
        let start = Town.gregorian.component(.hour, from: when.start) * 60 + Town.gregorian.component(.minute, from: when.start)
        let length = Int(when.end.timeIntervalSince(when.start) / 60)
        guard length < PlaceHours.day else {
            return FactLines(first: day(when.start), second: "\(Town.clock(when.start)) until \(day(when.end))")
        }
        return FactLines(first: day(when.start),
                         second: length > 0 ? PlaceHours.line([start..<start + length]) : Town.clock(when.start))
    }

    /// What the day row adds to the phone's calendar: the hours the app keeps (`EventWhen`, two
    /// hours when it gives no end). nil once it's called off or over, when the row adds nothing.
    static func calendarEntry(_ item: FeedCardItem, now: Date = .now) -> CalendarEntry? {
        guard !item.cancelled, item.game?.final == nil, let when = item.when, now < when.end else { return nil }
        return CalendarEntry(title: item.title, starts: when.start, ends: when.end, allDay: !when.timed,
                             place: placeText(item))
    }

    /// The place row: the name over the rest after its first comma ("Saint John's Abbey Arboretum"
    /// over "Collegeville"); one line without one.
    static func placeLines(_ place: String) -> FactLines {
        guard let comma = place.firstIndex(of: ",") else { return FactLines(first: place) }
        let name = place[..<comma].trimmingCharacters(in: .whitespaces)
        let rest = place[place.index(after: comma)...].trimmingCharacters(in: .whitespaces)
        return name.isEmpty || rest.isEmpty ? FactLines(first: place) : FactLines(first: name, second: rest)
    }

    /// `.other` is the fallback for a missing category, not a category.
    static func categoryText(_ category: EventCategory?) -> String? {
        guard let category, category != .other else { return nil }
        return category.label
    }

    static func placeText(_ item: FeedCardItem) -> String? {
        nonempty(item.whereLine)
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}

/// One fact under an Event's title (event-page-formats 06): Apple's glyph, a line over a grey line,
/// and at its end what a tap does, pressed as the link row is. A row that opens nothing has no end
/// and doesn't press (05).
struct FactRow: View {
    enum End { case add, opens }

    let glyph: String
    /// Two bubbles run wider than the page's other glyphs, and it's made to fit their box.
    var glyphSize: CGFloat = 19
    let lines: EventPage.FactLines
    let end: End?
    let hint: String
    /// A chat it pushes, instead of its action.
    var link: ChatRoute? = nil
    let action: () -> Void

    var body: some View {
        if let link {
            NavigationLink(value: link) { row }
                .buttonStyle(.press(.squish))
                .accessibilityLabel(lines.spoken)
                .accessibilityHint(hint)
        } else if end != nil {
            Button(action: action) { row }
                .buttonStyle(.press(.squish))
                .accessibilityLabel(lines.spoken)
                .accessibilityHint(hint)
        } else {
            row
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(lines.spoken)
        }
    }

    private var row: some View {
        let m = EventPage.Metric.self
        return HStack(spacing: m.rowGap) {
            Image(systemName: glyph)
                .font(.sans(glyphSize))
                .frame(width: m.rowGlyph, height: m.rowGlyph)
            VStack(alignment: .leading, spacing: m.rowLineGap) {
                Text(lines.first)
                    .font(.sansMedium(17))
                if let second = lines.second {
                    Text(second)
                        .font(.sans(15))
                        .foregroundStyle(Hue.inkSecondary)
                        .lineLimit(link == nil ? nil : 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let end {
                // The add glyph in ink, the chevron grey, as the mock.
                Image(systemName: end == .add ? "calendar.badge.plus" : "chevron.right")
                    .font(end == .add ? .sans(17) : .sansSemibold(15))
                    .foregroundStyle(end == .add ? Hue.ink : Hue.inkSecondary)
                    .frame(width: m.rowEnd, height: m.rowEnd)
            }
        }
        .foregroundStyle(Hue.ink)
        .padding(.vertical, m.rowPad)
        .contentShape(Rectangle())
    }
}

/// Apple's own add-to-Calendar sheet, filled in (event-page-formats 05). From iOS 17 it runs outside
/// the app with the calendars' own access, so it asks no permission (Apple, "Accessing the event
/// store"); Add or Cancel comes back to the page.
private struct AddToCalendar: UIViewControllerRepresentable {
    let entry: CalendarEntry
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let event = EKEvent(eventStore: EventKitCalendar.store)
        EventKitCalendar.write(entry, into: event)
        let controller = EKEventEditViewController()
        controller.eventStore = EventKitCalendar.store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func eventEditViewController(_ controller: EKEventEditViewController,
                                     didCompleteWith action: EKEventEditViewAction) {
            dismiss()
        }
    }
}
