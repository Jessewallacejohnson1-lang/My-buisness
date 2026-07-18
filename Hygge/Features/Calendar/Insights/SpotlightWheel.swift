//
//  SpotlightWheel.swift
//  Hygge — the paged hero for the Upcoming "Insights" face.
//
//  Replaces the single StreakHeroCard hero with a horizontally paged carousel of
//  it: your soonest event, the town's most-loved, then the town's next happening
//  (1…3 deduped pages built in InsightsData.buildSpotlight). The card layout,
//  size (218pt), and dark-blob background are FIXED — StreakHeroCard is reused
//  unchanged as each page. Custom coral dots sit on the light canvas directly
//  below the card so they never overlap the card's own subtitle.
//

import SwiftUI

struct SpotlightWheel: View {
    let pages: [InsightsData.SpotlightPage]

    @State private var selection: Int = 0
    @State private var loopTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cardHeight: CGFloat = 218
    private let dotSize: CGFloat = 6
    private let dotGap: CGFloat = 10

    var body: some View {
        Group {
            if pages.count <= 1 {
                singlePage
            } else {
                carousel
            }
        }
        .onAppear(perform: applyInitialSelection)
    }

    // MARK: - Single page (no TabView, no dots)

    private var singlePage: some View {
        heroCard(for: pages.first)
    }

    // MARK: - Paged carousel

    private var carousel: some View {
        VStack(spacing: dotGap) {
            TabView(selection: $selection) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    heroCard(for: page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: cardHeight)

            dots
        }
        .onAppear(perform: startLoopIfRequested)
        .onDisappear { loopTask?.cancel(); loopTask = nil }
        .onChange(of: pages.count) { _, newCount in
            // A data refresh can shrink the deduped page set; keep the paged hero
            // from resting on a now-missing page (instant clamp, no animation).
            if selection >= newCount { selection = max(0, newCount - 1) }
        }
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(pages.indices, id: \.self) { i in
                let isActive = i == selection
                Capsule(style: .continuous)
                    .fill(isActive ? Hue.accent : InsightsPalette.sectionLabel.opacity(0.4))
                    .frame(width: isActive ? dotSize * 2 : dotSize, height: dotSize)
                    .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82),
                               value: selection)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - One hero page

    @ViewBuilder
    private func heroCard(for page: InsightsData.SpotlightPage?) -> some View {
        if let page {
            StreakHeroCard(title: page.label,
                           value: page.value,
                           unit: page.unit,
                           subtitle: page.subtitle)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label(for: page))
        }
    }

    private func label(for page: InsightsData.SpotlightPage) -> String {
        let head = page.unit.isEmpty ? "\(page.label): \(page.value)"
                                     : "\(page.label): \(page.value) \(page.unit)"
        return "\(head). \(page.subtitle)"
    }

    // MARK: - Selection + DEBUG loop

    private func applyInitialSelection() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-insights-page"),
           idx + 1 < args.count, let n = Int(args[idx + 1]), !pages.isEmpty {
            selection = min(max(n - 1, 0), pages.count - 1)
        }
        #endif
    }

    private func startLoopIfRequested() {
        #if DEBUG
        guard !reduceMotion, pages.count > 1,
              ProcessInfo.processInfo.arguments.contains("-insights-wheel-loop") else { return }
        loopTask?.cancel()
        loopTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if Task.isCancelled { break }
                withAnimation(.spring(response: 0.44, dampingFraction: 0.82)) {
                    selection = (selection + 1) % pages.count
                }
            }
        }
        #endif
    }
}

#if DEBUG
#Preview {
    SpotlightWheel(pages: InsightsData.sample.spotlight)
        .padding()
        .background(InsightsPalette.canvas)
}
#endif
