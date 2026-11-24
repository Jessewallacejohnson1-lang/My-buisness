//
//  OnboardingChrome.swift
//  Block Party — the pieces every onboarding question screen shares, in Luma's look (BP app
//  onboarding 34, mock v8): the pale grey canvas, the back chevron, the icon circle over the question,
//  the one Next pill, the grey field box. The Big art look (onboarding 43, mock v2) is arriving a step
//  at a time: its dashes track every step, and Profile, Birthday and Find your friends wear its colour, large drawing,
//  centred question and white boxes. `OnboardingFlow` owns where they sit; the steps draw none of them.
//  Edit Profile's interests take the same Next pill.
//

import SwiftUI

/// The Big art look's measures (BP app onboarding 43, mock v2 `.phone`, `.screen`, `.pic`).
enum BigArt {
    /// A step's colour is solid this far down the screen, and has faded into the canvas by `fadeEnd`.
    static let solid: CGFloat = 150
    static let fadeEnd: CGFloat = 440
    /// The drawing's row starts 104 pt down and is 128 pt tall; the drawing in it is 124 pt tall.
    static let top: CGFloat = 104
    static let row: CGFloat = 128
    static let art: CGFloat = 124
    /// On a phone under `shortScreen` tall (the iPhone SE's 667), Birthday's cake is 112 pt in a 116 pt
    /// row, so the date clears Next (onboarding 47).
    static let shortScreen: CGFloat = 700
    static let shortArt: CGFloat = 112
    /// The colour glides to the next step's, and a dash fills, over the mock's 420 ms out-quint.
    static let glide: Animation = Motion.outQuint(0.42)
}

/// What lies behind every onboarding screen after the Welcome: Luma's pale grey, Log in and Create
/// account included, so white cards stand off it (mock v8 `--canvas`). A step in the Big art look
/// passes its colour: solid for the top 150 pt, then fading into the near-white canvas by 440 pt.
struct OnboardingBackdrop: View {
    var tint: Color? = nil
    /// Interests' Dusk over everything (onboarding 48): fades in and out as the step comes and goes.
    var deep = false
    /// Follow 3's night over that (onboarding 50).
    var night = false
    /// Clubhouse's Name and Photo steps (onboarding 55): the colour all the way down, no fade.
    var flat = false

    var body: some View {
        ZStack(alignment: .top) {
            tint == nil ? Hue.onboardingCanvas : Hue.bigArtCanvas
            (tint ?? Hue.onboardingCanvas).opacity(flat ? 1 : 0)
            // One colour under a still mask, so a move between steps glides the colour alone.
            (tint ?? Hue.onboardingCanvas)
                .frame(height: BigArt.fadeEnd)
                .mask {
                    LinearGradient(stops: [.init(color: .black, location: 0),
                                           .init(color: .black, location: BigArt.solid / BigArt.fadeEnd),
                                           .init(color: .clear, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
            // Mock v5: the top colour to 32% down, then into the bottom one.
            sky(Hue.deepTop, Hue.deepBottom).opacity(deep ? 1 : 0)
            sky(Hue.nightTop, Hue.nightBottom).opacity(night ? 1 : 0)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func sky(_ top: Color, _ bottom: Color) -> some View {
        LinearGradient(stops: [.init(color: top, location: 0), .init(color: top, location: 0.32),
                               .init(color: bottom, location: 1)],
                       startPoint: .top, endPoint: .bottom)
    }
}

/// Where a scrolling step meets the top row: the colour behind it fading out over 16 pt.
struct OnboardingScrollEdge: View {
    var color = Hue.onboardingCanvas
    var body: some View {
        LinearGradient(colors: [color, color.opacity(0)], startPoint: .top, endPoint: .bottom)
            .frame(height: 16)
            .padding(.top, FollowGridMetric.scrollTop)
            .allowsHitTesting(false)
    }
}

/// The back chevron at the top left of every question step: Luma's thin ink chevron, 44 pt to tap,
/// sinking under the finger.
struct OnboardingBackChevron: View {
    /// White on Interests' deep backdrop (onboarding 48).
    var color = Hue.ink
    let action: () -> Void
    var body: some View {
        Button(action: { Haptics.selection(); action() }) {
            Image(systemName: "chevron.left")
                .font(.glyph(20, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.press(.squish))
        .accessibilityLabel("Back")
    }
}

/// One dash for each step (BP app onboarding 43, mock v2 `.dash`; Posh's tracker): 4 pt tall, 4 pt
/// apart, ink on a track of ink at 14%. This step's dash fills from its start over 0.42 s as the step
/// arrives, and the next one empties on Back. Reduce Motion changes them at once.
struct OnboardingProgressBar: View {
    /// 1 to `total`.
    let index: Int
    let total: Int
    /// White on a white track at 28%, over Interests' deep backdrop (onboarding 48, mock v5 `.dash`).
    var deep = false

    static let height: CGFloat = 4
    static let gap: CGFloat = 4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Self.gap) {
            ForEach(1...max(total, 1), id: \.self) { dash in
                Capsule()
                    .fill(deep ? Hue.deepTrack : Hue.ink.opacity(0.14))
                    .overlay {
                        Capsule().fill(deep ? Color.white : Hue.ink)
                            .scaleEffect(x: dash <= index ? 1 : 0, anchor: .leading)
                    }
                    .clipShape(Capsule())
            }
        }
        .frame(height: Self.height)
        .animation(reduceMotion ? nil : BigArt.glide, value: index)
        .animation(reduceMotion ? nil : BigArt.glide, value: deep)
        .accessibilityElement()
        .accessibilityLabel("Step \(index) of \(total)")
    }
}

/// What sits over a question in Luma's look: a 52 pt grey circle holding a small grey SF Symbol where
/// the wordmark used to sit, then the question 18 pt under it, 24 pt semibold on a 30 pt line.
struct OnboardingHeading: View {
    let symbol: String
    let question: String
    @AccessibilityFocusState.Binding var focused: Bool

    static let disc: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: symbol)
                .font(.glyph(24, weight: .regular))
                .foregroundStyle(Hue.onboardingIcon)
                .frame(width: Self.disc, height: Self.disc)
                .background(Hue.onboardingField, in: Circle())
                .accessibilityHidden(true)
            OnboardingQuestion(question)
                .accessibilityFocused($focused)
        }
    }
}

/// What sits over a question in the Big art look (BP app onboarding 43, mock v2 `.pic`, `.q`, `.sub`):
/// one drawing, centred in a 128 pt row, which pops in as the step arrives; 14 pt under it the question,
/// centred, 26 pt bold on a 31 pt line; then, on Under 13, its grey line, centred. Reduce Motion skips the pop.
struct OnboardingBigArt<Art: View>: View {
    let question: String
    var line: String? = nil
    /// The drawing's row: 4 pt taller than the drawing.
    var row: CGFloat = BigArt.row
    @AccessibilityFocusState.Binding var focused: Bool
    @ViewBuilder let art: Art

    @State private var arrived = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            art
                .frame(height: row)
                // The mock's pop, 480 ms out-quint after 60 ms: from 72%, 10 pt low and clear, to 105% and
                // solid in the first 80 ms, then easing down to rest.
                .keyframeAnimator(initialValue: BigArtPop(), trigger: arrived) { art, pop in
                    art.scaleEffect(pop.scale).offset(y: pop.drop).opacity(pop.opacity)
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        MoveKeyframe(0.72)
                        LinearKeyframe(0.72, duration: 0.06)
                        LinearKeyframe(1.05, duration: 0.08)
                        LinearKeyframe(1, duration: 0.4, timingCurve: .easeOut)
                    }
                    KeyframeTrack(\.drop) {
                        MoveKeyframe(10)
                        LinearKeyframe(10, duration: 0.06)
                        LinearKeyframe(0, duration: 0.08)
                    }
                    KeyframeTrack(\.opacity) {
                        MoveKeyframe(0)
                        LinearKeyframe(0, duration: 0.06)
                        LinearKeyframe(1, duration: 0.08)
                    }
                }
                .padding(.bottom, 14)
            Text(question)
                .appleFont(26, weight: .bold)   // SF's own line at 26 pt is the mock's 31
                .kerning(-0.52)                 // the mock's -.02em
                .foregroundStyle(Hue.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focused)
            if let line {
                Text(line)
                    .font(.apple(15))
                    .lineSpacing(3)            // SF's 18 pt line at 15 pt, to the mock's 21
                    .foregroundStyle(Hue.bigArtWords)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 7.5)        // 6 pt under the question, and half that line's extra 3
                    .padding(.bottom, 1.5)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { if !reduceMotion { arrived = true } }
    }
}

/// The drawing's pop: at rest unless the keyframes above are playing.
private struct BigArtPop {
    var scale: CGFloat = 1
    var drop: CGFloat = 0
    var opacity: Double = 1
}

/// The grey line under a question (mock v8 `.sub`): 15 pt, 6 pt under it.
struct OnboardingSubline: View {
    let words: String
    init(_ words: String) { self.words = words }
    var body: some View {
        Text(words)
            .font(.apple(15))
            .foregroundStyle(Hue.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
    }
}

/// The question alone: Apple's font, 24 pt semibold, 30 pt line, ink.
struct OnboardingQuestion: View {
    let words: String
    init(_ words: String) { self.words = words }
    var body: some View {
        Text(words)
            .appleFont(24, weight: .semibold)
            .lineSpacing(1.4)   // SF's 28.6 pt line at 24 pt, to the mock's 30
            .kerning(-0.36)     // the mock's -.015em
            .foregroundStyle(Hue.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The one primary button, Luma's flat black pill: 48 pt, no raised edge. Pressed, it squishes to
/// 97% (`Press`, the 5 pt any width loses, 97% at this width) and lifts to `Hue.nextPressed` over 80 ms,
/// then springs back, with a light haptic on the press-down. Not allowed, it greys and shakes instead of
/// acting, so it stays tappable: a disabled button could not shake. The same pill on every step.
struct OnboardingNextBar: View {
    let title: String
    /// What's still to pick or follow, so the title's number rolls the way it goes.
    var count = 0
    var allowed = true
    /// Log in or Create account is waiting on the server: a spinner for the words, taps ignored.
    var busy = false
    /// Bumped when the server said no (a wrong password): the bar shakes as on a tap too early.
    var refused = 0
    /// White with ink words on Interests' deep backdrop, white at 26% while not allowed (onboarding 48, mock v5 `.btn`).
    var deep = false
    /// Its not-allowed fill is solid on Follow 3's night, where places scroll under it (onboarding 50).
    var night = false
    /// Clubhouse's "Next →" on the Name and Photo steps (onboarding 55): 20 pt words and an arrow, on the
    /// `narrow` pill. VoiceOver hears the title alone.
    var arrow = false
    let action: () -> Void

    static let height: CGFloat = 48
    /// Clubhouse's pill, 199.3 x 49.3 pt measured (`references/profile-clubhouse/SPEC.md`).
    static let narrow: CGFloat = 199
    static let narrowHeight: CGFloat = 49

    @State private var shakes = 0
    /// The arrow and the 8 pt before it, at 20 pt (title3), growing with large text.
    @ScaledMetric(relativeTo: .title3) private var arrowRoom: CGFloat = 28

    var body: some View {
        Button {
            if busy { return }
            if allowed { action() } else { shakes += 1; Haptics.error() }
        } label: {
            // One view around the branches: bare, the style's frame and capsule went round each branch, and a
            // move to or from the Name and Photo steps cross-faded two pills (onboarding 55's frames).
            // The one "Next" stays put between the pills; only the arrow comes and goes.
            ZStack {
                if busy {
                    ProgressView().tint(allowed ? Hue.surface : Hue.nextOffWords)
                } else {
                    HStack(spacing: 0) {
                        Text(title)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            // "Follow 3 more" rolls to 2, and back up on an unfollow (onboarding 26): Apple's
                            // number roll, the bar holding still.
                            .contentTransition(.numericText(value: Double(count)))
                            .animation(.snappy, value: title)
                        // Always here, shut to nothing off the Name and Photo steps: added and taken away, it
                        // trailed behind on the wrong side of Next as the pill changed width.
                        Image(systemName: "arrow.right")
                            .padding(.leading, 8)
                            .frame(width: arrow ? arrowRoom : 0, alignment: .leading)
                            .opacity(arrow ? 1 : 0)
                    }
                    .font(arrow ? .apple(20, weight: .semibold) : .apple(17, weight: .semibold))
                }
            }
        }
        .buttonStyle(NextBarStyle(allowed: allowed, deep: deep, night: night, height: arrow ? Self.narrowHeight : Self.height))
        .keyframeAnimator(initialValue: CGFloat(0), trigger: shakes) { bar, x in
            bar.offset(x: x)
        } keyframes: { _ in
            LinearKeyframe(-6, duration: 0.06)
            LinearKeyframe(5, duration: 0.06)
            LinearKeyframe(-3, duration: 0.06)
            LinearKeyframe(1, duration: 0.06)
            LinearKeyframe(0, duration: 0.06)
        }
        .onChange(of: refused) { shakes += 1; Haptics.error() }
        .accessibilityIdentifier("onboarding-next")
        .accessibilityLabel(title)   // the spinner too
        .accessibilityHint(allowed ? "" : "Not yet: answer the question first")
    }
}

private struct NextBarStyle: ButtonStyle {
    let allowed: Bool
    let deep: Bool
    let night: Bool
    let height: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed && allowed
        return configuration.label
            .foregroundStyle(words)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background {
                Capsule()
                    .fill(fill(down: down))
                    .animation(.easeOut(duration: Press.inSeconds), value: down)
            }
            .contentShape(Capsule())
            .press(.squish, down: down)
            .animation(.easeOut(duration: 0.2), value: allowed)
            .onChange(of: down) { _, pressed in if pressed { Haptics.light() } }
            .animation(.easeOut(duration: 0.2), value: deep)
    }

    private var words: Color {
        if deep { return allowed ? Hue.deepPillWords : Hue.deepOffWords }
        return allowed ? Hue.surface : Hue.nextOffWords
    }

    private func fill(down: Bool) -> Color {
        if deep { return allowed ? (down ? Hue.deepPressed : Color.white) : night ? Hue.nightOff : Hue.deepOff }
        return allowed ? (down ? Hue.nextPressed : Hue.ink) : Hue.nextOff
    }
}

/// The Phone and Code steps' small black pill, Hinge's (BP app onboarding 44 and 45): 120 x 48, faded to 28% until
/// it may go, sinking to 97% as the mock's does. Tapped too early, Continue shakes.
struct OnboardingHingePill: View {
    let title: String
    let size: CGFloat
    let allowed: Bool
    let busy: Bool
    /// Bumped when the server said no: the pill shakes as on a tap too early.
    let refused: Int
    /// Verify faded answers nothing (the mock's).
    var shakesEarly = true
    let action: () -> Void

    @State private var shakes = 0

    var body: some View {
        Button {
            if busy { return }
            if allowed { action() } else if shakesEarly { shakes += 1; Haptics.error() }
        } label: {
            ZStack {
                if busy {
                    ProgressView().tint(Hue.hingeWhite)
                } else {
                    Text(title).appleFont(size, weight: .medium)
                }
            }
            .foregroundStyle(Hue.hingeWhite)
            .frame(minWidth: 120, minHeight: 48)
        }
        .buttonStyle(HingePillStyle(allowed: allowed && !busy))
        .opacity(allowed ? 1 : 0.28)
        .animation(.easeOut(duration: 0.16), value: allowed)
        .modifier(HingeShake(trigger: shakes, way: (-7, 6, -4, 2), seconds: 0.32))
        .onChange(of: refused) { shakes += 1 }
        .accessibilityIdentifier("phone-next")
        .accessibilityLabel(title)   // the spinner too
        .accessibilityHint(allowed ? "" : "Not yet: fill it in first")
    }
}

private struct HingePillStyle: ButtonStyle {
    let allowed: Bool

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed && allowed
        return configuration.label
            .background {
                Capsule().fill(down ? Hue.hingePillDown : Hue.hingePill)
            }
            .contentShape(Capsule())
            .scaleEffect(down ? Press.shallowest : 1)
            .animation(down ? .easeOut(duration: Press.inSeconds) : Motion.outQuint(0.16), value: down)
            .onChange(of: down) { _, pressed in if pressed { Haptics.light() } }
    }
}

/// Luma's field: a soft grey box, 46 pt tall, 12 pt corners, the words 16 pt in. Focused, a 1.5 pt
/// ink line inside its edge (mock v8 `.field.on`). Grows with the text inside it.
struct OnboardingFieldBox: ViewModifier {
    var focused = false
    static let height: CGFloat = 46
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
        content
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: Self.height, alignment: .leading)
            .background(Hue.onboardingField, in: shape)
            .overlay(shape.strokeBorder(Hue.ink, lineWidth: focused ? 1.5 : 0))
    }
}

extension View {
    func onboardingField(focused: Bool = false) -> some View { modifier(OnboardingFieldBox(focused: focused)) }

    /// The Big art look's box (BP app onboarding 43, mock v2 `.field`, `.gp`): white with 12 pt corners,
    /// a hair of ink round it and a soft 1 pt shadow under it. Picked (a gender pill), it is flat ink.
    func bigArtBox(picked: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
        return background {
            shape.fill(picked ? Hue.ink : Hue.surface)
                .shadow(color: Hue.ink.opacity(picked ? 0 : 0.06), radius: 1, y: 1)
        }
        .overlay(shape.inset(by: -1).strokeBorder(Hue.ink.opacity(picked ? 0 : 0.04), lineWidth: 1))
    }
}

/// The small grey label over a field, 6 pt above it (mock v8 `.flabel`). A Big art step passes its own grey.
struct OnboardingFieldLabel: View {
    let words: String
    let color: Color
    init(_ words: String, color: Color = Hue.inkSecondary) { self.words = words; self.color = color }
    var body: some View {
        Text(words)
            .font(.apple(13))
            .foregroundStyle(color)
            .padding(.bottom, 6)
    }
}

/// The Skip / Not now / I already have an account link under the Next bar: ink words that
/// sink to 95% and dim under the finger.
struct OnboardingLink: View {
    let title: String
    /// The Photo step's Skip is Clubhouse's grey 17 pt (onboarding 55): `inkSecondary`, not Clubhouse's lighter
    /// grey, which reads under 4.5:1 on white.
    var font: Font = .apple(15, weight: .semibold)
    var color: Color = Hue.ink
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(font)
                .foregroundStyle(color)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.press(.dim))
    }
}

/// The search box over Follow 3's places and Contacts' people: Luma's 40 pt grey box, no edge, `top`
/// under the question (16 pt; Contacts' pinned one sets its own room).
struct OnboardingSearchField: View {
    let prompt: String
    @Binding var query: String
    @FocusState private var searching: Bool

    static let height: CGFloat = 40

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.glyph(15, weight: .semibold))
                .foregroundStyle(Hue.inkSecondary)
            TextField(prompt, text: $query, prompt: Text(prompt).foregroundStyle(Hue.inkSecondary))
                .font(.apple(16))
                .foregroundStyle(Hue.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .focused($searching)
        }
        .padding(.horizontal, 12)
        // 40 pt, growing with large text so its words aren't cut.
        .padding(.vertical, 6)
        .frame(minHeight: Self.height)
        .background(Hue.onboardingField, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        // The whole box takes the tap, not only the line of text.
        .contentShape(Rectangle())
        .onTapGesture { searching = true }
    }
}
