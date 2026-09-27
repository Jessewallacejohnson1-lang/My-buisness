//
//  FeedEventDetailDestination.swift
//  Block Party — the single event behind a Town or Your Day card.
//
//  Laid out to the Fresha venue page Jesse picked (`references/fresha-venue-detail.png`,
//  1180 px at 393 pt, 3.0 px a point): a photo carousel under three round buttons, a
//  sheet over its bottom edge with the title, category, when and where, an About that
//  clamps at four lines, and a bar along the bottom with the going count and Join.
//  Every size in `Metric` is measured off that screen; the few it could not give are
//  marked guessed.
//
//  Town pushes this onto the shell's stack; Your Day shows it as a sheet, where the
//  back arrow becomes a close "x". The system bar stays hidden either way.
//
//  PRODUCT RULE: never render a zero count or a placeholder. Every row below is
//  optional and simply absent when the data is: no description, no About; no
//  category (or `.other`), no grey line; no place, no pill; no photo, no hero.
//

import Combine
import SwiftUI

struct FeedEventDetailDestination: View {
    let item: FeedCardItem
    /// Shown as a sheet (Your Day) rather than pushed: the back arrow is a close "x".
    let inSheet: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model: FeedEventDetailModel
    /// Saves stay on the device, in the list the card's bookmark reads too, so the
    /// two always agree.
    @ObservedObject private var saves = SavedStore.shared
    /// The venue's photo, once `FeedCardVenuePhoto` has looked it up.
    @State private var venuePhoto: FeedCardImageSource?
    /// True until that lookup answers. Starts false when there is nothing to look up.
    @State private var venuePending: Bool
    @State private var photoPage: Int? = 0
    /// Photos whose bitmaps are on screen. Until then a page shows the skeleton,
    /// and a Google photo's credit waits for its photo.
    @State private var shownPhotos: Set<URL> = []
    /// Photos that could not be loaded. They leave the carousel, so a failure never
    /// holds a skeleton on screen.
    @State private var failedPhotos: Set<URL> = []
    @State private var aboutExpanded = false
    /// The About's height in full and at four lines, so "Read more" shows only when
    /// the clamp actually cuts something.
    @State private var aboutFullHeight: CGFloat = 0
    @State private var aboutClampedHeight: CGFloat = 0
    /// `model.failedRollbacks` when Join was last tapped. Equal means the neighbour has
    /// tapped since the last failed turn back, so its shake stops.
    @State private var joinTappedAt = 0

    init(item: FeedCardItem, inSheet: Bool = false, auth: AuthStore? = nil) {
        self.item = item
        self.inSheet = inSheet
        _model = StateObject(wrappedValue: FeedEventDetailModel(item: item, auth: auth))
        _venuePending = State(initialValue: Self.venueQuery(for: item) != nil)
    }

    /// Sizes off the Reference, in points. Measured 2026-09-26 on the original PNG.
    private enum Metric {
        /// Screen top to the sheet's edge: 303 of 393 pt. Other widths keep the
        /// ratio, so 324 pt on a 420 pt phone (guessed).
        static let heroAspect: CGFloat = 393.0 / 303.0
        /// The sheet's top corners: a circle fitted to the Reference's corner
        /// measures 72 px, 24 pt. No token is 24 (`card` 20, `bento` 22).
        static let sheetCorner: CGFloat = 24
        /// How far the photo runs on under the sheet: the corner, so no paper
        /// shows through the curve (guessed).
        static let heroUnderlap: CGFloat = sheetCorner
        /// Content, buttons, counter, pill and Join all sit 20 pt in from the edge.
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
        /// The About clamps at four lines.
        static let aboutLines = 4
        /// The bottom bar: 16 pt above and below a 111 x 48 pt Join.
        static let barPadding: CGFloat = 16
        static let joinSize = CGSize(width: 111, height: 48)

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
        static let bodyTop: CGFloat = 12.7
        static let clockGap: CGFloat = 4.5
        static let pinGap: CGFloat = 8
        /// Paper under the last row, above the bottom bar (guessed).
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
        .overlay(alignment: .top) { topButtons }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        // Hidden, never `navigationBarBackButtonHidden`. Hidden here, UIKit also turns
        // the swipe back off; `SwipeBack` (RootView) turns it back on.
        .toolbar(.hidden, for: .navigationBar)
        .animation(Motion.smooth, value: photos.count)
        .animation(Motion.smooth, value: venuePending)
        .task { await resolveVenuePhoto() }
        .onDisappear { model.pageClosed() }
    }

    // MARK: Photos

    private var photos: [FeedCardImageSource] {
        Self.photoList(event: item.image, venue: venuePhoto.map { [$0] } ?? [], failed: failedPhotos)
    }

    private var hasHero: Bool { !photos.isEmpty || venuePending }

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
                    }
                }
                .visualEffect { content, proxy in
                    let pull = max(0, proxy.frame(in: .scrollView(axis: .vertical)).minY)
                    return content.scaleEffect(1 + pull / max(proxy.size.height, 1), anchor: .bottom)
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
            // Only while the venue lookup is out. If it finds nothing, the hero goes.
            SkeletonBlock(cornerRadius: 0)
                .shimmering()
                .accessibilityLabel("Loading photo")
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                        heroPhoto(photo)
                            .containerRelativeFrame(.horizontal)
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $photoPage)
            .scrollDisabled(photos.count < 2)
            // For VoiceOver the carousel is one adjustable element: swipe up or down
            // for the next or previous photo. One photo has nothing to adjust.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Photos")
            .accessibilityValue(photoValue)
            .accessibilityAdjustableAction { direction in
                let page = photoPage ?? 0
                let next = direction == .increment ? page + 1 : page - 1
                guard photos.indices.contains(next) else { return }
                withAnimation(Motion.smooth) { photoPage = next }
            }
            .accessibilityHidden(photos.count < 2)
        }
    }

    @ViewBuilder
    private func heroPhoto(_ photo: FeedCardImageSource) -> some View {
        if let url = Self.url(of: photo) {
            let shown = isShown(url)
            FeedCardURLPhoto(url: url, onReady: { shownPhotos.insert(url) }, onFailure: { drop(url) })
                .frame(maxHeight: .infinity)
                .clipped()
                .overlay {
                    if !shown {
                        SkeletonBlock(cornerRadius: 0)
                            .shimmering()
                            .transition(.opacity)
                    }
                }
                .animation(Motion.smooth, value: shown)
                .accessibilityHidden(true)
        }
    }

    /// Drawn already (by its card, at another size) counts as shown: no skeleton.
    private func isShown(_ url: URL) -> Bool {
        shownPhotos.contains(url) || FeedCardImageLoader.shared.largest(for: url) != nil
    }

    /// Google's terms: the credit shows wherever its photo does, and only once the
    /// photo itself is on screen. It names the photo the counter counts, from outside
    /// the carousel like the counter, so the pull-down stretch leaves it in place.
    /// Bottom left, because the counter owns bottom right; its chip edges line up with
    /// the counter's (`PhotoCredit` pads itself 9 pt).
    @ViewBuilder
    private var credit: some View {
        let page = photoPage ?? 0
        if photos.indices.contains(page), let url = Self.url(of: photos[page]), isShown(url),
           let credit = photos[page].attribution {
            PhotoCredit(names: [credit])
                .padding(.leading, Metric.inset - 9)
                .padding(.bottom, Metric.counterBottom - 9)
                // The carousel says it, with the photo's number.
                .accessibilityHidden(true)
        }
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
            // 13: the Reference's digits stand 9 pt tall.
            Text(text)
                .font(.sansSemibold(13))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(minWidth: Metric.counterSize.width, minHeight: Metric.counterSize.height)
                // The Reference's chip is ink at about 55% over a light photo.
                // Black rather than `Hue.ink` so it stays dark in the dark ramp,
                // like `PhotoCredit`.
                .background(.black.opacity(0.55), in: Capsule())
                .padding(.trailing, Metric.inset)
                .padding(.bottom, Metric.counterBottom)
                // The carousel says it, with the credit.
                .accessibilityHidden(true)
                .transition(.opacity)
        }
    }

    // MARK: Buttons

    private var topButtons: some View {
        HStack(spacing: 0) {
            circleButton(
                glyph: Image(systemName: inSheet ? "xmark" : "arrow.left"),
                label: inSheet ? "Close" : "Back"
            ) { dismiss() }

            Spacer(minLength: 0)

            // The card's share reveal. 15, not the row's 17: the Reference's share
            // mark is 14 x 17 pt.
            circleButton(glyph: Image(systemName: "square.and.arrow.up").font(.sansSemibold(15)), label: "Share") {
                DailyFeedColumn.share(item)
            }

            // The app's bookmark, as on the card: saved, the brand yellow exactly
            // (Jesse, 2026-09-24) inside the ink outline, so it reads on the white circle.
            circleButton(glyph: BookmarkGlyph(saved: isSaved), label: isSaved ? "Saved" : "Save", action: toggleSave)
                .accessibilityAddTraits(isSaved ? .isSelected : [])
        }
        .padding(.horizontal, Metric.inset - (Metric.tapBox - Metric.button) / 2)
        .padding(.top, Metric.buttonTop - (Metric.tapBox - Metric.button) / 2)
    }

    private var isSaved: Bool { saves.isSaved(item.id) }

    /// A save is a commit, so it gets the light tap (taste.md); the fill springs in.
    private func toggleSave() {
        Haptics.light()
        withAnimation(Motion.snappy) { saves.toggle(item.id) }
    }

    /// A white circle with an ink glyph, lifted by the map's floating-button shadow
    /// (guessed; the Reference's heart is solid white). Not Liquid Glass: glass takes
    /// its colour from what is under it and went dark with white glyphs over a dark
    /// photo, even with the scheme pinned (measured 2026-09-26), and chrome never takes
    /// its colour from what is under it (taste.md).
    private func circleButton(
        glyph: some View,
        label: String,
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
        .buttonStyle(FeedCardJoinPressStyle(reduceMotion: reduceMotion, autoplayPressed: false))
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
                locationPill(place)
                    .padding(.top, Metric.pillTop)
            }

            if let about = Self.aboutText(item.description) {
                aboutSection(about)
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

    /// Opens Apple Maps on the venue, the same search Your Day's "Directions" opens.
    private func locationPill(_ place: String) -> some View {
        Button {
            if let url = DayScheduleLogic.directionsURL(forPlace: place) { openURL(url) }
        } label: {
            HStack(spacing: Metric.pinGap) {
                // SF Symbols has no filled teardrop like the Reference's; this is its pin.
                Image(systemName: "mappin")
                    .frame(width: Metric.pinBox)
                Text(place)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.sans(15))
            .foregroundStyle(Hue.ink)
            .padding(.horizontal, Metric.pillInset)
            .frame(height: Metric.pillHeight)
            .background(Hue.fill, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(FeedCardPressStyle())
        .accessibilityLabel(place)
        .accessibilityHint("Opens in Maps")
    }

    private func aboutSection(_ about: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("About")
                .font(.sansBold(20))
                .foregroundStyle(Hue.ink)
                .accessibilityAddTraits(.isHeader)

            // The text itself switches at once; only the box around it moves. Letting the
            // text animate cross-faded the two layouts, and a "lem" fragment floated at the
            // old place while it collapsed (independent review). Opening, the box uncovers
            // the lines; closing, it shuts over the space they leave.
            Text(about)
                .font(.sans(17))
                .foregroundStyle(Hue.ink)
                .lineLimit(aboutExpanded ? nil : Metric.aboutLines)
                .animation(nil, value: aboutExpanded)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { aboutProbe(about) }
                .frame(height: aboutBoxHeight, alignment: .top)
                .clipped()
                .padding(.top, Metric.bodyTop)

            // Its own line, in ink, and only when four lines really cut the text.
            if aboutFullHeight > aboutClampedHeight + 1 {
                Button {
                    withAnimation(Motion.smooth) { aboutExpanded.toggle() }
                } label: {
                    Text(aboutExpanded ? "Show less" : "Read more")
                        .font(.sansSemibold(17))
                        .foregroundStyle(Hue.ink)
                        .animation(nil, value: aboutExpanded)
                        // A 44 pt target on a 22 pt line.
                        .contentShape(Rectangle().inset(by: -11))
                }
                .buttonStyle(FeedCardJoinPressStyle(reduceMotion: reduceMotion, autoplayPressed: false))
            }
        }
    }

    /// The About's box: the full text's height open, four lines' shut. nil until the
    /// probe has measured, so the first frame lays out naturally.
    private var aboutBoxHeight: CGFloat? {
        guard aboutFullHeight > 0 else { return nil }
        return aboutExpanded ? aboutFullHeight : aboutClampedHeight
    }

    /// The About set twice out of sight, in full and at four lines, to learn whether
    /// the clamp cuts it. Text measuring text: nothing here reads the scroll.
    private func aboutProbe(_ about: String) -> some View {
        ZStack(alignment: .top) {
            Text(about)
                .font(.sans(17))
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { aboutFullHeight = $0 }
            Text(about)
                .font(.sans(17))
                .lineLimit(Metric.aboutLines)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { aboutClampedHeight = $0 }
        }
        .hidden()
        .accessibilityHidden(true)
    }

    // MARK: The bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            // `goingLabel` is nil at zero: never "0 going".
            if let going = YourDayLogic.goingLabel(for: model.goingCount) {
                Text(going)
                    .font(.sans(17))
                    .monospacedDigit()
                    .foregroundStyle(Hue.inkSecondary)
                    .contentTransition(.numericText())
                    .transition(.opacity)
            }

            Spacer(minLength: 0)

            // Optimistic: it answers at once, and a write that fails turns it back
            // (`FeedEventDetailModel`), with a shake.
            Button {
                joinTappedAt = model.failedRollbacks
                model.toggleGoing()
            } label: { joinFace }
                .buttonStyle(FeedCardJoinPressStyle(reduceMotion: reduceMotion, autoplayPressed: false))
                .keyframeAnimator(initialValue: CGFloat.zero, trigger: model.failedRollbacks) { [joinShakes] button, x in
                    button.offset(x: joinShakes ? x : 0)
                } keyframes: { _ in
                    // Out 6 pt, back past centre, dying away: 0.32 s. The app has no
                    // shake to copy, so every number here is guessed.
                    KeyframeTrack {
                        CubicKeyframe(6, duration: 0.06)
                        CubicKeyframe(-5, duration: 0.08)
                        CubicKeyframe(3, duration: 0.07)
                        CubicKeyframe(-1.5, duration: 0.06)
                        CubicKeyframe(0, duration: 0.05)
                    }
                }
                .accessibilityLabel(model.isGoing ? "Going" : "Join")
                .accessibilityAddTraits(model.isGoing ? .isSelected : [])
        }
        .animation(joinMorph, value: model.isGoing)
        .animation(joinMorph, value: model.goingCount)
        .padding(.horizontal, Metric.inset)
        .padding(.vertical, Metric.barPadding)
        .background(Hue.paper.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Hue.hairline)
                .frame(height: 1)
        }
    }

    /// Join is the Reference's black capsule. Going inverts it the way the card's join
    /// button inverts when joined: a white face, a hairline edge and an ink check. The
    /// Reference has no Going state, so this look is guessed.
    private var joinFace: some View {
        // A ZStack, not a Group: a Group hands the capsule below to each branch, so the
        // morph drew two capsules, and the one fading out stayed put while the shake
        // moved the other (the eyes pass, 2026-09-27). One capsule; only the words swap.
        ZStack {
            if model.isGoing {
                Label("Going", systemImage: "checkmark")
                    .labelStyle(.titleAndIcon)
            } else {
                Text("Join")
            }
        }
        .font(.sansSemibold(17))
        .foregroundStyle(model.isGoing ? Hue.ink : Hue.surface)
        .frame(width: Metric.joinSize.width, height: Metric.joinSize.height)
        .background {
            Capsule()
                .fill(model.isGoing ? Hue.surface : Hue.ink)
                .overlay { Capsule().strokeBorder(model.isGoing ? Hue.hairline : .clear, lineWidth: 1) }
        }
    }

    /// Whether the last failed turn back may still shake Join. Reduce Motion: never
    /// (the error buzz still comes, from the model). A tap since then: no, so a tap
    /// mid-shake stops it and acts at once.
    private var joinShakes: Bool {
        !reduceMotion && joinTappedAt != model.failedRollbacks
    }

    /// The card's join morph (`FeedEventCardJoinButton`), both ways, rollback included.
    private var joinMorph: Animation {
        .easeInOut(duration: reduceMotion ? 0.15 : FeedEventDetailModel.flip)
    }

    /// Takes a photo that failed out of the carousel and keeps the page in range.
    private func drop(_ url: URL) {
        failedPhotos.insert(url)
        photoPage = min(photoPage ?? 0, max(photos.count - 1, 0))
    }

    // MARK: Venue lookup

    private func resolveVenuePhoto() async {
        #if DEBUG
        // UI tests only: a second bundled photo in place of Google's, so the carousel
        // is there to swipe over with no network (`EventCardPhotoTapTests`).
        if ProcessInfo.processInfo.arguments.contains("-event-page-two-photos"),
           let url = Bundle.main.url(forResource: "centennial-park", withExtension: "jpg") {
            venuePhoto = .eventPhoto(url)
            venuePending = false
            return
        }
        #endif
        guard let query = Self.venueQuery(for: item) else { return }
        let resolved = await FeedCardVenuePhoto.resolve(name: query.name, hint: query.hint)
        guard !Task.isCancelled else { return }
        venuePhoto = resolved
        venuePending = false
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
            guard list.count < 3, let url = Self.url(of: photo), seen.insert(url).inserted else { continue }
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

    private static func url(of photo: FeedCardImageSource) -> URL? {
        switch photo {
        case .eventPhoto(let url), .placesPhoto(let url, _): url
        case .venueLookup, .fallback: nil
        }
    }

    /// The venue to ask Google about: a card's pending lookup, or the where line with
    /// the title as a hint. nil when `KnownVenues` has no anchor for it, the gate
    /// `confidentPhoto(forFreeText:hint:)` applies first, so the page knows up front
    /// that there is nothing to wait for and never flashes a skeleton.
    private static func venueQuery(for item: FeedCardItem) -> (name: String, hint: String?)? {
        let query: (name: String, hint: String?)
        if case .venueLookup(let name, let hint) = item.image {
            query = (name, hint)
        } else if let place = placeText(item) {
            query = (place, item.title)
        } else {
            return nil
        }
        guard KnownVenues.anchor(location: query.name, named: query.hint ?? query.name) != nil
        else { return nil }
        return query
    }
}

/// Optimistic RSVP with rollback, matching how `BriefingModel` treats a vote: the
/// control answers instantly and only reverts if the write actually fails.
@MainActor
final class FeedEventDetailModel: ObservableObject {
    @Published private(set) var isGoing: Bool
    @Published private(set) var goingCount: Int
    /// One more each time a failed write turns the button back by itself, once "Join"
    /// has landed (`flip` after the turn); the page shakes the button on it. A tap that
    /// turns it back sooner is not counted: that neighbour asked for the state they get.
    @Published private(set) var failedRollbacks = 0

    /// A failed Join still shows "Going" this long after the tap before it turns back,
    /// so the rollback reads as the app's answer, not a flicker. Signed out, the write
    /// failed 15 ms after the tap (measured 2026-09-26), about one frame. (guessed)
    static let rollbackFloor: Duration = .milliseconds(600)

    /// How long Join takes to turn from one face to the other, both ways: the card's
    /// join morph (`FeedEventCardJoinButton`), in seconds.
    static let flip: TimeInterval = 0.18

    let organizerImageURL: URL?

    private let eventID: String
    private let auth: AuthStore
    private var inFlight: Task<Void, Never>?
    /// False once the page has gone (`pageClosed`).
    private var pageOpen = true
    /// Where a failed write goes back to, while it waits out `rollbackFloor`.
    private var failedFrom: (isGoing: Bool, count: Int)?

    init(item: FeedCardItem, auth: AuthStore? = nil) {
        self.eventID = item.id
        self.auth = auth ?? .shared
        self.isGoing = item.isJoined
        self.goingCount = item.goingCount
        if case .eventPhoto(let url) = item.image {
            self.organizerImageURL = url
        } else {
            self.organizerImageURL = nil
        }
    }

    func toggleGoing() {
        Haptics.light()
        inFlight?.cancel()
        // The write already failed and is only waiting to turn back: turn back now,
        // rather than toggling a state the server never had.
        if let failedFrom {
            rollBack(to: failedFrom)
            return
        }

        let wasGoing = isGoing
        let previousCount = goingCount
        let tapped = ContinuousClock.now

        isGoing = !wasGoing
        goingCount = max(0, previousCount + (wasGoing ? -1 : 1))

        inFlight = Task { [eventID, auth] in
            do {
                let api = CommunityAPI(auth: auth)
                if wasGoing {
                    try await api.unRsvpEvent(eventID)
                } else {
                    try await api.rsvpEvent(eventID)
                }
            } catch {
                guard !Task.isCancelled else { return }
                Log.network("event rsvp toggle failed: \(error.localizedDescription)")
                failedFrom = (wasGoing, previousCount)
                try? await Task.sleep(until: tapped + Self.rollbackFloor)
                guard !Task.isCancelled, pageOpen else { return }
                rollBack(to: (wasGoing, previousCount))
                // Join first, then the shake: it waits for the face to finish turning, so
                // it never shakes the two labels mid cross-fade (Jesse, 2026-09-27). A tap
                // before then cancels it.
                try? await Task.sleep(for: .seconds(Self.flip))
                guard !Task.isCancelled, pageOpen else { return }
                failedRollbacks += 1
                // Here, not in the view: Reduce Motion drops the shake, never the buzz.
                Haptics.error()
            }
        }
    }

    /// The page has gone, so a failed Join no longer turns back, shakes or buzzes: the
    /// buzz used to land on Town after a pop. The write itself runs on, so a real RSVP
    /// still in flight is never cancelled by leaving the page.
    func pageClosed() {
        pageOpen = false
    }

    private func rollBack(to state: (isGoing: Bool, count: Int)) {
        failedFrom = nil
        isGoing = state.isGoing
        goingCount = state.count
    }
}
