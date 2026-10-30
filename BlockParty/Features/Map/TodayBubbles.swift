//
//  TodayBubbles.swift
//  Block Party — today's events on the map as liquid-glass photo bubbles.
//
//  Jesse's map-today idea (2026-10-22; References and the approved mock in BP app
//  `references/map-today/`, pulse.html). One bubble per place with an event today:
//  the event's photo, else the place's photo, else its logo, under Apple's Liquid
//  Glass, the middle bent toward you like a dome and the photo fading into the clear
//  glass at the rim. Every bubble counts down to its start all day; in the last hour
//  a black ring empties around it. While an event is on (EventWhen.isOn), the
//  bubble breathes 4% every 2.4 s with a dark shadow bleeding out, and its tag says
//  "Now" behind Apple's green dot (taste/town.md, 2026-10-20). The shadow bleed
//  replaces the plum live pulse for places that have a bubble (Jesse at Check-in 1).
//  Every bubble is squishy: it follows a drag a little, any direction, stretches
//  along it and springs back.
//
//  Map reset (BP app references/map-reset, 2026-10-30): one bubble per real spot, with
//  every Event there today behind it for the card to page through. It grows as you zoom
//  in, 36 pt zoomed out to 46 at the opening zoom to 72 (Jesse's picks); the tag under it
//  keeps its size. The tapped one grows 12% more and sits on top.
//

import SwiftUI
import CoreLocation

// MARK: - Rules (pure, tested in TodayBubblesTests)

enum TodayBubbleRules {
    /// Where an event stands at `now`.
    enum Phase: Equatable {
        case upcoming(secondsLeft: Int)
        case live
        case ended
        case untimed
    }

    /// From its start to its end (`EventWhen`: `end_at`, else two hours), as the Town card.
    /// Called off, or a game whose final is in, it's over.
    static func phase(_ event: FeedCardItem, now: Date) -> Phase {
        if event.cancelled || event.game?.final != nil { return .ended }
        guard let when = event.when, when.timed else { return .untimed }
        if now < when.start { return .upcoming(secondsLeft: Int(when.start.timeIntervalSince(now).rounded(.up))) }
        return when.isOn(now) ? .live : .ended
    }

    /// Its start, for ordering; untimed ones last.
    static func starts(_ event: FeedCardItem) -> Date {
        event.when.flatMap { $0.timed ? $0.start : nil } ?? .distantFuture
    }

    /// "1h 23m" an hour or more out, "8:05" inside the last hour.
    static func countdown(_ secondsLeft: Int) -> String {
        let s = max(0, secondsLeft)
        if s >= 3600 { return "\(s / 3600)h \(String(format: "%02d", s % 3600 / 60))m" }
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    /// The countdown as VoiceOver says it: "1 hour 23 minutes", "37 minutes", "under a minute".
    static func spokenCountdown(_ secondsLeft: Int) -> String {
        let m = max(0, secondsLeft) / 60, h = m / 60, rest = m % 60
        if m == 0 { return "under a minute" }
        let mins = rest == 1 ? "1 minute" : "\(rest) minutes"
        if h == 0 { return mins }
        let hours = h == 1 ? "1 hour" : "\(h) hours"
        return rest == 0 ? hours : "\(hours) \(mins)"
    }

    /// How much of the ring is left: full an hour out, empty at the start; nil before the last hour.
    static func ringLeft(_ secondsLeft: Int) -> Double? {
        guard secondsLeft <= 3600 else { return nil }
        return max(0, Double(secondsLeft) / 3600)
    }

    /// A spot's events in the order its bubble and card show them: the ones on now (earliest
    /// start first), then the ones still to start (soonest first), then untimed ones. Ended
    /// events drop off. The first is the one the bubble shows.
    static func order(_ events: [FeedCardItem], now: Date) -> [FeedCardItem] {
        func rank(_ p: Phase) -> Int? {
            switch p {
            case .live: 0
            case .upcoming: 1
            case .untimed: 2
            case .ended: nil
            }
        }
        return events
            .compactMap { e in rank(phase(e, now: now)).map { (e, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : starts($0.0) < starts($1.0) }
            .map(\.0)
    }

    /// The bead's width at a zoom, in points: 46 at the opening zoom, growing two zoom steps
    /// in to 72 and shrinking 1.6 steps out to 36, and holding past either end.
    static func bead(zoom: Double) -> CGFloat {
        let open = SJMapView.openZoom
        if zoom >= open { return min(72, 46 + CGFloat(zoom - open) * 13) }
        return max(36, 46 - CGFloat(open - zoom) * 6.25)
    }

    /// Rubber-band pull: follows the finger at first, then resists. A 40 pt drag moves it about
    /// 11 pt, a 100 pt drag 16 pt (Jesse's tuned mock, 2026-10-22: "move half as much").
    static func rubber(_ distance: CGFloat, dimension: CGFloat = 23, constant: CGFloat = 0.55) -> CGFloat {
        (distance * dimension * constant) / (dimension + constant * abs(distance))
    }

    /// How far the bubble stretches along the pull, from how far it's pulled and how fast.
    static func stretch(distance: CGFloat, speed: CGFloat) -> CGFloat {
        min(0.13, distance / 110 + speed / 5200)
    }

}

// MARK: - Clock

enum TodayBubbleClock {
    /// Now. In DEBUG, `-map-now HH:MM` pins the map's clock there at launch and lets it
    /// tick on, so recordings can show a live bubble and a countdown at any hour.
    static func now(_ real: Date = Date()) -> Date { real.addingTimeInterval(offset) }

    private static let offset: TimeInterval = {
        #if DEBUG
        guard let now = LaunchFlags.value(.mapNow) else { return 0 }
        let parts = now.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return 0 }
        let target = parts[0] * 3600 + parts[1] * 60
        return Town.gregorian.startOfDay(for: Date()).addingTimeInterval(TimeInterval(target)).timeIntervalSinceNow
        #else
        return 0
        #endif
    }()
}

// MARK: - Model

struct TodayBubble: Identifiable {
    let id: String              // its spot, "lat,lng"
    let coordinate: CLLocationCoordinate2D
    /// Every event here not yet over, in `TodayBubbleRules.order`; never empty.
    var events: [FeedCardItem]
    /// Its place in the opening pop-in, earliest start first.
    var order = 0

    /// The one the bubble shows.
    var event: FeedCardItem { events[0] }

    /// Its picture, as the card's first photo: the event's own, else its place's photo, else
    /// its place's logo (`isLogo` sits a logo inside the glass).
    var picture: (url: URL, isLogo: Bool)? {
        switch event.photos().first {
        case .eventPhoto(let url), .placePhoto(let url, _, _): (url, false)
        case .placeLogo(let logo): (logo.url, true)
        case .fallback, nil: nil
        }
    }
}

/// The map's zoom as the bubbles size themselves by it, kept out of the map view so a pinch
/// redraws only the bubbles (as `CompassHeading` keeps the bearing to the compass).
@Observable
final class MapZoom {
    private(set) var bead: CGFloat = 46

    func update(_ zoom: Double) {
        let new = TodayBubbleRules.bead(zoom: zoom)
        if abs(new - bead) >= 0.25 { bead = new }
    }
}

// MARK: - The bubble

struct TodayEventBubble: View {
    let bubble: TodayBubble
    let zoom: MapZoom
    var selected = false
    let onTap: () -> Void

    @ObservedObject private var images = POILogoCache.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var shown = false
    @State private var pull: CGSize = .zero
    @State private var stretch: CGFloat = 0
    @State private var pressed = false
    @State private var dragStart: Date?

    private static let bead: CGFloat = 46
    private static let ring: CGFloat = 53
    private static let breath: Double = 2.4       // seconds per breath (Jesse's pick on the mock)
    private static let swell: CGFloat = 0.04      // 4% bigger at the peak

    var body: some View {
        // Drawn at 46 pt and scaled as a whole, so a pinch never redraws the photo's dome.
        let scale = zoom.bead / Self.bead * (selected ? 1.12 : 1)
        TimelineView(.periodic(from: .now, by: tickSeconds)) { tick in
            let phase = TodayBubbleRules.phase(bubble.event, now: TodayBubbleClock.now(tick.date))
            ZStack {
                ZStack {
                    if phase == .live { LiveBleed(bead: Self.bead, period: Self.breath, still: reduceMotion) }
                    breathing(phase == .live, gel(phase, scale: scale))
                }
                .scaleEffect(scale)
                tag(phase)
                    .offset(y: Self.bead * scale / 2 + 20)
            }
            // Room for the shadow bleed to spread (2.1x the bead) without being clipped
            // by the annotation's frame; only the bead itself takes touches.
            .frame(width: 104 * scale, height: 104 * scale)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.65), value: selected)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(a11yLabel(phase))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap() }
        }
        .scaleEffect(shown ? 1 : 0.01)
        .onAppear {
            let pop = reduceMotion ? Motion.smooth : Animation.spring(response: 0.34, dampingFraction: 0.6)
            withAnimation(pop.delay(0.65 + Double(bubble.order) * 0.11)) { shown = true }
        }
    }

    /// The countdown only shows seconds in the last hour (and the ring only moves then),
    /// so before that the bubble redraws once a minute, not every second.
    private var tickSeconds: TimeInterval {
        if case .upcoming(let left) = TodayBubbleRules.phase(bubble.event, now: TodayBubbleClock.now()),
           left > 3600 + 60 { return 60 }
        return 1
    }

    // MARK: Parts

    /// The bead: a Liquid Glass disc with the photo on it, bent like a dome and fading
    /// into the clear glass at the rim, squished and stretched by the finger.
    private func gel(_ phase: TodayBubbleRules.Phase, scale: CGFloat) -> some View {
        let angle = Angle(radians: atan2(pull.height, pull.width))
        // At least 44 pt to the finger however small the zoom draws it.
        let target = max(Self.bead * 1.2, 44 / scale)
        let base: CGFloat = pressed ? 0.95 : 1
        return ZStack {
            Circle()
                .fill(MapBubbleInk.ink.opacity(0.30))
                .frame(width: Self.bead - 6, height: Self.bead - 6)
                .blur(radius: 7)
                .offset(y: 5)
            ring(phase)
            photo
                .frame(width: Self.bead, height: Self.bead)
                // Plain, not .interactive(): the interactive glass swells and whitens under
                // the finger on top of our own squish, which washed the photo out (frames
                // 2026-10-22). The squish below is the touch response Jesse tuned.
                .glassEffect(.regular, in: Circle())
                // The glass never takes the touch itself: when it did, iOS lit it up and
                // swelled it white over the photo and the ring (frames 2026-10-22). The
                // clear disc on top takes the drag instead.
                .allowsHitTesting(false)
            Circle()
                .fill(.clear)
                .frame(width: target, height: target)
                .contentShape(Circle())
                .gesture(squish)
        }
        .frame(width: 64, height: 64)
        // One affine matrix (stretch along the pull, thin across it) rather than rotate,
        // scale, rotate back: the glass layer took the scale but not the rotations, so it
        // stretched sideways while the photo stretched along the pull (frames 2026-10-22).
        .transformEffect(Self.stretchMatrix(angle: angle.radians, along: base * (1 + stretch),
                                            across: base / (1 + stretch), size: 64))
        .offset(pull)
    }

    /// Scale by `along` in the pull's direction and `across` at right angles, about the
    /// centre of a `size` square view.
    static func stretchMatrix(angle: Double, along: CGFloat, across: CGFloat, size: CGFloat) -> CGAffineTransform {
        let c = CGFloat(cos(angle)), s = CGFloat(sin(angle)), h = size / 2
        let m = CGAffineTransform(a: along * c * c + across * s * s, b: (along - across) * c * s,
                                  c: (along - across) * c * s, d: along * s * s + across * c * c,
                                  tx: 0, ty: 0)
        return CGAffineTransform(translationX: -h, y: -h).concatenating(m).concatenating(CGAffineTransform(translationX: h, y: h))
    }

    @ViewBuilder
    private var photo: some View {
        let picture = bubble.picture
        let image = picture.flatMap { images.image(for: $0.url) }
        let isLogo = picture?.isLogo ?? false
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: isLogo ? .fit : .fill)
                    .padding(isLogo ? 7 : 0)
                    .frame(width: Self.bead, height: Self.bead)
                    .visualEffect { content, proxy in
                        content.distortionEffect(
                            ShaderLibrary.bpDome(.float2(proxy.size)),
                            maxSampleOffset: CGSize(width: proxy.size.width * 0.2, height: proxy.size.height * 0.2)
                        )
                    }
                // The sides fall away a little, so the middle reads nearest.
                RadialGradient(stops: [
                    .init(color: .clear, location: 0.50),
                    .init(color: MapBubbleInk.ink.opacity(0.18), location: 0.78),
                    .init(color: MapBubbleInk.ink.opacity(0.26), location: 1),
                ], center: UnitPoint(x: 0.5, y: 0.55), startRadius: 0, endRadius: Self.bead / 2)
            } else {
                Image(systemName: (bubble.event.category ?? .other).glyph)
                    .font(.sans(17).weight(.semibold))
                    .foregroundStyle(MapBubbleInk.ink)
            }
        }
        .frame(width: Self.bead, height: Self.bead)
        // Solid in the middle, fading into the clear glass near the rim.
        .mask(RadialGradient(stops: [
            .init(color: .black, location: 0.70),
            .init(color: .black.opacity(0.5), location: 0.82),
            .init(color: .clear, location: 0.92),
        ], center: .center, startRadius: 0, endRadius: Self.bead / 2))
    }

    @ViewBuilder
    private func ring(_ phase: TodayBubbleRules.Phase) -> some View {
        if case .upcoming(let left) = phase, let rest = TodayBubbleRules.ringLeft(left) {
            ZStack {
                Circle().stroke(MapBubbleInk.ink.opacity(0.07), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: rest)
                    .stroke(MapBubbleInk.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.9), value: rest)
            }
            .frame(width: Self.ring, height: Self.ring)
        }
    }

    @ViewBuilder
    private func tag(_ phase: TodayBubbleRules.Phase) -> some View {
        switch phase {
        case .live:
            HStack(spacing: 5) {
                Circle().fill(Hue.now).frame(width: 7, height: 7)
                Text("Now")
            }
            .modifier(BubbleTag())
        case .upcoming(let left):
            Text(TodayBubbleRules.countdown(left))
                .monospacedDigit()
                .modifier(BubbleTag())
        case .untimed, .ended:
            EmptyView()
        }
    }

    /// The slow breath while it's on: 1 → 1.04 → 1 every 2.4 s, eased like a sine.
    @ViewBuilder
    private func breathing<C: View>(_ on: Bool, _ content: C) -> some View {
        if on && !reduceMotion {
            TimelineView(.animation) { t in
                let p = t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.breath) / Self.breath
                content.scaleEffect(1 + Self.swell * CGFloat((1 - cos(2 * .pi * p)) / 2))
            }
        } else {
            content
        }
    }

    // MARK: Touch

    /// Any direction: the bubble follows the finger with rubber-band resistance, stretches
    /// along the pull and thins across it, then springs home with the release speed and one
    /// small wobble. A touch that barely moves is a tap.
    private var squish: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if dragStart == nil {
                    dragStart = Date()
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.8)) { pressed = true }
                }
                let raw = v.translation
                let d = hypot(raw.width, raw.height)
                let f = d > 0 ? TodayBubbleRules.rubber(d) / d : 0
                let speed = hypot(v.velocity.width, v.velocity.height)
                pull = CGSize(width: raw.width * f, height: raw.height * f)
                stretch = TodayBubbleRules.stretch(distance: hypot(pull.width, pull.height), speed: speed)
            }
            .onEnded { v in
                let moved = hypot(v.translation.width, v.translation.height)
                dragStart = nil
                // Stiffness 300, damping 15: home in about half a second with one small overshoot.
                withAnimation(.interpolatingSpring(stiffness: 300, damping: 15)) {
                    pull = .zero
                    stretch = 0
                    pressed = false
                }
                if moved < 6 { onTap() }
            }
    }

    private func a11yLabel(_ phase: TodayBubbleRules.Phase) -> String {
        let more = bubble.events.count > 1 ? ", and \(bubble.events.count - 1) more here" : ""
        switch phase {
        case .live: return "\(bubble.event.title), happening now\(more)"
        case .upcoming(let left): return "\(bubble.event.title), starts in \(TodayBubbleRules.spokenCountdown(left))\(more)"
        default: return bubble.event.title + more
        }
    }
}

/// A dark shadow bleeding out from under a live bubble once per breath, fading as it spreads.
private struct LiveBleed: View {
    let bead: CGFloat
    let period: Double
    let still: Bool

    var body: some View {
        if still {
            disc.opacity(0.25)
        } else {
            TimelineView(.animation) { t in
                let p = t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                let e = Self.ease(p)
                disc.scaleEffect(0.95 + 1.15 * e).opacity(0.9 * (1 - e))
            }
        }
    }

    private var disc: some View {
        Circle()
            .fill(RadialGradient(stops: [
                .init(color: MapBubbleInk.ink.opacity(0.6), location: 0.55),    // 1.5x the mock's 0.42:
                .init(color: MapBubbleInk.ink.opacity(0.26), location: 0.78),   // faint on tan (Jesse, Check-in 2)
                .init(color: .clear, location: 1),
            ], center: .center, startRadius: 0, endRadius: bead / 2))
            .frame(width: bead, height: bead)
            .allowsHitTesting(false)
    }

    /// The mock's cubic-bezier(.2, .6, .35, 1): quick out, long soft tail.
    static func ease(_ p: Double) -> Double {
        UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.2, y: 0.6),
                         endControlPoint: UnitPoint(x: 0.35, y: 1)).value(at: p)
    }
}

/// The time tag under a bubble: a small glass capsule, ink text.
private struct BubbleTag: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.sans(13).weight(.bold))
            .foregroundStyle(MapBubbleInk.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .glassEffect(.regular, in: Capsule())
            .fixedSize()
            .allowsHitTesting(false)
    }
}

/// The map is drawn light in both appearances, so the bubble's ink is the light-canvas ink.
private enum MapBubbleInk {
    static let ink = Hue.ink.onLightCanvas
}
