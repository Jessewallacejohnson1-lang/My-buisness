//
//  LoginView.swift
//  Hygge — email + password auth (confirmation ON), Log in / Sign up toggle.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthStore

    private enum Mode { case signIn, signUp }
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var message: String?
    @State private var messageIsError = true

    var body: some View {
        ZStack {
            Hue.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hygge")
                            .font(.display(44))
                            .foregroundStyle(Hue.ink)
                        Text("One calm place for everything happening in St. Joe.")
                            .font(.sans(15))
                            .foregroundStyle(Hue.ink2)
                    }
                    .padding(.top, 60)

                    modeToggle

                    VStack(spacing: 12) {
                        field("Email", text: $email, secure: false, keyboard: .emailAddress)
                        field("Password", text: $password, secure: true, keyboard: .default)
                    }

                    if mode == .signIn {
                        Button(action: resetPassword) {
                            Text("Forgot password?")
                                .font(.sans(13))
                                .foregroundStyle(Hue.ink3)
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                    }

                    if let message {
                        Text(message)
                            .font(.sans(13))
                            .foregroundStyle(messageIsError ? Hue.clay700 : Hue.moss500)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(action: submit) {
                        HStack {
                            if busy { ProgressView().tint(Hue.paper) }
                            Text(mode == .signIn ? "Log in" : "Create account")
                                .font(.sansSemibold(16))
                        }
                        .foregroundStyle(Hue.paper)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canSubmit ? Hue.moss700 : Hue.moss700.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit || busy)
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 0) {
            toggleButton("Log in", .signIn)
            toggleButton("Sign up", .signUp)
        }
        .padding(3)
        .background(Hue.paper200)
        .clipShape(Capsule())
    }

    private func toggleButton(_ label: String, _ m: Mode) -> some View {
        let on = mode == m
        return Button {
            withAnimation(.easeOut(duration: 0.18)) { mode = m; message = nil }
        } label: {
            Text(label)
                .font(.sansSemibold(14))
                .foregroundStyle(on ? Hue.ink : Hue.ink3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(on ? Hue.paper : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func field(_ placeholder: String, text: Binding<String>, secure: Bool, keyboard: UIKeyboardType) -> some View {
        Group {
            if secure {
                SecureField(placeholder, text: text)
            } else {
                TextField(placeholder, text: text)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .font(.sans(15))
        .foregroundStyle(Hue.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Hue.paper)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .hyggeHairline()
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && password.count >= 6
    }

    private func resetPassword() {
        let mail = email.trimmingCharacters(in: .whitespaces)
        guard !mail.isEmpty else {
            message = "Enter your email above first, then tap this."
            messageIsError = true
            return
        }
        busy = true
        message = nil
        Task {
            let err = await auth.resetPassword(email: mail)
            busy = false
            if let err {
                message = err; messageIsError = true
            } else {
                message = "Check your email for a reset link."; messageIsError = false
            }
        }
    }

    private func submit() {
        let mail = email.trimmingCharacters(in: .whitespaces)
        busy = true
        message = nil
        Task {
            if mode == .signIn {
                let err = await auth.signIn(email: mail, password: password)
                busy = false
                if let err { message = err; messageIsError = true }
                // success → AuthStore publishes session → RootView swaps to tabs
            } else {
                let result = await auth.signUp(email: mail, password: password)
                busy = false
                if let err = result.error {
                    message = err; messageIsError = true
                } else if result.needsConfirm {
                    mode = .signIn
                    message = "Check your email to confirm, then log in."
                    messageIsError = false
                }
            }
        }
    }
}
