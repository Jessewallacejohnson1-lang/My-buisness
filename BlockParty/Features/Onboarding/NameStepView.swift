//
//  NameStepView.swift
//  Block Party — "What should we call you?" One warm centered field. First data step.
//

import SwiftUI

struct NameStepView: View {
    @Binding var name: String
    /// Nil when this is the first step (the trimmed wizard: name → interests).
    var onBack: (() -> Void)?
    let onContinue: () -> Void
    /// The wizard's escape hatch. It used to live on the removed `hello` step, and a
    /// user who won't type a name must still be able to get into the app — both
    /// remaining steps gate their CTA on having an answer.
    var onSkip: (() -> Void)?

    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canContinue: Bool { !trimmed.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingTopBar(index: 0, total: 2, onBack: onBack)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text("Your name on the block")
                    .font(.display(32))
                    .foregroundStyle(Hue.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("What should neighbors call you?")
                    .font(.sans(16))
                    .foregroundStyle(Hue.inkSecondary)
            }
            .padding(.top, 40)

            Spacer()

            TextField("", text: $name, prompt: Text("Your name").foregroundColor(Hue.inkSecondary))
                .font(.display(34))
                .foregroundStyle(Hue.ink)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($focused)
                .onChange(of: name) { _, v in if v.count > 24 { name = String(v.prefix(24)) } }
                .onSubmit { if canContinue { onContinue() } }
                .padding(.bottom, 10)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Hue.hairline).frame(height: 1)
                }
                .padding(.horizontal, 8)

            Spacer()
            Spacer()

            VStack(spacing: 6) {
                ContinueButton(title: "Continue", enabled: canContinue) {
                    Haptics.selection(); onContinue()
                }
                if let onSkip {
                    Button("Skip for now") { Haptics.selection(); onSkip() }
                        .font(.sans(15))
                        .foregroundStyle(Hue.inkSecondary)
                        .padding(.vertical, 10)
                }
            }
        }
        .padding(24)
        .background(Hue.paper.ignoresSafeArea())
        .onAppear {
            // Auto-focus the field (a beat after the transition settles).
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.35)) { focused = true }
        }
    }
}

/// The shared coral pill CTA used across the wizard (enable state springs in).
struct ContinueButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.sansSemibold(17))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(enabled ? Hue.ink : Hue.ink.opacity(0.4),
                            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: enabled)
    }
}
