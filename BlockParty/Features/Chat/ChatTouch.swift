//
//  ChatTouch.swift
//  Block Party — a message's two touches beyond a tap (BP app messages 03): a swipe right to reply and a hold for the
//  emoji row and menu. The double tap's heart is the feed's `PhotoDoubleTap`.
//
//  UIKit's, not SwiftUI's, for the reason `ChatTimesPan` gives: a SwiftUI drag or long press on a scroll's content takes
//  the touch on its way down and the chat stops scrolling (docs/rules/swift-traps.md). Apple's context menu can't carry
//  an emoji row over the bubble, so the hold opens our own (`ChatHeld`).
//

import SwiftUI

/// A finger moving right across a message: the row follows it and a reply arrow comes in behind. It begins only for a
/// finger moving right, more across than down, and not from the left edge, where the stack's swipe back stays; the
/// stack's swipe back from anywhere else on the page waits for it to say no, as the scroll's own pan does.
struct ChatReplyPan: UIGestureRecognizerRepresentable {
    /// How far right the finger has come, in points, never under 0.
    let changed: (CGFloat) -> Void
    let ended: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        switch pan.state {
        case .began, .changed: changed(max(0, pan.translation(in: pan.view).x))
        case .ended, .cancelled, .failed: ended()
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer, let window = pan.view?.window else { return false }
            let speed = pan.velocity(in: window)
            let start = pan.location(in: window).x - pan.translation(in: window).x
            return speed.x > 0 && abs(speed.x) > abs(speed.y) * 1.2 && start > ChatMetric.replyEdge
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            if other.view is UIScrollView { return true }
            var responder: UIResponder? = recognizer.view
            while let next = responder, !(next is UINavigationController) { responder = next.next }
            return other === (responder as? UINavigationController)?.interactiveContentPopGestureRecognizer
        }
    }
}

/// A finger held still on a message for `ChatMotion.hold`: the menu opens. A finger that moves first is a scroll's.
struct ChatHold: UIGestureRecognizerRepresentable {
    let began: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let press = UILongPressGestureRecognizer()
        press.minimumPressDuration = ChatMotion.hold
        return press
    }

    func handleUIGestureRecognizerAction(_ press: UILongPressGestureRecognizer, context: Context) {
        if press.state == .began { began() }
    }
}
