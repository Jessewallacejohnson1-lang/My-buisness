//
//  LoginView.swift
//  Block Party — Log in and Create account (BP app onboarding 27): onboarding's grey canvas with
//  the icon circle, a header, Luma's two labelled grey boxes and the black Next pill (onboarding 34). No app icon (Jesse,
//  2026-11-02: "no logo icon i dont like it"). Onboarding shows them from the Welcome. Log in's
//  "Forgot password?" leads to three more in the same look: the email, the emailed code and a new
//  password (onboarding 40).
//

import SwiftUI

/// Which of the Welcome's two ways in is up, or which step of Log in's Forgot password.
enum OnboardingAccount {
    case create, logIn
    /// Forgot password (onboarding 40, Instagram's flow): the email, the emailed code, a new password.
    case forgot, code, newPassword

    var title: String {
        switch self {
        case .create: "Create account"
        case .logIn: "Log in"
        case .forgot: "Find your account"
        case .code: "Enter the code"
        case .newPassword: "Make a new password"
        }
    }

    var button: String {
        switch self {
        case .logIn, .newPassword: "Log in"
        case .create, .code: "Next"
        case .forgot: "Send code"
        }
    }

    /// The SF Symbol in the grey circle over the header (onboarding 34): a lock where a password is
    /// found or made, else email.
    var symbol: String { self == .forgot || self == .newPassword ? "lock" : "envelope" }

    /// Forgot password's steps.
    var resets: Bool { self == .forgot || self == .code || self == .newPassword }

    /// Where the back chevron goes: Forgot password steps back through itself to Log in, the rest to
    /// the Welcome (nil). The new password has none: the code has signed the phone in.
    var back: OnboardingAccount? {
        switch self {
        case .forgot: .logIn
        case .code: .forgot
        default: nil
        }
    }
}

/// What's typed into Log in or Create account, and the server's answer.
@MainActor @Observable
final class AccountForm {
    var email = "" { didSet { message = nil } }
    var password = "" { didSet { message = nil } }
    /// The emailed code, digits only, up to 6.
    var code = "" { didSet { message = nil } }
    private(set) var busy = false
    /// "Send code again" went: its link says Sent until the screen is left.
    private(set) var resent = false
    /// The new password reached the server, so a retry after a failed profile read doesn't send it
    /// again (the server would call it the old one).
    private var passwordSaved = false
    /// The line under the boxes: why the server said no.
    private(set) var message: String?
    /// Bumped on each no, for the Next bar's shake.
    private(set) var refusals = 0

    func canSubmit(_ way: OnboardingAccount) -> Bool {
        switch way {
        case .create, .logIn: Self.looksLikeEmail(email) && password.count >= 6
        case .forgot: Self.looksLikeEmail(email)
        case .code: code.count == 6
        case .newPassword: password.count >= 6
        }
    }

    var mail: String { email.trimmingCharacters(in: .whitespaces) }

    nonisolated static func looksLikeEmail(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s]+/) != nil
    }

    /// Logs in or makes the account, then runs `then` (what comes next: the Town feed or the first
    /// question), which answers a line when it couldn't go on. A retry once the account is in only
    /// runs `then` again.
    func submit(_ way: OnboardingAccount, auth: AuthStore, then: () async -> String?) async {
        guard canSubmit(way), !busy else { return }
        busy = true
        defer { busy = false }
        let refused: String?
        switch way {
        case .logIn where !auth.hasAccount:
            refused = await auth.signIn(email: mail, password: password)
        case .create where !auth.hasAccount:
            let made = await auth.signUp(email: mail, password: password)
            refused = made.error ?? (made.needsConfirm ? "Check your email to confirm, then log in." : nil)
        case .logIn, .create:
            refused = nil
        case .forgot:
            refused = await auth.sendResetCode(email: mail)
            resent = false
            // Back here and sent again: the old code no longer works, so its box starts empty.
            if refused == nil { code = "" }
        case .code:
            refused = await auth.verifyResetCode(email: mail, code: code)
            // The new password's box starts empty, not with the one that didn't work.
            if refused == nil { password = "" }
        case .newPassword where passwordSaved:
            refused = nil
        case .newPassword:
            refused = await auth.setPassword(password)
            passwordSaved = refused == nil
        }
        if let refused { return refuse(refused) }
        if let stuck = await then() { refuse(stuck) }
    }

    /// The code screen's "Send code again".
    func resend(auth: AuthStore) async {
        guard !busy, !resent else { return }
        busy = true
        defer { busy = false }
        if let refused = await auth.sendResetCode(email: mail) { return refuse(refused) }
        resent = true
        AccessibilityNotification.Announcement("Code sent").post()
    }

    private func refuse(_ line: String) {
        message = line
        refusals += 1
        AccessibilityNotification.Announcement(line).post()
    }
}

/// The boxes, Luma's (onboarding 34): each a small grey label over a grey box; the hint on
/// Create account and the new password, and the server's no under them. Log in adds "Forgot
/// password?"; Forgot password's steps take the email, the code or the new password (onboarding 40).
struct AccountFields: View {
    @Bindable var form: AccountForm
    let way: OnboardingAccount
    let submit: () -> Void
    /// Log in's "Forgot password?".
    var forgot: () -> Void = {}
    /// The code screen's "Send code again".
    var resend: () -> Void = {}

    private enum Field { case email, password, code }
    @FocusState private var focus: Field?
    @State private var showPassword = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if way == .forgot { OnboardingSubline("We'll email you a code.") }
            if way == .code {
                Text("We sent it to \(Text(form.mail).fontWeight(.semibold).foregroundStyle(Hue.ink)).")
                    .font(.apple(15))
                    .foregroundStyle(Hue.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            VStack(alignment: .leading, spacing: 0) {
                if way != .code && way != .newPassword {
                    box("Email", .email) {
                        TextField("", text: $form.email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(way == .forgot ? .go : .next)
                            .accessibilityLabel("Email")
                    }
                }
                if way == .code { codeBox }
                if way != .forgot && way != .code {
                    box(way == .newPassword ? "New password" : "Password", .password) {
                        HStack(spacing: 0) {
                            Group {
                                if showPassword { TextField("", text: $form.password) } else { SecureField("", text: $form.password) }
                            }
                            .textContentType(way == .logIn ? .password : .newPassword)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .accessibilityLabel(way == .newPassword ? "New password" : "Password")
                            // Once there's something to show, as Instagram's.
                            if !form.password.isEmpty { eye }
                        }
                    }
                }
            }
            if way == .create || way == .newPassword {
                Text("6 or more characters")
                    .font(.apple(13))
                    .foregroundStyle(Hue.inkSecondary)
                    .padding(.top, 12)
            }
            if let message = form.message {
                Label { Text(message) } icon: { Image(systemName: "exclamationmark.circle.fill") }
                    .font(.apple(15))
                    .foregroundStyle(Hue.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
            if way == .logIn { link("Forgot password?", action: forgot) }
            if way == .code {
                link(form.resent ? "Sent" : "Send code again", action: resend)
                    .disabled(form.resent)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: form.resent)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: form.message)
        .onSubmit { if focus == .email && way != .forgot { focus = .password } else { submit() } }
        .onAppear { focus = way == .code ? .code : way == .newPassword ? .password : .email }
    }

    /// An ink link under the boxes, its words lined up with theirs (mock `.link`).
    private func link(_ title: String, action: @escaping () -> Void) -> some View {
        OnboardingLink(title: title, action: action)
            .padding(.leading, -12)
            .padding(.top, 6)
    }

    /// The code, Luma's code box (mock v8 `.codebox`): six slots 22 pt apart in a 56 pt grey box, the
    /// digits typed in ink, a dot for each still to come, and a caret on the next. A field you can't
    /// see takes the typing, so iOS offers the code from Mail over the keyboard.
    private var codeBox: some View {
        let digits = Array(form.code)
        let shape = RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
        return HStack(spacing: 22) {
            ForEach(0..<6, id: \.self) { i in
                ZStack {
                    if i < digits.count {
                        Text(String(digits[i])).foregroundStyle(Hue.ink)
                    } else if i == digits.count, focus == .code {
                        Capsule().fill(Hue.ink).frame(width: 2, height: 28)
                            .phaseAnimator([1.0, 0.0]) { $0.opacity($1) } animation: { _ in .linear(duration: 0.01).delay(0.53) }
                    } else {
                        Text("·").foregroundStyle(Hue.codeSlot)
                    }
                }
                .frame(width: 16)
            }
        }
        .font(.apple(26, weight: .semibold))
        .monospacedDigit()
        // The field over it reads the code out.
        .accessibilityHidden(true)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(Hue.onboardingField, in: shape)
        .overlay(shape.strokeBorder(Hue.ink, lineWidth: focus == .code ? 1.5 : 0))
        .overlay {
            TextField("", text: $form.code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .focused($focus, equals: .code)
                .foregroundStyle(.clear)
                .tint(.clear)
                .padding(.horizontal, 18)
                .accessibilityLabel("Code")
                .onChange(of: form.code) { _, typed in
                    let kept = String(typed.filter(\.isNumber).prefix(6))
                    if kept != typed { form.code = kept }
                }
        }
        .contentShape(shape)
        .onTapGesture { focus = .code }
        .padding(.top, 24)
    }

    /// One box, Luma's: the small grey label 24 pt above it, a 46 pt grey box, an ink line inside its
    /// edge while typing in it (mock v8 `.flabel`, `.field`).
    private func box<Input: View>(_ label: String, _ field: Field,
                                  @ViewBuilder input: () -> Input) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingFieldLabel(label)
                .accessibilityHidden(true)
            input()
                .font(.apple(17))
                .foregroundStyle(Hue.ink)
                .tint(Hue.ink)
                .focused($focus, equals: field)
                .onboardingField(focused: focus == field)
                .contentShape(Rectangle())
                .onTapGesture { focus = field }
        }
        .padding(.top, 24)
    }

    /// Shows or hides the password, keeping the keyboard on it.
    private var eye: some View {
        Button {
            showPassword.toggle()
            focus = .password
        } label: {
            Image(systemName: showPassword ? "eye" : "eye.slash")
                .font(.glyph(17, weight: .medium))
                .foregroundStyle(Hue.inkSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.press(.squish))
        .padding(.trailing, -12)
        .accessibilityLabel(showPassword ? "Hide password" : "Show password")
    }
}
