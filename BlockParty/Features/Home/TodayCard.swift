//
//  TodayCard.swift
//  Block Party — the "today" hero. Honest empty state until events are wired.
//

import SwiftUI

struct TodayCard: View {
    var onAdd: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.mono(11))
                .tracking(1.5)
                .foregroundStyle(Hue.inkSecondary)

            Text("Nothing planned yet")
                .font(.displaySemi(24))
                .foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text("Add an event, club, or trail and it shows up here.")
                .font(.sans(14))
                .foregroundStyle(Hue.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button { onAdd?() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Add something")
                        .font(.sansSemibold(14))
                }
                .foregroundStyle(Hue.surface)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Hue.ink)
                .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .blockPartyCard(padding: 18)
    }
}
