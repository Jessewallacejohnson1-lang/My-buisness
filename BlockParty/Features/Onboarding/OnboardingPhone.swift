//
//  OnboardingPhone.swift
//  Block Party — phone sign-in's two steps (BP app onboarding 17, 44, 45): "What's your phone number?" and
//  "Enter your verification code", copies of Hinge's with its layout, colours and words, in Apple's font
//  (Jesse, 2026-11-22). Measured in BP app `references/phone-hinge/SPEC.md` and `references/code-hinge/SPEC.md`.
//  One screen of its own, over onboarding's Welcome and Log in, and over Settings to change your number. It
//  draws its own X and its own small black pill, not onboarding's chrome: Hinge has neither dashes nor Next.
//

import SwiftUI

/// Phone sign-in's one switch. Off, the app is as it was before it (Continue with email, Log in with an email,
/// no number in Settings): no texts go until Jesse's Twilio account is open, and nobody meets a code that never
/// comes. DEBUG `-phone-sign-in` shows it on.
nonisolated enum PhoneSignIn {
    private static let textsWork = false

    static var isOn: Bool { textsWork || LaunchFlags.has(.phoneSignIn) }
}

/// Where a text may go (Jesse, 2026-11-23: two countries, so a bad day costs $10.58 and not $131). Both are +1
/// and ten digits, so only the flag differs.
nonisolated enum PhoneCountry: String, CaseIterable, Identifiable {
    case us, canada

    var id: String { rawValue }
    var flag: String { self == .us ? "🇺🇸" : "🇨🇦" }
    var name: String { self == .us ? "United States" : "Canada" }
    static let code = "+1"
}

/// A +1 number, as typed, sent and shown.
nonisolated enum PhoneNumber {
    static let length = 10

    /// The ten digits in what was typed, pasted or filled in: "+1 (320) 555-0142" is 3205550142.
    static func digits(_ text: String) -> String {
        var digits = text.filter { $0.isASCII && $0.isNumber }
        if digits.count > length, digits.hasPrefix("1") { digits.removeFirst() }
        return String(digits.prefix(length))
    }

    /// Hinge's spacing: "320 555 0142".
    static func spaced(_ digits: String) -> String {
        [digits.prefix(3), digits.dropFirst(3).prefix(3), digits.dropFirst(6)]
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// As the server takes it.
    static func sent(_ digits: String) -> String { PhoneCountry.code + digits }

    /// Ten digits, or eleven with the 1, and nothing an email has: Log in's one box holds a phone number.
    static func looksLike(_ text: String) -> Bool {
        let typed = text.trimmingCharacters(in: .whitespaces)
        let count = typed.filter(\.isNumber).count
        return typed.allSatisfy { $0.isASCII && ($0.isNumber || "+()-. ".contains($0)) }
            && (count == length || (count == length + 1 && digits(typed).count == length && typed.first { $0.isNumber } == "1"))
    }
}

/// What's typed on the two steps, and the server's answers.
@MainActor @Observable
final class PhoneForm: Identifiable {
    enum Stage { case number, code }

    /// The server, or a test's stand-in.
    struct Calls {
        var send: (String) async -> String?
        var verify: (_ code: String, _ phone: String) async -> AuthStore.CodeAnswer
        var signOut: () async -> Void
    }

    static let codeLength = 6
    /// The server texts one number this often (its `sms_max_frequency`): sooner, Continue goes back to the code sent.
    static let resendWait: TimeInterval = 30
    /// The boxes' shake, then they empty.
    static let shake: Duration = .milliseconds(340)

    /// Settings' change of number, not a sign-in.
    let changing: Bool
    var country = PhoneCountry.us
    var digits: String { didSet { if digits != oldValue { line = nil } } }
    var code = "" { didSet { if !code.isEmpty, code != oldValue { line = nil } } }
    private(set) var stage: Stage
    private(set) var busy = false
    /// Why the server said no: red, where the link or the pencil line was, until you type.
    private(set) var line: String?
    /// Bumped on each no, for the pill's shake, and on each wrong code, for the boxes'.
    private(set) var refusals = 0
    private(set) var wrongs = 0
    /// The way the last move went, so the step slides in from the right side.
    private(set) var forward = true
    /// The code that was right: what's left is what comes after it, and a retry sends no code again.
    private(set) var right: String?
    var checked: Bool { right != nil }

    private let calls: Calls
    /// The number this account has now, which a change can't be to.
    private let current: String?
    private var texted: (digits: String, at: Date)?
    private var out: Task<Void, Never>?

    /// `texted`: Log in already texted this number, so it opens on the code.
    init(changing: Bool = false, texted digits: String? = nil, current: String? = nil, calls: Calls) {
        self.changing = changing
        self.digits = digits ?? ""
        self.current = current.map(PhoneNumber.digits)
        self.calls = calls
        stage = digits == nil ? .number : .code
        texted = digits.map { ($0, Date()) }
    }

    /// Signing in or up, on the Welcome and Log in.
    static func signIn(texted digits: String? = nil) -> PhoneForm {
        let auth = AuthStore.shared
        return PhoneForm(texted: digits, calls: Calls(
            send: { await auth.sendCode(to: $0) },
            verify: { await auth.verifyCode($0, for: $1) },
            signOut: { await auth.signOut() }))
    }

    /// Settings' Phone number: the signed-in account's new one.
    static func change() -> PhoneForm {
        let auth = AuthStore.shared
        return PhoneForm(changing: true, current: auth.phone, calls: Calls(
            send: { await auth.sendChangeCode(to: $0) },
            verify: { await auth.verifyChangeCode($0, for: $1) },
            signOut: {}))
    }

    var canSend: Bool { digits.count == PhoneNumber.length }
    var canVerify: Bool { code.count == Self.codeLength }

    /// Continue: texts the code and goes on to its step. Short of ten digits the pill shakes instead.
    @discardableResult
    func send(now: Date = Date()) -> Task<Void, Never>? {
        guard canSend, !busy else { return nil }
        if digits == current { refuse(AuthStore.Words.samePhone); return nil }
        if let texted, texted.digits == digits, now.timeIntervalSince(texted.at) < Self.resendWait {
            go(to: .code)
            return nil
        }
        busy = true
        let number = digits
        let task = Task {
            let refused = await calls.send(PhoneNumber.sent(number))
            guard !Task.isCancelled else { return }
            busy = false
            if let refused { return refuse(refused) }
            texted = (number, Date())
            // Typed on while it was out: the code went to the number sent.
            digits = number
            go(to: .code)
        }
        out = task
        return task
    }

    /// Verify: checks the code, then runs `done` (what comes next), which answers a line when it couldn't go on.
    @discardableResult
    func verify(_ done: @escaping () async -> String?) -> Task<Void, Never>? {
        guard canVerify, !busy else { return nil }
        busy = true
        let typed = code
        let task = Task {
            if !checked {
                let answer = await calls.verify(typed, PhoneNumber.sent(digits))
                // Left (the X, the pencil) as the answer landed: nobody is signed in behind them.
                if Task.isCancelled {
                    if answer == .right { await calls.signOut() }
                    return
                }
                switch answer {
                case .right:
                    right = typed
                case .wrong:
                    return await wrong(typed)
                case .refused(let words):
                    busy = false
                    return refuse(words)
                }
            }
            let stuck = await done()
            guard !Task.isCancelled else { return }
            busy = false
            if let stuck { refuse(stuck) }
        }
        out = task
        return task
    }

    /// The pencil: back to the number, kept, to fix it or text a new code.
    func editNumber() {
        guard !checked else { return }
        leave()
        go(to: .number)
    }

    /// The X. A right code whose next step never loaded (no signal) is signed out, so nobody is left half in.
    func close() {
        leave()
        if checked, !changing { Task { await calls.signOut() } }
    }

    /// What the server still has out answers nobody.
    private func leave() {
        out?.cancel()
        out = nil
        busy = false
    }

    private func go(to new: Stage) {
        forward = new == .code
        code = ""
        line = nil
        stage = new
    }

    /// The line says so at once; the boxes shake, then empty.
    private func wrong(_ typed: String) async {
        busy = false
        wrongs += 1
        say(AuthStore.Words.wrongCode)
        try? await Task.sleep(for: Self.shake)
        if code == typed { code = "" }
    }

    private func refuse(_ words: String) {
        refusals += 1
        say(words)
    }

    private func say(_ words: String) {
        line = words
        Haptics.error()
        AccessibilityNotification.Announcement(words).post()
    }
}

/// The two steps on one screen: Hinge's fade and X stay, the step between them slides.
struct PhoneSignInScreen: View {
    @Bindable var form: PhoneForm
    /// The X: back to the Welcome, or Settings.
    let close: () -> Void
    /// The code is right: on to what comes next, or a line when it couldn't.
    let done: () async -> String?

    private enum Field { case number, code }
    @FocusState private var typing: Field?
    @AccessibilityFocusState private var heading: Bool
    /// What the number box shows, spaced; `form.digits` is the number.
    @State private var typed = ""
    @State private var whyOpen = false
    @State private var countryOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        ZStack(alignment: .top) {
            fade
            Group {
                switch form.stage {
                case .number: numberStep
                case .code: codeStep
                }
            }
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .offset(x: form.forward ? 36 : -36).combined(with: .opacity),
                removal: .opacity.animation(.easeOut(duration: 0.12))))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .top)
            closeButton
                .accessibilitySortPriority(1)
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : Motion.outQuint(0.34), value: form.stage)
        // Dark words and a dark clock on the fade, whatever the phone is set to.
        .environment(\.colorScheme, .light)
        // iOS 26 inks the clock white over the grey fade; Hinge's is black.
        .onAppear { AppearanceStore.shared.holdClock("phone", true); focus() }
        .onDisappear { AppearanceStore.shared.holdClock("phone", false) }
        .onChange(of: form.stage) { focus() }
        .sheet(isPresented: $countryOpen, onDismiss: focus) { countrySheet }
        .sheet(isPresented: $whyOpen, onDismiss: focus) { whySheet }
    }

    private func focus() {
        typed = PhoneNumber.spaced(form.digits)
        // VoiceOver hears the question first; everyone else gets the number pad.
        if voiceOver { heading = true } else { typing = form.stage == .number ? .number : .code }
    }

    // MARK: Phone (onboarding 44)

    private var numberStep: some View {
        VStack(spacing: 0) {
            lead(Self.numberTop)
            question("What's your phone\nnumber?", gutter: 40)
            Text("We only ask to verify it's you. It won't show up anywhere, including your profile.")
                .appleFont(14)
                .lineHeight(.multiple(factor: 17 / 14))
                .foregroundStyle(Hue.hingeSub)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
                .padding(.top, 16)
            HStack(spacing: 8.3) {
                countryBox
                numberBox
            }
            .padding(.horizontal, 20)
            .padding(.top, 61)
            underBoxes {
                if !form.changing {
                    Button { whyOpen = true } label: { underLine("What if my number changes?") }
                        .buttonStyle(.press(.dim))
                }
            }
            .padding(.top, 3)
            Spacer(minLength: 4)
            OnboardingHingePill(title: "Continue", size: 15, allowed: form.canSend, busy: form.busy,
                                refused: form.refusals) { form.send() }
            Text("Block Party will send you a text with a verification code. Message and data rates may apply.")
                .appleFont(10)
                .foregroundStyle(Hue.hingeSmall)
                .multilineTextAlignment(.center)
                .frame(width: 300)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 20)
                .padding(.bottom, 1)
        }
    }

    private var countryBox: some View {
        Button { countryOpen = true } label: {
            HStack(spacing: 0) {
                Text(form.country.flag).appleFont(20)
                Text(PhoneCountry.code).appleFont(18).lineLimit(1).fixedSize().padding(.leading, 11)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.glyph(17, weight: .bold))
                    .foregroundStyle(Hue.hingeChevron)
            }
            .foregroundStyle(Hue.hingeInk)
            .padding(.leading, 17)
            .padding(.trailing, 18)
            .frame(width: 113)
            .frame(minHeight: 56)
            .background(Hue.hingeBox, in: Self.box)
            .contentShape(Self.box)
        }
        .buttonStyle(.press(.squish))
        .accessibilityLabel("Country, \(form.country.name), \(PhoneCountry.code)")
    }

    private var numberBox: some View {
        TextField("", text: $typed)
            .textContentType(.telephoneNumber)
            .keyboardType(.numberPad)
            .focused($typing, equals: .number)
            .appleFont(18)
            .monospacedDigit()
            .kerning(0.2)
            .foregroundStyle(Hue.hingeInk)
            .tint(Hue.hingeCaret)
            .accessibilityLabel("Phone number")
            // Hinge's groups as they are typed: a binding that spaced them itself showed only on losing the keyboard.
            .onChange(of: typed) { _, now in
                form.digits = PhoneNumber.digits(now)
                let spaced = PhoneNumber.spaced(form.digits)
                if spaced != now { typed = spaced }
            }
            .padding(.leading, 21)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(Hue.hingeBox, in: Self.box)
            .contentShape(Self.box)
            .onTapGesture { typing = .number }
    }

    // MARK: Code (onboarding 45)

    private var codeStep: some View {
        VStack(spacing: 0) {
            lead(Self.codeTop)
            question("Enter your verification\ncode", gutter: 30)
            boxes
                .padding(.top, 64)
            underBoxes {
                Button { form.editNumber() } label: {
                    HStack(spacing: 9) {
                        underLine("Sent to \(PhoneNumber.spaced(form.digits)) •")
                        Image(systemName: "pencil").font(.glyph(15, weight: .semibold)).foregroundStyle(Hue.hingeInk)
                    }
                }
                .buttonStyle(.press(.dim))
                .accessibilityLabel("Sent to \(PhoneNumber.spaced(form.digits)). Edit number")
            }
            .padding(.top, 6)
            Spacer(minLength: 4)
            OnboardingHingePill(title: "Verify", size: 16, allowed: form.canVerify, busy: form.busy,
                                refused: form.refusals, shakesEarly: false) { form.verify(done) }
                .padding(.bottom, 1)
        }
    }

    /// Six boxes over one field you can't see, so iOS offers the code from Messages over the keypad and one tap
    /// fills them all.
    private var boxes: some View {
        let typed = Array(form.code)
        return HStack(spacing: 14) {
            ForEach(0..<PhoneForm.codeLength, id: \.self) { i in
                ZStack {
                    Self.digit.fill(Hue.hingeDigit)
                    Self.digit.inset(by: -1).strokeBorder(Hue.hingeRing, lineWidth: 1)
                    if i < typed.count {
                        Text(String(typed[i]))
                            .appleFont(18)
                            .monospacedDigit()
                            .foregroundStyle(Hue.hingeInk)
                            .transition(reduceMotion ? .identity : .asymmetric(
                                insertion: .scale(scale: 0.6).combined(with: .opacity), removal: .identity))
                    } else if i == typed.count, typing == .code {
                        Capsule().fill(Hue.hingeCaret).frame(width: 2, height: 22)
                            .phaseAnimator([1.0, 0.0]) { $0.opacity($1) } animation: { _ in .linear(duration: 0.01).delay(0.5) }
                            .transition(.identity)
                    }
                }
                .frame(width: 42.8, height: 98)
            }
        }
        .animation(Motion.outQuint(0.18), value: form.code)
        // The field over it reads the code out.
        .accessibilityHidden(true)
        .overlay {
            TextField("", text: $form.code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .focused($typing, equals: .code)
                .foregroundStyle(.clear)
                .tint(.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Verification code")
                .onChange(of: form.code) { _, typed in
                    // A right code stays, and the number pad with it, till the next step loads.
                    if let right = form.right {
                        if typed != right { form.code = right }
                        return
                    }
                    let kept = String(typed.filter { $0.isASCII && $0.isNumber }.prefix(PhoneForm.codeLength))
                    if kept != typed { form.code = kept }
                }
        }
        .contentShape(Rectangle())
        .onTapGesture { typing = .code }
        .modifier(HingeShake(trigger: form.wrongs, way: (-8, 7, -4, 2), seconds: 0.34))
    }

    // MARK: Shared

    /// Where each step's question starts, down Hinge's screen; less on a phone too short for it (the iPhone SE).
    private static let numberTop: CGFloat = 122
    private static let codeTop: CGFloat = 136
    private static let box = RoundedRectangle(cornerRadius: Radius.hingeBox, style: .continuous)
    private static let digit = RoundedRectangle(cornerRadius: Radius.hingeDigit, style: .continuous)

    /// The room over the question, taken first and given up first.
    private func lead(_ top: CGFloat) -> some View {
        Color.clear.frame(minHeight: 24, maxHeight: top).layoutPriority(1)
    }

    /// Hinge's big centred question in Apple's font: 33 regular on a 36 pt line (Jesse: "yes apple regular").
    private func question(_ words: String, gutter: CGFloat) -> some View {
        Text(words)
            .appleFont(33)
            .lineHeight(.multiple(factor: 36 / 33))
            .foregroundStyle(Hue.hingeInk)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, gutter)
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($heading)
    }

    private func underLine(_ words: String) -> some View {
        Text(words).appleFont(12, weight: .semibold).foregroundStyle(Hue.hingeInk)
    }

    /// The one line under the boxes: the link or the pencil, or the server's no in red till you type.
    private func underBoxes<Line: View>(@ViewBuilder _ line: () -> Line) -> some View {
        ZStack {
            line()
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .opacity(form.line == nil ? 1 : 0)
                .allowsHitTesting(form.line == nil)
                .accessibilityHidden(form.line != nil)
            if let words = form.line {
                Text(words)
                    .appleFont(12, weight: .semibold)
                    .foregroundStyle(Hue.hingeError)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .transition(.opacity)
            }
        }
        .frame(minHeight: 44)
        .animation(.easeOut(duration: 0.16), value: form.line)
    }

    private var closeButton: some View {
        Button {
            form.close()
            typing = nil
            close()
        } label: {
            Image(systemName: "xmark")
                .font(.glyph(15, weight: .bold))
                .foregroundStyle(Hue.hingeInk)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.press(.dim))
        .accessibilityLabel("Close")
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 8)
        .padding(.top, 61)
        .ignoresSafeArea(.container, edges: .top)
    }

    /// Hinge's grey, top to bottom as far as the keypad, then flat under it.
    private var fade: some View {
        LinearGradient(stops: Hue.hingeFade.map { .init(color: $0.color, location: $0.y / 874) },
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }

    // MARK: The two sheets, Apple's

    private var countrySheet: some View {
        sheet("Country", height: 170) {
            VStack(spacing: 0) {
                ForEach(PhoneCountry.allCases) { country in
                    Button {
                        Haptics.selection()
                        form.country = country
                        countryOpen = false
                    } label: {
                        HStack(spacing: 12) {
                            Text(country.flag)
                            Text(country.name)
                            Spacer(minLength: 8)
                            Text(PhoneCountry.code).foregroundStyle(Hue.hingeGrey)
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .opacity(form.country == country ? 1 : 0)
                        }
                        .font(.apple(17))
                        .foregroundStyle(Hue.hingeInk)
                        .frame(minHeight: 46)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.press(.row))
                    .accessibilityAddTraits(form.country == country ? .isSelected : [])
                }
            }
        }
    }

    private var whySheet: some View {
        sheet("What if my number changes?", height: 170) {
            Text("Your number is how you log in. Got a new one? Log in with your old number, then change it in Settings.")
                .font(.apple(15))
                .foregroundStyle(Hue.hingeSheetWords)
                .fixedSize(horizontal: false, vertical: true)
            Button { whyOpen = false } label: {
                Text("Got it")
                    .font(.apple(16, weight: .semibold))
                    .foregroundStyle(Hue.hingeWhite)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Hue.hingePill, in: Capsule())
            }
            .buttonStyle(.press(.squish))
            .padding(.top, 12)
        }
    }

    private func sheet<Content: View>(_ title: String, height: CGFloat, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .appleFont(19, weight: .semibold)
                .foregroundStyle(Hue.hingeInk)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(.horizontal, 22)
        .padding(.top, 33)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Hue.hingeWhite)
    }
}

/// A sideways shake, in points: the Continue pill's and the code boxes'. Reduce Motion skips it.
struct HingeShake: ViewModifier {
    let trigger: Int
    let way: (CGFloat, CGFloat, CGFloat, CGFloat)
    let seconds: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: CGFloat(0), trigger: reduceMotion ? 0 : trigger) { view, x in
            view.offset(x: x)
        } keyframes: { _ in
            LinearKeyframe(way.0, duration: seconds / 5)
            LinearKeyframe(way.1, duration: seconds / 5)
            LinearKeyframe(way.2, duration: seconds / 5)
            LinearKeyframe(way.3, duration: seconds / 5)
            LinearKeyframe(0, duration: seconds / 5)
        }
    }
}
