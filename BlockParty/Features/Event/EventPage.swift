//
//  EventPage.swift
//  Block Party — the Event page: the single event behind a card.
//
//  Laid out to the Fresha venue page Jesse picked (`references/fresha-venue-detail.png`,
//  1180 px at 393 pt, 3.0 px a point): a photo carousel under three round buttons, a
//  sheet over its bottom edge with the title, and an About that clamps at four lines. Every
//  size in `Metric` is measured off that screen; the few it could not give are marked guessed.
//  Under the title, the facts as Meetup's Event page lays them out (event-page-formats 06): a
//  day row, a place row and the host in a grey card, the Interest in grey words under About.
//  Over it floats Meetup's white capsule with the RSVP words and pill the Town card has
//  (rsvp-and-groups 02, Figma "Meetup depth").
//
//  Every list pushes this onto the shell's stack; the system bar stays hidden.
//
//  PRODUCT RULE: never render a zero count or a placeholder. Every row below is
//  optional and simply absent when the data is: no description, no About; no
//  category (or `.other`), no Interest; no place, no place row; no photo, no hero.
//

import EventKitUI
import SwiftUI

struct EventPage: View {
    let item: FeedCardItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    /// Going and Save, shared with the card behind the page (`RealLifeActions`).
    @Environment(RealLifeActions.self) private var actions
    /// Every game's newest score, from whatever tab opened the page (codebase-health-2 08); nil in previews.
    @Environment(LiveGames.self) private var live: LiveGames?
    /// The page's hold on Live games while it's open, its own, so two pages of one Event let go one at a time.
    @State private var liveHolder = "page:" + UUID().uuidString
    /// `actions.saveFailureCount` when the bookmark was last tapped: equal means a tap since the
    /// last failed turn back, so its shake stops (as the RSVP pill's, `RSVPArea`).
    @State private var saveTappedAt = 0
    @State private var photoPage: Int? = 0
    /// Photos whose bitmaps are on screen. Until then a page shows the skeleton,
    /// and a photo's credit waits for its photo.
    @State private var shownPhotos: Set<URL> = []
    /// Photos that could not be loaded. They leave the carousel, so a failure never
    /// holds a skeleton on screen.
    @State private var failedPhotos: Set<URL> = []
    /// How far the hero's pages have been swiped, for the lettering a flyer's page goes without.
    @State private var heroSwipe: CGFloat = 0
    /// The Event's place's name in its own lettering, once read (follows 02).
    @State private var placeName: PlaceName?
    /// Apple's add-to-Calendar sheet, from the day row, with the entry as it was at the tap: one
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

    /// The Going chat's row: not on the map's own stack, which has no chat to push to.
    private let goingChat: Bool

    init(item: FeedCardItem, goingChat: Bool = true) {
        self.item = item
        self.goingChat = goingChat
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
        /// A page name in Inter Tight (profile, group, business): its line is 7 pt taller than the
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
                } else {
                    hero
                }
                sheet
            }
        }
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > Metric.scrolledAfter } action: { _, now in
            scrolled = now
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in
            LeftOff.pageY[item.id] = y
        }
        // The page's height comes in over a few layouts, and a jump past it stops at the top. As far
        // as it can each time, so a page that's shorter now ("Read more" closed) still lands low.
        .onScrollGeometryChange(for: CGFloat.self) {
            $0.contentSize.height + $0.contentInsets.top + $0.contentInsets.bottom - $0.containerSize.height
        } action: { _, room in
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
        // The photo runs up under the status bar; with no photo the page starts
        // below it like any other.
        .ignoresSafeArea(edges: hasHero && game == nil ? .top : [])
        // A game's page is its teams' colors from edge to edge, fixed while the page scrolls over them
        // (game-card 08); the rest are paper.
        .background {
            if let game { GameMatchup.backdrop(game).ignoresSafeArea() } else { Hue.paper.ignoresSafeArea() }
        }
        // Outside the scroll, so the buttons stay put while the page moves under them.
        // The sort priority asks VoiceOver to read them first, as they sit, not after the
        // About. AXe's element tree does not show sort priority, so the sim can't prove it.
        .overlay(alignment: .top) {
            topButtons
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
            if let words = actions.rsvp(current, bar: true) {
                rsvpBar(words)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom))
            }
        }
        .animation(Motion.smooth, value: actions.canAct)
        // Light words on a game's dark, its rows, buttons and bar with them, as a school's page (TeamPage).
        .environment(\.colorScheme, game != nil ? .dark : colorScheme)
        // Hidden, never `navigationBarBackButtonHidden`. Hidden here, UIKit also turns
        // the swipe back off; `SwipeBack` (RootView) turns it back on.
        .toolbar(.hidden, for: .navigationBar)
        .animation(Motion.smooth, value: photos.count)
        // A goal's scorer under the score and its play in the list move the rest of the page down together
        // (game-card 09), rather than the page jumping.
        .animation(reduceMotion ? nil : Motion.smooth, value: game?.plays.count)
        .sheet(isPresented: $calendarShown) {
            if let adding { AddToCalendar(entry: adding) }
        }
        // A failed Join or Save shakes and buzzes only while its page is open: the buzz
        // used to land on Town after a pop. Leaving never cancels the write itself.
        .onAppear {
            actions.pageOpened(item.id)
            live?.hold(liveHolder, [item])
            LeftOff.page = item.id
        }
        .onDisappear {
            if LeftOff.page == item.id { LeftOff.page = nil }
            actions.pageClosed(item.id)
            live?.hold(liveHolder, [])
        }
        .task(id: item.id) { placeName = await Self.readPlaceName(item.id) }
    }

    /// `event_place_name`; nothing under DEBUG samples or offline.
    private static func readPlaceName(_ eventID: String) async -> PlaceName? {
        guard LaunchFlags.backend == .live,
              UUID(uuidString: eventID) != nil else { return nil }
        return try? await CommunityAPI(auth: AuthStore.shared).eventPlaceName(eventID)
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

    // MARK: Photos

    /// The card's photos (`FeedCardItem.photos`): saved by Block Party, so nothing is looked up.
    private var photos: [FeedCardImageSource] {
        item.photos(failed: failedPhotos)
    }

    /// A place we have no photo of fills the hero with its logo on its backdrop, as its
    /// card does (Jesse, 2026-10-16).
    private var heroLogo: SearchLogo? {
        photos.isEmpty ? item.place?.logo : nil
    }

    private var hasHero: Bool { !photos.isEmpty || heroLogo != nil }

    /// The visible hero is exactly 303/393 of the width; the photos draw on
    /// `heroUnderlap` further, under the sheet. Pulling the page down past its top
    /// stretches the hero from its bottom edge. That is a visual effect only, so the
    /// scroll never reads back a size it caused.
    @ViewBuilder
    private var hero: some View {
        if hasHero {
            Color.clear
                .aspectRatio(Metric.heroAspect, contentMode: .fit)
                .overlay(alignment: .top) {
                    GeometryReader { proxy in
                        heroPhotos
                            .frame(width: proxy.size.width, height: proxy.size.height + Metric.heroUnderlap)
                            // Called off: black and white, as on its card, with no tag over it
                            // (Jesse, 2026-10-17).
                            .grayscale(item.cancelled ? 1 : 0)
                    }
                }
                .visualEffect { content, proxy in
                    let pull = max(0, proxy.frame(in: .scrollView(axis: .vertical)).minY)
                    return content.scaleEffect(1 + pull / max(proxy.size.height, 1), anchor: .bottom)
                }
                // The place's name at the bottom centre, over its photos only: with none, the
                // hero is its logo, which says it already.
                .overlay(alignment: .bottom) {
                    if let placeName, !photos.isEmpty {
                        ZStack(alignment: .bottom) {
                            if !placeName.emblem { PlaceNameArt.fade }
                            PlaceNameArt(name: placeName, spoken: item.whereLine ?? "")
                                .padding(.bottom, PlaceNameArt.bottom)
                        }
                        // Over a flyer it would cover the flyer's words (Jesse, 2026-11-05).
                        .opacity(Self.letteringOpacity(flyerFirst: flyer != nil, swipe: heroSwipe))
                        .transition(.opacity)
                    }
                }
                // After the stretch, so it stays put at the hero's bottom corner, unscaled. No counter: the
                // page shows one picture (BP app inside-cards 15).
                .overlay(alignment: .bottomLeading) { credit }
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var heroPhotos: some View {
        if photos.isEmpty {
            // Under the clock and between the round buttons, clear of the sheet (picked: 101 pt
            // down, 150 pt tall on a 420 pt phone).
            if let logo = heroLogo { FeedCardPlaceLogo(logo: logo, topShare: 0.29, sideShare: 0.43) }
        } else {
            PhotoPager(urls: photos.compactMap(\.url), page: $photoPage, shown: $shownPhotos,
                       value: photoValue, onFailure: drop, flyer: flyer, flyerTop: HelloDropView.safeTop,
                       onSwipe: flyer == nil ? nil : { heroSwipe = $0 })
        }
    }

    /// The first photo, when it is a flyer (BP app event-photos 16): one that failed to load has left the list.
    private var flyer: URL? {
        guard item.whole, let url = item.image.url, photos.first?.url == url else { return nil }
        return url
    }

    /// The credit shows wherever its photo does (a site, or a free photo's author and
    /// licence), and only once the photo itself is on screen. It sits outside the carousel, so the pull-down
    /// stretch leaves it in place, bottom left as on a business page (`PhotoCredit` pads itself `edgeInset`).
    /// A tap on it reports the photo (BP app place-photos 06).
    @ViewBuilder
    private var credit: some View {
        if let credit = creditName {
            // With two or more photos the carousel says it, with the photo's number;
            // with one, the carousel is hidden, so the credit speaks for itself.
            PhotoCredit(names: [credit], report: photos[photoPage ?? 0].report(place: item.whereLine),
                        spoken: photos.count < 2)
                .padding(.leading, Metric.inset - PhotoCredit.edgeInset)
                .padding(.bottom, Metric.counterBottom - PhotoCredit.edgeInset)
        }
    }

    /// Whose photo is on screen, once it is: nil before, and for a photo with no credit.
    private var creditName: String? {
        let page = photoPage ?? 0
        guard photos.indices.contains(page), let url = photos[page].url,
              PhotoPager.isShown(url, in: shownPhotos) else { return nil }
        return photos[page].attribution
    }

    /// "Photo 2 of 2, by Ada Lovelace": where VoiceOver is in the carousel, and whose
    /// photo it is.
    private var photoValue: String {
        let page = photoPage ?? 0
        let credit = photos.indices.contains(page) ? photos[page].attribution : nil
        return "Photo \(page + 1) of \(photos.count)" + (credit.map { ", by \($0)" } ?? "")
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

            // The card's share reveal. 15, not the row's 17: the Reference's share
            // mark is 14 x 17 pt.
            Self.circleButton(glyph: Image(systemName: "square.and.arrow.up").font(.sansSemibold(15)), label: "Share",
                              onColor: game != nil) {
                ShareCenter.shared.present(.event(item))
            }

            // The app's bookmark, as on the card: saved, the brand yellow exactly
            // (Jesse, 2026-09-24) inside the ink outline, so it reads on the white circle.
            let saved = actions.saved(item)
            let failures = actions.saveFailureCount(item.id)
            Self.circleButton(glyph: BookmarkGlyph(saved: saved), label: saved ? "Saved" : "Save",
                              onColor: game != nil, action: toggleSave)
                .turnBackShake(failures: failures, shakes: !reduceMotion && saveTappedAt != failures)
                .accessibilityAddTraits(saved ? .isSelected : [])
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

    /// A save is a commit, so it gets the light tap (taste.md, from `RealLifeActions`);
    /// the fill springs in.
    private func toggleSave() {
        saveTappedAt = actions.saveFailureCount(item.id)
        withAnimation(Motion.snappy) { actions.toggleSave(item) }
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
                // under each glyph and dulled the saved yellow to #F8E404. On a game's colors
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

    // MARK: The sheet

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            // A game's score says its title (game-card 08): its plays lead, the facts follow.
            if let game {
                GameScoring(game: game, top: Metric.sectionTop)
            } else {
                Text(item.title)
                    .font(.eventDisplay(28))
                    .lineSpacing(Metric.titleLineSpacing)
                    .foregroundStyle(Hue.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    // Called off, VoiceOver says so with the title: the bar's red pill comes last.
                    .accessibilityValue(item.cancelled ? "Canceled" : "")
                    .padding(.top, Metric.titleTop)
            }

            facts
                .padding(.top, game == nil ? 0 : Metric.sectionTop - Metric.rowsTop)

            // Who hosts it, with Follow (follows 02), in Meetup's grey card.
            EventHostRow(item: item, top: Metric.hostTop, placeNamed: placeName?.emblem == false && !photos.isEmpty && flyer == nil)

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
        .background(
            game == nil ? Hue.paper : .clear,
            in: UnevenRoundedRectangle(
                topLeadingRadius: Metric.sheetCorner,
                topTrailingRadius: Metric.sheetCorner,
                style: .continuous
            )
        )
        .padding(.top, hasHero || game != nil ? 0 : Metric.buttonTop + Metric.button + Metric.noPhotoGap)
    }

    // MARK: The facts (event-page-formats 06)

    /// The day and the place under the title, each its own row with Apple's glyph, as Meetup's
    /// Event page lays them out: the day adds it to the phone's calendar, the place opens Maps.
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

    /// Meetup's capsule floating over the page, with the card's RSVP words and pill
    /// (`RSVPArea`); Invite opens the invite card the top share does. Under it the page fades
    /// to paper, as Meetup's does, so words never run hard into its edge or the home bar.
    private func rsvpBar(_ words: RSVPWords) -> some View {
        RSVPArea(item: current, words: words, size: .page, yellow: game != nil, tint: game.flatMap { GameMatchup.attend($0) }) {
            ShareCenter.shared.present(.event(item))
        }
            .padding(.leading, Metric.barWordsInset)
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
                // A game's page fades to its own near-black (game-card 08).
                let ground = game == nil ? Hue.paper : Hue.gameNight
                LinearGradient(colors: [ground.opacity(0), ground], startPoint: .top, endPoint: .bottom)
                    .padding(.top, -Metric.fadeAboveBar)
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)
            }
    }

    /// Takes a photo that failed out of the carousel and keeps the page in range.
    private func drop(_ url: URL) {
        failedPhotos.insert(url)
        photoPage = min(photoPage ?? 0, max(photos.count - 1, 0))
    }

    // MARK: Pure rules (EventPageTests)

    /// The hero's picture: the event's own, else the venue's first photo, alone, so the page doesn't
    /// swipe (Jesse, 2026-11-06, BP app inside-cards 15). Anything that is not a photo yet, or that
    /// `failed` to load, is skipped, so the next one takes its place. `most` is 2 only for a UI test.
    static func photoList(
        event: FeedCardImageSource,
        venue: [FeedCardImageSource],
        failed: Set<URL> = [],
        most: Int = 1
    ) -> [FeedCardImageSource] {
        var seen = failed
        var list: [FeedCardImageSource] = []
        for photo in [event] + venue {
            guard list.count < most, let url = photo.url, seen.insert(url).inserted else { continue }
            list.append(photo)
        }
        return list
    }

    /// The place's lettering: gone on a flyer's page, back with the finger as it swipes to the next photo.
    static func letteringOpacity(flyerFirst: Bool, swipe: CGFloat) -> Double {
        flyerFirst ? Double(min(max(swipe, 0), 1)) : 1
    }

    /// "2/3" on the second of three; nil when there is only one photo to show.
    static func counterText(page: Int, count: Int) -> String? {
        count >= 2 ? "\(page + 1)/\(count)" : nil
    }

    static func aboutText(_ description: String?) -> String? {
        nonempty(description)
    }

    /// The found page as the Business page draws a link: "Facebook", "Instagram", else the site's name.
    static func sourceLink(_ url: URL?) -> BusinessPage.LinkRow? {
        guard let url, let host = url.host()?.lowercased() else { return nil }
        let kind = host.hasSuffix("facebook.com") ? "facebook" : host.hasSuffix("instagram.com") ? "instagram" : "website"
        return BusinessPage.rows([PlaceLink(kind: kind, url: url.absoluteString)]).first
    }

    /// A fact's two lines, as its row prints them and as VoiceOver reads them.
    struct FactLines: Equatable {
        let first: String
        var second: String? = nil

        var spoken: String {
            [first, second?.replacingOccurrences(of: " – ", with: " to ")].compactMap { $0 }.joined(separator: ", ")
        }
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

    private static func dayAndHours(_ item: FeedCardItem, now: Date) -> FactLines? {
        guard let when = item.when else { return item.whenLine.map { FactLines(first: $0.text) } }
        let withYear = abs(Town.days(from: now, to: when.start)) > 183
        let day = { (date: Date) in Town.format(date, withYear ? "EEEEMMMMdyyyy" : "EEEEMMMMd") }
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
        init(dismiss: DismissAction) { self.dismiss = dismiss }

        func eventEditViewController(_ controller: EKEventEditViewController,
                                     didCompleteWith action: EKEventEditViewAction) {
            dismiss()
        }
    }
}
