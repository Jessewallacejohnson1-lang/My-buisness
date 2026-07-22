//
//  ParkDetailView.swift
//  Block Party — full-screen detail sheet for one city park: hero photo, the real
//  description, and its amenities. Mirrors PlaceDetailView's shape.
//

import SwiftUI
import CoreLocation

struct ParkDetailView: View {
    let park: Park
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                hero
                content
            }
        }
        .background(Hue.paper)
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .topLeading) { closeButton }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            photo
                .frame(height: 320)
                .frame(maxWidth: .infinity)
                .clipped()

            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                .frame(height: 320)

            VStack(alignment: .leading, spacing: 4) {
                Text(park.title)
                    .font(.display(32))
                    .foregroundStyle(.white)
                Text(park.address)
                    .font(.sans(15))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(20)
            .shadow(color: .black.opacity(0.35), radius: 8, y: 1)
        }
    }

    @ViewBuilder
    private var photo: some View {
        if let localName = KnownLocalPhoto.name(forTitle: park.title) {
            PhotoView(name: localName).scaledToFill()
        } else {
            let venue = ActivityVenue.park(park)
            VenuePhoto(venueName: venue.name, coordinate: venue.anchor,
                       maxWidth: 1600) { ExploreBlankPhoto() }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 22) {
            // About
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("About")
                Text(park.description)
                    .font(.sans(15))
                    .foregroundStyle(Hue.inkSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Amenities — acreage (if known) leads the list, then every real
            // feature transcribed from the park's city facilities page.
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Amenities")
                VStack(spacing: 0) {
                    ForEach(Array(amenityRows.enumerated()), id: \.offset) { i, row in
                        HStack(spacing: 10) {
                            Image(systemName: row.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Hue.ink)
                                .frame(width: 18)
                            Text(row.text)
                                .font(.sans(14))
                                .foregroundStyle(Hue.ink)
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        if i < amenityRows.count - 1 {
                            Rectangle().fill(Hue.hairline).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .background(Hue.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(Hue.hairline, lineWidth: 1))
            }

            // Open in Maps
            Button { openInMaps() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "map")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Open in Maps")
                        .font(.sansSemibold(15))
                }
                .foregroundStyle(Hue.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Hue.fill)
                .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    private struct AmenityRow { let icon: String; let text: String }
    private var amenityRows: [AmenityRow] {
        var rows: [AmenityRow] = []
        if let acres = park.acres { rows.append(AmenityRow(icon: "leaf.fill", text: "\(acres) acres")) }
        rows.append(contentsOf: park.features.map { AmenityRow(icon: "checkmark.circle.fill", text: $0) })
        return rows
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.mono(11))
            .tracking(1.5)
            .foregroundStyle(Hue.inkSecondary)
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Hue.ink)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Hue.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.leading, 16)
        .padding(.top, 56)
    }

    private func openInMaps() {
        let q = "\(park.title), \(park.address)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "http://maps.apple.com/?q=\(q)") {
            UIApplication.shared.open(url)
        }
    }
}
