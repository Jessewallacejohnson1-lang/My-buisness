//
//  OnboardingChrome.swift
//  Hygge — shared top chrome for the onboarding wizard: a circular back button
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
                .background(Hue.paper, in: Circle())
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
    let onBack: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            OnboardingBackButton(action: onBack)
            OnboardingProgressBar(index: index, total: total)
        }
    }
}
