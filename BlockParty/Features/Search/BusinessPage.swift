//
//  BusinessPage.swift
//  Block Party — a business opened from its logo in Search. Its backdrop grows out of
//  the tile, the logo flies to the top right, and its Google Maps photos rise in a grid,
//  row by row. Back, or a drag down on the coloured band, sends it home the way it came.
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
        }
    }
}

private struct BusinessPageBody: View {
    let item: SearchItem
    let logo: SearchLogo
    let source: BusinessOpener.Source
    let opener: BusinessOpener
    /// nil while Google is being asked.
    @State private var photos: [PlacePhoto]?
    @State private var dragFrom: CGFloat?

    var body: some View {
        // Measured inside the safe area, drawn over the whole screen: a reader that
        // ignores the safe area reports no insets, and the bar needs the top one.
        GeometryReader { geo in
            let p = opener.progress.value
            let c = min(max(p, 0), 1)
            let insets = geo.safeAreaInsets
            let full = CGSize(width: geo.size.width + insets.leading + insets.trailing,
                              height: geo.size.height + insets.top + insets.bottom)
            let frame = geo.frame(in: .global)
            let origin = CGPoint(x: frame.minX - insets.leading, y: frame.minY - insets.top)
            let top = insets.top
            let screen = CGRect(origin: .zero, size: full)
            let box = source.box.offsetBy(dx: -origin.x, dy: -origin.y)
            let from = source.logo.offsetBy(dx: -origin.x, dy: -origin.y)
            let side = SearchMetric.bizLogo
            let dock = CGRect(x: full.width - SearchMetric.bizLogoRight - side,
                              y: top + SearchMetric.bizLogoCenter - side / 2, width: side, height: side)
            let gridTop = top + SearchMetric.bizGridTop

            ZStack(alignment: .topLeading) {
                // The backdrop grows out of the card it came from.
                SearchBackdrop(colors: logo.backdrop)
                    .clipShape(RoundedClip(rect: lerp(box, screen, c), radius: lerp(source.radius, 0, c)))
                    .opacity(source.radius > 0 && !source.fades ? 1 : min(1, c * 4))

                photoGrid(width: full.width, travel: full.height - gridTop, p: p)
                    .padding(.top, gridTop)
                    .opacity(p > 0.001 ? 1 : 0)

                // The band above the photos: drag it down to send the page home.
                Color.clear
                    .frame(height: gridTop)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .gesture(drag)

                backButton
                    .opacity(min(max(p * 2 - 1, 0), 1))
                    .scaleEffect(lerp(SearchMetric.bizBackFrom, 1, c))
                    .offset(x: SearchMetric.bizBackLeft, y: top + SearchMetric.bizBackTop)

                // The logo flies to the top right. Mid-flight it lifts: its shadow
                // stretches and fades a little, and settles as it docks.
                let lift = sin(.pi * c)
                let flying = lerp(from, dock, p)
                CastLogo(logo: logo, side: flying.width, shadow: source.shadow,
                         stretch: 1 + lift * SearchMetric.liftStretch, strength: 1 - lift * SearchMetric.liftFade)
                    .offset(x: flying.minX, y: flying.minY)
                    .opacity(source.fades ? min(1, c * 4) : 1)
                    .allowsHitTesting(false)
                    .accessibilityLabel(item.name)
            }
            .frame(width: full.width, height: full.height, alignment: .topLeading)
            .offset(x: -insets.leading, y: -insets.top)
        }
        .ignoresSafeArea(.keyboard)
        .allowsHitTesting(opener.isOpen)
        // Over the whole screen: VoiceOver stays on the business, not the rows behind it.
        .accessibilityAddTraits(opener.isOpen ? .isModal : [])
        .task(id: item.id) {
            photos = nil
            photos = await item.googlePhotos().all
        }
    }

    private var backButton: some View {
        Button { opener.close() } label: {
            Image(systemName: "chevron.left")
                .font(.glyph(18, weight: .semibold))
                .foregroundStyle(Hue.ink)
                .frame(width: SearchMetric.bizBack, height: SearchMetric.bizBack)
                .background(Hue.surface, in: Circle())
                .mapFloatShadow()
        }
        .buttonStyle(SquishStyle())
        .accessibilityLabel("Back")
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                let from = dragFrom ?? opener.progress.value
                dragFrom = from
                opener.progress.set(min(max(from - value.translation.height / SearchMetric.bizDrag, 0), SearchMetric.bizOverDrag))
            }
            .onEnded { value in
                dragFrom = nil
                let speed = -value.velocity.height / SearchMetric.bizDrag
                if value.velocity.height > SearchMetric.bizFlick || opener.progress.value < SearchMetric.bizKeepOpen {
                    opener.close(velocity: speed)
                } else {
                    opener.settleOpen(velocity: speed)
                }
            }
    }

    /// The photos rise from below, a row at a time, growing slightly as they come.
    private func photoGrid(width: CGFloat, travel: CGFloat, p: CGFloat) -> some View {
        let gap = SearchMetric.bizGridGap
        let tile = (width - gap * 2) / 3
        let tiles = Self.tiles(photos)
        return ScrollView(showsIndicators: false) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(tile), spacing: gap), count: 3), spacing: gap) {
                ForEach(tiles.indices, id: \.self) { i in
                    let lag = Double(i / 3) * SearchMetric.bizRowLag
                    let local = max(0, (p - lag) / (1 - lag))
                    BusinessPhotoTile(tile: tiles[i], index: i, logo: logo)
                        .frame(width: tile, height: tile)
                        .clipped()
                        .scaleEffect(p >= 1 ? 1 : lerp(SearchMetric.bizRiseScale, 1, min(local, 1)))
                        .offset(y: p >= 1 ? 0 : (1 - local) * travel)
                }
            }
            .padding(.bottom, SearchMetric.tabBarClearance)
        }
        .scrollDisabled(p < 1)
    }

    enum Tile { case loading, photo(PlacePhoto), none }

    /// Nine waiting tiles while Google is asked; then its photos, or the mockup's 15
    /// blank tiles in the logo's colour when it has none.
    static func tiles(_ photos: [PlacePhoto]?) -> [Tile] {
        guard let photos else { return Array(repeating: .loading, count: SearchMetric.bizLoadingTiles) }
        return photos.isEmpty ? Array(repeating: .none, count: SearchMetric.bizBlankTiles) : photos.map { .photo($0) }
    }

}

private struct BusinessPhotoTile: View {
    let tile: BusinessPageBody.Tile
    let index: Int
    let logo: SearchLogo
    @State private var shown = false
    @State private var failed = false

    var body: some View {
        ZStack {
            switch tile {
            case .loading:
                Hue.ink.opacity(SearchMetric.bizTileShade).shimmering()
            case .photo(let photo) where !failed:
                let url = GooglePlacesService.shared.photoURL(name: photo.name, maxWidth: SearchMetric.bizPhotoPixels)
                Hue.ink.opacity(SearchMetric.bizTileShade)
                FeedCardURLPhoto(url: url, onReady: { withAnimation(.easeOut(duration: 0.2)) { shown = true } },
                                 onFailure: { failed = true }, loadingFill: .clear)
                // A photo already decoded elsewhere draws at once: so does its credit.
                if shown || FeedCardImageLoader.shared.largest(for: url) != nil {
                    PhotoCredit(names: photo.attributions)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            case .photo, .none:
                Hue.hsl(logo.hue, logo.chroma ? 26 : 8, 80 - Double((index * 7) % 9))
                Image(systemName: "photo")
                    .font(.glyph(24, weight: .light))
                    .foregroundStyle(Hue.ink.opacity(0.22))
                    .accessibilityHidden(true)
            }
        }
        // A photo reads as its credit ("Photo by …"); a blank tile reads as nothing.
        .accessibilityElement(children: .combine)
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

    var body: some View {
        if let image = cache.image(for: logo.url) {
            let color = shadow ?? logo.shadow, k = stretch
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: side, height: side)
                .shadow(color: color.opacity(0.36 * strength), radius: max(1.2, side * 0.016) * k / 2, y: side * 0.008 * k)
                .shadow(color: color.opacity(0.22 * strength), radius: side * 0.07 * k / 2, y: side * 0.03 * k)
                .shadow(color: color.opacity(0.14 * strength), radius: side * 0.18 * k / 2, y: side * 0.075 * k)
        }
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
