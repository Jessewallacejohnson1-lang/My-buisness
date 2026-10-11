//
//  PhoneTilt.swift
//  Block Party — how the phone is held, for the things that lean or catch the light with it:
//  Daily's Spotlight card and Search's logo shine.
//

import CoreMotion
import SwiftUI

/// How the phone is held, as a lean from -1 to 1 on each axis against a rest that
/// slowly catches up with the hand, so any comfortable grip reads as level. Apple's own
/// tilt (`UIInterpolatingMotionEffect`, the wallpaper's) is UIKit-only, so this reads
/// the motion sensor directly; that needs no permission.
@Observable
final class PhoneTilt {
    /// A full lean is the phone tipped this far (in gravity, about 17°) from the way it
    /// is being held.
    nonisolated static let range: Double = 0.3
    /// How fast "the way it is being held" catches up with the hand, per reading: at 60
    /// readings a second the lean settles back in about 1.5 s.
    nonisolated static let restFollow: Double = 0.012
    static let readingsPerSecond: Double = 60
    /// A lean change smaller than this isn't drawn: it is sensor noise on a phone lying
    /// still, and redrawing for it 60 times a second would cost battery.
    static let still: Double = 0.005

    private(set) var lean: CGPoint = .zero
    /// Made on the first start, not with the page: `@State` builds a new `PhoneTilt`
    /// every time the page view is rebuilt and keeps only the first.
    @ObservationIgnored private var motion: CMMotionManager?
    @ObservationIgnored private var rest: (x: Double, z: Double)?

    func start() {
        #if DEBUG
        if let held = Self.debugLean { lean = held; return }
        #endif
        let motion = self.motion ?? CMMotionManager()
        self.motion = motion
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1 / Self.readingsPerSecond
        motion.startDeviceMotionUpdates(to: .main) { [weak self] reading, _ in
            guard let gravity = reading?.gravity else { return }
            let x = gravity.x, z = gravity.z
            MainActor.assumeIsolated { self?.read(x: x, z: z) }
        }
    }

    func stop() {
        motion?.stopDeviceMotionUpdates()
        rest = nil
        lean = .zero
    }

    private func read(x: Double, z: Double) {
        var held = rest ?? (x, z)
        let next = Self.lean(gravity: (x, z), rest: &held)
        rest = held
        if abs(next.x - lean.x) > Self.still || abs(next.y - lean.y) > Self.still {
            lean = next
        }
    }

    /// One reading: the lean against the rest, then the rest moves a little toward it.
    nonisolated static func lean(gravity: (x: Double, z: Double),
                                 rest: inout (x: Double, z: Double)) -> CGPoint {
        let lean = CGPoint(x: min(1, max(-1, (gravity.x - rest.x) / range)),
                           y: min(1, max(-1, (gravity.z - rest.z) / range)))
        rest.x += (gravity.x - rest.x) * restFollow
        rest.z += (gravity.z - rest.z) * restFollow
        return lean
    }

    #if DEBUG
    /// DEBUG-only: `-tilt <x>,<y>` holds the lean there, since the simulator has no
    /// motion sensor.
    private static var debugLean: CGPoint? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-tilt"), i + 1 < args.count else { return nil }
        let parts = args[i + 1].split(separator: ",").compactMap { Double($0) }
        return parts.count == 2 ? CGPoint(x: parts[0], y: parts[1]) : nil
    }
    #endif
}

extension View {
    /// Runs `tilt` while this view is on screen, the app is in front and Reduce Motion is
    /// off, and hands it to the views inside. Stopping it also forgets the grip, so coming
    /// back in a new one doesn't jump to a lean.
    func following(_ tilt: PhoneTilt) -> some View { modifier(FollowTilt(tilt: tilt)) }
}

private struct FollowTilt: ViewModifier {
    let tilt: PhoneTilt
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .environment(tilt)
            .onAppear { shown = true; update(shown: true) }
            .onDisappear { shown = false; update(shown: false) }
            .onChange(of: reduceMotion) { update(shown: shown) }
            .onChange(of: scenePhase) { update(shown: shown) }
    }

    private func update(shown: Bool) {
        if shown && scenePhase == .active && !reduceMotion { tilt.start() } else { tilt.stop() }
    }
}
