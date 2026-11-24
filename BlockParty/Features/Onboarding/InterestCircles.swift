//
//  InterestCircles.swift
//  Block Party — "What do you love doing?" as 12 photo circles on the Dusk backdrop (BP app onboarding 48,
//  mock v5; Reference: Jesse's "Intrests ref" clip, BP app references/onboarding-interests/circles/). One tap
//  picks a circle's whole group: a white ring and a green check. On Next the words fade, the circles gather at
//  the middle and burst out, picked ones larger, in under a second; a tap skips it, Reduce Motion has none.
//

import SwiftUI

/// Mock v5's measures at 402 pt.
private enum Metric {
    /// The question's top, and the grid's, from the top of the screen.
    static let headingTop: CGFloat = 110
    static let gridTop: CGFloat = 186
    static let side: CGFloat = 24
    static let circle: CGFloat = 92
    static let labelGap: CGFloat = 8
    static let label: CGFloat = 16
    static let rowGap: CGFloat = 22
    /// A circle's row, centre to centre.
    static let pitch: CGFloat = circle + labelGap + label + rowGap
    /// A pick's white ring inside the circle, and its check: 26 pt, 2 pt of white round it, 5 pt past the top right.
    static let ring: CGFloat = 3
    static let check: CGFloat = 26
    static let checkOut: CGFloat = 5
}

/// The burst's four moments (guessed from the Reference, cut to under a second): at rest, grown as the words go,
/// gathered at the middle, gone off the screen.
enum InterestBurst { case rest, grow, gather, out }

struct InterestCircles: View {
    /// The interests saved: a circle saves its whole group.
    @Binding var picked: [String]
    /// Schools saves no interest: picked, Follow 3 leads with schools.
    @Binding var schools: Bool
    /// Set by Next: the burst plays, then `done` moves on. A tap while it plays moves on at once.
    let bursting: Bool
    let done: () -> Void
    /// What the step keeps clear under the grid: the Next pill and its slot.
    let bottomClear: CGFloat
    @AccessibilityFocusState.Binding var focused: Bool

    @State private var burst = InterestBurst.rest
    @State private var width: CGFloat = 402

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heading
                grid
                    .padding(.top, Metric.gridTop - Metric.headingTop - headingHeight)
            }
            .padding(.top, Metric.headingTop - FollowGridMetric.scrollTop)
            .frame(maxWidth: .infinity)
        }
        // Holds still where it fits (every phone from the 6.1"); a small phone scrolls it clear of the pill.
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .scrollDisabled(burst != .rest)
        // The burst flies past the edges; at rest a small phone's scroll stays under the dashes.
        .scrollClipDisabled(burst != .rest)
        .contentMargins(.bottom, bottomClear, for: .scrollContent)
        .padding(.top, FollowGridMetric.scrollTop)
        .ignoresSafeArea(.container, edges: .top)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        // A tap anywhere while it bursts moves on at once.
        .overlay {
            if burst != .rest {
                Color.clear.contentShape(Rectangle()).onTapGesture { done() }
                    .accessibilityHidden(true)
            }
        }
        .onChange(of: bursting) { _, now in if now { play() } }
    }

    /// Two lines of 26 pt: the question and its line, both 18 pt medium, white, centred.
    private static let lineHeight: CGFloat = 26
    /// SF's line at 18 pt is 21.5: the rest of the mock's 26.
    private static let lineLead: CGFloat = lineHeight - 21.5
    private var headingHeight: CGFloat { Self.lineHeight * 2 }

    private var heading: some View {
        VStack(spacing: 0) {
            Text(OnboardingStep.interests.question)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focused)
                .padding(.vertical, Self.lineLead / 2)
            Text("You can change these later in your profile")
                .padding(.vertical, Self.lineLead / 2)
        }
        .appleFont(18, weight: .medium)
        .lineSpacing(Self.lineLead)
        .foregroundStyle(Color.white)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: headingHeight)
        .padding(.horizontal, FollowGridMetric.gutter)
        .opacity(burst == .rest ? 1 : 0)
    }

    private var column: CGFloat { (width - Metric.side * 2) / 3 }

    /// The circles all in one stack, each at its spot, so a picked one rides over every other in the burst.
    private var grid: some View {
        let rows = Interests.circles.count / 3
        let cell = Metric.circle + Metric.labelGap + Metric.label
        return ZStack {
            ForEach(Array(Interests.circles.enumerated()), id: \.element.id) { index, circle in
                self.cell(circle, index: index, rows: rows)
                    .frame(width: column, height: cell)
                    .position(x: (CGFloat(index % 3) + 0.5) * column, y: CGFloat(index / 3) * Metric.pitch + cell / 2)
            }
        }
        .frame(height: CGFloat(rows) * Metric.pitch - Metric.rowGap)
        .padding(.horizontal, Metric.side)
    }

    private func isOn(_ circle: InterestPick) -> Bool {
        circle.ids.isEmpty ? schools : circle.isOn(in: picked)
    }

    private func cell(_ circle: InterestPick, index: Int, rows: Int) -> some View {
        let on = isOn(circle)
        let move = burstMove(index: index, rows: rows, on: on)
        return Button {
            Haptics.light()
            if circle.ids.isEmpty { schools.toggle() } else { picked = Interests.toggled(circle, in: picked) }
        } label: {
            VStack(spacing: Metric.labelGap) {
                InterestPhotoCircle(photo: Interests.photo(circle), on: on)
                    .scaleEffect(move.scale)
                    .offset(move.offset)
                Text(circle.label)
                    .font(.apple(13, weight: .medium))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(height: Metric.label)
                    .opacity(burst == .rest ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CirclePress())
        .disabled(burst != .rest)
        .zIndex(on ? 1 : 0)
        .accessibilityLabel(circle.label)
        .accessibilityIdentifier("interest-chip")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Where a circle is in the burst, from where it rests: the grid's middle is (0, 0).
    private func burstMove(index: Int, rows: Int, on: Bool) -> (offset: CGSize, scale: CGFloat) {
        let x = CGFloat(index % 3 - 1) * column
        let y = (CGFloat(index / 3) - CGFloat(rows - 1) / 2) * Metric.pitch
        switch burst {
        case .rest: return (.zero, 1)
        case .grow: return (.zero, on ? 1.16 : 1.1)
        case .gather: return (CGSize(width: -x * 0.86, height: -y * 0.86), on ? 0.55 : 0.42)
        case .out:
            // Straight out from the middle, each turned a little its own way, off the screen.
            let turn = (Double((index * 37) % 21) - 10) * .pi / 180
            let angle = (x == 0 && y == 0 ? 0 : atan2(Double(y), Double(x))) + turn
            let reach: CGFloat = 560
            return (CGSize(width: -x + reach * CGFloat(cos(angle)), height: -y + reach * CGFloat(sin(angle))),
                    on ? 1.15 : 0.7)
        }
    }

    /// Grow 0.12 s as the words fade, gather 0.24 s, then out 0.3 s, speeding up so the circles leave the screen
    /// as it ends: 0.66 s, then on. Building Follow 3 holds the main thread about 0.3 s on BP Build (2026-11-21),
    /// which froze the circles mid-burst when the move started earlier. Reduce Motion never starts it.
    private func play() {
        withAnimation(.easeOut(duration: 0.12)) { burst = .grow } completion: {
            withAnimation(.easeIn(duration: 0.24)) { burst = .gather } completion: {
                withAnimation(.easeIn(duration: 0.3)) { burst = .out } completion: { done() }
            }
        }
    }
}

/// The press squashes the circle alone, as the Reference's does, never its label. Follow 3's circles take it too.
struct CirclePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.environment(\.circlePressed, configuration.isPressed)
    }
}

extension EnvironmentValues {
    @Entry var circlePressed = false
}

/// One photo circle: 92 pt, with a 3 pt white ring, which fades in, and the green check at its top right once picked.
private struct InterestPhotoCircle: View {
    let photo: String
    let on: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.circlePressed) private var pressed

    var body: some View {
        ZStack {
            Hue.deepTop
            if let image = UIImage(named: photo) {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .frame(width: Metric.circle, height: Metric.circle)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white, lineWidth: on ? Metric.ring : 0))
        .overlay(alignment: .topTrailing) {
            PickCheck(on: on, side: Metric.check, glyph: 12)
                .offset(x: Metric.checkOut, y: -Metric.checkOut)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: on)
        .press(.squish, down: pressed)
        .accessibilityHidden(true)
    }
}

/// A picked circle's green check in 2 pt of white, popping .6 to 112% and back over 0.26 s (Interests and Follow 3).
struct PickCheck: View {
    let on: Bool
    let side: CGFloat
    let glyph: CGFloat

    @State private var pop: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(Hue.pickCheck)
            Circle().strokeBorder(Color.white, lineWidth: 2)
            Image(systemName: "checkmark")
                .font(.glyph(glyph, weight: .bold))
                .foregroundStyle(Color.white)
        }
        .frame(width: side, height: side)
        .scaleEffect(on ? pop : 0.6)
        .opacity(on ? 1 : 0)
        .onChange(of: on) { _, now in
            guard now, !reduceMotion else { return }
            pop = 0.6
            withAnimation(.easeOut(duration: 0.156)) { pop = 1.12 } completion: {
                withAnimation(.easeOut(duration: 0.104)) { pop = 1 }
            }
        }
    }
}
