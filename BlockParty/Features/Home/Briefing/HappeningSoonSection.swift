//
//  HappeningSoonSection.swift
//  Block Party — the featured events module in the daily briefing.
//

import SwiftUI

struct HappeningSoonSection: View {
    let events: [BriefingEvent]
    let fallback: BriefingFallback?
    var onOpen: ((BriefingEvent) -> Void)? = nil
    var onRsvp: ((BriefingEvent, Bool) -> Void)? = nil

    @ViewBuilder
    var body: some View {
        if events.isEmpty {
            if let fallback {
                section {
                    fallbackContent(fallback)
                }
            }
        } else {
            section {
                if events.count == 1, let event = events.first {
                    HappeningSoonEventCard(
                        event: event,
                        isHero: true,
                        onOpen: onOpen,
                        onRsvp: onRsvp
                    )
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(events) { event in
                                HappeningSoonEventCard(
                                    event: event,
                                    isHero: false,
                                    onOpen: onOpen,
                                    onRsvp: onRsvp
                                )
                                .frame(width: 300)
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.vertical, 8)
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .scrollClipDisabled()
                }
            }
        }
    }

    private func section<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HAPPENING SOON")
                .font(.sansSemibold(11))
                .tracking(1)
                .foregroundStyle(Hue.inkSecondary)
                .accessibilityAddTraits(.isHeader)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fallbackContent(_ fallback: BriefingFallback) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = fallback.title, !title.isEmpty {
                Text(title)
                    .font(.displaySemi(20))
                    .foregroundStyle(Hue.ink)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(fallback.body)
                .font(.sans(15))
                .foregroundStyle(Hue.inkSecondary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)

            // TODO(jesse): render `fallback.deeplink` as a real control once Today
            // can switch tabs. Until then there is deliberately NO call to action
            // here — a row styled like a button that does nothing reads as a broken
            // screen, which is worse than the copy standing on its own.
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Hue.fill)
        .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
    }
}

private struct HappeningSoonEventCard: View {
    let event: BriefingEvent
    let isHero: Bool
    let onOpen: ((BriefingEvent) -> Void)?
    let onRsvp: ((BriefingEvent, Bool) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if let onOpen {
                Button {
                    Haptics.light()
                    onOpen(event)
                } label: {
                    primaryContent
                }
                .buttonStyle(BriefingCardPressStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(openAccessibilityLabel)
                .accessibilityHint("Opens event details")
            } else {
                primaryContent
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(openAccessibilityLabel)
            }

            actionRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .blockPartyCard(padding: 0)
    }

    private var primaryContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            media

            VStack(alignment: .leading, spacing: 6) {
                if let metaLine {
                    Text(metaLine)
                        .font(.sansMedium(13))
                        .foregroundStyle(Hue.inkSecondary)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let clubName = event.clubName, !clubName.isEmpty {
                    Text(clubName)
                        .font(.sans(13))
                        .foregroundStyle(Hue.inkSecondary)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .contentShape(Rectangle())
    }

    private var media: some View {
        ZStack(alignment: .bottomLeading) {
            eventImage
                .frame(maxWidth: .infinity)
                .frame(height: isHero ? 188 : 154)
                .clipped()

            LinearGradient(
                colors: [Hue.ink.opacity(0), Hue.ink.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(event.category.uppercased())
                    .font(.sansSemibold(10))
                    .tracking(1)

                Text(event.title)
                    .font(isHero ? .display(28) : .displaySemi(22))
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Hue.surface)
            .padding(16)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var eventImage: some View {
        if let imageURL = event.imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .empty:
                    Hue.fill
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Hue.ink
                @unknown default:
                    Hue.fill
                }
            }
        } else {
            Hue.ink
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Text("\(event.goingCount) going")
                .font(.mono(12))
                .monospacedDigit()
                .foregroundStyle(Hue.inkSecondary)

            Spacer(minLength: 8)

            if let onRsvp {
                // The app's existing RSVP control, reused unchanged: a 44pt rounded
                // square (never a pill) whose plus rotates into a checkmark over
                // 0.18s, with a square ring burst on join and a 0.88 press scale on
                // spring(0.25, 0.6). Reusing it rather than inventing a second RSVP
                // affordance is the whole point — joining should feel identical
                // wherever you do it.
                //
                // Haptics fire HERE rather than inside the button: the feed's call
                // site uses raw generators, which is a documented deviation, and new
                // call sites go through the `Haptics` helper (it no-ops under Low
                // Power Mode).
                FeedEventCardJoinButton(
                    isJoined: event.rsvpd,
                    isFallback: false,
                    reduceMotion: reduceMotion,
                    autoplayPressed: false,
                    onToggle: {
                        let joining = !event.rsvpd
                        if joining { Haptics.success() } else { Haptics.light() }
                        onRsvp(event, joining)
                    }
                )
                .accessibilityLabel(
                    event.rsvpd
                        ? "Cancel RSVP for \(event.title)"
                        : "RSVP to \(event.title)"
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    private nonisolated var metaLine: String? {
        let parts = [event.startTime, event.location]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private nonisolated var openAccessibilityLabel: String {
        var parts = [event.title]
        if let metaLine { parts.append(metaLine) }
        if let clubName = event.clubName, !clubName.isEmpty { parts.append(clubName) }
        parts.append("\(event.goingCount) going")
        return parts.joined(separator: ", ")
    }
}

private struct BriefingCardPressStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.985

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? pressedScale : 1))
            .opacity(reduceMotion && configuration.isPressed ? 0.78 : 1)
            .animation(
                reduceMotion ? .easeOut(duration: 0.1) : Motion.tilePress,
                value: configuration.isPressed
            )
    }
}
