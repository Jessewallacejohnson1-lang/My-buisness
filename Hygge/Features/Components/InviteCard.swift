//
//  InviteCard.swift
//  Hygge — "Bring a neighbor": a warm invite card + share sheet from any event.
//  The card renders to an image; the share sheet carries the image + a short line.
//

import SwiftUI
import UIKit

/// The visual that gets rendered to an image and shared.
struct InviteCard: View {
    let title: String
    let dateLabel: String
    let time: String?
    let location: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("YOU'RE INVITED")
                .font(.mono(12)).tracking(2).foregroundStyle(Hue.ink3)
            Text(title)
                .font(.display(30)).foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                row("calendar", "\(dateLabel)\(time.map { " · \($0)" } ?? "")", mono: true)
                if let location, !location.isEmpty { row("mappin.and.ellipse", location, mono: false) }
            }
            Rectangle().fill(Hue.hairline).frame(height: 1).padding(.top, 2)
            Text("Come with me — from Hygge, St. Joseph, MN")
                .font(.sans(13)).foregroundStyle(Hue.ink2)
        }
        .padding(24)
        .frame(width: 360, alignment: .leading)
        .background(Hue.paper)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).stroke(Hue.hairline, lineWidth: 1))
        .padding(16)
        .background(Hue.canvas)
    }

    private func row(_ symbol: String, _ text: String, mono: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(Hue.moss500)
            Text(text).font(mono ? .monoMedium(15) : .sans(15)).foregroundStyle(Hue.ink)
        }
    }
}

/// A tap-to-share "Invite a neighbor" button. Renders the card on tap only
/// (never per row-render), then presents the OS share sheet with image + text.
struct InviteButton: View {
    let title: String
    let dateLabel: String
    let time: String?
    let location: String?

    @State private var shareItems: [Any]?

    private var inviteText: String {
        var s = "Come to \(title) with me — \(dateLabel)"
        if let time, !time.isEmpty { s += " at \(time)" }
        if let location, !location.isEmpty { s += ", \(location)" }
        return s + ". (via Hygge)"
    }

    var body: some View {
        Button {
            var items: [Any] = [inviteText]
            if let image = renderCard() { items.insert(image, at: 0) }
            shareItems = items
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up").font(.system(size: 12, weight: .semibold))
                Text("Invite a neighbor").font(.sansSemibold(13))
            }
            .foregroundStyle(Hue.sky700)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: Binding(get: { shareItems != nil }, set: { if !$0 { shareItems = nil } })) {
            if let shareItems { ActivityView(items: shareItems) }
        }
    }

    @MainActor private func renderCard() -> UIImage? {
        let renderer = ImageRenderer(content: InviteCard(title: title, dateLabel: dateLabel, time: time, location: location))
        renderer.scale = 3   // retina; avoids the deprecated UIScreen.main
        return renderer.uiImage
    }
}

/// Thin wrapper over UIActivityViewController for SwiftUI.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
