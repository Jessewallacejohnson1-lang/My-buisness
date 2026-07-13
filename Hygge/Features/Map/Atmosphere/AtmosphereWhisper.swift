//
//  AtmosphereWhisper.swift
//  Hygge — the quiet "why" under the town pill: "❄ 38° · light snow · 4:15".
//  Neutral ink + a muted weather glyph — never coral (coral stays live/tappable).
//  Hidden until weather resolves; expands in with a gentle fade+slide.
//

import SwiftUI

struct AtmosphereWhisper: View {
    let atmosphere: TownAtmosphere
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let line = atmosphere.whisperLine(now: Date()) {
                HStack(spacing: 5) {
                    Image(systemName: atmosphere.glyph)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Hue.ink3)
                    Text(line)
                        .font(.sansMedium(12))
                        .foregroundStyle(Hue.ink2)
                        .lineLimit(1)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(atmosphere.accessibilityText ?? line)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: atmosphere.resolvedAt != nil)
    }
}
