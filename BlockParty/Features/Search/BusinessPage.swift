//
//  BusinessPage.swift
//  Block Party — a business opened from its logo in Search. Its backdrop grows out of
//  the tile, the logo flies to the top right, and its page rises: laid out like the Event
//  page (Jesse, 2026-10-17), the photos Block Party saved of it swiping at the top under the
//  logo, then its name, what it is, its street, its own words and its links. With no photo
//  the logo lands in the middle of the top, as an Event page draws a place it has no photo of.
//  Back, or a drag down on the band under the clock, sends it home the way it came.
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
        /// Opened from a photo card, where the logo isn't on screen: the backdrop
        /// fades in over the photo and the logo fades in as it flies.
        var fades = false
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
}

/// The open business, over the whole screen. Draws nothing while nothing is open.
struct BusinessPage: View {
    @Environment(BusinessOpener.self) private var opener

    var body: some View {
        if let item = opener.item, let logo = item.logo, let source = opener.source {
            BusinessPageBody(item: item, logo: logo, source: source, opener: opener)
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

    /// Where the logo rests beside a photo: the top right, as before (the mockup's 76 pt, 10 pt
    /// in, its middle 29 pt under the safe area).
    static func corner(width: CGFloat, top: CGFloat) -> CGRect {
        let side = SearchMetric.bizLogo
        return CGRect(x: width - SearchMetric.bizLogoRight - side, y: top + SearchMetric.bizLogoCenter - side / 2,
                      width: side, height: side)
    }

    /// Where it rests with no photo: where the Event page draws a place's logo in a hero it has no
    /// photo for (`FeedCardPlaceLogo`, 29% down a hero as tall as the photos and the sheet's
    /// underlap, at most 43% of it), so the two pages agree.
    static func middle(width: CGFloat) -> CGRect {
        let m = FeedEventDetailDestination.Metric.self
        let hero = width / m.heroAspect + m.heroUnderlap
        let top = hero * 0.29, room = hero - top - 8
        let side = min(hero * 0.43, width * 0.4, room)
        return CGRect(x: (width - side) / 2, y: top + (room - side) / 2, width: side, height: side)
    }
}

/// What the page's scroll tells the logo over it: how far down the page is, and whether a photo
/// is left for it to rest beside (none, and it sits in the middle of the top instead).
@MainActor @Observable
private final class PageState {
    var scrollY: CGFloat = 0
    var hasPhotos: Bool

    init(hasPhotos: Bool) { self.hasPhotos = hasPhotos }
}

private struct BusinessPageBody: View {
    let item: SearchItem
    let logo: SearchLogo
    let source: BusinessOpener.Source
    let opener: BusinessOpener
    @State private var page: PageState

    init(item: SearchItem, logo: SearchLogo, source: BusinessOpener.Source, opener: BusinessOpener) {
        self.item = item
        self.logo = logo
        self.source = source
        self.opener = opener
        _page = State(initialValue: PageState(hasPhotos: !item.photos.isEmpty))
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

            ZStack(alignment: .topLeading) {
                // The backdrop grows out of the card it came from.
                GrowingBackdrop(colors: logo.backdrop, box: source.box.offsetBy(dx: -origin.x, dy: -origin.y),
                                radius: source.radius, fades: source.fades,
                                screen: CGRect(origin: .zero, size: full), progress: opener.progress)

                Rising(progress: opener.progress, travel: full.height) {
                    BusinessPageContent(item: item, page: page, size: full)
                }

                CloseBand(opener: opener, page: page, height: insets.top + SearchMetric.bizBand)

                BackCircle(opener: opener, top: insets.top)

                FlyingLogo(logo: logo, source: source, from: source.logo.offsetBy(dx: -origin.x, dy: -origin.y),
                           corner: BusinessPage.corner(width: full.width, top: insets.top),
                           middle: BusinessPage.middle(width: full.width), progress: opener.progress, page: page)
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

/// The page itself, laid out like the Event page (`FeedEventDetailDestination`): its photos at
/// the top, and a sheet over their bottom edge with its name, what it is, its street, its About
/// and its links. Every row is absent when its data is.
private struct BusinessPageContent: View {
    let item: SearchItem
    let page: PageState
    let size: CGSize

    @State private var photoPage: Int? = 0
    /// Photos whose bitmaps are on screen: until then a photo shimmers, and its credit waits.
    @State private var shown: Set<URL> = []
    /// Photos that could not be loaded leave the pager, so a failure never holds a skeleton.
    @State private var failed: Set<URL> = []

    private typealias Metric = FeedEventDetailDestination.Metric

    private var photos: [PlacePicture] { item.photos.filter { !failed.contains($0.url) } }

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
    }

    /// As tall as the Event page's: 303/393 of the width, the photos running on under the
    /// sheet's corners. With no photo it stays clear: the backdrop and the logo fill it.
    private var hero: some View {
        Color.clear
            .aspectRatio(Metric.heroAspect, contentMode: .fit)
            .overlay(alignment: .top) {
                if !photos.isEmpty {
                    GeometryReader { proxy in
                        PhotoPager(urls: photos.map(\.url), page: $photoPage, shown: $shown, value: photoValue) { url in
                            failed.insert(url)
                            photoPage = min(photoPage ?? 0, max(photos.count - 1, 0))
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height + Metric.heroUnderlap)
                    }
                }
            }
            // Pulling the page down past its top stretches the photo from its bottom edge, as on
            // the Event page.
            .visualEffect { content, proxy in
                let pull = max(0, proxy.frame(in: .scrollView(axis: .vertical)).minY)
                return content.scaleEffect(1 + pull / max(proxy.size.height, 1), anchor: .bottom)
            }
            .overlay(alignment: .bottomLeading) { credit }
            .overlay(alignment: .bottomTrailing) { counter }
    }

    /// The photo on screen's credit, once it is drawn: the site it came from, or a free photo's
    /// author and licence. Bottom left, as on the Event page; the counter has the right.
    @ViewBuilder private var credit: some View {
        let index = photoPage ?? 0
        if photos.indices.contains(index), PhotoPager.isShown(photos[index].url, in: shown),
           let credit = photos[index].creditLine {
            PhotoCredit(names: [credit])
                .padding(.leading, Metric.inset - PhotoCredit.edgeInset)
                .padding(.bottom, Metric.counterBottom - PhotoCredit.edgeInset)
                // With two or more photos the pager says it, with the photo's number.
                .accessibilityHidden(photos.count >= 2)
        }
    }

    @ViewBuilder private var counter: some View {
        if let text = FeedEventDetailDestination.counterText(page: photoPage ?? 0, count: photos.count) {
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
            Text(item.name)
                .font(.eventDisplay(28))
                .lineSpacing(Metric.titleLineSpacing)
                .foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, Metric.titleTop)

            if let sub = item.sub {
                Text(sub)
                    .font(.sans(17))
                    .foregroundStyle(Hue.inkSecondary)
                    .padding(.top, Metric.categoryTop)
            }

            if let street = item.street {
                InfoPill(glyph: "mappin", text: street, url: DayScheduleLogic.directionsURL(forPlace: street),
                         hint: "Opens in Maps", glyphBox: SearchMetric.bizGlyphBox)
                    .padding(.top, Metric.pillTop)
            }

            if let about = item.about {
                AboutSection(text: about)
                    .padding(.top, Metric.aboutTop)
            }

            if !rows.isEmpty {
                VStack(spacing: SearchMetric.bizLinkGap) {
                    ForEach(rows, id: \.self) { row in
                        InfoPill(glyph: row.glyph, text: row.text, url: row.url, hint: "Opens outside Block Party",
                                 glyphBox: SearchMetric.bizGlyphBox, leaves: true)
                    }
                }
                .padding(.top, item.about != nil ? SearchMetric.bizLinksTop
                         : item.street != nil ? SearchMetric.bizLinkGap : Metric.pillTop)
            }
        }
        .padding(.horizontal, Metric.inset)
        .padding(.bottom, SearchMetric.tabBarClearance)
        // Paper to the bottom of the screen, however little the page says, and a screen further,
        // so pushing the page up past its end never shows the backdrop under it.
        .frame(maxWidth: .infinity, minHeight: size.height - size.width / Metric.heroAspect, alignment: .topLeading)
        .background(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: Metric.sheetCorner, topTrailingRadius: Metric.sheetCorner,
                                   style: .continuous)
                .fill(Hue.paper)
                .padding(.bottom, -size.height)
        }
    }
}

/// The backdrop, growing out of the card it came from into the whole screen.
private struct GrowingBackdrop: View {
    let colors: [Color]
    let box: CGRect
    let radius: CGFloat
    let fades: Bool
    let screen: CGRect
    let progress: LiveSpring

    var body: some View {
        let c = min(max(progress.value, 0), 1)
        SearchBackdrop(colors: colors)
            .clipShape(RoundedClip(rect: lerp(box, screen, c), radius: lerp(radius, 0, c)))
            .opacity(radius > 0 && !fades ? 1 : min(1, c * 4))
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
        let m = FeedEventDetailDestination.Metric.self
        let pad = (m.tapBox - m.button) / 2
        FeedEventDetailDestination.circleButton(glyph: Image(systemName: "arrow.left"), label: "Back",
                                                reduceMotion: reduceMotion) { opener.close() }
            .opacity(min(max(p * 2 - 1, 0), 1))
            .scaleEffect(lerp(SearchMetric.bizBackFrom, 1, min(max(p, 0), 1)))
            .offset(x: m.inset - pad, y: top + m.buttonTop - pad)
            // VoiceOver reads it first, as it sits.
            .accessibilitySortPriority(1)
    }
}

/// The logo flies from where it was tapped to its corner, or to the middle of the top when the
/// business has no photo. Mid-flight it lifts: its shadow stretches and fades a little, and
/// settles as it lands. Open, it scrolls away with the photos.
private struct FlyingLogo: View {
    let logo: SearchLogo
    let source: BusinessOpener.Source
    let from: CGRect
    let corner: CGRect
    let middle: CGRect
    let progress: LiveSpring
    let page: PageState

    var body: some View {
        let p = progress.value
        let c = min(max(p, 0), 1)
        let lift = sin(.pi * c)
        let flying = lerp(from, page.hasPhotos ? corner : middle, p)
        CastLogo(logo: logo, side: flying.width, shadow: source.shadow,
                 stretch: 1 + lift * SearchMetric.liftStretch, strength: 1 - lift * SearchMetric.liftFade)
            .offset(x: flying.minX, y: flying.minY - max(0, page.scrollY) * c)
            .opacity(source.fades ? min(1, c * 4) : 1)
            // Every photo failed after it landed: it moves to the middle, not jumps.
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

    /// The logo wall's one studio backdrop.
    static var studio: SearchBackdrop {
        let h = Hue.searchStudioHue
        return SearchBackdrop(colors: [Hue.hsl(h, 9, 94), Hue.hsl(h, 8, 88), Hue.hsl(h, 7, 80)], stops: [0, 0.55, 1],
                              center: UnitPoint(x: 0.5, y: 0), radii: CGSize(width: 1.4, height: 0.8))
    }

    /// The studio's top, for the bar over the wall.
    static var studioTop: Color { Hue.hsl(Hue.searchStudioHue, 9, 94) }
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
/// (Photoroom's "Soft" shadow, taste.md 2026-10-02). Three layers, each a share of the
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
                let color = shadow ?? logo.shadow, k = stretch
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .shadow(color: color.opacity(0.36 * strength), radius: max(1.2, side * 0.016) * k / 2, y: side * 0.008 * k)
                    .shadow(color: color.opacity(0.22 * strength), radius: side * 0.07 * k / 2, y: side * 0.03 * k)
                    .shadow(color: color.opacity(0.14 * strength), radius: side * 0.18 * k / 2, y: side * 0.075 * k)
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
