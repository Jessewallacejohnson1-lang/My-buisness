//
//  CommunityFeedTimelineView.swift
//  Block Party — future community plans, grouped by a transparent time order.
//

import SwiftUI

struct CommunityFeedTimelineView: View {
    let events: [UpcomingEvent]
    let isLoading: Bool
    var onToggleRsvp: (UpcomingEvent) -> Void
    var onCompose: (() -> Void)?

    private var sections: [CommunityFeedSection] {
        CommunityFeedBucketer.sections(for: events)
    }

    var body: some View {
        Group {
            if isLoading {
                CommunityFeedLoadingState()
            } else if sections.isEmpty {
                CommunityFeedEmptyState(onCompose: onCompose)
            } else {
                VStack(alignment: .leading, spacing: 26) {
                    ForEach(sections) { section in
                        CommunityFeedSectionView(
                            section: section,
                            onToggleRsvp: onToggleRsvp
                        )
                    }

                    CommunityFeedEndState()
                }
            }
        }
    }
}

private struct CommunityFeedSectionView: View {
    let section: CommunityFeedSection
    let onToggleRsvp: (UpcomingEvent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.bucket.title)
                .font(.displaySemi(22))
                .foregroundStyle(Hue.ink)
                .accessibilityAddTraits(.isHeader)

            ForEach(section.events) { event in
                CommunityFeedEventCard(
                    event: event,
                    showsImage: section.bucket == .fresh,
                    onToggleRsvp: onToggleRsvp
                )
            }
        }
    }
}

private struct CommunityFeedEventCard: View {
    let event: UpcomingEvent
    let showsImage: Bool
    let onToggleRsvp: (UpcomingEvent) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reminderOn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsImage, let url = event.imageUrl.flatMap(URL.init) {
                CommunityFeedPostedImage(url: url)
            }

            VStack(alignment: .leading, spacing: 14) {
                eventDetails

                HStack(spacing: 10) {
                    rsvpButton
                    reminderButton
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .blockPartyCard(padding: 0)
        .task(id: event.id) {
            reminderOn = await Reminders.isScheduled(eventId: event.id)
        }
    }

    private var dateBadge: some View {
        VStack(spacing: 3) {
            Text(DateHelpers.weekdayLabel(event.eventDate).uppercased())
                .font(.mono(10))
                .tracking(0.6)
            Text(DateHelpers.prettyDate(event.eventDate))
                .font(.sansSemibold(11))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Hue.ink)
        .frame(width: 74)
        .frame(minHeight: 48)
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .background(Hue.fill, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        .accessibilityHidden(true)
    }

    private var eventDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                dateBadge

                VStack(alignment: .leading, spacing: 5) {
                    Text(event.title)
                        .font(.sansBold(17))
                        .foregroundStyle(Hue.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    if let clubName = event.clubName, !clubName.isEmpty {
                        Text(clubName)
                            .font(.sans(13))
                            .foregroundStyle(Hue.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            timeAndPlace

            Text("\(event.goingCount) going")
                .font(.mono(12))
                .monospacedDigit()
                .foregroundStyle(Hue.inkSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(event.title)
        .accessibilityValue(cardAccessibilityValue)
    }

    @ViewBuilder
    private var timeAndPlace: some View {
        if hasTimeOrPlace {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let startTime = event.startTime, !startTime.isEmpty {
                    Text(startTime)
                        .font(.mono(12))
                        .monospacedDigit()
                }

                if let location = event.location, !location.isEmpty {
                    if event.startTime?.isEmpty == false {
                        Text("•")
                    }
                    Text(location)
                        .font(.sans(13))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(Hue.inkSecondary)
        }
    }

    private var rsvpButton: some View {
        Button(event.rsvpd ? "Going" : "RSVP") {
            Haptics.light()
            onToggleRsvp(event)
        }
        .font(.sansSemibold(14))
        .foregroundStyle(event.rsvpd ? Hue.surface : Hue.ink)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(event.rsvpd ? Hue.ink : Hue.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                .stroke(event.rsvpd ? Color.clear : Hue.ink.opacity(0.4), lineWidth: 1)
        )
        .buttonStyle(PressableStyle(scale: 0.96))
        .animation(reduceMotion ? nil : Motion.snappy, value: event.rsvpd)
        .accessibilityLabel(event.rsvpd ? "Going" : "RSVP")
        .accessibilityHint("Updates your attendance for \(event.title)")
    }

    private var reminderButton: some View {
        Button(action: toggleReminder) {
            Text(reminderOn ? "Saved" : "Save")
                .font(.sansSemibold(14))
                .foregroundStyle(reminderOn ? Hue.ink : Hue.inkSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Hue.fill, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .stroke(Hue.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(PressableStyle(scale: 0.96))
        .accessibilityLabel(reminderOn ? "Saved reminder" : "Save reminder")
        .accessibilityHint("Saves a reminder for \(event.title)")
    }

    private var hasTimeOrPlace: Bool {
        let hasTime = event.startTime?.isEmpty == false
        let hasLocation = event.location?.isEmpty == false
        return hasTime || hasLocation
    }

    private var cardAccessibilityValue: String {
        let time = event.startTime?.isEmpty == false ? event.startTime! : "Time not listed"
        let location = event.location?.isEmpty == false ? event.location! : "Place not listed"
        let rsvp = event.rsvpd ? "You are going" : "Not yet RSVP’d"
        return "\(DateHelpers.prettyDate(event.eventDate)), \(time), \(location), \(event.goingCount) going, \(rsvp)"
    }

    private func toggleReminder() {
        Task {
            if reminderOn {
                Reminders.cancel(eventId: event.id)
                reminderOn = false
            } else if await Reminders.requestAuth() {
                await Reminders.schedule(
                    eventId: event.id,
                    title: event.title,
                    date: event.eventDate,
                    startTime: event.startTime
                )
                reminderOn = await Reminders.isScheduled(eventId: event.id)
            }
        }
    }
}

private struct CommunityFeedPostedImage: View {
    let url: URL

    var body: some View {
        AsyncImage(url: url) { phase in
            if case .success(let image) = phase {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 154)
                    .clipped()
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct CommunityFeedLoadingState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Loading community plans")
                .font(.sans(14))
                .foregroundStyle(Hue.inkSecondary)
                .accessibilityAddTraits(.updatesFrequently)

            CommunityFeedSkeletonCard()
            CommunityFeedSkeletonCard()
        }
    }
}

private struct CommunityFeedSkeletonCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                .fill(Hue.fill)
                .frame(width: 74, height: 58)

            VStack(alignment: .leading, spacing: 9) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Hue.fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 17)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Hue.fill)
                    .frame(width: 150, height: 13)
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .fill(Hue.fill)
                    .frame(width: 110, height: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .blockPartyCard(padding: 16)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

private struct CommunityFeedEmptyState: View {
    var onCompose: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("It’s a quiet day in St. Joe 🌿")
                .font(.displaySemi(22))
                .foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text("Here’s what’s coming up when neighbors add plans.")
                .font(.sans(14))
                .foregroundStyle(Hue.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Post something") {
                onCompose?()
            }
            .font(.sansSemibold(14))
            .foregroundStyle(Hue.ink)
            .frame(minHeight: 44)
            .buttonStyle(PressableStyle(scale: 0.96))
            .disabled(onCompose == nil)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .blockPartyCard(padding: 18)
    }
}

private struct CommunityFeedEndState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("You’re all caught up for now.")
                .font(.sansSemibold(14))
                .foregroundStyle(Hue.inkSecondary)
            Text("More neighbor plans will appear here.")
                .font(.sans(13))
                .foregroundStyle(Hue.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
