//
//  RollCallSection.swift
//  Hygge — the Streetlight roll call: the anti-streak.
//
//  Counts the TOWN showing up this week — never a personal streak, nothing to
//  break, no guilt. `count` is the town-wide tally of RSVPs to real events from
//  today through the next seven days (real data only; a calm empty state when
//  the town is quiet). Every number is mono, per the house rules.
//

import SwiftUI

struct RollCallSection: View {
    /// Town-wide RSVPs to events happening today through the next 7 days.
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Hue.accent)
                Text("THE ROLL CALL")
                    .font(.mono(11))
                    .tracking(1.5)
                    .foregroundStyle(Hue.ink3)
            }

            if count > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(count)")
                        .font(.mono(36))
                        .monospacedDigit()
                        .foregroundStyle(Hue.accent)
                    Text(count == 1 ? "time St. Joe is\nshowing up this week"
                                    : "times St. Joe is\nshowing up this week")
                        .font(.displaySemi(18))
                        .foregroundStyle(Hue.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Quiet week in St. Joe")
                    .font(.displaySemi(20))
                    .foregroundStyle(Hue.ink)
                Text("Nothing on the board yet this week — be the first to show up.")
                    .font(.sans(14))
                    .foregroundStyle(Hue.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("No streaks to break. No guilt. Just the town, showing up.")
                .font(.sans(13))
                .foregroundStyle(Hue.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Hue.paper100)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Hue.hairline, lineWidth: 1))
    }
}
