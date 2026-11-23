//
//  TodayBubbles.swift
//  Block Party — today's events on the map as glass-ringed photo bubbles.
//
//  Jesse's map-today idea (2026-10-22; References and the approved mock in BP app
//  `references/map-today/`, pulse.html). One bubble per place with an event today:
//  the event's photo, else the place's photo, else its logo. Since map-glass-ring
//  (2026-11-17, BP app `references/map-glass-ring/`, SPEC.md) it is the iPhone Camera's
//  record button: a ring of Apple's Liquid Glass, dark like the Camera's, with the photo
//  flat in the middle (0.845 of the button, Jesse's screenshot measured), and the ring
//  turns the Now dot's green while the event is on. In the last hour before its start a
//  bubble counts down and a black ring empties around it; further out it is the plain grey
//  ring, no tag (Jesse, 2026-11-17). While an event is on (EventWhen.isOn), the
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
//  Friends on the map (BP app five-tabs 08, 2026-11-05): friends Going to an Event here today
//  sit on the bubble's top right, up to two faces and then how many more, never anyone's
//  location. The faces keep their size as the bubble grows, as the time tag does.
//
//  An Event its page asked for, of another day (BP app inside-cards 19): its tag says the day,
//  "Thu, Nov 19", or "Until Dec 15" while one that began before today is still on, never a
//  countdown, and it's first to pop in.
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
        // On, but a place being open rather than a real happening (town-feed 41): no live ring.
        if when.isOn(now) { return event.liveKind ? .live : .untimed }
        return .ended
    }

    /// Its start, for ordering; untimed ones last.
    static func starts(_ event: FeedCardItem) -> Date {
        event.when.flatMap { $0.timed ? $0.start : nil } ?? .distantFuture
    }

    /// The last hour before a start, in seconds: the only time a bubble counts down, with its ring
    /// (Jesse, 2026-11-17: "only do the countdown when it's under 1 hour").
    static let lastHour = 3600

    /// "8:05" in the last hour, as its ring empties; nil further out, where the bubble is its
    /// plain grey ring.
    static func countdown(_ secondsLeft: Int) -> String? {
        guard secondsLeft < lastHour else { return nil }
        let s = max(0, secondsLeft)
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
        guard secondsLeft < lastHour else { return nil }
        return max(0, Double(secondsLeft) / Double(lastHour))
    }

    /// A bubble's next redraw after `date`: once a minute until `fast`, the start of its last hour
    /// (landing on it exactly), then every second, as the countdown shows seconds only then.
    static func nextTick(after date: Date, fast: Date) -> Date {
        date < fast ? min(date.addingTimeInterval(60), fast) : date.addingTimeInterval(1)
    }

    /// A spot's events in the order its bubble and card show them: the ones on now (earliest
    /// start first), then the ones still to start (soonest first), then untimed ones. Ended
    /// events drop off. The first is the one the bubble shows. `first`, the Event an Event page
    /// asked for (inside-cards 19), leads whatever its day, over or called off.
    static func order(_ events: [FeedCardItem], now: Date, first: String? = nil) -> [FeedCardItem] {
        func rank(_ p: Phase) -> Int? {
            switch p {
            case .live: 0
            case .upcoming: 1
            case .untimed: 2
            case .ended: nil
            }
        }
        return events
            .compactMap { e in (e.id == first ? -1 : rank(phase(e, now: now))).map { (e, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : starts($0.0) < starts($1.0) }
            .map(\.0)
    }

    /// The tag under another day's bubble (inside-cards 19): "Tomorrow", "Thu, Nov 19", or "Until Dec 15"
    /// while one that began before today is still on; never a countdown. nil for today's, which count down.
    static func dayTag(_ event: FeedCardItem, now: Date) -> String? {
        guard let when = event.when, Town.days(from: now, to: when.start) != 0 else { return nil }
        if when.stillOnFromBefore(now) { return "Until \(when.until(now))" }
        return when.dayWord(now) ?? Town.format(when.start, "EEEMMMd")
    }

    /// Everyone Going to any of a spot's events, each once, in the card's order. The Town feed
    /// already leaves out a friend with "Show my plans to friends" off. One event's friends are
    /// all different people, even two Sams with no photo; across events only a name and photo say so.
    static func friends(_ events: [FeedCardItem]) -> [FeedFriend] {
        if events.count == 1 { return events[0].friendsGoing }
        var seen = Set<FeedFriend>()
        return events.flatMap(\.friendsGoing).filter { seen.insert($0).inserted }
    }

    /// The page a bubble's card opens on: the first event friends are Going to, else the first.
    static func firstPage(_ events: [FeedCardItem]) -> Int {
        events.firstIndex { !$0.friendsGoing.isEmpty } ?? 0
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
    /// tick on, so recordings can show a live bubble and a countdown at any hour; `HH:MM+1`
    /// is that time a day on, for tomorrow's real Events when today's are over.
    static func now(_ real: Date = Date()) -> Date { real.addingTimeInterval(offset) }

    private static let offset: TimeInterval = {
        #if DEBUG
        guard let now = LaunchFlags.value(.mapNow) else { return 0 }
        let day = now.split(separator: "+")
        let parts = (day.first ?? "").split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return 0 }
        let target = (day.count == 2 ? Int(day[1]) ?? 0 : 0) * 86_400 + parts[0] * 3600 + parts[1] * 60
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
        case .eventPhoto(let url), .placePhoto(let url, _, _, _): (url, false)
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
    /// The photo's share of the button: the record button's red, 0.845 of it (BP app
    /// references/map-glass-ring/SPEC.md), so the glass ring is 3.5 pt wide at 46.
    private static let window: CGFloat = 0.845
    private static let ring: CGFloat = 53
    private static let breath: Double = 2.4       // seconds per breath (Jesse's pick on the mock)
    private static let swell: CGFloat = 0.04      // 4% bigger at the peak

    var body: some View {
        // Drawn at 46 pt and scaled as a whole, so a pinch never redraws the photo.
        let scale = zoom.bead / Self.bead * (selected ? 1.12 : 1)
        let friends = TodayBubbleRules.friends(bubble.events)
        // Where the bubble's rim crosses its top right, at 45 degrees.
        let rim = Self.bead * scale / 2 * 0.7071
        // Room for the shadow bleed to spread (2.1x the bead) and the faces to reach past the rim
        // without being clipped by the annotation's frame; only the bead and faces take touches.
        let room = max(104 * scale, friends.isEmpty ? 0 : 2 * (rim + BubbleFaces.reach))
        TimelineView(BubbleTicks(fast: fastFrom)) { tick in
            let now = TodayBubbleClock.now(tick.date)
            let phase = TodayBubbleRules.phase(bubble.event, now: now)
            // Another day's Event, its page's ask (inside-cards 19): its day, unless it's on now.
            let day = phase == .live ? nil : TodayBubbleRules.dayTag(bubble.event, now: now)
            ZStack {
                ZStack {
                    if phase == .live { LiveBleed(bead: Self.bead, period: Self.breath, still: reduceMotion) }
                    breathing(phase == .live, gel(phase, scale: scale))
                }
                .scaleEffect(scale)
                tag(phase, day: day)
                    .offset(y: Self.bead * scale / 2 + 20)
                if !friends.isEmpty {
                    BubbleFaces(friends: friends)
                        // A touch on a face is a touch on the bubble.
                        .gesture(squish)
                        // They follow a drag with the bubble (`pull` is in the bubble's own points).
                        .offset(x: rim + pull.width * scale, y: -rim + pull.height * scale)
                }
            }
            .frame(width: room, height: room)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.65), value: selected)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(a11yLabel(phase, day: day, friends: friends))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap() }
        }
        .scaleEffect(shown ? 1 : 0.01)
        .onAppear {
            let pop = reduceMotion ? Motion.smooth : Animation.spring(response: 0.34, dampingFraction: 0.6)
            withAnimation(pop.delay(0.65 + Double(bubble.order) * 0.11)) { shown = true }
        }
    }

    /// When the bubble starts redrawing every second: the start of its last hour (the countdown
    /// shows seconds only then, and the ring only moves then); on, untimed or over, now. Before
    /// that it redraws once a minute (`BubbleTicks`).
    private var fastFrom: Date {
        let real = Date()
        guard case .upcoming(let left) = TodayBubbleRules.phase(bubble.event, now: TodayBubbleClock.now(real))
        else { return real }
        return real.addingTimeInterval(TimeInterval(left - TodayBubbleRules.lastHour))
    }

    // MARK: Parts

    /// The bead: the Camera's record button, a Liquid Glass disc with the photo set flat in
    /// its middle so the glass shows only as the ring, squished and stretched by the finger.
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
                // Dark like the Camera's, and the Now dot's green while it's on (Jesse, 2026-11-17).
                // It turns at the start, with the tag's Now: the glass's tint doesn't animate (frames 2026-11-17).
                .glassEffect(.regular.tint(phase == .live ? MapBubbleInk.live : MapBubbleInk.glass), in: Circle())
                // The simulator's glass draws no edge light; the Camera's ring has one (frames 2026-11-17).
                .overlay { RecordRim() }
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
        let side = Self.bead * Self.window
        ZStack {
            if let image, !isLogo {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: side, height: side)
            } else {
                // A logo, or no picture at all, sits on white, as on the Camera's button the red does.
                Circle().fill(MapBubbleInk.paper)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(4)
                } else {
                    Image(systemName: (bubble.event.category ?? .other).glyph)
                        .font(.sans(17).weight(.semibold))
                        .foregroundStyle(MapBubbleInk.ink)
                }
            }
        }
        .frame(width: side, height: side)
        // Cut clean, as the record button's red: no fade, no bend.
        .clipShape(Circle())
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
    private func tag(_ phase: TodayBubbleRules.Phase, day: String?) -> some View {
        if let day {
            Text(day).modifier(BubbleTag())
        } else {
            switch phase {
            case .live:
                HStack(spacing: 5) {
                    Circle().fill(Hue.now).frame(width: 7, height: 7)
                    Text("Now")
                }
                .modifier(BubbleTag())
            case .upcoming(let left):
                if let countdown = TodayBubbleRules.countdown(left) {
                    Text(countdown)
                        .monospacedDigit()
                        .modifier(BubbleTag())
                }
            case .untimed, .ended:
                EmptyView()
            }
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

    private func a11yLabel(_ phase: TodayBubbleRules.Phase, day: String?, friends going: [FeedFriend]) -> String {
        let more = bubble.events.count > 1 ? ", and \(bubble.events.count - 1) more here" : ""
        // "here": they may be Going to another of the spot's events than the one just named.
        let friends = RSVPWords.friendsLine(going.map(\.name), bar: false).map { ", \($0) here" } ?? ""
        if let day { return "\(bubble.event.title), \(day)\(more)\(friends)" }
        switch phase {
        case .live: return "\(bubble.event.title), happening now\(more)\(friends)"
        case .upcoming(let left): return "\(bubble.event.title), starts in \(TodayBubbleRules.spokenCountdown(left))\(more)\(friends)"
        default: return bubble.event.title + more + friends
        }
    }
}

/// Friends Going, on a bubble's rim: up to two faces, then a white "+3". 20 pt, each tucked a third
/// under the one before as `FriendFaces` does, the first face centred on the spot it's offset to
/// (Jesse at five-tabs 08's Check-in 1, 2026-11-05: BP app references/friends-on-map).
private struct BubbleFaces: View {
    let friends: [FeedFriend]

    private static let side: CGFloat = 20
    private static let tuck: CGFloat = side * FriendFaces.overlap / FriendFaces.side
    /// How far the widest stack can reach from its first face's centre: "+99" included.
    static let reach: CGFloat = side / 2 + (side - tuck) + 40

    var body: some View {
        HStack(spacing: -Self.tuck) {
            ForEach(Array(friends.prefix(2).enumerated()), id: \.offset) { index, friend in
                Avatar(friend.photo, size: Self.side)
                    .background { FaceShape().fill(.white).padding(-1.5) }
                    .zIndex(Double(3 - index))
            }
            if friends.count > 2 {
                Text("+\(friends.count - 2)")
                    .font(.sansBold(11))
                    .monospacedDigit()
                    .foregroundStyle(MapBubbleInk.ink)
                    .padding(.leading, Self.tuck + 3)
                    .padding(.trailing, 5)
                    .frame(minWidth: Self.side, minHeight: Self.side)
                    .background { Capsule().fill(.white) }
            }
        }
        .compositingGroup()
        .shadow(color: MapBubbleInk.ink.opacity(0.3), radius: 1.5, x: 0, y: 1)
        .fixedSize()
        .contentShape(Capsule())
        .frame(width: Self.side, height: Self.side, alignment: .leading)
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

/// A bubble's redraws: once a minute until `fast`, then every second (`TodayBubbleRules.nextTick`).
/// Fixed times, so a bubble crossing into its last hour counts seconds even if nothing redraws it.
private struct BubbleTicks: TimelineSchedule {
    let fast: Date

    func entries(from start: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        var next = start
        return AnyIterator {
            defer { next = TodayBubbleRules.nextTick(after: next, fast: fast) }
            return next
        }
    }
}

/// The record button's edge: a thin light on the outer rim, bright top and bottom and faint at the
/// sides, and a hairline just outside it, as measured off Jesse's Camera screenshot (BP app
/// references/map-glass-ring/SPEC.md: the light's strength every 30 degrees from the top).
private struct RecordRim: View {
    private static let light: [Double] = [0.72, 0.42, 0.2, 0.05, 0.08, 0.36, 0.72, 0.33, 0.06, 0.05, 0.2, 0.42, 0.72]

    var body: some View {
        ZStack {
            Circle().strokeBorder(
                AngularGradient(stops: Self.light.enumerated().map { i, a in
                    .init(color: MapBubbleInk.paper.opacity(a), location: Double(i) / 12)
                }, center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                lineWidth: 1)
            Circle().stroke(MapBubbleInk.ink.opacity(0.45), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
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
    /// The record button's dark glass ring (BP app references/map-glass-ring).
    static let glass = Hue.ink.onLightCanvas.opacity(0.66)
    /// The ring while the event is on: the Now dot's green (Jesse, 2026-11-17).
    static let live = Hue.now.onLightCanvas.opacity(0.85)
    /// Under a logo, or a bubble with no picture.
    static let paper = Hue.surface.onLightCanvas
}
