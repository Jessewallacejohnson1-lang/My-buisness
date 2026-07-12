//
//  AppInviteCard.swift
//  Hygge — the preview card for "SHARE HYGGE" (app invite). Typographic only,
//  matching InviteCard's language — no illustration (house rule).
//

import SwiftUI

struct AppInviteCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ST. JOSEPH, MN")
                .font(.mono(12)).tracking(2).foregroundStyle(Hue.ink3)
            Text("Come see what's happening in town")
                .font(.display(28)).foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("The town calendar, today's happenings, and a live map of what's on — in one calm place.")
                .font(.sans(15)).foregroundStyle(Hue.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Hue.hairline).frame(height: 1).padding(.top, 2)
            Text("Hygge")
                .font(.logo(20)).foregroundStyle(Hue.accent)
        }
        .padding(24)
        .frame(width: 360, alignment: .leading)
        .background(Hue.paper)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).stroke(Hue.hairline, lineWidth: 1))
        .padding(16)
        .background(Hue.canvas)
    }
}
