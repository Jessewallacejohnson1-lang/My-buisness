//
//  LoginView.swift
//  Block Party — Log in and Create account (BP app onboarding 27): onboarding's white screen with
//  the wordmark, a header, Instagram's two boxes and the charcoal Next bar. No app icon (Jesse,
//  2026-11-02: "no logo icon i dont like it"). Onboarding shows them from the Welcome; a tap that
//  needs an account shows Log in alone in a sheet (`signInSheet`).
//

import SwiftUI

/// Which of the Welcome's two ways in is up.
enum OnboardingAccount {
    case create, logIn

    var title: String { self == .logIn ? "Log in" : "Create account" }
    var button: String { self == .logIn ? "Log in" : "Next" }
}

/// What's typed into Log in or Create account, and the server's answer.
@MainActor @Observable
final class AccountForm {
    var email = "" { didSet { message = nil } }
    var password = "" { didSet { message = nil } }
    private(set) var busy = false
    /// The line under the boxes: why the server said no.
    private(set) var message: String?
    /// Bumped on each no, for the Next bar's shake.
    private(set) var refusals = 0

    var canSubmit: Bool { Self.looksLikeEmail(email) && password.count >= 6 }

    nonisolated static func looksLikeEmail(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s]+/) != nil
    }

    /// Logs in or makes the account, then runs `then` (what comes next: the Town feed or the first
    /// question), which answers a line when it couldn't go on. A retry once the account is in only
    /// runs `then` again.
    func submit(_ way: OnboardingAccount, auth: AuthStore, then: () async -> String?) async {
        guard canSubmit, !busy else { return }
        busy = true
        defer { busy = false }
        let mail = email.trimmingCharacters(in: .whitespaces)
        if !auth.hasAccount {
            let refused: String?
            switch way {
            case .logIn:
                refused = await auth.signIn(email: mail, password: password)
            case .create:
                let made = await auth.signUp(email: mail, password: password)
                refused = made.error ?? (made.needsConfirm ? "Check your email to confirm, then log in." : nil)
            }
            if let refused { return refuse(refused) }
        }
        if let stuck = await then() { refuse(stuck) }
    }

    private func refuse(_ line: String) {
        message = line
        refusals += 1
        AccessibilityNotification.Announcement(line).post()
    }
}

/// The two boxes, Instagram's (BP app references/log-in: 60 pt tall, 12 pt corners, 12 pt apart,
/// a 1 pt line), each label rising out of the way once the box is touched; the hint on Create
/// account and the server's no under them.
struct AccountFields: View {
    @Bindable var form: AccountForm
    let way: OnboardingAccount
    let submit: () -> Void

    private enum Field { case email, password }
    @FocusState private var focus: Field?
    @State private var showPassword = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 12) {
                box("Email", .email, filled: !form.email.isEmpty) {
                    TextField("", text: $form.email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .accessibilityLabel("Email")
                }
                box("Password", .password, filled: !form.password.isEmpty) {
                    HStack(spacing: 0) {
                        Group {
                            if showPassword { TextField("", text: $form.password) } else { SecureField("", text: $form.password) }
                        }
                        .textContentType(way == .create ? .newPassword : .password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .accessibilityLabel("Password")
                        // Once there's something to show, as Instagram's.
                        if !form.password.isEmpty { eye }
                    }
                }
            }
            .padding(.top, 32)
            if way == .create {
                Text("6 or more characters")
                    .font(.sans(15))
                    .foregroundStyle(Hue.inkSecondary)
                    .padding(.top, 12)
            }
            if let message = form.message {
                Label { Text(message) } icon: { Image(systemName: "exclamationmark.circle.fill") }
                    .font(.sans(15))
                    .foregroundStyle(Hue.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: form.message)
        .onSubmit { if focus == .email { focus = .password } else { submit() } }
        .onAppear { focus = .email }
    }

    /// One box: white, the hairline going ink while it's typed in. The label sits in the middle
    /// until the box is touched or filled, then rises to the top at 12 pt.
    private func box<Input: View>(_ label: String, _ field: Field, filled: Bool,
                                  @ViewBuilder input: () -> Input) -> some View {
        let up = filled || focus == field
        let shape = RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
        return ZStack(alignment: .leading) {
            Text(label)
                .font(.sans(17))
                .foregroundStyle(Hue.inkSecondary)
                .scaleEffect(up ? 12.0 / 17.0 : 1, anchor: .leading)
                .offset(y: up ? -12 : 0)
                .accessibilityHidden(true)
            input()
                .font(.sans(17))
                .foregroundStyle(Hue.ink)
                .tint(Hue.ink)
                .focused($focus, equals: field)
                .offset(y: 9)
        }
        .padding(.leading, 16)
        .frame(height: 60)
        .background(Hue.surface, in: shape)
        .overlay(shape.strokeBorder(focus == field ? Hue.ink : Hue.hairline, lineWidth: focus == field ? 1.5 : 1))
        .contentShape(shape)
        .onTapGesture { focus = field }
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: up)
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
        .buttonStyle(OnboardingPress(scale: 0.88))
        .padding(.trailing, 4)
        .offset(y: -9)
        .accessibilityLabel(showPassword ? "Hide password" : "Show password")
    }
}

/// Log in alone, over another screen: the tap needed an account. Since onboarding 27 nobody is in
/// the app without one, so only DEBUG runs reach it; the sheets go in a follow-up.
struct LoginView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var form = AccountForm()

    var body: some View {
        ZStack(alignment: .topLeading) {
            OnboardingBackdrop()
            VStack(alignment: .leading, spacing: 32) {
                BlockPartyWordmark(height: 33)
                    .foregroundStyle(Hue.ink)
                VStack(alignment: .leading, spacing: 0) {
                    Text(OnboardingAccount.logIn.title)
                        .font(.display(30))
                        .foregroundStyle(Hue.ink)
                        .accessibilityAddTraits(.isHeader)
                    AccountFields(form: form, way: .logIn, submit: submit)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 72)
        }
        .safeAreaInset(edge: .bottom) {
            OnboardingNextBar(title: OnboardingAccount.logIn.button, allowed: form.canSubmit, busy: form.busy,
                              refused: form.refusals, action: submit)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
        }
    }

    private func submit() {
        // Signed in, the sheet closes itself (`SignInSheet`).
        Task { await form.submit(.logIn, auth: auth) { nil } }
    }
}

extension View {
    /// Sign in over this screen, for a tap that needs an account while there is none:
    /// a bookmark with no account yet opens it (Jesse, 2026-10-12), and so does finding
    /// neighbours from an Anonymous one. It closes once a real account is signed in.
    func signInSheet(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            SignInSheet().environmentObject(AuthStore.shared)
        }
    }
}

private struct SignInSheet: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LoginView()
            // A real account, not just a session: an Anonymous one is already signed in.
            .onChange(of: auth.hasAccount) { _, real in if real { dismiss() } }
    }
}
