//
//  InviteCard.swift
//  Block Party — "Bring a neighbor": a warm invite card, previewed + shared via the
//  app-wide ShareCenter reveal (Features/Share/ShareCenter.swift).
//

import SwiftUI

/// The visual that gets rendered to an image and shared.
struct InviteCard: View {
    let title: String
    let dateLabel: String
    let time: String?
    let location: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("You're invited")
                .font(.mono(12)).tracking(2).foregroundStyle(Hue.inkSecondary)
            Text(title)
                .font(.display(30)).foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                row("calendar", "\(dateLabel)\(time.map { " · \($0)" } ?? "")", mono: true)
                if let location, !location.isEmpty { row("mappin.and.ellipse", location, mono: false) }
            }
            Rectangle().fill(Hue.hairline).frame(height: 1).padding(.top, 2)
            Text("Come with me. Shared from Block Party in St. Joseph, MN.")
                .font(.sans(13)).foregroundStyle(Hue.inkSecondary)
        }
        .padding(24)
        .frame(width: 360, alignment: .leading)
        .background(Hue.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(Hue.hairline, lineWidth: 1))
    }

    private func row(_ symbol: String, _ text: String, mono: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(Hue.ink)
            Text(text).font(mono ? .monoMedium(15) : .sans(15)).foregroundStyle(Hue.ink)
        }
    }
}

/// The typographic place card rendered + shared by `SharePayload.place(...)` —
/// the map pin-detail sheet's share action. Same discipline as `InviteCard`:
/// type only, no drawn art.
struct PlaceShareCard: View {
    let name: String
    let categoryLabel: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Meet me at")
                .font(.mono(12)).tracking(2).foregroundStyle(Hue.inkSecondary)
            Text(name)
                .font(.display(30)).foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                row("mappin.and.ellipse", categoryLabel)
                if let detail, !detail.isEmpty { row("text.alignleft", detail) }
            }
            Rectangle().fill(Hue.hairline).frame(height: 1).padding(.top, 2)
            Text("Find it on the Block Party map of St. Joseph, MN.")
                .font(.sans(13)).foregroundStyle(Hue.inkSecondary)
        }
        .padding(24)
        .frame(width: 360, alignment: .leading)
        .background(Hue.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(Hue.hairline, lineWidth: 1))
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(Hue.ink)
            Text(text).font(.sans(15)).foregroundStyle(Hue.ink)
        }
    }
}

/// A tap-to-share "Invite a neighbor" button. Presents the app-wide share
/// reveal (`ShareCenter`) instead of jumping straight to the OS share sheet.
struct InviteButton: View {
    let title: String
    let dateLabel: String
    let time: String?
    let location: String?

    var body: some View {
        Button {
            ShareCenter.shared.present(.event(title: title, dateLabel: dateLabel, time: time, location: location))
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up").font(.system(size: 12, weight: .semibold))
                Text("Invite a neighbor").font(.sansSemibold(13))
            }
            .foregroundStyle(Hue.ink)
        }
        .buttonStyle(.plain)
    }
}
