//
//  RefreshLoop.swift
//  Block Party — the Town feed's pull-to-refresh: one chunky ink line round one loop, with
//  gravity (BP app town-feed 69; taste/town.md 2026-11-15). Apple's `.refreshable` still does the
//  pull, the trigger and the gap it holds open; its swirl is hidden (`.tint(.clear)` on the feed)
//  and this draws in that gap.
//

import SwiftUI

/// Where a read the loop shows began: a pull starts the line at the top of the loop, a Town tab
/// tap at the bottom.
enum RefreshStart { case pull, tab }

/// How far the Town feed is pulled down, and the read out now. A box of its own, as `BarTravel`
/// is, so the scroll can write it every frame and only the loop reads it.
@Observable
final class RefreshPull {
    var points: CGFloat = 0
    var reading: RefreshStart?
}

/// The loop's numbers and motion, from mock round 3 (https://claude.ai/artifact/SN3prfQQhsD43FkVaC8pjX).
/// Angles are radians from the bottom of the loop, clockwise on screen: bottom, left, top, right.
enum LoopRide {
    static let diameter: CGFloat = 28
    static let lineWidth: CGFloat = 4
    /// One lap, and the least the line rides however fast the read comes back.
    static let lap: Double = 1.2
    /// Speed over the top as a share of speed through the bottom.
    static let topSpeedShare = 0.32
    /// The pull at which the line reaches the top: where `.refreshable` starts the read. Measured
    /// on iOS 26.5: Apple's swirl fills its last spoke between 149 and 171 pt of pull (refresh-coaster
    /// before frames 503–510).
    static let triggerPoints: CGFloat = 160
    static let fade: Double = 0.3
    /// The gap a Town tab tap opens: the one `.refreshable` holds during a pull's read.
    static let tabGap: CGFloat = 64

    /// Gravity: speed² = bottom speed² − 2g·height, with the bottom speed 1 and the radius 1.
    private static let gravity = (1 - topSpeedShare * topSpeedShare) / 4
    static func speed(at angle: Double) -> Double {
        (1 - 2 * gravity * (1 - cos(angle))).squareRoot()
    }

    /// The line's length in radians: short over the top, long through the bottom.
    static func arc(at angle: Double) -> Double { 0.55 + 2.1 * speed(at: angle) }

    private static let steps = 720
    /// Time to reach each step from the bottom, unscaled.
    private static let times: [Double] = {
        let step = 2 * Double.pi / Double(steps)
        var times = [0.0]
        for i in 0..<steps { times.append(times[i] + step / speed(at: (Double(i) + 0.5) * step)) }
        return times
    }()

    /// Where the head is `seconds` after the read began.
    static func angle(after seconds: Double, from start: RefreshStart) -> Double {
        let lapTime = times[steps]
        let begin = start == .pull ? times[steps / 2] : 0
        let t = (begin + seconds * lapTime / lap).truncatingRemainder(dividingBy: lapTime)
        var low = 0, high = steps
        while high - low > 1 {
            let mid = (low + high) / 2
            if times[mid] <= t { low = mid } else { high = mid }
        }
        let within = (t - times[low]) / (times[high] - times[low])
        return (Double(low) + within) * 2 * .pi / Double(steps)
    }

    struct Stroke: Equatable {
        var head: Double
        var length: Double
        var opacity: Double
    }

    /// While pulling: the line climbs the left side with the finger and reaches the top at the trigger.
    static func stroke(pull: CGFloat) -> Stroke? {
        guard pull > 0 else { return nil }
        let share = Double(min(1, pull / triggerPoints))
        return Stroke(head: share * .pi, length: share * .pi, opacity: min(1, share * 4))
    }

    /// During a read: the ride, then once it has ended (`endsAfter`, seconds in) a short fade.
    static func stroke(from start: RefreshStart, since seconds: Double, endsAfter: Double?) -> Stroke? {
        let head = angle(after: seconds, from: start)
        var length = arc(at: head)
        var opacity = 1.0
        if start == .pull, seconds < 0.25 {
            // The half drawn in by the pull lets go as the line falls.
            length += (.pi - length) * pow(1 - seconds / 0.25, 2)
        } else if start == .tab, seconds < 0.15 {
            length *= seconds / 0.15
        }
        if let endsAfter, seconds >= endsAfter {
            let left = 1 - (seconds - endsAfter) / fade
            guard left > 0 else { return nil }
            length *= left
            opacity = left
        }
        return Stroke(head: head, length: length, opacity: opacity)
    }

    /// How far above the first card the loop's centre sits, for a gap of `gap` points over it.
    static func rise(gap: CGFloat) -> CGFloat { -(gap - min(gap, tabGap) / 2) }

    /// What is left of the one lap the line always rides, after a read took `seconds`.
    static func rest(afterReading seconds: Double) -> Double { max(0, lap - seconds) }
}

/// The loop itself, centred in the gap above the feed's first card.
struct RefreshLoop: View {
    var pull: RefreshPull
    /// The gap a Town tab tap opens, which no pull measures.
    var tabGap: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Ride: Equatable {
        var start: Date
        var from: RefreshStart
        var ends: Date?
    }
    @State private var ride: Ride?

    var body: some View {
        let live = ride != nil || pull.points > 0
        let side = LoopRide.diameter + LoopRide.lineWidth
        TimelineView(.animation(paused: !live)) { context in
            Canvas { canvas, size in
                guard let stroke = stroke(at: context.date) else { return }
                var path = Path()
                let radius = LoopRide.diameter / 2
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                let pieces = 48
                for i in 0...pieces {
                    let angle = stroke.head - stroke.length + stroke.length * Double(i) / Double(pieces)
                    let point = CGPoint(x: centre.x - sin(angle) * radius, y: centre.y + cos(angle) * radius)
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                canvas.stroke(path, with: .color(Hue.ink.opacity(stroke.opacity)),
                              style: StrokeStyle(lineWidth: LoopRide.lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: side, height: side)
        // Centred in the gap until the gap passes the one a read holds open, then pinned under the
        // bar there, as Apple's swirl is.
        .offset(y: LoopRide.rise(gap: max(pull.points, tabGap)))
        .background(SwirlHider(pulling: pull.points > 0))
        .frame(height: 0)
        // Kept in the tree, as a paused timeline keeps its last frame (swift-traps.md).
        .opacity(live ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: pull.reading) { _, reading in
            if let reading {
                ride = Ride(start: .now, from: reading)
            } else if var ended = ride {
                ended.ends = .now
                ride = ended
            }
        }
        .task(id: ride) {
            guard let ends = ride?.ends else { return }
            try? await Task.sleep(for: .seconds(max(0, ends.timeIntervalSinceNow) + LoopRide.fade))
            guard !Task.isCancelled else { return }
            ride = nil
        }
    }

    private func stroke(at date: Date) -> LoopRide.Stroke? {
        if let ride {
            let seconds = date.timeIntervalSince(ride.start)
            let endsAfter = ride.ends.map { $0.timeIntervalSince(ride.start) }
            if reduceMotion {
                // Reduce Motion: the loop fills, holds, and fades; nothing rides.
                let filled = ride.from == .tab ? min(1, seconds / 0.3) : 1
                let left = endsAfter.map { 1 - (seconds - $0) / LoopRide.fade } ?? 1
                guard left > 0 else { return nil }
                return .init(head: 2 * .pi * filled, length: 2 * .pi * filled, opacity: min(1, left))
            }
            return LoopRide.stroke(from: ride.from, since: seconds, endsAfter: endsAfter)
        }
        if reduceMotion, let pulled = LoopRide.stroke(pull: pull.points) {
            return .init(head: pulled.head * 2, length: pulled.length * 2, opacity: pulled.opacity)
        }
        return LoopRide.stroke(pull: pull.points)
    }
}

/// Apple's swirl, hidden. `.tint(.clear)` on the feed doesn't reach the `UIRefreshControl` that
/// `.refreshable` puts in the scroll view (iOS 26.5: the grey swirl showed over the gap, refresh-coaster
/// before frames 470–530), so this finds that scroll view and clears the control's tint, again each
/// time a pull starts in case SwiftUI set it back. DECISIONS.md: the one reach into the feed's UIKit.
private struct SwirlHider: UIViewRepresentable {
    var pulling: Bool

    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ probe: Probe, context: Context) { probe.clearSwirl() }

    final class Probe: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            clearSwirl()
        }

        func clearSwirl() {
            var view = superview
            while let current = view {
                if let scroll = current as? UIScrollView, let control = scroll.refreshControl {
                    control.tintColor = .clear
                    return
                }
                view = current.superview
            }
        }
    }
}
