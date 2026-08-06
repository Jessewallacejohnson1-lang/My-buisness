//
//  DwellTracker.swift
//  Block Party — "was this actually read?", not "was it on screen for a frame".
//
//  Fires once the view has been continuously visible for `seconds`. Scrolling
//  past cancels it, so a fast scroll to the bottom does not count as reading the
//  almanac. Fires at most once per view lifetime.
//

import SwiftUI

private struct DwellTracker: ViewModifier {
    let seconds: TimeInterval
    let onDwell: () -> Void

    @State private var timer: Task<Void, Never>?
    @State private var fired = false

    func body(content: Content) -> some View {
        content
            .onScrollVisibilityChange(threshold: 0.6) { visible in
                timer?.cancel()
                guard visible, !fired else { timer = nil; return }
                timer = Task {
                    try? await Task.sleep(for: .seconds(seconds))
                    guard !Task.isCancelled, !fired else { return }
                    fired = true
                    onDwell()
                }
            }
            .onDisappear {
                timer?.cancel()
                timer = nil
            }
    }
}

extension View {
    /// Calls `onDwell` after this view has been continuously visible for
    /// `seconds`. At most once.
    func dwell(seconds: TimeInterval = 3, onDwell: @escaping () -> Void) -> some View {
        modifier(DwellTracker(seconds: seconds, onDwell: onDwell))
    }
}
