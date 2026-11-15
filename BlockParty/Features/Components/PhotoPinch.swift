//
//  PhotoPinch.swift
//  Block Party — two fingers lift a photo where it sits, as Instagram's feed does (BP app photo-zoom;
//  Jesse: "make photos allowed to be zoomable", "make sure it matches instas code"; mock
//  https://claude.ai/artifact/DcZb6e6WrmSAoJ7KmQJpBV).
//
//  Instagram's way, in UIKit: a pinch recognizer on the photo, a picture of the photo lifted into the
//  window above everything (tab bar and top bar included), black behind it growing with the scale, the
//  photo following both fingers, and on letting go one spring back into its spot. The scroll under it
//  stands still while two fingers are down. A tap, a double tap and a scroll are untouched: a pinch
//  takes two fingers, and the recognizer runs beside every other (DECISIONS.md, 2026-11-09).
//

import SwiftUI
import UIKit

/// The lift's numbers, apart from UIKit so they're tested (`PhotoPinchTests`). Guessed until Jesse's
/// recording of Instagram's pinch is measured.
nonisolated enum PinchMath {
    /// The biggest it goes before it stretches.
    static let most: CGFloat = 4
    /// Black behind it at its darkest, reached by 2×.
    static let dimMost: CGFloat = 0.75
    /// The spring back into its spot.
    static let springSeconds: Double = 0.35
    static let bounce: CGFloat = 0.14

    /// The scale drawn for the fingers' scale: theirs from 1 to `most`, a quarter as much past `most`,
    /// and about a third as much under 1, so it stretches at both ends.
    static func shown(_ fingers: CGFloat) -> CGFloat {
        if fingers > most { return most + (fingers - most) * 0.25 }
        if fingers < 1 { return 1 - (1 - max(fingers, 0)) * 0.35 }
        return fingers
    }

    /// How dark it is behind the photo at the scale drawn: clear at 1, darkest by 2×.
    static func dim(_ shown: CGFloat) -> CGFloat {
        min(1, max(0, shown - 1)) * dimMost
    }

    /// The point of the photo (from its top left, at 1×) under the fingers, as it's drawn now.
    static func anchor(fingers: CGPoint, offset: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: (fingers.x - offset.x) / scale, y: (fingers.y - offset.y) / scale)
    }

    /// The photo's offset from its spot that keeps `anchor` under the fingers at `scale`; points are
    /// from the spot's top left.
    static func offset(anchor: CGPoint, fingers: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: fingers.x - anchor.x * scale, y: fingers.y - anchor.y * scale)
    }
}

extension View {
    /// Two fingers lift this where it sits and it springs back when they let go (`PhotoPinch`). `slot` is
    /// what shows in its spot meanwhile, the ground under it; `lifted` is true from the pinch's start until
    /// it has landed, for what should step aside (a press's squish, buttons over the photo).
    func pinchToZoom(corner: CGFloat = 0, slot: Color, lifted: Binding<Bool>? = nil) -> some View {
        modifier(PinchToZoom(corner: corner, slot: slot, lifted: lifted))
    }
}

private struct PinchToZoom: ViewModifier {
    let corner: CGFloat
    let slot: Color
    let lifted: Binding<Bool>?
    @State private var spot = PinchSpot()
    /// Its picture is up (`PhotoLift`), so the real one isn't drawn.
    @State private var away = false

    func body(content: Content) -> some View {
        content
            // Nothing of the real one may show round its empty spot: an edge, a corner, a white card's shadow
            // (Jesse's phone, 2026-11-14). 0.001, not 0: SwiftUI stops hit-testing a view at 0, and a second
            // pinch must still catch the picture on its way home.
            .opacity(away ? 0.001 : 1)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { spot.rect = $0 }
            .gesture(PhotoPinch(spot: spot, corner: corner, slot: UIColor(slot), onAway: { gone in
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { away = gone }
            }) { lifted?.wrappedValue = $0 })
    }
}

/// Where the photo sits on screen, kept out of SwiftUI's state so a scroll doesn't redraw it. A lift
/// that's up hears each move (`PhotoLift.follow`).
@MainActor private final class PinchSpot {
    var rect: CGRect = .zero {
        didSet { if rect != oldValue { onMove?(rect) } }
    }
    var onMove: ((CGRect) -> Void)?
}

/// The pinch itself, a UIKit recognizer that runs beside every other one.
private struct PhotoPinch: UIGestureRecognizerRepresentable {
    let spot: PinchSpot
    let corner: CGFloat
    let slot: UIColor
    let onAway: (Bool) -> Void
    let onLift: (Bool) -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let lift: PhotoLift

        init(spot: PinchSpot) {
            let lift = PhotoLift(place: spot)
            self.lift = lift
            super.init()
            spot.onMove = { [weak lift] in lift?.follow($0) }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(spot: spot)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPinchGestureRecognizer {
        let recognizer = UIPinchGestureRecognizer()
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPinchGestureRecognizer, context: Context) {
        let lift = context.coordinator.lift
        // Gone from the screen mid-pinch (a swipe back, a refresh): it still lands, so nothing stays up.
        guard recognizer.state == .began || recognizer.state == .changed, let window = recognizer.view?.window else {
            lift.land()
            return
        }
        let fingers = recognizer.location(in: window)
        if recognizer.state == .began {
            lift.begin(in: window, corner: corner, slot: slot, fingers: fingers, onAway: onAway, onLift: onLift)
        } else if recognizer.numberOfTouches < 2 {
            // One finger up ends it, as Instagram's does: its lone finger would jump the photo.
            lift.land()
        } else {
            lift.move(fingers: fingers, scale: recognizer.scale)
        }
    }
}

/// The lifted photo: a picture of it over a dimmed window, the spot it left showing its ground.
@MainActor private final class PhotoLift {
    private let stage = UIView()
    private let ground = UIView()
    private let dim = UIView()
    private var photo: UIView?
    /// Where the photo sits now, read when the lift is drawn and followed while it's up.
    private let place: PinchSpot
    private var onAway: (Bool) -> Void = { _ in }
    private var onLift: (Bool) -> Void = { _ in }
    /// The fingers' scale when they landed, and the point of the photo under them.
    private var startScale: CGFloat = 1
    private var anchor: CGPoint = .zero
    /// The fingers now, in the window, and their scale since landing.
    private var point: CGPoint = .zero
    private var pinch: CGFloat = 1
    private var held = false
    /// Counts landings, so a landing caught by a new pinch doesn't clear the stage when its spring ends.
    private var landings = 0
    private var stopped: [UIScrollView] = []

    init(place: PinchSpot) {
        self.place = place
        stage.isUserInteractionEnabled = false
        dim.backgroundColor = .black
        stage.addSubview(ground)
        stage.addSubview(dim)
    }

    func begin(in window: UIWindow, corner: CGFloat, slot: UIColor, fingers point: CGPoint,
               onAway: @escaping (Bool) -> Void, onLift: @escaping (Bool) -> Void) {
        held = true
        landings += 1
        pinch = 1
        self.point = point
        stopScrolls(under: point, in: window)
        if let photo, stage.superview != nil {
            // Caught on its way home: on from where it is now.
            let now = photo.layer.presentation()?.affineTransform() ?? photo.transform
            let dimNow = CGFloat(dim.layer.presentation()?.opacity ?? Float(dim.alpha))
            photo.layer.removeAllAnimations()
            dim.layer.removeAllAnimations()
            photo.transform = now
            dim.alpha = dimNow
            startScale = now.a
            anchor = PinchMath.anchor(fingers: fingers, offset: CGPoint(x: now.tx, y: now.ty), scale: now.a)
            return
        }
        self.onAway = onAway
        self.onLift = onLift
        startScale = 1
        onLift(true)
        // A turn later, once what steps aside for the lift (a press's squish) has drawn without it. As it's on
        // screen, not drawn again: a fresh draw leaves out the grey glass heart.
        // Where it sits is read then too, not when the fingers landed: the squish was still letting go and
        // the feed still moving, so the ground sat off its spot and a dark edge of the photo showed round it
        // (Jesse's phone, 2026-11-14).
        DispatchQueue.main.async { [self] in
            let spot = place.rect
            guard held, photo == nil,
                  let picture = window.resizableSnapshotView(from: spot, afterScreenUpdates: false, withCapInsets: .zero)
            else { if photo == nil { finish() }; return }
            anchor = fingers
            stage.frame = window.bounds
            ground.frame = spot
            ground.backgroundColor = slot
            ground.layer.cornerRadius = corner
            ground.layer.cornerCurve = .continuous
            dim.frame = window.bounds
            dim.alpha = 0
            picture.layer.anchorPoint = .zero
            picture.frame = spot
            picture.layer.cornerRadius = corner
            picture.layer.cornerCurve = .continuous
            picture.clipsToBounds = true
            stage.addSubview(picture)
            photo = picture
            window.addSubview(stage)
            onAway(true)
            draw()
        }
    }

    func move(fingers point: CGPoint, scale: CGFloat) {
        guard held else { return }
        self.point = point
        pinch = scale
        draw()
    }

    /// The fingers from the spot's top left.
    private var fingers: CGPoint {
        CGPoint(x: point.x - place.rect.minX, y: point.y - place.rect.minY)
    }

    /// The real photo moved under the lift (a squish letting go late, a scroll settling): its ground and its
    /// home move with it, and the picture stays under the fingers, the same point of it when it grows.
    func follow(_ rect: CGRect) {
        guard let photo else { return }
        let was = photo.bounds.size
        if was.width > 0, was.height > 0 {
            anchor = CGPoint(x: anchor.x * rect.width / was.width, y: anchor.y * rect.height / was.height)
        }
        ground.frame = rect
        photo.layer.position = rect.origin
        photo.bounds.size = rect.size
        if held { draw() }
    }

    private func draw() {
        guard let photo else { return }
        let shown = PinchMath.shown(startScale * pinch)
        let offset = PinchMath.offset(anchor: anchor, fingers: fingers, scale: shown)
        photo.transform = CGAffineTransform(translationX: offset.x, y: offset.y).scaledBy(x: shown, y: shown)
        dim.alpha = PinchMath.dim(shown)
    }

    func land() {
        guard held else { return }
        held = false
        restartScrolls()
        guard let photo else { return }
        let landing = landings
        let home = {
            photo.transform = .identity
            self.dim.alpha = 0
        }
        let done: (Bool) -> Void = { _ in
            if self.landings == landing { self.finish() }
        }
        if UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.15, delay: 0, options: [.allowUserInteraction], animations: home, completion: done)
        } else {
            UIView.animate(springDuration: PinchMath.springSeconds, bounce: PinchMath.bounce, initialSpringVelocity: 0,
                           delay: 0, options: [.allowUserInteraction], animations: home, completion: done)
        }
    }

    /// Landed: the stage goes and the photo in its spot is the real one again.
    private func finish() {
        onAway(false)
        photo?.removeFromSuperview()
        photo = nil
        stage.removeFromSuperview()
        onLift(false)
    }

    /// The scrolls under the fingers stand still while they're down, the feed's and a pager's alike.
    private func stopScrolls(under point: CGPoint, in window: UIWindow) {
        var view = window.hitTest(point, with: nil)
        while let current = view {
            if let scroll = current as? UIScrollView, scroll.isScrollEnabled {
                scroll.isScrollEnabled = false
                stopped.append(scroll)
            }
            view = current.superview
        }
    }

    private func restartScrolls() {
        stopped.forEach { $0.isScrollEnabled = true }
        stopped = []
    }
}
