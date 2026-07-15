//
//  POIDetailSheet.swift
//  Hygge — the detail sheet for a tapped POI marker: name + family, address +
//  Open in Maps, and the live Google enrichment (open-now/hours, website, phone,
//  and a confident-match photo) reused from VenueInfoView. Presented via
//  .sheet(item:) from SJMapView. No fake rows — VenueInfoView renders nothing until
//  real data arrives, and nothing for a venue with no hours/website/phone/photo.
//

import SwiftUI

struct POIDetailSheet: View {
    let poi: POI
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let address = poi.address, !address.isEmpty {
                    Text(address)
                        .font(.sans(14)).foregroundStyle(Hue.gray)
                        .fixedSize(horizontal: false, vertical: true)
                }
                openInMapsButton
                VenueInfoView(query: poi.name,
                              identity: VenueIdentity(name: poi.name, coordinate: poi.coordinate))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(poi.family.tint).frame(width: 46, height: 46)
                Image(systemName: poi.glyph)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(poi.name).font(.display(21)).foregroundStyle(Hue.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(poi.family.label.uppercased())
                    .font(.mono(11)).tracking(1.2).foregroundStyle(Hue.gray)
            }
        }
    }

    private var openInMapsButton: some View {
        Button(action: openInMaps) {
            HStack(spacing: 8) {
                Image(systemName: "map.fill").font(.system(size: 14, weight: .semibold))
                Text("Open in Maps").font(.sansMedium(15))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Hue.accent, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(poi.name) in Maps")
    }

    private func openInMaps() {
        let q = poi.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "http://maps.apple.com/?q=\(q)&ll=\(poi.lat),\(poi.lon)") {
            openURL(url)
        }
    }
}
