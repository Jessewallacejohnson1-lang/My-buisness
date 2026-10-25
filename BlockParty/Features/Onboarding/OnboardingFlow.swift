//
//  OnboardingFlow.swift
//  Block Party — the first-launch onboarding (BP app docs/plans/onboarding, ticket 16): the
//  Welcome (Nextdoor's layout, ticket 25 mock), then nine question steps on one fixed frame:
//  the faint yellow backdrop, back and the progress bar on top, the wordmark, and the one
//  Next bar 84 pt from the bottom with its slot under it. Only the question moves between
//  steps. The steps are placeholders, a question each, until tickets 17 to 24 fill them.
//

import SwiftUI

/// The flow's steps in order. The bar counts the nine after the Welcome.
enum OnboardingStep: Int, CaseIterable {
    case welcome, phone, code, name, photo, birthday, interests, follow, friends, contacts

    static let barTotal = 9

    var question: String {
        switch self {
        case .welcome:   "Love where\nyou live."
        case .phone:     "What's your phone number?"
        case .code:      "Enter the code we texted you"
        case .name:      "What's your name?"
        case .photo:     "Add a profile picture"
        case .birthday:  "When's your birthday?"
        case .interests: "What do you love doing?"
        case .follow:    "Follow 3 places"
        case .friends:   "Find your friends"
        case .contacts:  "Friends on Block Party"
        }
    }

    /// The link in the slot under the Next bar, where the step has one.
    var slot: String? {
        switch self {
        case .photo:   "Skip"
        case .friends: "Not now"
        default:       nil
        }
    }
}

/// Where the neighbour is in onboarding, saved on every change so a relaunch resumes there,
/// and whether they have finished it (then it never shows again).
@Observable
final class OnboardingStore {
    private(set) var step: OnboardingStep
    private(set) var finished: Bool
    /// The way the last move went, so the next question slides in from the right side.
    private(set) var forward = true

    private let defaults: UserDefaults
    private static let stepKey = "onboarding.step"
    private static let finishedKey = "onboarding.finished"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        step = OnboardingStep(rawValue: defaults.integer(forKey: Self.stepKey)) ?? .welcome
        finished = defaults.bool(forKey: Self.finishedKey)
    }

    /// 1 to 9 on the question steps, 0 on the Welcome.
    var barIndex: Int { step.rawValue }

    func next() {
        guard let after = OnboardingStep(rawValue: step.rawValue + 1) else { return finish() }
        move(to: after, forward: true)
    }

    func back() {
        guard let before = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        move(to: before, forward: false)
    }

    /// "Not now" on Find your friends skips Contacts too (SPEC step 9).
    func skipFriends() { finish() }

    func finish() {
        finished = true
        defaults.set(true, forKey: Self.finishedKey)
    }

    /// The server's `onboarded_at` says this account finished on another install. Taken only
    /// on the Welcome, so a slow read can't pull someone out halfway through.
    func serverSaysFinished() {
        guard step == .welcome else { return }
        finish()
    }

    private func move(to new: OnboardingStep, forward: Bool) {
        self.forward = forward
        step = new
        defaults.set(new.rawValue, forKey: Self.stepKey)
    }
}

struct OnboardingFlow: View {
    let store: OnboardingStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var questionFocused: Bool
    @State private var keyboardUp = false

    /// Out-quint over 0.34 s, the mock's question slide.
    private static let slide: Animation = .timingCurve(0.22, 1, 0.36, 1, duration: 0.34)

    var body: some View {
        // The question frame sits under the Welcome the whole time, so the Welcome fades off
        // the chrome rather than off a blank screen, and only the question slides in.
        ZStack {
            questions
                .accessibilityHidden(store.step == .welcome)
            if store.step == .welcome {
                OnboardingWelcome(start: go { [store] in store.next() })
                    .zIndex(1)
                    .transition(.opacity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(Motion.sheet) { keyboardUp = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(Motion.sheet) { keyboardUp = false }
        }
    }

    /// Every question step: the backdrop, the fixed top row and Next bar, and the one part
    /// that moves, the question.
    private var questions: some View {
        ZStack(alignment: .top) {
            OnboardingBackdrop()

            if store.step != .welcome {
                question
                    .id(store.step)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .offset(x: store.forward ? 36 : -36).combined(with: .opacity),
                        removal: .opacity.animation(.easeOut(duration: 0.12))))
            }

            HStack(spacing: 6) {
                OnboardingBackChevron(action: go { [store] in store.back() })
                OnboardingProgressBar(index: store.barIndex, total: OnboardingStep.barTotal)
            }
            .padding(.leading, 10)
            .padding(.trailing, 32)
            .padding(.top, 56)
            .ignoresSafeArea(.container)
        }
        .overlay(alignment: .bottom) { bottom }
    }

    private var question: some View {
        VStack(alignment: .leading, spacing: 32) {
            BlockPartyWordmark(height: 33)
                .foregroundStyle(Hue.ink)
            Text(store.step.question)
                .font(.display(30))
                .lineSpacing(-6)   // Jost's 44 pt line to the mock's 38
                .foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($questionFocused)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
        .padding(.top, 128)
        .ignoresSafeArea(.container)
        .onAppear { questionFocused = true }
    }

    /// The Next bar, 84 pt from the bottom with a fixed 44 pt slot under it, or 12 pt above an
    /// open keyboard (the slot hides behind the keyboard then).
    private var bottom: some View {
        VStack(spacing: 6) {
            OnboardingNextBar(title: "Next", allowed: nextAllowed, action: go { [store] in store.next() })
            if !keyboardUp { slot.frame(height: 44) }
        }
        .padding(.horizontal, 24)
        // The home indicator's 34 pt safe area is the mock's 34 under the slot; the keyboard's
        // safe area carries the bar up with it.
        .padding(.bottom, keyboardUp ? 12 : 0)
    }

    /// Skip on Photo, Not now on Find your friends (which skips Contacts too), else empty.
    @ViewBuilder private var slot: some View {
        if let title = store.step.slot {
            OnboardingLink(title: title, action: go { [store] in
                if store.step == .friends { store.skipFriends() } else { store.next() }
            })
        } else {
            Color.clear
        }
    }

    /// Placeholders always allow Next; a step that asks something says when it may (17 to 24).
    /// DEBUG `-onboarding-not-yet` holds it grey, to show the shake.
    private var nextAllowed: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-onboarding-not-yet") { return false }
        #endif
        return true
    }

    /// A move between steps, on the slide's timing.
    private func go(_ move: @escaping () -> Void) -> () -> Void {
        { withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Self.slide) { move() } }
    }
}

/// Step 1, Nextdoor's welcome in BP's words (ticket 25 mock, Jesse 2026-10-24): a St. Joseph
/// photo full bleed (a stand-in until Jesse's comes), the white wordmark and headline top
/// left, two white pills where Nextdoor's last two sit, the Terms line and Log in. Until
/// ticket 25 wires Apple, both pills go to the first question. Log in opens the existing
/// sign-in.
struct OnboardingWelcome: View {
    let start: () -> Void

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var loggingIn = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            photo
            header
            actions
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .onAppear { shown = true }
        .sheet(isPresented: $loggingIn) { LoginView() }
        // Signed into a real account: the sheet's job is done.
        .onChange(of: auth.isAnonymous) { _, anonymous in if !anonymous && auth.isSignedIn { loggingIn = false } }
    }

    /// The white wordmark at 88 pt and the headline at 150 pt, 24 pt from the left.
    private var header: some View {
        let mark = 180 / BlockPartyWordmark.aspect
        return VStack(alignment: .leading, spacing: 0) {
            BlockPartyWordmark(height: mark)
                .foregroundStyle(.white)
                .rise(shown, delay: 0)
            Text(OnboardingStep.welcome.question)
                .font(.sansHeadline(36))
                .lineSpacing(-4)   // BP Body's 44 pt line to the mock's 40
                .foregroundStyle(.white)
                .padding(.top, 150 - 88 - mark)
                .accessibilityAddTraits(.isHeader)
                .rise(shown, delay: 0.06)
        }
        .padding(.horizontal, 24)
        .padding(.top, 88)
    }

    private var terms: Text {
        let terms = Text("Terms").fontWeight(.semibold).underline()
        let privacy = Text("Privacy Policy").fontWeight(.semibold).underline()
        return Text("By continuing, you agree to our \(terms) and \(privacy).")
    }

    /// The two pills, the Terms line and Log in, from the bottom up.
    private var actions: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                WelcomePill(title: "Continue with Apple", symbol: "apple.logo", action: start)
                    .rise(shown, delay: 0.16)
                WelcomePill(title: "Continue with phone", symbol: "iphone", action: start)
                    .rise(shown, delay: 0.22)
            }
            .padding(.horizontal, 24)
            terms
                .font(.sans(13))
                .foregroundStyle(.white.opacity(0.88))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 18)
                .rise(shown, delay: 0.3)
            Button { loggingIn = true } label: { logIn }
                .buttonStyle(WelcomePress(scale: 0.96, dim: 0.7))
                .padding(.top, 10)
                .rise(shown, delay: 0.3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 61)
    }

    private var logIn: some View {
        Text("Already have an account? \(Text("Log in").fontWeight(.semibold))")
            .font(.sans(15))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }

    /// The photo, with Nextdoor's scrims: darker at the top for the headline and at the bottom
    /// for the small print. ponytail: a drawn stand-in; swap in Jesse's St. Joseph photo (ticket 25).
    private var photo: some View {
        ZStack {
            LinearGradient(stops: [.init(color: Hue.welcomeStandInTop, location: 0),
                                   .init(color: Hue.welcomeStandInMid, location: 0.55),
                                   .init(color: Hue.welcomeStandInLow, location: 1)],
                           startPoint: .top, endPoint: .bottom)
            EllipticalGradient(colors: [Hue.welcomeStandInGreen, Hue.welcomeStandInGreen.opacity(0)],
                               center: UnitPoint(x: 0.3, y: 0.55), endRadiusFraction: 0.7)
            EllipticalGradient(colors: [Hue.welcomeStandInWarm, Hue.welcomeStandInWarm.opacity(0)],
                               center: UnitPoint(x: 0.8, y: 0.75), endRadiusFraction: 0.7)
            LinearGradient(stops: [.init(color: Hue.welcomeScrim.opacity(0.45), location: 0),
                                   .init(color: Hue.welcomeScrim.opacity(0), location: 0.34),
                                   .init(color: Hue.welcomeScrim.opacity(0), location: 0.58),
                                   .init(color: Hue.welcomeScrim.opacity(0.5), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .accessibilityHidden(true)
    }
}

/// A white 48 pt pill on the Welcome: sinks to 97% and greys a touch under the finger.
private struct WelcomePill: View {
    let title: String
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.glyph(19, weight: .medium))
                Text(title).font(.sansSemibold(17))
            }
            .foregroundStyle(Hue.onBrandDisc)
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(WelcomePress(scale: 0.97, dim: 1, pill: true))
    }
}

private struct WelcomePress: ButtonStyle {
    let scale: CGFloat
    let dim: Double
    var pill = false
    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        configuration.label
            .background { if pill { Capsule().fill(down ? Hue.welcomePillDown : .white) } }
            .scaleEffect(down ? scale : 1)
            .opacity(down ? dim : 1)
            .animation(down ? .easeOut(duration: 0.08) : .spring(response: 0.12, dampingFraction: 0.62), value: down)
            .onChange(of: down) { _, pressed in if pressed { Haptics.light() } }
    }
}

private extension View {
    /// The Welcome's entrance: up 14 pt and in over 0.55 s, out-quint, after `delay`.
    func rise(_ shown: Bool, delay: Double) -> some View {
        modifier(Rise(shown: shown, delay: delay))
    }
}

private struct Rise: ViewModifier {
    let shown: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.55).delay(delay), value: shown)
    }
}
