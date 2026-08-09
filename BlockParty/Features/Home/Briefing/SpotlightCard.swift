//
//  SpotlightCard.swift
//  Block Party — one town place or business held steady for the week.
//

import SwiftUI

struct SpotlightCard: View {
    let spotlight: BriefingSpotlight
    /// Human week label from `SpotlightWeekLabel`, e.g. "week of August 3" — not
    /// the "2026-W32" archive key, which is machine syntax and used to render here.
    var weekLabel: String? = nil
    var onOpen: (() -> Void)? = nil

    var body: some View {
        card
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                Text("Spotlight · \(displayWeekLabel)")
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
                .buttonStyle(FeedCardPressStyle())
                .padding(18)
                .accessibilityHint("Opens this place in Maps")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .blockPartyCard(padding: 0)
    }

    /// "this week" is the honest fallback when a date could not be parsed: the
    /// eyebrow must still say the subject is weekly, and it must never guess a date.
    private var displayWeekLabel: String {
        weekLabel ?? SpotlightWeekLabel.label(for: Date()) ?? "this week"
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
