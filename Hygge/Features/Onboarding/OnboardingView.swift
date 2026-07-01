//
//  OnboardingView.swift
//  Hygge — first-run welcome + interest picking. Personalizes the app;
//  interests live on-device. Mirrors the Expo onboarding (hello → interests).
//

import SwiftUI

struct OnboardingView: View {
    var onDone: () -> Void

    private enum Step { case hello, interests }
    @State private var step: Step = .hello
    @State private var selected: Set<String> = Set(Interests.get())

    var body: some View {
        ZStack {
            Hue.canvas.ignoresSafeArea()
            switch step {
            case .hello: hello
            case .interests: interests
            }
        }
    }

    private var hello: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Text("Welcome to Hygge")
                .font(.display(38))
                .foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("One calm place for everything happening in St. Joseph — a daily look at town, a shared calendar anyone can add to, and small nudges to get out and meet your neighbors.")
                .font(.sans(16))
                .foregroundStyle(Hue.ink2)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            primaryButton("Get started") { step = .interests }
            skipButton
        }
        .padding(24)
    }

    private var interests: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What are you into?")
                    .font(.display(30))
                    .foregroundStyle(Hue.ink)
                Text("We'll quietly surface clubs and trails that fit. Pick a few.")
                    .font(.sans(15))
                    .foregroundStyle(Hue.ink2)
            }
            .padding(.top, 60)

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(Interests.all) { interest in
                        chip(interest)
                    }
                }
            }

            primaryButton("Continue", enabled: !selected.isEmpty) { finish() }
            skipButton
        }
        .padding(24)
    }

    private func chip(_ interest: Interest) -> some View {
        let on = selected.contains(interest.id)
        return Button {
            if on { selected.remove(interest.id) } else { selected.insert(interest.id) }
        } label: {
            Text(interest.label)
                .font(.sansMedium(14))
                .multilineTextAlignment(.center)
                .foregroundStyle(on ? Hue.paper : Hue.ink)
                .frame(maxWidth: .infinity, minHeight: 30)
                .padding(.vertical, 12).padding(.horizontal, 10)
                .background(on ? Hue.moss700 : Hue.paper)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(Hue.hairline, lineWidth: on ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    private func primaryButton(_ label: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.sansSemibold(16))
                .foregroundStyle(Hue.paper)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(enabled ? Hue.moss700 : Hue.moss700.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var skipButton: some View {
        Button { finish() } label: {
            Text("Skip for now").font(.sans(14)).foregroundStyle(Hue.ink3)
                .frame(maxWidth: .infinity).padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func finish() {
        Interests.set(Array(selected))
        Interests.setOnboarded()
        onDone()
    }
}
