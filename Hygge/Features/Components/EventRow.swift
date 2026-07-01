//
//  EventRow.swift
//  Hygge — a timeline event row: time, title, place, going count, RSVP toggle.
//

import SwiftUI

struct EventRow: View {
    let event: TimelineEvent
    var onToggleRsvp: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let time = event.startTime, !time.isEmpty {
                    Text(time)
                        .font(.mono(12))
                        .monospacedDigit()
                        .foregroundStyle(Hue.ink3)
                }
                Text(event.title)
                    .font(.sansBold(16))
                    .foregroundStyle(Hue.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let club = event.clubName, !club.isEmpty {
                    Text(club)
                        .font(.sans(12))
                        .foregroundStyle(Hue.sky600)
                }
                if let loc = event.location, !loc.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 11))
                        Text(loc).font(.sans(13))
                    }
                    .foregroundStyle(Hue.ink2)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                if let onToggleRsvp {
                    Button(action: onToggleRsvp) {
                        Text(event.rsvpd ? "Going" : "RSVP")
                            .font(.sansSemibold(13))
                            .foregroundStyle(event.rsvpd ? Hue.paper : Hue.moss700)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(event.rsvpd ? Hue.moss700 : Hue.paper)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(event.rsvpd ? Color.clear : Hue.moss700.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                if event.goingCount > 0 {
                    Text("\(event.goingCount) going")
                        .font(.mono(11))
                        .monospacedDigit()
                        .foregroundStyle(Hue.ink3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hyggeCard(padding: 16)
    }
}
