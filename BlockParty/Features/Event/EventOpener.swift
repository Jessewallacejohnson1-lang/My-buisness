//
//  EventOpener.swift
//  Block Party — a Town card's Event page, opened our own way (BP app tab-lag 02, round 5, plan B).
//
//  A push on the shell's stack started to move about 100 ms after the tap on an iPhone 16 Pro: SwiftUI built
//  the whole page before UIKit's slide began, and the slide itself cost 40 to 55 ms more. Here the page is drawn
//  over the shell, inside the stack's root, so its rows still push their pages over it and the map still rises
//  over it. The card's photo grows into the page's top picture and the page rides its foot, as a Place page
//  opens from a card (`BusinessOpener`, BP app place-photos 10; Jesse at round 5's Check-in 1: "yes to all").
//  A card with no photo to grow (a white card, a flyer, a game, a logo) grows its own box into the page.
//  Back, a pull down on the band under the clock while the page is at its top, and a swipe from the left edge
//  send it home into its card, following the finger. Everything runs off one `LiveSpring`, so a finger can take
//  it over mid-flight. Only the Town feed's cards open this way; every other list still pushes the page.
//

import SwiftUI
import UIKit

/// Which Event is open over Town, the card it came from, and how far open it is.
@MainActor @Observable
final class EventOpener {
    struct Source {
        /// The card's face on screen, in the window's points.
        var box: CGRect
        /// The photo the card showed, grown into the page's top picture; nil grows the box itself.
        var photo: URL?
    }

    private(set) var item: FeedCardItem?
    private(set) var source = Source(box: .zero)
    /// Where it is headed: open, or home.
    private(set) var isOpen = false
    /// On screen, from the open until it is home: false while it is only built. Set once each way, so the cards that
    /// read it never redraw with the spring.
    private(set) var shown = false
    let progress = LiveSpring(0)
    @ObservationIgnored var reduceMotion = false
    /// Counted as an open, for popularity, as the pushed page's onAppear did (`RootView`).
    @ObservationIgnored var counted: (String) -> Void = { _ in }

    /// The finger lifted off a card's photo: the page is built now, hidden, while the photo waits 0.2 s for a second
    /// tap (`PhotoDoubleTap.window`), so the open has nothing left to build. A like, or no open at all, throws it away.
    func prepare(_ item: FeedCardItem, from source: Source) {
        guard !isOpen, progress.value == 0 else { return }
        self.item = item
        self.source = source
        LeftOff.pageY[item.id] = 0
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(PhotoDoubleTap.window + 0.6))
            self?.discard(item.id)
        }
    }

    /// The page built for a tap that turned out to be a like, or that never opened.
    func discard(_ id: String) {
        guard !isOpen, item?.id == id, progress.value == 0 else { return }
        item = nil
    }

    func open(_ item: FeedCardItem, from source: Source) {
        // A new page starts at its top: the last open's scroll would fly the photo above the screen.
        if self.item?.id != item.id { LeftOff.pageY[item.id] = 0 }
        self.item = item
        self.source = source
        isOpen = true
        shown = true
        counted(item.id)
        progress.animate(to: 1, response: SearchMetric.openResponse, damping: SearchMetric.openDamping, instant: reduceMotion,
                         completion: mostlyOpen)
    }

    /// Home, from wherever it is. `velocity` is the finger's, in progress per second.
    func close(velocity: CGFloat? = nil) {
        guard item != nil else { return }
        isOpen = false
        AppearanceStore.shared.eventOver = false
        progress.animate(to: 0, response: SearchMetric.closeResponse, damping: 1, velocity: velocity,
                         instant: reduceMotion) { [weak self] in
            guard let self, !self.isOpen else { return }
            item = nil
            shown = false
        }
    }

    /// Gone at once: the tab changed or the stack was reset under it.
    func closeNow() {
        guard item != nil else { return }
        isOpen = false
        progress.set(0)
        item = nil
        shown = false
        AppearanceStore.shared.eventOver = false
    }

    /// A drag let go short of closing: back open, carrying the finger's speed.
    func settleOpen(velocity: CGFloat) {
        isOpen = true
        progress.animate(to: 1, response: SearchMetric.settleResponse, damping: SearchMetric.settleDamping,
                         velocity: velocity, instant: reduceMotion, completion: mostlyOpen)
    }

    /// Most of the way open, the page's clock is its own: white over its picture, as a pushed page's turned during its
    /// slide. Not at the tap: the whole app redraws for a new scheme.
    func mostlyOpen() {
        if isOpen { AppearanceStore.shared.eventOver = true }
    }


    /// Its page is open, or on its way in or home: the card is covered, as by a pushed page.
    func isAway(_ id: String) -> Bool { item?.id == id }

    /// The card's photo is the one flying, so the card's own hides: only ever one photo. A card that grows its box
    /// stays, so the page fades into it and out of it with no empty slot.
    /// Not while the page is only built, during the double-tap wait: the card stays whole until its photo moves, and
    /// a like never touches it.
    func hidesCard(_ id: String) -> Bool { isAway(id) && source.photo != nil && shown }

    /// Where the flying picture is at `progress`: from the card's box to the page's top picture, scrolled up by
    /// `scrollY`. Not clamped, so the open's overshoot grows it a touch past its spot and back.
    static func flight(from box: CGRect, to hero: CGRect, scrollY: CGFloat, progress p: CGFloat) -> CGRect {
        let to = hero.offsetBy(dx: 0, dy: -max(0, scrollY))
        return CGRect(x: box.minX + (to.minX - box.minX) * p, y: box.minY + (to.minY - box.minY) * p,
                      width: box.width + (to.width - box.width) * p, height: box.height + (to.height - box.height) * p)
    }

    /// How far open the page takes the clock from Town.
    static let clockTurns: CGFloat = 0.6

    /// The page under the flying photo, from a third of the way in, whole at 85%.
    static func pageOpacity(_ p: CGFloat) -> Double {
        p >= 1 ? 1 : Double(min(max((p - 0.35) / 0.5, 0), 1))
    }

    /// The flying photo hands over to the page's own picture over the last quarter of the way, so the page's melt
    /// and its sharper bitmap never pop in.
    static func photoOpacity(_ p: CGFloat) -> Double {
        Double(min(max((1 - p) / 0.25, 0), 1))
    }
}

extension EnvironmentValues {
    /// The Town feed's opener: set on Town only, where a card opens its page over the shell.
    @Entry var eventOpener: EventOpener? = nil
    /// Back on an Event page opened over the shell, in place of the stack's dismiss.
    @Entry var eventPageClose: EventOpener? = nil
    /// False while an Event page is built hidden during a tap's double-tap wait: nothing on it runs until it opens.
    @Entry var eventPageShown = true
}

/// The open Event over the shell. Draws nothing while nothing is open. The page lays out as a pushed page did, in the
/// safe area with its picture running up under the clock, so its buttons and bar sit where they always have; the
/// flight works in the window's points.
struct EventOverlay: View {
    let opener: EventOpener
    /// The whole screen, and the safe area the page lays out in, in the window's points.
    @State private var screen = CGRect.zero
    @State private var safe = CGRect.zero

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let item = opener.item {
                EventOverlayBody(item: item, source: opener.source, opener: opener, screen: screen, safe: safe)
                    .id(item.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { safe = $0 }
        .background {
            Color.clear
                .ignoresSafeArea()
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { screen = $0 }
        }
    }
}

private struct EventOverlayBody: View {
    let item: FeedCardItem
    let source: EventOpener.Source
    let opener: EventOpener
    let screen: CGRect
    let safe: CGRect

    var body: some View {
        EventFlight(item: item, box: source.box, screen: screen, safe: safe, photo: source.photo, opener: opener)
            .gesture(EventClosePan(opener: opener, item: item.id,
                                   band: screen.minY + EventLook.photoHeight * screen.width / EventLook.mockWidth))
            .gesture(EventEdgePan(opener: opener, width: screen.width))
            .ignoresSafeArea(.keyboard)
            .allowsHitTesting(opener.isOpen)
            // VoiceOver stays on the Event, not Town under it; its two-finger scrub sends the page home.
            .accessibilityAddTraits(opener.isOpen ? .isModal : [])
            .accessibilityHidden(!opener.isOpen)
            .environment(\.eventPageShown, opener.isOpen)
            .accessibilityAction(.escape) { opener.close() }
    }
}

/// The page and the picture flying into it, in the window's points. Only this view reads the spring, so its frames
/// redraw the frame and the transform, never the page's own body.
private struct EventFlight: View {
    let item: FeedCardItem
    let box: CGRect
    let screen: CGRect
    let safe: CGRect
    let photo: URL?
    let opener: EventOpener

    var body: some View {
        let p = opener.progress.value
        let c = min(max(p, 0), 1)
        let flying = p != 1
        let scrollY = max(0, LeftOff.pageY[item.id] ?? 0)
        // An Event's page draws from the screen's top (its picture under the clock); a game's from the safe area's.
        let origin = item.game == nil ? screen.origin : safe.origin
        let hero = CGRect(x: screen.minX, y: screen.minY, width: screen.width,
                          height: EventLook.photoHeight * screen.width / EventLook.mockWidth)
        let f = EventOpener.flight(from: box, to: hero, scrollY: scrollY, progress: p)
        let k = flying ? f.width / max(screen.width, 1) : 1
        Group {
            if let photo {
                // The page rides the photo's foot, shrunk to its width; the photo flies over it.
                page
                    .scaleEffect(k, anchor: .topLeading)
                    .offset(x: flying ? f.minX - origin.x : 0,
                            y: flying ? f.maxY - origin.y - k * (hero.maxY - scrollY - origin.y) : 0)
                    .opacity(EventOpener.pageOpacity(p))
                    .overlay(alignment: .topLeading) {
                        if flying {
                            Color.clear
                                .ignoresSafeArea()
                                .overlay(alignment: .topLeading) {
                                    FlyingPhoto(url: photo, frame: f.offsetBy(dx: -screen.minX, dy: -screen.minY),
                                                radius: mix(Radius.card, 0, c), opacity: EventOpener.photoOpacity(p))
                                }
                        }
                    }
            } else {
                // No photo to grow: the card's box grows into the screen, the page shrunk to its width inside it,
                // fading in over the card.
                let r = mix(box, screen, c)
                let s = r.width / max(screen.width, 1)
                page
                    .scaleEffect(s, anchor: .topLeading)
                    .offset(x: r.minX - origin.x, y: r.minY - origin.y)
                    .clipShape(RoundedClip(rect: r.offsetBy(dx: -origin.x, dy: -origin.y), radius: mix(Radius.card, 0, c)))
                    .opacity(min(1, Double(c) * 4))
            }
        }
        .onChange(of: p > 0) { _, moved in
            #if DEBUG
            if moved, FrameGapLog.enabled { FrameGapLog.shared.moved("event") }
            #endif
        }
        .onChange(of: p > EventOpener.clockTurns) { _, past in if past { opener.mostlyOpen() } }
    }

    private var page: some View {
        EventPageHost(item: item).equatable()
    }
}

/// The page itself, its body built once per open: nothing here reads the spring.
private struct EventPageHost: View, Equatable {
    let item: FeedCardItem
    static func == (a: Self, b: Self) -> Bool { a.item.id == b.item.id }

    var body: some View {
        EventPage(item: item)
            .timesOpen("event")
    }
}

/// The card's photo, growing into the page's top picture and back, its corners squaring off as it goes. Drawn
/// as the card draws it, round the photo's focus, from the largest bitmap already decoded.
private struct FlyingPhoto: View {
    let url: URL
    let frame: CGRect
    let radius: CGFloat
    let opacity: Double

    var body: some View {
        let loader = FeedCardImageLoader.shared
        ZStack {
            if let image = loader.largest(for: url) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .offset(FeedCardURLPhoto.offset(image: CGSize(width: image.width, height: image.height),
                                                    box: frame.size, focus: loader.focus(for: url)))
            } else {
                Hue.fill
            }
        }
        .frame(width: frame.width, height: frame.height)
        .clipShape(RoundedRectangle(cornerRadius: max(0, radius), style: .continuous))
        .offset(x: frame.minX, y: frame.minY)
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A drag down that starts in the band under the clock sends the page home, following the finger, only while the
/// page is at its top (`LeftOff.pageY`, which the page writes as it scrolls). UIKit's pan, as the Place page's
/// (`CoverClosePan`): it begins only for a finger moving down, more down than across, and the page's scroll waits
/// for it to say no.
private struct EventClosePan: UIGestureRecognizerRepresentable {
    let opener: EventOpener
    let item: String
    let band: CGFloat

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_ pan: UIPanGestureRecognizer, context: Context) {
        context.coordinator.band = band
        context.coordinator.item = item
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        let c = context.coordinator
        switch pan.state {
        case .began, .changed:
            let from = c.from ?? opener.progress.value
            c.from = from
            let drop = pan.translation(in: nil).y
            opener.progress.set(min(max(from - drop / SearchMetric.bizDrag, 0), SearchMetric.bizOverDrag))
        case .ended, .cancelled:
            c.from = nil
            let down = pan.velocity(in: nil).y
            let speed = -down / SearchMetric.bizDrag
            if down > SearchMetric.bizFlick || opener.progress.value < SearchMetric.bizKeepOpen {
                opener.close(velocity: speed)
            } else {
                opener.settleOpen(velocity: speed)
            }
        default: c.from = nil
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var band: CGFloat = 0
        var item = ""
        var from: CGFloat?

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer, (LeftOff.pageY[item] ?? 0) <= 1 else { return false }
            let start = pan.location(in: nil).y - pan.translation(in: nil).y
            let speed = pan.velocity(in: nil)
            return start < band && speed.y > 0 && speed.y > abs(speed.x)
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other.view is UIScrollView
        }
    }
}

/// A swipe from the left edge sends the page home as the stack's swipe back did, following the finger across the
/// screen's width.
private struct EventEdgePan: UIGestureRecognizerRepresentable {
    let opener: EventOpener
    let width: CGFloat

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIScreenEdgePanGestureRecognizer {
        let pan = UIScreenEdgePanGestureRecognizer()
        pan.edges = .left
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: UIScreenEdgePanGestureRecognizer, context: Context) {
        let c = context.coordinator
        let across = max(width, 1)
        switch pan.state {
        case .began, .changed:
            let from = c.from ?? opener.progress.value
            c.from = from
            opener.progress.set(min(max(from - pan.translation(in: nil).x / across, 0), 1))
        case .ended, .cancelled:
            c.from = nil
            let right = pan.velocity(in: nil).x
            let speed = -right / across
            if right > SearchMetric.bizFlick || opener.progress.value < SearchMetric.bizKeepOpen {
                opener.close(velocity: speed)
            } else {
                opener.settleOpen(velocity: speed)
            }
        default: c.from = nil
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var from: CGFloat?

        /// The edge wins over the page's scroll and its picture's swipe.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            false
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
            false
        }
    }
}

private func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

private func mix(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
    CGRect(x: mix(a.minX, b.minX, t), y: mix(a.minY, b.minY, t), width: mix(a.width, b.width, t), height: mix(a.height, b.height, t))
}
