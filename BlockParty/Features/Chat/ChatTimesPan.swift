//
//  ChatTimesPan.swift
//  Block Party — the drag that shows a chat's times (BP app messages 02): a finger moving left across the chat brings
//  it over, and the times come in at the right.
//
//  UIKit's pan, not a SwiftUI drag: a SwiftUI gesture on a scroll's content takes the touch on its way down and the
//  chat stops scrolling (docs/rules/swift-traps.md). This one begins only for a finger moving left, more across than
//  down, and the scroll's own pan waits for it to say no, which it does at once for a finger moving up or down. A
//  finger moving right is the stack's swipe back, and never begins it.
//

import SwiftUI

struct ChatTimesPan: UIGestureRecognizerRepresentable {
    /// How far left the finger has come, in points, never under 0.
    let changed: (CGFloat) -> Void
    let ended: () -> Void

    init(changed: @escaping (CGFloat) -> Void, ended: @escaping () -> Void) {
        self.changed = changed
        self.ended = ended
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        switch pan.state {
        case .began, .changed: changed(max(0, -pan.translation(in: pan.view).x))
        case .ended, .cancelled, .failed: ended()
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let speed = pan.velocity(in: pan.view)
            return speed.x < 0 && abs(speed.x) > abs(speed.y) * 1.2
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other.view is UIScrollView
        }
    }
}
