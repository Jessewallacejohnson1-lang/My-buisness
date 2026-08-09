//
//  SpotlightCard.swift
//  Block Party — one town place or business held steady for the week.
//

import SwiftUI

struct SpotlightCard: View {
    let spotlight: BriefingSpotlight
    var weekIdentifier: String? = nil
    var onOpen: (() -> Void)? = nil

    var body: some View {
        card
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                Text("This week's spotlight · \(displayWeekIdentifier)")
                    .font(.sansSemibold(11))
                    .tracking(0.7)
                    .foregroundStyle(Hue.inkSecondary)

                Text(spotlight.title)
                    .font(.displaySemi(22))
                    .foregroundStyle(Hue.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(spotlight.blurb)
                    .font(.sans(16))
                    .foregroundStyle(Hue.inkSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)

            // `image_url` is deliberately not used here. Google Places photo names
            // may live only in the service's in-memory cache; VenuePhoto re-fetches
            // through the confidence gate and owns the required attribution overlay.
            Color.clear
                .frame(maxWidth: .infinity)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    VenuePhoto(
                        venueName: spotlight.title,
                        coordinate: KnownVenues.coordinate(for: spotlight.title),
                        maxWidth: 1_400
                    ) {
                        imagePlaceholder
                    }
                }
                .clipped()

            if let onOpen {
                Button {
                    Haptics.light()
                    onOpen()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "map")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Open map")
                            .font(.sansSemibold(15))
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Hue.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Hue.fill)
                    .clipShape(
                        RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    )
                }
                .buttonStyle(SpotlightPressStyle())
                .padding(18)
                .accessibilityHint("Opens this place in Maps")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .blockPartyCard(padding: 0)
    }

    private var displayWeekIdentifier: String {
        weekIdentifier ?? SpotlightWeek.identifier(for: Date()) ?? "This week"
    }

    private var imagePlaceholder: some View {
        ZStack {
            Hue.fill
            Image(systemName: "building.2")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Hue.inkSecondary)
        }
        .accessibilityLabel("Photo unavailable")
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
