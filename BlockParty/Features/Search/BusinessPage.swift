//
//  BusinessPage.swift
//  Block Party — a business opened from its logo in Search. Its backdrop grows out of
//  the tile, the logo flies to the middle, and its page rises: laid out like a person's Profile
//  (Jesse, 2026-11-19, BP app place-pages 08): the photos Block Party saved of it swiping as the
//  cover, its own lettering see-through low on it, its whole logo on a white disc in the middle of
//  the sheet's edge, its name, what it is, Follow and Map under it, then its hours, Events, street,
//  own words and links. With no photo there is no cover: the logo sits at the top of the plain page.
//  Back, or a drag down on the band under the clock, sends it home the way it came. Opened from a
//  photo (a card, an Around town tile), the photo itself grows into the page's top photo instead,
//  the page riding its foot (BP app place-photos 10).
//
//  Everything runs off one progress value (0 closed, 1 open), stepped by a spring that
//  always starts from where it is, so the page can stop and turn around anywhere and a
//  finger can take it over mid-flight. The values are the mockup's (Jesse's Search
//  mockup v7, 2026-10-02). Not Apple's zoom transition: that grows the whole page out
//  of the tile at once, and can't fly the logo to its corner on its own path.
//

import SwiftUI
import UIKit

/// The mockup's spring: response and damping ratio, Apple's two knobs, stepped every
/// frame from the live value and velocity. SwiftUI's own animations can't hand back
/// their live value, which a drag that grabs the page mid-flight has to start from.
@MainActor @Observable
final class LiveSpring: NSObject {
    private(set) var value: CGFloat
    @ObservationIgnored private var velocity: CGFloat = 0
    @ObservationIgnored private var target: CGFloat
    @ObservationIgnored private var response: CGFloat = 0.5
    @ObservationIgnored private var damping: CGFloat = 1
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var last: CFTimeInterval = 0
    @ObservationIgnored private var done: (() -> Void)?

    init(_ value: CGFloat) {
        self.value = value
        target = value
    }

    /// Puts it somewhere at once: a finger dragging it, or Reduce Motion.
    func set(_ value: CGFloat) {
        stop()
        self.value = value
        target = value
        velocity = 0
    }

    /// Springs to `target` from the live value. A new call turns it around mid-flight,
    /// keeping its speed; `completion` runs only if it comes to rest at this target.
    func animate(to target: CGFloat, response: CGFloat, damping: CGFloat, velocity: CGFloat? = nil,
                 instant: Bool = false, completion: (() -> Void)? = nil) {
        self.target = target
        self.response = response
        self.damping = damping
        if let velocity { self.velocity = velocity }
        done = completion
        if instant {
            set(target)
            finish()
            return
        }
        guard link == nil else { return }
        last = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        advance(by: link.timestamp - last)
        last = link.timestamp
    }

    /// One frame of the spring, in four steps. Long frames are cut to 34 ms, so a
    /// hitch never throws it.
    func advance(by seconds: CFTimeInterval) {
        let k = pow(2 * .pi / response, 2), c = 4 * .pi * damping / response
        let dt = min(0.034, max(0, seconds)) / 4
        var x = value
        for _ in 0..<4 {
            velocity += (-k * (x - target) - c * velocity) * dt
            x += velocity * dt
        }
        if abs(x - target) < 0.0005 && abs(velocity) < 0.005 {
            value = target
            velocity = 0
            stop()
            finish()
        } else {
            value = x
        }
    }

    private func finish() {
        let done = self.done
        self.done = nil
        done?()
    }

    private func stop() {
        link?.invalidate()
        link = nil
    }
}

/// Which business is open, where its logo came from, and how far open it is.
@MainActor @Observable
final class BusinessOpener {
    struct Source {
        /// The logo's square on screen, and the box the backdrop grows out of.
        var logo: CGRect
        var box: CGRect
        /// The box's corner. 0 means it came from a logo with no tile of its own (the
        /// wall, a result row): there the backdrop fades in instead of growing out.
        var radius: CGFloat
        var shadow: Color
        /// Opened from a photo (a card, an Around town tile): that photo grows out of `box` into the
        /// page's top photo and the page comes with it, with no backdrop growing and nothing rising
        /// from below (BP app place-photos 10). Nil opens from a logo.
        var photo: URL? = nil
        /// Opened from a round photo (a Following row), where the logo isn't on screen: the backdrop
        /// fades in over it and the logo fades in as it flies.
        var fades = false

        /// From a tile on Search: its photo grows when the tile shows it; a tile showing the logo instead
        /// (no photo saved, or it failed or hasn't landed) flies the logo out of its middle, as before.
        static func tile(_ item: SearchItem, box: CGRect, radius: CGFloat) -> Source {
            if let cover = item.cover, FeedCardImageLoader.shared.largest(for: cover) != nil {
                return Source(logo: box, box: box, radius: radius, shadow: item.markShadow, photo: cover)
            }
            let side = SearchMetric.logoOnTile
            return Source(logo: CGRect(x: box.midX - side / 2, y: box.midY - side / 2, width: side, height: side),
                          box: box, radius: radius, shadow: item.markShadow, fades: true)
        }
    }

    private(set) var item: SearchItem?
    private(set) var source: Source?
    /// Where it is headed: open, or home.
    private(set) var isOpen = false
    let progress = LiveSpring(0)
    @ObservationIgnored var reduceMotion = false

    func open(_ item: SearchItem, from source: Source) {
        self.item = item
        self.source = source
        // Opened from anywhere: the Town feed's next round of places puts it last (town-feed 23).
        OpenedPlaces.add(item.placeID)
        isOpen = true
        progress.animate(to: 1, response: SearchMetric.openResponse, damping: SearchMetric.openDamping, instant: reduceMotion)
    }

    /// Home, from wherever it is. `velocity` is the finger's, in progress per second.
    func close(velocity: CGFloat? = nil) {
        guard item != nil else { return }
        isOpen = false
        progress.animate(to: 0, response: SearchMetric.closeResponse, damping: 1, velocity: velocity,
                         instant: reduceMotion) { [weak self] in
            guard let self, !self.isOpen else { return }
            item = nil
            source = nil
        }
    }

    /// A drag let go short of closing: back open, carrying the finger's speed.
    func settleOpen(velocity: CGFloat) {
        isOpen = true
        progress.animate(to: 1, response: SearchMetric.settleResponse, damping: SearchMetric.settleDamping,
                         velocity: velocity, instant: reduceMotion)
    }

    /// Hides the logo it flew from while it is away, so there is only ever one.
    func isAway(_ item: SearchItem) -> Bool { self.item?.id == item.id }

    /// The same, for a tile whose photo grew: only the tile it grew from, when the place shows twice on
    /// Search (the open-now row and Around town).
    func isAway(_ item: SearchItem, from box: CGRect) -> Bool { isAway(item) && source?.box == box }
}

/// The open business, over the whole screen. Draws nothing while nothing is open.
struct BusinessPage: View {
    @Environment(BusinessOpener.self) private var opener

    var body: some View {
        if let item = opener.item, let source = opener.source {
            BusinessPageBody(item: item, source: source, opener: opener)
                .timesOpen("place")
                // A new business starts on its first photo, at the top.
                .id(item.id)
        }
    }

    /// A row under the page's About: the glyph, its words, what it opens.
    struct LinkRow: Hashable {
        let glyph: String
        let text: String
        let url: URL
    }

    /// The links a page draws, website first, then Facebook, then Instagram, one of each: a
    /// website by its name without "www." ("krewemn.com"), a social page by the app's. A kind it
    /// doesn't know, or an address that isn't a web page, is left out.
    static func rows(_ links: [PlaceLink]) -> [LinkRow] {
        ["website", "facebook", "instagram"].compactMap { kind in
            guard let link = links.first(where: { $0.kind == kind }),
                  let url = URL(string: link.url), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  let host = url.host(), !host.isEmpty
            else { return nil }
            switch kind {
            case "website": return LinkRow(glyph: "globe", text: host.hasPrefix("www.") ? String(host.dropFirst(4)) : host, url: url)
            case "facebook": return LinkRow(glyph: "f.circle", text: "Facebook", url: url)
            default: return LinkRow(glyph: "camera", text: "Instagram", url: url)
            }
        }
    }

    /// The cover, the Profile's (`GroupPage.Metric.heroAspect`: 245 pt tall on a 402 pt phone), its
    /// photo running on under the sheet's corners.
    static let heroAspect = GroupPage.Metric.heroAspect

    /// With no cover, the sheet's edge, where the logo's middle sits, this far under the safe area's
    /// top: the mock's 118 pt on a 402 pt phone with a 62 pt safe area.
    static let bareEdge: CGFloat = 56

    /// The logo inside its white disc, 5 pt in from the disc's edge all round (the mock's 4 pt and its 1 pt
    /// line), whole: a round logo fills it, a wide one keeps its width, nothing is cut.
    static let logoSide = ProfileMetric.photo - 10

    /// The logo's ink, its file's empty border left out, at most this wide or tall: the mock's 72 pt.
    static let logoInk: CGFloat = 72

    /// How much bigger than `logoSide` the logo's file is drawn at rest, so its ink shows as the mock's:
    /// at most `logoInk` across, and never past `logoSide`'s circle (a square sits smaller, `LogoFit`).
    @MainActor static func logoGrow(_ image: UIImage, url: URL) -> CGFloat {
        let fit = LogoFit.of(image, url: url)
        let ink = fit.image.size, file = max(image.size.width, image.size.height)
        guard ink.width > 0, ink.height > 0, file > 0 else { return 1 }
        let across = min(logoInk * min(1, ink.width / ink.height), logoSide / 2 / max(fit.reach, 0.5))
        return across * file / ink.width / logoSide
    }

    /// Where the sheet's edge is, the logo's middle on it: the cover's foot, or with none under Back.
    static func edge(width: CGFloat, top: CGFloat, cover: Bool) -> CGFloat {
        cover ? width / heroAspect : top + bareEdge
    }

    /// Where the logo rests: in the middle of the sheet's edge, as the Profile's photo.
    static func logo(width: CGFloat, top: CGFloat, cover: Bool) -> CGRect {
        let mid = edge(width: width, top: top, cover: cover)
        return CGRect(x: (width - logoSide) / 2, y: mid - logoSide / 2, width: logoSide, height: logoSide)
    }

    /// Where a photo opened from a card is at `progress`: from the card's `box` to the page's top photo
    /// (full width, running on under the sheet's corners), scrolled up by `scrollY`. Not clamped: the
    /// open's overshoot grows it a touch past its spot and back.
    static func flight(from box: CGRect, width: CGFloat, scrollY: CGFloat, progress p: CGFloat) -> CGRect {
        let to = CGRect(x: 0, y: -max(0, scrollY), width: width, height: width / heroAspect + EventPage.Metric.heroUnderlap)
        return CGRect(x: box.minX + (to.minX - box.minX) * p, y: box.minY + (to.minY - box.minY) * p,
                      width: box.width + (to.width - box.width) * p, height: box.height + (to.height - box.height) * p)
    }

    /// While a photo opened from a card is on its way (in or home, or held by a drag), the page's own
    /// photos wait under it; at rest open, they take over from it.
    static func inFlight(_ progress: CGFloat) -> Bool { progress != 1 }
}

/// What the page's scroll tells the logo over it: how far down the page is, whether a photo is left
/// for it to rest beside (none, and it sits in the middle of the top instead), and which photo is on
/// screen, which goes home into the card it came from (Jesse, 2026-11-15, place-photos 10).
@MainActor @Observable
private final class PageState {
    var scrollY: CGFloat = 0
    var hasPhotos: Bool
    var photo: URL?

    init(hasPhotos: Bool, photo: URL?) {
        self.hasPhotos = hasPhotos
        self.photo = photo
    }
}

private struct BusinessPageBody: View {
    let item: SearchItem
    let source: BusinessOpener.Source
    let opener: BusinessOpener
    @State private var page: PageState

    init(item: SearchItem, source: BusinessOpener.Source, opener: BusinessOpener) {
        self.item = item
        self.source = source
        self.opener = opener
        _page = State(initialValue: PageState(hasPhotos: !item.photos.isEmpty, photo: source.photo))
    }

    var body: some View {
        // Measured inside the safe area, drawn over the whole screen: a reader that ignores the
        // safe area reports no insets, and the page needs the top one. Nothing here reads the
        // spring, so each of its frames redraws only the parts that move.
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            let full = CGSize(width: geo.size.width + insets.leading + insets.trailing,
                              height: geo.size.height + insets.top + insets.bottom)
            let frame = geo.frame(in: .global)
            let origin = CGPoint(x: frame.minX - insets.leading, y: frame.minY - insets.top)

            let box = source.box.offsetBy(dx: -origin.x, dy: -origin.y)
            ZStack(alignment: .topLeading) {
                // The page's paper grows out of the card it came from; under a photo, it fades in.
                GrowingBackdrop(box: box, radius: source.radius, photo: source.photo != nil, fades: source.fades,
                                screen: CGRect(origin: .zero, size: full), progress: opener.progress)

                if let photo = source.photo {
                    // The card's photo grows into the page's top photo, the page riding its foot.
                    GrowingPhoto(url: page.photo ?? photo, box: box, radius: source.radius, width: full.width,
                                 page: page, progress: opener.progress)
                    RidingPhoto(box: box, width: full.width, page: page, progress: opener.progress) {
                        BusinessPageContent(item: item, page: page, size: full, top: insets.top, flight: opener.progress)
                    }
                } else {
                    Rising(progress: opener.progress, travel: full.height) {
                        BusinessPageContent(item: item, page: page, size: full, top: insets.top)
                    }
                }

                CloseBand(opener: opener, page: page, height: insets.top + SearchMetric.bizBand)

                FlyingLogo(item: item, source: source, from: source.logo.offsetBy(dx: -origin.x, dy: -origin.y),
                           width: full.width, top: insets.top, progress: opener.progress, page: page)

                // Over the logo, which scrolls up under it.
                BackCircle(opener: opener, top: insets.top)
            }
            .frame(width: full.width, height: full.height, alignment: .topLeading)
            .offset(x: -insets.leading, y: -insets.top)
            .accessibilityElement(children: .contain)
        }
        .ignoresSafeArea(.keyboard)
        .allowsHitTesting(opener.isOpen)
        // Over the whole screen: VoiceOver stays on the business, not the rows behind it, and
        // its two-finger scrub sends the page home.
        .accessibilityAddTraits(opener.isOpen ? .isModal : [])
        .accessibilityAction(.escape) { opener.close() }
    }
}

/// The page itself, laid out as a person's Profile (`ProfilePage`, place-pages 08): its photos as the
/// cover, and a sheet over their bottom edge with its name and what it is in the middle under the logo,
/// Follow and Map, then its hours, Events, street, About and links. Every row is absent when its data is.
private struct BusinessPageContent: View {
    let item: SearchItem
    let page: PageState
    let size: CGSize
    /// The safe area's top: with no cover the sheet's edge sits under it.
    let top: CGFloat
    /// Opened from a photo: the open's progress, which holds the page's photos back while the card's
    /// photo is on its way and fades in the name and credit over it as it lands.
    var flight: LiveSpring? = nil

    @State private var photoPage: Int? = 0
    /// Photos whose bitmaps are on screen: until then a photo shimmers, and its credit waits.
    @State private var shown: Set<URL> = []
    /// Photos that could not be loaded leave the pager, so a failure never holds a skeleton.
    @State private var failed: Set<URL> = []

    private typealias Metric = EventPage.Metric

    private var photos: [PlacePicture] { item.photos.filter { !failed.contains($0.url) } }

    @Environment(RealLifeActions.self) private var actions
    @Environment(\.openURL) private var openURL

    /// What its Follow follows: the place itself.
    private var follow: FollowTarget? { item.placeID.map { FollowTarget(type: .place, id: $0) } }

    private var kindLine: String? {
        let parts = [item.sub, follow.flatMap { FollowWords.count(actions.follow($0).count) }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                hero
                sheet
            }
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in
            page.scrollY = y
        }
        .onChange(of: photos.isEmpty) { _, none in page.hasPhotos = !none }
        .onChange(of: photoPage) { _, index in
            if let index, photos.indices.contains(index) { page.photo = photos[index].url }
        }
    }

    /// The cover, as tall as the Profile's, the photos running on under the sheet's corners. With no
    /// photo it is only the room above the logo: the backdrop fills it.
    private var hero: some View {
        Color.clear
            .frame(height: BusinessPage.edge(width: size.width, top: top, cover: !photos.isEmpty))
            .overlay(alignment: .top) {
                if !photos.isEmpty {
                    GeometryReader { proxy in
                        PhotoPager(urls: photos.map(\.url), page: $photoPage, shown: $shown, value: photoValue) { url in
                            failed.insert(url)
                            photoPage = min(photoPage ?? 0, max(photos.count - 1, 0))
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height + Metric.heroUnderlap)
                        .modifier(Landed(flight: flight, from: 1))
                    }
                }
            }
            // Pulling the page down past its top stretches the photo from its bottom edge, as on
            // the Event page.
            .visualEffect { content, proxy in
                let pull = max(0, proxy.frame(in: .scrollView(axis: .vertical)).minY)
                return content.scaleEffect(1 + pull / max(proxy.size.height, 1), anchor: .bottom)
            }
            // Its name in its own lettering, white and see-through, low on the cover behind the logo,
            // which hides its foot (place-pages 08). Only lettering: an emblem shows nothing here.
            .overlay(alignment: .bottom) {
                if let name = item.nameArt, !name.emblem, !photos.isEmpty {
                    PlaceNameArt(name: name, spoken: item.name)
                        .opacity(PlaceNameArt.seeThrough)
                        .padding(.bottom, PlaceNameArt.bottom)
                        .modifier(Landed(flight: flight, from: Self.lettersFrom))
                }
            }
            .overlay(alignment: .bottomLeading) { credit.modifier(Landed(flight: flight, from: Self.lettersFrom)) }
            .overlay(alignment: .bottomTrailing) { counter.modifier(Landed(flight: flight, from: Self.lettersFrom)) }
    }

    /// Opened from a photo, the name, credit and counter fade in over its last 45% (the mock's).
    static let lettersFrom: CGFloat = 0.55

    /// The photo on screen's credit, once it is drawn: the site it came from, or a free photo's
    /// author and licence. Bottom left, as on the Event page; the counter has the right. A tap
    /// on it reports the photo (BP app place-photos 06).
    @ViewBuilder private var credit: some View {
        let index = photoPage ?? 0
        if photos.indices.contains(index), PhotoPager.isShown(photos[index].url, in: shown),
           let credit = photos[index].creditLine {
            // With two or more photos the pager says it, with the photo's number.
            PhotoCredit(names: [credit], report: PhotoReport(place: item.name, photo: photos[index].url),
                        spoken: photos.count < 2)
                .padding(.leading, Metric.inset - PhotoCredit.edgeInset)
                .padding(.bottom, Metric.counterBottom - PhotoCredit.edgeInset)
        }
    }

    @ViewBuilder private var counter: some View {
        if let text = EventPage.counterText(page: photoPage ?? 0, count: photos.count) {
            PhotoCounter(text: text)
                .padding(.trailing, Metric.inset)
                .padding(.bottom, Metric.counterBottom)
        }
    }

    /// "Photo 2 of 2, by krewemn.com".
    private var photoValue: String {
        let index = photoPage ?? 0
        let credit = photos.indices.contains(index) ? photos[index].creditLine : nil
        return "Photo \(index + 1) of \(photos.count)" + (credit.map { ", by \($0)" } ?? "")
    }

    private var sheet: some View {
        let rows = BusinessPage.rows(item.links)
        return VStack(alignment: .leading, spacing: 0) {
            head

            if let hours = item.hours {
                HoursPill(hours: hours)
                    .padding(.top, SearchMetric.bizCardsTop)
            }

            // Its Events, folded under its hours (place-pages 05): no row when nothing is coming up.
            if let entry = item.entryId {
                PlaceEventsPill(entryId: entry)
            }

            if let street = item.street {
                InfoPill(glyph: "mappin", text: street, url: Directions.url(forPlace: street),
                         hint: "Opens in Maps", glyphBox: SearchMetric.bizGlyphBox)
                    .padding(.top, item.hours != nil ? SearchMetric.bizLinkGap : SearchMetric.bizCardsTop)
            }

            if let about = item.about {
                AboutSection(text: about)
                    .padding(.top, Metric.aboutTop)
            }

            if !rows.isEmpty {
                VStack(spacing: SearchMetric.bizLinkGap) {
                    ForEach(rows, id: \.self) { row in
                        InfoPill(glyph: row.glyph, text: row.text, url: row.url, hint: "Opens the link",
                                 glyphBox: SearchMetric.bizGlyphBox, leaves: true)
                    }
                }
                .padding(.top, item.about != nil ? SearchMetric.bizLinksTop
                         : item.street != nil ? SearchMetric.bizLinkGap : SearchMetric.bizCardsTop)
            }
        }
        .padding(.horizontal, Metric.inset)
        .padding(.bottom, SearchMetric.tabBarClearance)
        // Paper to the bottom of the screen, however little the page says, and a screen further,
        // so pushing the page up past its end never shows the backdrop under it.
        .frame(maxWidth: .infinity,
               minHeight: size.height - BusinessPage.edge(width: size.width, top: top, cover: !photos.isEmpty),
               alignment: .topLeading)
        .background(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: Metric.sheetCorner, topTrailingRadius: Metric.sheetCorner,
                                   style: .continuous)
                .fill(Hue.paper)
                .padding(.bottom, -size.height)
        }
        // The follower count on the kind line and the friends under the buttons.
        .task(id: follow) { if let follow { await actions.refreshFollow(follow) } }
    }

    /// In the middle under the logo, as the Profile's head: the name 10 pt under the logo's ring, what
    /// it is with its real count ("Cajun · 128 followers", follows 02), Follow and Map side by side, and
    /// the friends who follow it.
    private var head: some View {
        VStack(spacing: 0) {
            Text(item.name)
                .font(.displaySemi(26))
                .tracking(ProfileMetric.nameTracking)
                .foregroundStyle(Hue.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, ProfileMetric.nameTop)

            if let kind = kindLine {
                Text(kind)
                    .font(.sans(15))
                    .foregroundStyle(Hue.inkSecondary)
                    .multilineTextAlignment(.center)
                    .contentTransition(.numericText())
                    .animation(Motion.smooth, value: kind)
                    .padding(.top, SearchMetric.bizKindTop)
            }

            HStack(spacing: ProfileMetric.buttonGap) {
                if let follow {
                    FollowButton(target: follow, name: item.name, size: .profile)
                }
                // Apple Maps on the place, as its street row opens (picked): the town map shows Events,
                // not places. The squish without a haptic: opening a map is not a commit.
                if let map = Directions.url(forPlace: item.street ?? item.name) {
                    Button { openURL(map) } label: {
                        ProfileBlackButton {
                            Image(systemName: "globe")
                                .font(.glyph(15, weight: .semibold))
                                .accessibilityHidden(true)
                            Text("Map")
                        }
                    }
                    .buttonStyle(.press(.squish))
                    .accessibilityHint("Opens in Maps")
                }
            }
            .padding(.top, ProfileMetric.buttonsTop)

            if let follow {
                FollowedBy(target: follow, top: SearchMetric.bizFriendsTop)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Whether it's open now, on the row the street and links use: a green dot "Open till 9 PM",
/// orange "Closes soon · 9 PM", red "Closed till Tue 4 PM" (Jesse, 2026-10-25; Reference Google
/// Maps, BP app references/business-hours). A tap drops the week open inside it, today first and
/// in bold, and folds it back; the spring turns around mid-way. It rereads the clock each minute.
private struct HoursPill: View {
    let hours: PlaceHours

    @State private var expanded = false

    private typealias Metric = EventPage.Metric

    var body: some View {
        TimelineView(.everyMinute) { context in
            if let status = hours.status(at: context.date) {
                Button {
                    withAnimation(Motion.bentoExpand) { expanded.toggle() }
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        row(status)
                        if expanded {
                            week(context.date)
                                // Fades in place as the row grows: a slide drew the days over
                                // the status line on the way.
                                .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Hue.fill)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.press(.squish))
                .accessibilityLabel(PlaceHours.words(status))
                .accessibilityValue(expanded ? ([hours.seasonLine].compactMap { $0 }
                    + hours.week(from: context.date).map { "\($0.day) \($0.hours)" }).joined(separator: ", ") : "")
                .accessibilityHint(expanded ? "Hides the week's hours" : "Shows the week's hours")
            }
        }
    }

    private func row(_ status: PlaceHours.Status) -> some View {
        let words = PlaceHours.words(status)
        let lead = Self.lead(status)
        return HStack(spacing: Metric.pinGap) {
            Circle()
                .fill(Self.dot(status))
                .frame(width: Self.dotSize, height: Self.dotSize)
                .frame(width: SearchMetric.bizGlyphBox)
            Text("\(Text(lead).font(.sansSemibold(15)))\(String(words.dropFirst(lead.count)))")
                .font(.sans(15))
                .foregroundStyle(Hue.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .font(.sans(12))
                .foregroundStyle(Hue.inkSecondary)
                .rotationEffect(.degrees(expanded ? 180 : 0))
        }
        .padding(.horizontal, Metric.pillInset)
        .frame(height: Metric.pillHeight)
    }

    /// Tight rows, the hours lined up under the row's words (Jesse: "remove the excess space").
    private func week(_ now: Date) -> some View {
        VStack(alignment: .leading, spacing: Self.weekRowGap) {
            if let season = hours.seasonLine {
                Text(season)
                    .font(.sansSemibold(15))
                    .foregroundStyle(Hue.ink)
            }
            ForEach(hours.week(from: now), id: \.day) { day in
                HStack {
                    Text(day.day)
                    Spacer(minLength: Metric.pinGap)
                    Text(day.hours).monospacedDigit()
                }
                .font(day.today ? .sansSemibold(15) : .sans(15))
                .foregroundStyle(day.today ? Hue.ink : Hue.inkSecondary)
            }
        }
        .padding(.leading, Metric.pillInset + SearchMetric.bizGlyphBox + Metric.pinGap)
        .padding(.trailing, Metric.pillInset)
        .padding(.bottom, Self.weekBottom)
    }

    static let dotSize: CGFloat = 9
    static let weekRowGap: CGFloat = 6
    static let weekBottom: CGFloat = 12

    static func dot(_ status: PlaceHours.Status) -> Color {
        switch status {
        case .open, .always: Hue.open
        case .closesSoon: Hue.closesSoon
        case .closed, .offSeason: Hue.closed
        }
    }

    /// The words set in bold: "Open", "Closes soon", "Closed", "Open 24 hours".
    static func lead(_ status: PlaceHours.Status) -> String {
        switch status {
        case .open: "Open"
        case .closesSoon: "Closes soon"
        case .closed, .offSeason: "Closed"
        case .always: "Open 24 hours"
        }
    }
}

/// The page's paper, growing out of the card it came from into the whole screen.
private struct GrowingBackdrop: View {
    let box: CGRect
    let radius: CGFloat
    /// Opened from a photo: no box grows, the paper fades in over the whole screen while the photo
    /// grows over it, gone from Search by 40% of the way (the mock's).
    let photo: Bool
    let fades: Bool
    let screen: CGRect
    let progress: LiveSpring

    var body: some View {
        let c = min(max(progress.value, 0), 1)
        if photo {
            Hue.paper.opacity(min(1, c * 2.5))
        } else {
            Hue.paper
                .clipShape(RoundedClip(rect: lerp(box, screen, c), radius: lerp(radius, 0, c)))
                .opacity(radius > 0 && !fades ? 1 : min(1, c * 4))
        }
    }
}

/// The photo a card showed, growing out of the card into the page's top photo and back, its corners
/// squaring off as it goes (Jesse, 2026-11-15: "yes I agree with the mockup 100%", place-photos 10).
/// Drawn as the card and the page draw it, filling its frame round the photo's focus, so the hand-over
/// to the page's own photos at rest can't be seen. It reads the largest bitmap already decoded: the
/// card's at first, the page's sharper one once the pager under it has loaded.
private struct GrowingPhoto: View {
    let url: URL
    let box: CGRect
    let radius: CGFloat
    let width: CGFloat
    let page: PageState
    let progress: LiveSpring

    var body: some View {
        let p = progress.value
        if BusinessPage.inFlight(p) {
            let f = BusinessPage.flight(from: box, width: width, scrollY: page.scrollY, progress: p)
            let loader = FeedCardImageLoader.shared
            ZStack {
                if let image = loader.largest(for: url) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .offset(FeedCardURLPhoto.offset(image: CGSize(width: image.width, height: image.height),
                                                        box: f.size, focus: loader.focus(for: url)))
                } else {
                    Hue.fill
                }
            }
            .frame(width: f.width, height: f.height)
            .clipShape(RoundedRectangle(cornerRadius: max(0, lerp(radius, 0, min(max(p, 0), 1))), style: .continuous))
            .offset(x: f.minX, y: f.minY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// The page under a growing photo: shrunk to the photo's width and riding its foot, so the sheet's
/// corners sit on the photo the whole way, its words fading in from a third of the way (the mock's).
private struct RidingPhoto<Content: View>: View {
    let box: CGRect
    let width: CGFloat
    let page: PageState
    let progress: LiveSpring
    @ViewBuilder let content: Content

    var body: some View {
        let p = progress.value
        let c = min(max(p, 0), 1)
        let flying = BusinessPage.inFlight(p)
        let f = BusinessPage.flight(from: box, width: width, scrollY: page.scrollY, progress: p)
        let k = flying ? f.width / max(width, 1) : 1
        // Where the page's own photo (as tall as the flight's end, scrolled up by scrollY) puts its
        // foot on the flying photo's.
        let photo = width / BusinessPage.heroAspect + EventPage.Metric.heroUnderlap - max(0, page.scrollY)
        content
            .scaleEffect(k, anchor: .topLeading)
            .offset(x: flying ? f.minX : 0, y: flying ? f.maxY - k * photo : 0)
            .opacity(flying ? min(max((c - 0.35) / 0.5, 0), 1) : 1)
    }
}

/// Opened from a photo, what waits for it to land: hidden while it's on its way, then fading in over
/// the end of the way from `from` (1: only once it rests). Nothing to wait for opens as before.
private struct Landed: ViewModifier {
    let flight: LiveSpring?
    let from: CGFloat

    func body(content: Content) -> some View {
        content.opacity(Self.opacity(flight?.value, from: from))
    }

    static func opacity(_ progress: CGFloat?, from: CGFloat) -> Double {
        guard let progress, BusinessPage.inFlight(progress) else { return 1 }
        guard from < 1 else { return 0 }
        return min(max((min(progress, 1) - from) / (1 - from), 0), 1)
    }
}

/// The page rises from below as it opens and sinks back as it closes.
private struct Rising<Content: View>: View {
    let progress: LiveSpring
    let travel: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        let p = progress.value
        content
            .offset(y: p >= 1 ? 0 : (1 - max(p, 0)) * travel)
            .opacity(p > 0.001 ? 1 : 0)
    }
}

/// The band under the clock and Back: a drag down on it sends the page home, following the
/// finger. Only while the page is at its top (scrolled, its words are under the band and scroll
/// instead), and only for a drag that sets off up or down.
private struct CloseBand: View {
    let opener: BusinessOpener
    let page: PageState
    let height: CGFloat
    @State private var dragFrom: CGFloat?
    @State private var sideways = false

    var body: some View {
        Color.clear
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(drag)
            .allowsHitTesting(page.scrollY <= 1)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: SearchMetric.bizDragStart, coordinateSpace: .global)
            .onChanged { value in
                if dragFrom == nil, abs(value.translation.width) > abs(value.translation.height) { sideways = true }
                guard !sideways else { return }
                let from = dragFrom ?? opener.progress.value
                dragFrom = from
                opener.progress.set(min(max(from - value.translation.height / SearchMetric.bizDrag, 0), SearchMetric.bizOverDrag))
            }
            .onEnded { value in
                defer { dragFrom = nil; sideways = false }
                guard dragFrom != nil else { return }
                let speed = -value.velocity.height / SearchMetric.bizDrag
                if value.velocity.height > SearchMetric.bizFlick || opener.progress.value < SearchMetric.bizKeepOpen {
                    opener.close(velocity: speed)
                } else {
                    opener.settleOpen(velocity: speed)
                }
            }
    }
}

/// The Event page's Back circle, where the Event page has it, fading and growing in as the page
/// opens. It stays put while the page scrolls under it.
private struct BackCircle: View {
    let opener: BusinessOpener
    let top: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let p = opener.progress.value
        let m = EventPage.Metric.self
        let pad = (m.tapBox - m.button) / 2
        EventPage.circleButton(glyph: Image(systemName: "arrow.left"), label: "Back") { opener.close() }
            .opacity(min(max(p * 2 - 1, 0), 1))
            .scaleEffect(lerp(SearchMetric.bizBackFrom, 1, min(max(p, 0), 1)))
            .offset(x: m.inset - pad, y: top + m.buttonTop - pad)
            // VoiceOver reads it first, as it sits.
            .accessibilitySortPriority(1)
    }
}

/// The logo flies from where it was tapped to the middle of the sheet's edge, the white disc and its
/// ring of paper growing in round it, the Profile's photo (place-pages 08); on the cover's foot, or at
/// the top with no cover. Mid-flight it lifts: its shadow stretches and fades a little, and goes as it
/// lands on the disc. Open, it scrolls with the page. A place with no logo yet flies its letter disc the
/// same way (place-pages 01).
private struct FlyingLogo: View {
    let item: SearchItem
    let source: BusinessOpener.Source
    let from: CGRect
    let width: CGFloat
    let top: CGFloat
    let progress: LiveSpring
    let page: PageState

    @ObservedObject private var logos = POILogoCache.shared

    var body: some View {
        let p = progress.value
        let c = min(max(p, 0), 1)
        // From a photo the logo was never on screen: it doesn't fly, it fades in where it rests as
        // the photo lands (Jesse, 2026-11-15, place-photos 10).
        let fromPhoto = source.photo != nil
        let lift = fromPhoto ? 0 : sin(.pi * c)
        let rest = BusinessPage.logo(width: width, top: top, cover: page.hasPhotos)
        let flying = lerp(fromPhoto ? rest : from, rest, p)
        let shown = fromPhoto ? Landed.opacity(p, from: BusinessPageContent.lettersFrom)
            : (source.fades ? min(1, c * 4) : 1)
        // The disc grows with the logo: 96 pt round the logo's 86 at rest.
        let k = flying.width / BusinessPage.logoSide
        // Search's tile draws the file with its border; the disc shows the ink at the mock's size.
        let grow = item.logo.flatMap { logo in
            logos.image(for: logo.url).map { BusinessPage.logoGrow($0, url: logo.url) }
        } ?? 1
        Group {
            if let logo = item.logo {
                CastLogo(logo: logo, side: flying.width * lerp(fromPhoto ? grow : 1, grow, p), shadow: source.shadow,
                         stretch: 1 + lift * SearchMetric.liftStretch,
                         strength: (1 - lift * SearchMetric.liftFade) * (1 - c))
            } else {
                LetterDisc(initial: item.initial, side: flying.width)
            }
        }
            // The file's empty border spills past the disc's box; the disc stays centred on it.
            .frame(width: flying.width, height: flying.width)
            .background {
                Circle()
                    .fill(Hue.surface)
                    .overlay { Circle().strokeBorder(Hue.ink.opacity(0.16), lineWidth: FriendsMetric.ring) }
                    .padding(ProfileMetric.ring * k)
                    .background(Hue.paper, in: Circle())
                    .frame(width: (ProfileMetric.photo + 2 * ProfileMetric.ring) * k,
                           height: (ProfileMetric.photo + 2 * ProfileMetric.ring) * k)
                    .opacity(fromPhoto ? 1 : c)
            }
            // With the page as it scrolls, and down with it when pulled past its top.
            .offset(x: flying.minX, y: flying.minY - page.scrollY * c)
            .opacity(shown)
            // Every photo failed after it landed: it moves to the top, not jumps.
            .animation(Motion.smooth, value: page.hasPhotos)
            .allowsHitTesting(false)
            // The page's title says the name.
            .accessibilityHidden(true)
    }
}

// MARK: - Drawing a logo on its set

/// A photo-shoot backdrop: a soft light centred near the top, as the mockup's CSS
/// `radial-gradient(130% 95% at 50% 24%, …)` draws it. The ellipse's radii are a
/// share of the box's own width and height, which no SwiftUI gradient takes.
struct SearchBackdrop: View {
    let colors: [Color]
    var stops: [CGFloat] = [0, 0.5, 1]
    var center = UnitPoint(x: 0.5, y: 0.24)
    var radii = CGSize(width: 1.3, height: 0.95)

    var body: some View {
        Canvas { context, size in
            let rx = size.width * radii.width, ry = size.height * radii.height
            guard rx > 0, ry > 0 else { return }
            let c = CGPoint(x: size.width * center.x, y: size.height * center.y)
            context.translateBy(x: c.x, y: c.y)
            context.scaleBy(x: 1, y: ry / rx)
            let gradient = Gradient(stops: zip(colors, stops).map { Gradient.Stop(color: $0, location: $1) })
            let all = CGRect(x: -c.x, y: -c.y * rx / ry, width: size.width, height: size.height * rx / ry)
            context.fill(Path(all), with: .radialGradient(gradient, center: .zero, startRadius: 0, endRadius: rx))
        }
    }
}

/// The floor under a logo: the backdrop darkens a touch toward the bottom, so the logo
/// stands on something.
struct SearchFloor: View {
    var body: some View {
        LinearGradient(stops: [.init(color: Hue.searchFloor.opacity(0), location: 0.6),
                               .init(color: Hue.searchFloor.opacity(0.05), location: 0.68),
                               .init(color: Hue.searchFloor.opacity(0.1), location: 1)],
                       startPoint: .top, endPoint: .bottom)
    }
}

/// The logo itself, with its own outline cast straight down onto the backdrop by an
/// overhead light: dark and tight at the edge, wider and fainter further out
/// (Photoroom's "Soft" shadow, taste.md 2026-10-02; lifted higher off the page 2026-11-08:
/// it falls further below the logo and spreads wider, a little fainter). Three layers, each a share of the
/// logo's size; the CSS blurs are halved, as a SwiftUI shadow radius blurs about as
/// much as a CSS blur twice its size. `stretch` and `strength` lift it mid-flight.
struct CastLogo: View {
    let logo: SearchLogo
    let side: CGFloat
    var shadow: Color? = nil
    var stretch: CGFloat = 1
    var strength: Double = 1

    @ObservedObject private var cache = POILogoCache.shared
    /// Handed down by a page that follows the phone's tilt; none, and the logo has no shine.
    @Environment(PhoneTilt.self) private var tilt: PhoneTilt?

    var body: some View {
        let image = cache.image(for: logo.url)
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    // Search's logos are square; a school's crest isn't, and kept its shape.
                    .scaledToFit()
                    .castShadow(shadow ?? logo.shadow, side: side, stretch: stretch, strength: strength)
                    // Over the shadows, not under them: a new lean then redraws the light alone.
                    .overlay { if let tilt { LogoShine(image: image, side: side, tilt: tilt) } }
                    .transition(.opacity)
            }
        }
        .frame(width: side, height: side)
        // A logo that lands after its tile is showing fades in rather than popping; a cached
        // one is there on the first frame and never animates.
        .animation(Motion.smooth, value: image != nil)
        // A logo whose fetch failed (offline when the places loaded) asks again when it is
        // next on screen; one already loaded or in flight is skipped by the cache.
        .task(id: logo.url) { cache.prefetch([logo.url]) }
        #if DEBUG
        .onAppear { ReadAheadLog.cameOn("logo", ready: cache.image(for: logo.url) != nil, logo.url) }
        #endif
    }
}

extension View {
    /// `CastLogo`'s shadow, the view's own outline cast straight down in three layers, each a share of `side`: Search's
    /// logos and a game's team logos (game-card 26). `stretch` and `strength` lift it mid-flight; a game's page casts it
    /// stronger to show on the team colors.
    func castShadow(_ color: Color, side: CGFloat, stretch: CGFloat = 1, strength: Double = 1) -> some View {
        shadow(color: color.opacity(0.32 * strength), radius: max(1.4, side * 0.02) * stretch / 2, y: side * 0.016 * stretch)
            .shadow(color: color.opacity(0.20 * strength), radius: side * 0.10 * stretch / 2, y: side * 0.055 * stretch)
            .shadow(color: color.opacity(0.13 * strength), radius: side * 0.26 * stretch / 2, y: side * 0.13 * stretch)
    }
}

/// A soft oval glow on a logo, in the logo's own shape: the reflection of a light straight
/// above, over the logo's middle while the phone is held level, moving whichever way it
/// tips (Jesse, 2026-10-11, taste.md: a 360 light, an oval, shining straight down). Its own
/// view, so a new lean redraws the glow and not the logo.
private struct LogoShine: View {
    let image: UIImage
    let side: CGFloat
    let tilt: PhoneTilt

    var body: some View {
        let m = SearchMetric.self
        // An oval wider than it is tall, its edge where the frame's is, centred where the
        // lean puts it, then cut to the logo.
        EllipticalGradient(stops: [
            .init(color: Hue.logoShine.opacity(m.shinePeak), location: 0),
            .init(color: Hue.logoShine.opacity(m.shineShoulder), location: m.shineShoulderAt),
            .init(color: Hue.logoShine.opacity(0), location: m.shineFadeAt),
        ], center: .center, endRadiusFraction: 0.5)
            .frame(width: side * 2 * m.shineReachX, height: side * 2 * m.shineReachY)
            .position(x: side * (0.5 + m.shineTravel * tilt.lean.x),
                      y: side * (0.5 + m.shineTravel * tilt.lean.y))
            .frame(width: side, height: side)
            .mask { Image(uiImage: image).resizable() }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A rounded rectangle at a set place: the backdrop's window as it grows.
nonisolated struct RoundedClip: Shape {
    var rect: CGRect
    var radius: CGFloat

    func path(in _: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
    }
}

private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

private func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
    CGRect(x: lerp(a.minX, b.minX, t), y: lerp(a.minY, b.minY, t),
           width: lerp(a.width, b.width, t), height: lerp(a.height, b.height, t))
}
