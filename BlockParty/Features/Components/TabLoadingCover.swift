//
//  TabLoadingCover.swift
//  Block Party — the full-screen "warming up" cover shown while a tab's content is
//  still loading, so the user never watches a half-built screen pop into place.
//
//  Layout mirrors the reference: a quiet wordmark up top, a short title in the
//  upper third, the monochrome-wave indicator dead centre, and a soft rotating
//  subtitle in the lower third — over a deep, faintly-vignetted dark field (the
//  app is otherwise light, so this reads as an intentional "loading" moment, and
//  the neutral dots need a dark backdrop to read). The gradient stays within
//  the canonical ink ramp.
//
//  The subtitle is honest about the wait (loading the town's daily data) and then
//  cross-fades through a few real, neighborly facts about the app — not marketing
//  fluff (CLAUDE.md: "voice is a neighbor, not a brand").
//
//  Entrance is deliberately minimal — the cover exists to PREVENT a jarring
//  pop, so the text just settles in; the indicator carries the life. Dismissal
//  (a fade) is owned by `TabLoadingHost`.
//

import SwiftUI

struct TabLoadingCover: View {
    var title: String = "Loading the town"
    /// A small wordmark at the top, echoing the reference. Nil hides it.
    var wordmark: String? = "Block Party"
    /// Lower-third lines: the honest "what's loading" line first, then a few real
    /// things worth knowing about Block Party / St. Joe. They cross-fade while the cover
    /// is up (most loads only ever show the first one).
    var facts: [String] = [
        "Loading today's happenings in St. Joe…",
        "A pulsing map pin marks what's happening now.",
        "The calendar shows what neighbors have added.",
        "You can add an event, club, or trail.",
        "Find today's plans and places around town.",
    ]

    private static let factInterval: Duration = .seconds(2.6)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textIn = false
    @State private var factIndex = 0

    private var currentFact: String { facts.isEmpty ? "" : facts[factIndex % facts.count] }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                background

                if let wordmark {
                    Text(wordmark)
                        .font(.logo(22))
                        .foregroundStyle(.white.opacity(0.92))
                        .position(x: w / 2, y: h * 0.12)
                        .opacity(textIn ? 1 : 0)
                }

                Text(title)
                    .font(.display(30))
                    .foregroundStyle(.white)
                    .position(x: w / 2, y: h * 0.30)
                    .opacity(textIn ? 1 : 0)
                    .offset(y: textIn ? 0 : 6)

                RainbowWaveIndicator(dotDiameter: 15)
                    .position(x: w / 2, y: h * 0.50)

                Text(currentFact)
                    .font(.sansMedium(15))
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .contentTransition(.opacity)            // cross-fade line swaps
                    .animation(Motion.smooth, value: factIndex)
                    .frame(maxWidth: min(320, w - 56), minHeight: 42, alignment: .top)
                    .position(x: w / 2, y: h * 0.80)
                    .opacity(textIn ? 1 : 0)
                    .offset(y: textIn ? 0 : 6)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { textIn = true; return }
            withAnimation(Motion.smooth.delay(0.04)) { textIn = true }
        }
        .task { await rotateFacts() }
        // One labelled element so VoiceOver reads the cover, not the (masked)
        // half-built tab beneath it. `TabLoadingHost` posts an announcement when it
        // appears; VoiceOver users get the static title, not the shifting fact.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
    }

    /// Cross-fade through the facts while the cover is on screen. The `.task` is
    /// torn down with the cover, so this stops the moment the tab is ready.
    private func rotateFacts() async {
        guard facts.count > 1 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.factInterval)
            if Task.isCancelled { return }
            factIndex += 1
        }
    }

    private var background: some View {
        // A value-only gradient within the canonical ink ramp.
        LinearGradient(
            colors: [Hue.inkSecondary, Hue.ink],
            startPoint: .top, endPoint: .bottom
        )
        .overlay(
            // A faint glow behind the indicator, like the reference's vignette.
            RadialGradient(
                colors: [Color.white.opacity(0.05), .clear],
                center: .init(x: 0.5, y: 0.5), startRadius: 0, endRadius: 280
            )
        )
        .ignoresSafeArea()
    }
}

#if DEBUG
#Preview("Tab loading cover") {
    TabLoadingCover()
}
#endif
