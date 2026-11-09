//
//  OnboardingChrome.swift
//  Block Party — the pieces every onboarding question screen shares, in Luma's look (BP app
//  onboarding 34, mock v8): the pale grey canvas, the back chevron, the 4 pt progress line, the icon
//  circle over the question, the one Next pill, the grey field box. `OnboardingFlow` owns where they
//  sit; the steps draw none of them. Edit Profile's interests take the same Next pill.
//

import SwiftUI

/// Luma's pale grey behind every onboarding screen after the Welcome, Log in and Create account
/// included, so white cards stand off it (mock v8 `--canvas`). It was plain white from 2026-11-02.
struct OnboardingBackdrop: View {
    var body: some View {
        Hue.onboardingCanvas
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// The back chevron at the top left of every question step: Luma's thin ink chevron, 44 pt to tap,
/// sinking under the finger.
struct OnboardingBackChevron: View {
    let action: () -> Void
    var body: some View {
        Button(action: { Haptics.selection(); action() }) {
            Image(systemName: "chevron.left")
                .font(.glyph(20, weight: .medium))
                .foregroundStyle(Hue.ink)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.press(.squish))
        .accessibilityLabel("Back")
    }
}

/// A 4 pt ink line on a grey track (mock v8). Each step it glides to its mark over 0.42 s on the
/// mock's out-quint and stops: no overshoot, stripe or glint. Reduce Motion cross-fades it instead.
struct OnboardingProgressBar: View {
    /// 1 to `total`.
    let index: Int
    let total: Int

    static let height: CGFloat = 4
    /// The mock's `cubic-bezier(.22,1,.36,1)` over 420 ms.
    static let glide: Animation = .timingCurve(0.22, 1, 0.36, 1, duration: 0.42)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width * CGFloat(index) / CGFloat(max(total, 1))
            Capsule()
                .fill(Hue.onboardingTrack)
                .overlay(alignment: .leading) {
                    if reduceMotion {
                        // A new fill per step, faded over the old one, so nothing slides.
                        Capsule().fill(Hue.ink).frame(width: w)
                            .id(index)
                            .transition(.opacity)
                            .animation(.easeOut(duration: 0.2), value: index)
                    } else {
                        Capsule().fill(Hue.ink).frame(width: w)
                            .animation(Self.glide, value: index)
                    }
                }
        }
        .frame(height: Self.height)
        .accessibilityElement()
        .accessibilityLabel("Step \(index) of \(total)")
    }
}

/// What sits over every question, Luma's: a 52 pt grey circle holding a small grey SF Symbol where
/// the wordmark used to sit, then the question 18 pt under it, 24 pt semibold on a 30 pt line.
/// Birthday's alone is Jesse's cake, 36 pt tall in a lilac circle: the one coloured icon (onboarding 36).
struct OnboardingHeading: View {
    let symbol: String
    let question: String
    /// Draws Jesse's cake in place of the symbol.
    var cake = false
    @AccessibilityFocusState.Binding var focused: Bool

    static let disc: CGFloat = 52
    /// Jesse's drawing (BP app references/birthday-icon), as the Going chat's birthday ask shows it.
    static let cakeImage = "BirthdayCake"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Group {
                if cake {
                    Image(decorative: Self.cakeImage)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 36)
                } else {
                    Image(systemName: symbol)
                        .font(.glyph(24, weight: .regular))
                        .foregroundStyle(Hue.onboardingIcon)
                }
            }
            .frame(width: Self.disc, height: Self.disc)
            .background(cake ? Hue.birthdayDisc : Hue.onboardingField, in: Circle())
            .accessibilityHidden(true)
            OnboardingQuestion(question)
                .accessibilityFocused($focused)
        }
    }
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
    /// Profile's Save Profile (onboarding 35): Luma's 352 x 49 pt pill, words at 17 pt medium, a soft
    /// shadow under it, in the same spot (its bottom edge where every step's sits).
    var profile = false
    let action: () -> Void

    static let height: CGFloat = 48
    static let profileSize = CGSize(width: 352, height: 49)

    @State private var shakes = 0

    var body: some View {
        Button {
            if busy { return }
            if allowed { action() } else { shakes += 1; Haptics.error() }
        } label: {
            if busy {
                ProgressView().tint(.white)
            } else {
                Text(title)
                    .font(.apple(17, weight: profile ? .medium : .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    // "Follow 3 more" rolls to 2, and back up on an unfollow (onboarding 26): Apple's number
                    // roll, the bar holding still.
                    .contentTransition(.numericText(value: Double(count)))
                    .animation(.snappy, value: title)
            }
        }
        .buttonStyle(NextBarStyle(allowed: allowed, profile: profile))
        .frame(maxWidth: profile ? Self.profileSize.width : .infinity)
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
    var profile = false

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed && allowed
        let on = profile ? Hue.saveProfile : Hue.ink
        let off = profile ? Hue.saveProfileOff : Hue.nextOff
        return configuration.label
            .foregroundStyle(allowed ? Color.white : (profile ? Hue.saveProfileOffWords : Hue.nextOffWords))
            .frame(maxWidth: .infinity)
            .frame(height: profile ? OnboardingNextBar.profileSize.height : OnboardingNextBar.height)
            .background {
                Capsule()
                    .fill(allowed ? (down ? Hue.nextPressed : on) : off)
                    // Luma's soft shadow under Save Profile (mock v8 `0 12px 24px -12px`).
                    .shadow(color: Hue.ink.opacity(profile ? 0.2 : 0), radius: 10, y: 10)
                    .animation(.easeOut(duration: Press.inSeconds), value: down)
            }
            .contentShape(Capsule())
            .press(.squish, down: down)
            .animation(.easeOut(duration: 0.2), value: allowed)
            .onChange(of: down) { _, pressed in if pressed { Haptics.light() } }
    }
}

/// Luma's field: a soft grey box, 46 pt tall, 12 pt corners, the words 16 pt in. Focused, a 1.5 pt
/// ink line inside its edge (mock v8 `.field.on`). Grows with the text inside it.
struct OnboardingFieldBox: ViewModifier {
    var focused = false
    static let height: CGFloat = 46
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        content
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: Self.height, alignment: .leading)
            .background(Hue.onboardingField, in: shape)
            .overlay(shape.strokeBorder(Hue.ink, lineWidth: focused ? 1.5 : 0))
    }
}

extension View {
    func onboardingField(focused: Bool = false) -> some View { modifier(OnboardingFieldBox(focused: focused)) }
}

/// The small grey label over a field, 6 pt above it (mock v8 `.flabel`).
struct OnboardingFieldLabel: View {
    let words: String
    init(_ words: String) { self.words = words }
    var body: some View {
        Text(words)
            .font(.apple(13))
            .foregroundStyle(Hue.inkSecondary)
            .padding(.bottom, 6)
    }
}

/// The Skip / Not now / I already have an account link under the Next bar: ink words that
/// sink to 95% and dim under the finger.
struct OnboardingLink: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.apple(15, weight: .semibold))
                .foregroundStyle(Hue.ink)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.press(.dim))
    }
}

/// The search box over Follow 3's places: Luma's 40 pt grey box, no edge, 16 pt under the question.
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
        .frame(height: Self.height)
        .background(Hue.onboardingField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        // The whole box takes the tap, not only the line of text.
        .contentShape(Rectangle())
        .onTapGesture { searching = true }
        .padding(.top, 16)
    }
}
