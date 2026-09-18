//
//  OnboardingChrome.swift
//  Block Party — shared top chrome for the onboarding wizard: a circular back button
//  and a slim segmented progress bar. Present only on the data-collection steps
//  (name · interests · avatar); Welcome and the Map finale are full-bleed.
//

import SwiftUI

struct OnboardingBackButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: { Haptics.selection(); action() }) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Hue.ink)
                .frame(width: 44, height: 44)
                .background(Hue.surface, in: Circle())
                .overlay(Circle().stroke(Hue.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }
}

struct OnboardingProgressBar: View {
    let index: Int
    let total: Int
    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 6
            let w = (geo.size.width - gap * CGFloat(total - 1)) / CGFloat(total)
            HStack(spacing: gap) {
                ForEach(0..<total, id: \.self) { i in
                    Capsule()
                        .fill(i <= index ? Hue.ink : Hue.hairline)
                        .frame(width: max(w, 0), height: 5)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: index)
        }
        .frame(height: 5)
        .accessibilityElement()
        .accessibilityLabel("Step \(index + 1) of \(total)")
    }
}

struct OnboardingTopBar: View {
    let index: Int
    let total: Int
    /// Nil on the first step, which has nowhere to go back to. A back button that does
    /// nothing is worse than no back button.
    var onBack: (() -> Void)?
    var body: some View {
        HStack(spacing: 14) {
            if let onBack {
                OnboardingBackButton(action: onBack)
            }
            OnboardingProgressBar(index: index, total: total)
        }
    }
}

/// The full-width ink CTA. It was the wizard's shared pill; the interest picker
/// outlived the wizard (Edit Profile presents it), so the button moved here with
/// the rest of that screen's chrome when the onboarding flow was deleted on
/// 2026-09-18.
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
