//
//  AppInviteCard.swift
//  Block Party — the preview card for "SHARE BLOCK PARTY" (app invite). The canonical
//  app mark is the only image; the rest stays typographic, with no illustration.
//

import SwiftUI

struct AppInviteCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("St. Joseph, MN")
                .font(.mono(12)).tracking(2).foregroundStyle(Hue.inkSecondary)
            Text("Come see what's happening in town")
                .font(.display(28)).foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Today's events, the town calendar, and a live map — all in one place.")
                .font(.sans(15)).foregroundStyle(Hue.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Hue.hairline).frame(height: 1).padding(.top, 2)
            HStack(spacing: 9) {
                BlockPartyMark(side: 30)
                Text("Block Party")
                    .font(.logo(20)).foregroundStyle(Hue.ink)
            }
        }
        .padding(24)
        .frame(width: 360, alignment: .leading)
        .background(Hue.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(Hue.hairline, lineWidth: 1))
    }
}
