//
//  HelloMoments.swift
//  Block Party — firsts and milestones for the hello pill (BP app hello-drop 02): what each
//  says, saying each once ever, the green tick with its haptics, and the confetti.
//

import CoreHaptics
import SwiftUI
import UIKit

/// A first or a milestone. Each is said once ever, in one short line with the tick.
enum HelloMoment: String, CaseIterable {
    case firstEvent, tenthEvent, hundredthEvent
    case firstFriend, firstShare
    case firstPlace, firstPerson, firstGroup, firstTeam

    var text: String {
        switch self {
        case .firstEvent: "Attended your first event!"
        case .tenthEvent: "Attended your 10th event!"
        case .hundredthEvent: "Attended your 100th event!"
        case .firstFriend: "Added your first friend!"
        case .firstShare: "Shared your first event!"
        case .firstPlace: "Followed your first place!"
        case .firstPerson: "Followed your first person!"
        case .firstGroup: "Followed your first group!"
        case .firstTeam: "Followed your first team!"
        }
    }

    /// Confetti only for the 10th and 100th (Jesse, 2026-10-23); firsts get the tick alone.
    var confetti: Bool { self == .tenthEvent || self == .hundredthEvent }

    /// The attended milestone a count has reached, highest first.
    static func attended(_ count: Int) -> [HelloMoment] {
        let steps: [(Int, HelloMoment)] = [(100, .hundredthEvent), (10, .tenthEvent), (1, .firstEvent)]
        return steps.filter { count >= $0.0 }.map(\.1)
    }

    /// Events attended: Going, not called off, and over.
    static func attendedCount(_ going: [DailyEvent], now: Date) -> Int {
        going.filter { !$0.item.cancelled && $0.ends <= now }.count
    }
}

/// The moments waiting for the pill. Any screen calls `reach`; the pill takes one when it can.
@MainActor @Observable
final class HelloMoments {
    static let shared = HelloMoments()

    /// In the order reached; the pill shows the first and the rest after it.
    private(set) var queue: [HelloMoment] = []
    var waiting: HelloMoment? { queue.first }
    // ponytail: once ever per phone (UserDefaults); per account if two people share a phone.
    // ponytail: "first friend" fires when you confirm a request, not when yours is accepted.
    private let said: UserDefaults

    init(said: UserDefaults = .standard) { self.said = said }

    private func key(_ moment: HelloMoment) -> String { "helloDrop.said.\(moment.rawValue)" }

    func hasSaid(_ moment: HelloMoment) -> Bool { said.bool(forKey: key(moment)) }

    /// Says a moment once ever: a second reach of the same one does nothing.
    func reach(_ moment: HelloMoment) {
        guard !hasSaid(moment) else { return }
        said.set(true, forKey: key(moment))
        queue.append(moment)
    }

    /// The attended count, after the events it counts are over. Only the highest milestone
    /// shows; the ones under it are marked said, so a long-time neighbour isn't told "first".
    func attended(_ count: Int) {
        let reached = HelloMoment.attended(count).filter { !hasSaid($0) }
        guard let top = reached.first else { return }
        for moment in reached.dropFirst() { said.set(true, forKey: key(moment)) }
        reach(top)
    }

    #if DEBUG
    /// `-hello-moment`: shows one whether or not it was said.
    func show(_ moment: HelloMoment) { queue.append(moment) }
    #endif

    func take() -> HelloMoment? {
        queue.isEmpty ? nil : queue.removeFirst()
    }
}

// MARK: - The tick

/// The check's two strokes, in a unit square.
private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// A chunky green ball: its ring draws clockwise from 12 o'clock, it fills with a small pop,
/// then a black check strokes across. `stage` 0 shows nothing, 3 the finished tick.
struct HelloTick: View {
    let stage: Int
    static let size: CGFloat = 38

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: stage >= 1 ? 1 : 0)
                .stroke(Hue.now, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(2.5)
            Circle()
                .fill(Hue.now)
                // Lit from above and a darker rim below, so it reads as a ball, not a dot.
                .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.32), .clear],
                                                      startPoint: .top, endPoint: .center)))
                .overlay(Circle().strokeBorder(.black.opacity(0.14), lineWidth: 2))
                .scaleEffect(stage >= 2 ? 1 : 0.82)
                .opacity(stage >= 2 ? 1 : 0)
            CheckShape()
                .trim(from: 0, to: stage >= 3 ? 1 : 0)
                .stroke(Hue.ink.onLightCanvas, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
                .frame(width: 15, height: 11)
                .offset(y: 0.5)
        }
        .frame(width: Self.size, height: Self.size)
        .accessibilityHidden(true)
    }

    /// The ring, the pop and the check, with the haptics under them. Reduce Motion: the
    /// finished tick and one click.
    static func play(reduceMotion: Bool, stage: Binding<Int>) async {
        if reduceMotion {
            stage.wrappedValue = 3
            Haptics.success()
            return
        }
        TickHaptics.play()
        withAnimation(.timingCurve(0.45, 0, 0.25, 1, duration: ringTime)) { stage.wrappedValue = 1 }
        try? await Task.sleep(for: .seconds(ringTime))
        withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) { stage.wrappedValue = 2 }
        try? await Task.sleep(for: .seconds(popTime))
        withAnimation(.timingCurve(0.3, 0, 0.2, 1, duration: checkTime)) { stage.wrappedValue = 3 }
        try? await Task.sleep(for: .seconds(checkTime))
    }

    static let ringTime = 0.6
    static let popTime = 0.14
    static let checkTime = 0.24
}

/// Duolingo's feel: one smooth rise under the ring, then a crisp click as the check lands.
enum TickHaptics {
    private static var engine: CHHapticEngine?

    /// Silent in Low Power Mode, as every buzz in the app is (`Haptics`, spec §10).
    static func play() {
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled,
              CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            if engine == nil {
                let made = try CHHapticEngine()
                made.isAutoShutdownEnabled = true
                engine = made
            }
            try engine?.start()
            let ring = HelloTick.ringTime
            let rise = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2),
            ], relativeTime: 0, duration: ring)
            let swell = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
                .init(relativeTime: 0, value: 0.2),
                .init(relativeTime: ring, value: 0.8),
            ], relativeTime: 0)
            let click = CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9),
            ], relativeTime: ring + HelloTick.popTime + HelloTick.checkTime)
            let pattern = try CHHapticPattern(events: [rise, click], parameterCurves: [swell])
            try engine?.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            Haptics.success()
        }
    }
}

// MARK: - Confetti

/// One burst of flat pieces falling across the screen, about 70% BP yellow and 30% black.
/// Touches pass through it. Each new `burst` value fires once.
struct HelloConfetti: UIViewRepresentable {
    let burst: Int
    /// A team's colours, in equal shares; empty for BP's yellow and black.
    var colors: [UInt32] = []

    func makeUIView(context: Context) -> ConfettiView { ConfettiView() }

    func updateUIView(_ view: ConfettiView, context: Context) {
        guard burst != view.fired else { return }
        view.fired = burst
        if burst > 0 { view.fire(colors.map { UIColor(Color(hex: $0)) }) }
    }

    final class ConfettiView: UIView {
        var fired = 0
        private let emitter = CAEmitterLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            emitter.birthRate = 0
            layer.addSublayer(emitter)
        }

        required init?(coder: NSCoder) { nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            emitter.frame = bounds
            emitter.emitterShape = .line
            emitter.emitterPosition = CGPoint(x: bounds.midX, y: -20)
            emitter.emitterSize = CGSize(width: bounds.width, height: 1)
        }

        func fire(_ team: [UIColor] = []) {
            let yellow = UIColor(Hue.brandDisc)
            let ink = UIColor(Hue.ink.onLightCanvas)
            // 7 yellow to 3 black, by birth rate; a team's colours share 10 evenly.
            let shares: [(UIColor, Int)] = team.isEmpty ? [(yellow, 7), (ink, 3)]
                : team.map { ($0, max(1, 10 / team.count)) }
            emitter.emitterCells = shares.flatMap { color, share in
                [Self.piece(round: false), Self.piece(round: true)].map { image in
                    let cell = CAEmitterCell()
                    cell.contents = image.cgImage
                    cell.contentsScale = image.scale
                    cell.color = color.cgColor
                    cell.birthRate = Float(share) * 25
                    cell.lifetime = 5
                    cell.velocity = 170
                    cell.velocityRange = 90
                    cell.emissionLongitude = .pi
                    cell.emissionRange = .pi / 5
                    cell.yAcceleration = 260
                    cell.spin = 3.5
                    cell.spinRange = 5
                    cell.scale = 1
                    cell.scaleRange = 0.3
                    return cell
                }
            }
            emitter.beginTime = CACurrentMediaTime()
            emitter.birthRate = 1
            // About 1.5 s of falling from a short release, ~180 pieces.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) { [weak self] in
                self?.emitter.birthRate = 0
            }
        }

        /// A white piece the cell tints: a 7 × 11 pt strip, or a 6 pt dot.
        private static func piece(round: Bool) -> UIImage {
            let size = round ? CGSize(width: 6, height: 6) : CGSize(width: 7, height: 11)
            return UIGraphicsImageRenderer(size: size).image { _ in
                UIColor.white.setFill()
                let rect = CGRect(origin: .zero, size: size)
                (round ? UIBezierPath(ovalIn: rect) : UIBezierPath(rect: rect)).fill()
            }
        }
    }
}
