//
//  SpotlightCard.swift
//  Block Party — one place or local story worth noticing today.
//

import SwiftUI

struct SpotlightCard: View {
    let spotlight: BriefingSpotlight
    var onOpen: (() -> Void)? = nil

    var body: some View {
        if let onOpen {
            Button {
                Haptics.light()
                onOpen()
            } label: {
                card
            }
            .buttonStyle(SpotlightPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Around town. \(spotlight.title). \(spotlight.blurb)")
            .accessibilityHint("Opens place details")
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                Text("AROUND TOWN")
                    .font(.sansSemibold(11))
                    .tracking(1)
                    .foregroundStyle(Hue.ink.opacity(0.35))

                Text(spotlight.title)
                    .font(.displaySemi(22))
                    .foregroundStyle(Hue.ink)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)

                Text(spotlight.blurb)
                    .font(.sans(16))
                    .foregroundStyle(Hue.inkSecondary)
                    .lineSpacing(4)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)

            if let imageURL = spotlight.imageURL {
                // The box is established FIRST by a clear spacer, and the image
                // fills into it as an overlay. Putting `.aspectRatio(_, .fit)` on
                // the AsyncImage itself does not bound a `scaledToFill` child —
                // the image grows unbounded and runs off the screen.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .overlay {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .empty:
                                Hue.fill
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                imagePlaceholder
                            @unknown default:
                                Hue.fill
                            }
                        }
                    }
                    .clipped()
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .blockPartyCard(padding: 0)
    }

    private var imagePlaceholder: some View {
        ZStack {
            Hue.fill
            Image(systemName: "building.2.fill")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Hue.inkSecondary)
        }
    }
}

private struct SpotlightPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.985 : 1))
            .opacity(reduceMotion && configuration.isPressed ? 0.78 : 1)
            .animation(
                reduceMotion ? .easeOut(duration: 0.1) : Motion.tilePress,
                value: configuration.isPressed
            )
    }
}
