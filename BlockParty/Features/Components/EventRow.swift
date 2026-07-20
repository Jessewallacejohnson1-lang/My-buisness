//
//  EventRow.swift
//  Block Party — a timeline event row: time, title, place, going count, RSVP toggle.
//

import SwiftUI

struct EventRow: View {
    let event: TimelineEvent
    var date: String?               // YYYY-MM-DD — enables the "Remind me" bell
    var onToggleRsvp: (() -> Void)?

    @State private var reminderOn = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let time = event.startTime, !time.isEmpty {
                    Text(time)
                        .font(.mono(12))
                        .monospacedDigit()
                        .foregroundStyle(Hue.inkSecondary)
                }
                Text(event.title)
                    .font(.sansBold(16))
                    .foregroundStyle(Hue.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let club = event.clubName, !club.isEmpty {
                    Text(club)
                        .font(.sans(12))
                        .foregroundStyle(Hue.ink)
                }
                if let loc = event.location, !loc.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 11))
                        Text(loc).font(.sans(13))
                    }
                    .foregroundStyle(Hue.inkSecondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                if let onToggleRsvp {
                    Button {
                        Haptics.light()
                        onToggleRsvp()
                    } label: {
                        Text(event.rsvpd ? "Going" : "RSVP")
                            .font(.sansSemibold(13))
                            .foregroundStyle(event.rsvpd ? .white : Hue.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(event.rsvpd ? Hue.ink : Hue.surface)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).stroke(event.rsvpd ? Color.clear : Hue.ink.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(PressableStyle(scale: 0.94))
                }
                if event.goingCount > 0 {
                    Text("\(event.goingCount) going")
                        .font(.mono(11))
                        .monospacedDigit()
                        .foregroundStyle(Hue.inkSecondary)
                }
                if date != nil {
                    Button(action: toggleReminder) {
                        Image(systemName: reminderOn ? "bell.fill" : "bell")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(reminderOn ? Hue.ink : Hue.inkSecondary)
                            .symbolEffect(.bounce, value: reminderOn)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .blockPartyCard(padding: 16)
        .task {
            if date != nil { reminderOn = await Reminders.isScheduled(eventId: event.id) }
        }
    }

    private func toggleReminder() {
        guard let date else { return }
        Task {
            if reminderOn {
                Reminders.cancel(eventId: event.id)
                reminderOn = false
            } else if await Reminders.requestAuth() {
                await Reminders.schedule(eventId: event.id, title: event.title, date: date, startTime: event.startTime)
                reminderOn = true
            }
        }
    }
}
