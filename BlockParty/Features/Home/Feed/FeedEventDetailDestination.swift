//
//  FeedEventDetailDestination.swift
//  Block Party — the single event behind a Town or Your Day card.
//
//  Laid out to the Fresha venue page Jesse picked (`references/fresha-venue-detail.png`,
//  1180 px at 393 pt, 3.0 px a point): a photo carousel under three round buttons, a
//  sheet over its bottom edge with the title, category, when and where, and an About that
//  clamps at four lines. Every size in `Metric` is measured off that screen; the few it
//  could not give are marked guessed. Over it floats Meetup's white capsule with the RSVP
//  words and pill the Town card has (rsvp-and-groups 02, Figma "Meetup depth").
//
//  Town pushes this onto the shell's stack; Your Day shows it as a sheet, where the
//  back arrow becomes a close "x". The system bar stays hidden either way.
//
//  PRODUCT RULE: never render a zero count or a placeholder. Every row below is
//  optional and simply absent when the data is: no description, no About; no
//  category (or `.other`), no grey line; no place, no pill; no photo, no hero.
//

import SwiftUI

struct FeedEventDetailDestination: View {
    let item: FeedCardItem
    /// Shown as a sheet (Your Day) rather than pushed: the back arrow is a close "x".
    let inSheet: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Going and Save, shared with the card behind the page (`RealLifeActions`).
    @Environment(RealLifeActions.self) private var actions
    /// `actions.saveFailureCount` when the bookmark was last tapped: equal means a tap since the
    /// last failed turn back, so its shake stops (as the RSVP pill's, `RSVPArea`).
    @State private var saveTappedAt = 0
    /// The bookmark tapped with no account yet opens sign in (Jesse, 2026-10-12).
    @State private var signInShown = false
    @State private var photoPage: Int? = 0
    /// Photos whose bitmaps are on screen. Until then a page shows the skeleton,
    /// and a photo's credit waits for its photo.
    @State private var shownPhotos: Set<URL> = []
    /// Photos that could not be loaded. They leave the carousel, so a failure never
    /// holds a skeleton on screen.
    @State private var failedPhotos: Set<URL> = []
    /// The Event's place's name in its own lettering, once read (follows 02).
    @State private var placeName: PlaceName?

    init(item: FeedCardItem, inSheet: Bool = false) {
        self.item = item
        self.inSheet = inSheet
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
        static let categoryTop: CGFloat = 8
        static let whenTop: CGFloat = 14
        static let pillTop: CGFloat = 17.3
        static let aboutTop: CGFloat = 33
        static let clockGap: CGFloat = 4.5
        static let pinGap: CGFloat = 8
        /// Paper under the last row, above the RSVP bar (guessed): with the bar's 57 + 1 pt
        /// inset, the last line rests just above the fade.
        static let contentBottom: CGFloat = 24
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                hero
                sheet
            }
        }
        // The photo runs up under the status bar; with no photo the page starts
        // below it like any other.
        .ignoresSafeArea(edges: hasHero ? .top : [])
        .background(Hue.paper.ignoresSafeArea())
        // Outside the scroll, so the buttons stay put while the page moves under them.
        // The sort priority asks VoiceOver to read them first, as they sit, not after the
        // About. AXe's element tree does not show sort priority, so the sim can't prove it.
        .overlay(alignment: .top) {
            topButtons
                .accessibilityElement(children: .contain)
                .accessibilitySortPriority(1)
        }
        .accessibilityElement(children: .contain)
        // Whether the person may act is the module's, not the card's the page was opened
        // with: on first launch the quiet account can arrive while the page is open, and
        // the bar comes up then. An inset, so the page scrolls under the capsule and its last
        // line stops clear of it. Not `.safeAreaBar`: it let iOS recolour the Town bar
        // (2026-09-24); the bar brings its own fade.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let words = actions.rsvp(item, bar: true) {
                rsvpBar(words)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom))
            }
        }
        .animation(Motion.smooth, value: actions.canAct)
        // Hidden, never `navigationBarBackButtonHidden`. Hidden here, UIKit also turns
        // the swipe back off; `SwipeBack` (RootView) turns it back on.
        .toolbar(.hidden, for: .navigationBar)
        .animation(Motion.smooth, value: photos.count)
        .signInSheet(isPresented: $signInShown)
        // A failed Join or Save shakes and buzzes only while its page is open: the buzz
        // used to land on Town after a pop. Leaving never cancels the write itself.
        .onAppear { actions.pageOpened(item.id) }
        .onDisappear { actions.pageClosed(item.id) }
        .task(id: item.id) { placeName = await Self.readPlaceName(item.id) }
    }

    /// `event_place_name`; nothing under DEBUG samples or offline.
    private static func readPlaceName(_ eventID: String) async -> PlaceName? {
        guard RealLifeActions.backend(for: ProcessInfo.processInfo.arguments) == .live,
              UUID(uuidString: eventID) != nil else { return nil }
        return try? await CommunityAPI(auth: AuthStore.shared).eventPlaceName(eventID)
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
                        PlaceNameArt(name: placeName, photo: photos[min(photoPage ?? 0, photos.count - 1)].url,
                                     spoken: item.whereLine ?? "")
                            .padding(.bottom, PlaceNameArt.bottom)
                            .transition(.opacity)
                    }
                }
                // After the stretch, so they stay put at the hero's bottom corners, unscaled.
                .overlay(alignment: .bottomLeading) { credit }
                .overlay(alignment: .bottomTrailing) { counter }
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
                       value: photoValue, onFailure: drop)
        }
    }

    /// The credit shows wherever its photo does (a site, or a free photo's author and
    /// licence), and only once the photo itself is on screen. It names the photo the counter counts, from outside
    /// the carousel like the counter, so the pull-down stretch leaves it in place.
    /// Bottom left, because the counter owns bottom right; its chip edges line up with
    /// the counter's (`PhotoCredit` pads itself `edgeInset`). A tap on it reports the photo
    /// (BP app place-photos 06).
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

    @ViewBuilder
    private var counter: some View {
        if let text = Self.counterText(page: photoPage ?? 0, count: photos.count) {
            PhotoCounter(text: text)
                .padding(.trailing, Metric.inset)
                .padding(.bottom, Metric.counterBottom)
                .transition(.opacity)
        }
    }

    // MARK: Buttons

    private var topButtons: some View {
        HStack(spacing: 0) {
            Self.circleButton(
                glyph: Image(systemName: inSheet ? "xmark" : "arrow.left"),
                label: inSheet ? "Close" : "Back",
                reduceMotion: reduceMotion
            ) { dismiss() }

            Spacer(minLength: 0)

            // The card's share reveal. 15, not the row's 17: the Reference's share
            // mark is 14 x 17 pt.
            Self.circleButton(glyph: Image(systemName: "square.and.arrow.up").font(.sansSemibold(15)), label: "Share",
                              reduceMotion: reduceMotion) {
                ShareCenter.shared.present(.event(item))
            }

            // The app's bookmark, as on the card: saved, the brand yellow exactly
            // (Jesse, 2026-09-24) inside the ink outline, so it reads on the white circle.
            let saved = actions.saved(item)
            let failures = actions.saveFailureCount(item.id)
            Self.circleButton(glyph: BookmarkGlyph(saved: saved), label: saved ? "Saved" : "Save",
                              reduceMotion: reduceMotion, action: toggleSave)
                .turnBackShake(failures: failures, shakes: !reduceMotion && saveTappedAt != failures)
                .accessibilityAddTraits(saved ? .isSelected : [])
        }
        .padding(.horizontal, Metric.inset - (Metric.tapBox - Metric.button) / 2)
        .padding(.top, Metric.buttonTop - (Metric.tapBox - Metric.button) / 2)
    }

    /// A save is a commit, so it gets the light tap (taste.md, from `RealLifeActions`);
    /// the fill springs in. With no account yet, sign in instead.
    private func toggleSave() {
        guard actions.canAct else { signInShown = true; return }
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
        reduceMotion: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            glyph
                .font(.sansSemibold(17))
                .foregroundStyle(Hue.ink)
                .frame(width: Metric.button, height: Metric.button)
                // The shadow on the circle alone: on the whole button it also lands
                // under each glyph and dulled the saved yellow to #F8E404.
                .background { Circle().fill(Hue.surface).mapFloatShadow() }
                .frame(width: Metric.tapBox, height: Metric.tapBox)
                .contentShape(Rectangle())
        }
        .buttonStyle(FeedCardJoinPressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(label)
    }

    // MARK: The sheet

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(item.title)
                .font(.eventDisplay(28))
                .lineSpacing(Metric.titleLineSpacing)
                .foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                // Called off, VoiceOver says so with the title: the bar's red pill comes last.
                .accessibilityValue(item.cancelled ? "Canceled" : "")
                .padding(.top, Metric.titleTop)

            if let category = Self.categoryText(item.category) {
                Text(category)
                    .font(.sans(17))
                    .foregroundStyle(Hue.inkSecondary)
                    .padding(.top, Metric.categoryTop)
            }

            if let when = item.whenLine {
                HStack(spacing: Metric.clockGap) {
                    Image(systemName: "clock")
                        .font(.sans(13))
                    Text(when.text)
                        .font(.sans(17))
                        .monospacedDigit()
                }
                .foregroundStyle(Hue.inkSecondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(when.spoken)
                .padding(.top, Metric.whenTop)
            }

            if let place = Self.placeText(item) {
                // Opens Apple Maps on the venue, the same search Your Day's "Directions" opens.
                InfoPill(glyph: "mappin", text: place, url: DayScheduleLogic.directionsURL(forPlace: place),
                         hint: "Opens in Maps")
                    .padding(.top, Metric.pillTop)
            }

            // Who hosts it, with Follow (follows 02): Eventbrite's "Organized by".
            EventHostRow(item: item, top: Metric.pillTop, placeNamed: placeName?.emblem == false && !photos.isEmpty)

            if let about = Self.aboutText(item.description) {
                AboutSection(text: about)
                    .padding(.top, Metric.aboutTop)
            }
        }
        .padding(.horizontal, Metric.inset)
        .padding(.bottom, Metric.contentBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Hue.paper,
            in: UnevenRoundedRectangle(
                topLeadingRadius: Metric.sheetCorner,
                topTrailingRadius: Metric.sheetCorner,
                style: .continuous
            )
        )
        .padding(.top, hasHero ? 0 : Metric.buttonTop + Metric.button + Metric.noPhotoGap)
    }

    // MARK: The bar

    /// Meetup's capsule floating over the page, with the card's RSVP words and pill
    /// (`RSVPArea`); Invite opens the invite card the top share does. Under it the page fades
    /// to paper, as Meetup's does, so words never run hard into its edge or the home bar.
    private func rsvpBar(_ words: RSVPWords) -> some View {
        RSVPArea(item: item, words: words, size: .page) { ShareCenter.shared.present(.event(item)) }
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
            // the tab bar's way (RootView), since the glass alone darkens over dark content.
            .glassEffect(.regular, in: Capsule())
            .background {
                Capsule()
                    .fill(Hue.surface.opacity(Metric.barWhite))
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, Metric.inset)
            .padding(.bottom, Metric.barBottom)
            .background {
                LinearGradient(colors: [Hue.paper.opacity(0), Hue.paper], startPoint: .top, endPoint: .bottom)
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

    // MARK: Pure rules (EventDetailPageTests)

    /// The hero's photos: the event's own first, then the venue's, the same picture
    /// only once, at most three. Anything that is not a photo yet, or that `failed`
    /// to load, is left out.
    static func photoList(
        event: FeedCardImageSource,
        venue: [FeedCardImageSource],
        failed: Set<URL> = []
    ) -> [FeedCardImageSource] {
        var seen = failed
        var list: [FeedCardImageSource] = []
        for photo in [event] + venue {
            guard list.count < 3, let url = photo.url, seen.insert(url).inserted else { continue }
            list.append(photo)
        }
        return list
    }

    /// "2/3" on the second of three; nil when there is only one photo to show.
    static func counterText(page: Int, count: Int) -> String? {
        count >= 2 ? "\(page + 1)/\(count)" : nil
    }

    static func aboutText(_ description: String?) -> String? {
        nonempty(description)
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
