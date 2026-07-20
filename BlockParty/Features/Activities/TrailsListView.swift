//
//  TrailsListView.swift
//  Block Party — AllTrails-style list of trails.
//
//  Wobegon card uses a bundled photo. Community trail cards prefer the trail's own
//  uploaded photo, else a confidently-identified real Google Places photo (never a
//  generic stock photo — see GooglePlacesService.confidentPhoto(forFreeText:hint:)).
//  Google Maps URLs use Nominatim-geocoded coordinates for accurate pins.
//

import SwiftUI
import MapKit

// MARK: - Main list

struct TrailsListView: View {
    let trails: [Trail]
    var onBack: () -> Void
    var onViewMap: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 20)

                WobegonListCard(openURL: { openURL($0) })
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)

                ForEach(trails) { trail in
                    CommunityTrailCard(trail: trail, openURL: { openURL($0) })
                        .padding(.horizontal, 18)
                        .padding(.bottom, 14)
                }

                if trails.isEmpty {
                    Text("Community-posted trails will appear here once neighbors add them.")
                        .font(.sans(14))
                        .foregroundStyle(Hue.ink3)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 18)
                        .padding(.top, 20)
                }

                Color.clear.frame(height: 100)
            }
        }
        .background(Hue.canvas)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Activities")
                            .font(.sansMedium(13))
                    }
                    .foregroundStyle(Hue.sky700)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onViewMap) {
                    HStack(spacing: 5) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 12, weight: .medium))
                        Text("Map")
                            .font(.sansSemibold(13))
                    }
                    .foregroundStyle(Hue.moss700)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Hue.moss700.opacity(0.09))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Hue.moss700.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            Text("Trails")
                .font(.display(30))
                .foregroundStyle(Hue.ink)
        }
    }
}

// MARK: - Wobegon card (bundled photo, coords resolved via KnownVenues)

private struct WobegonListCard: View {
    var openURL: (URL) -> Void

    // Lake Wobegon trailhead under the water tower, 610 County Rd 2 — resolved from the single source of truth (KnownVenues)
    private let coord = KnownVenues.coordinate(for: "Wobegon Trailhead")
        ?? CLLocationCoordinate2D(latitude: 45.5697, longitude: -94.3180)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                PhotoView(name: "wobegon-trail")
                    .scaledToFill()
                    .frame(height: 190)
                    .clipped()

                Button {
                    if let url = googleMapsURL(label: "Lake Wobegon Trailhead, 610 County Rd 2, St. Joseph MN", coord: coord) {
                        openURL(url)
                    }
                } label: { mapPill() }
                .buttonStyle(.plain)
                .padding(12)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Lake Wobegon Trail")
                    .font(.sansBold(17))
                    .foregroundStyle(Hue.ink)
                Text("Trailhead by the water tower · County Rd 2")
                    .font(.sans(13))
                    .foregroundStyle(Hue.ink2)
                HStack(spacing: 6) {
                    statBadge(icon: "figure.hiking", label: "Easy")
                    dot
                    Text("65 mi paved").font(.mono(11)).foregroundStyle(Hue.sky600)
                    dot
                    Text("Bike · Run · Walk").font(.mono(11)).foregroundStyle(Hue.sky600)
                }
            }
            .padding(14)
        }
        .background(Hue.paper)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Hue.hairline, lineWidth: 1))
        .modifier(CardShadow())
    }
}

// MARK: - Community trail card (Pexels photo + Nominatim Maps link)

private struct CommunityTrailCard: View {
    let trail: Trail
    var openURL: (URL) -> Void

    @State private var geocodedCoord: CLLocationCoordinate2D?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                photoArea
                    .frame(height: 160)
                    .clipped()

                Button {
                    let label = "\(trail.title) \(trail.location ?? "St. Joseph MN")"
                    if let url = googleMapsURL(label: label, coord: geocodedCoord) {
                        openURL(url)
                    }
                } label: { mapPill() }
                .buttonStyle(.plain)
                .padding(12)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(trail.title).font(.sansBold(16)).foregroundStyle(Hue.ink)

                if let loc = trail.location, !loc.isEmpty {
                    Text(loc).font(.sans(13)).foregroundStyle(Hue.ink2)
                }

                let meta = [trail.difficulty, trail.length]
                    .compactMap { $0 }.filter { !$0.isEmpty }
                if !meta.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(meta.enumerated()), id: \.offset) { i, s in
                            if i > 0 { dot }
                            Text(s).font(.mono(11)).foregroundStyle(Hue.sky600)
                        }
                    }
                }

                if let desc = trail.description, !desc.isEmpty {
                    Text(desc).font(.sans(13)).foregroundStyle(Hue.ink2).lineLimit(2)
                }
            }
            .padding(14)
        }
        .background(Hue.paper)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Hue.hairline, lineWidth: 1))
        .modifier(CardShadow())
        .task {
            // Geocode location for accurate Maps pin
            let geocodeQuery = "\(trail.title) \(trail.location ?? "St. Joseph MN")"
            geocodedCoord = await GeocoderService.shared.coordinate(for: geocodeQuery)
        }
    }

    @ViewBuilder
    private var photoArea: some View {
        if let url = trail.imageUrl.flatMap(URL.init) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: placeholder
                }
            }
        } else if let localName = KnownLocalPhoto.name(forTitle: trail.title) {
            PhotoView(name: localName).scaledToFill()
        } else {
            VenuePhoto(venueName: trail.title, hint: trail.location) { placeholder }
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [Hue.sky800.opacity(0.4), Hue.moss700.opacity(0.5)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            ProgressView().tint(.white.opacity(0.7))
        }
    }
}

// MARK: - Shared helpers

private func mapPill() -> some View {
    HStack(spacing: 5) {
        Image(systemName: "map.fill").font(.system(size: 11, weight: .semibold))
        Text("Map").font(.sansSemibold(13))
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    .background(Hue.moss700)
    .clipShape(Capsule())
    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
}

private func statBadge(icon: String, label: String) -> some View {
    HStack(spacing: 3) {
        Image(systemName: icon).font(.system(size: 10, weight: .medium))
        Text(label).font(.mono(11))
    }
    .foregroundStyle(Hue.moss500)
}

private var dot: some View {
    Text("·").font(.mono(11)).foregroundStyle(Hue.ink3)
}

private func googleMapsURL(label: String, coord: CLLocationCoordinate2D? = nil) -> URL? {
    var c = URLComponents()
    c.scheme = "https"; c.host = "maps.google.com"; c.path = "/"
    if let coord {
        c.queryItems = [
            URLQueryItem(name: "q",  value: "\(coord.latitude),\(coord.longitude)"),
            URLQueryItem(name: "ll", value: "\(coord.latitude),\(coord.longitude)"),
            URLQueryItem(name: "z",  value: "15"),
        ]
    } else {
        c.queryItems = [URLQueryItem(name: "q", value: label)]
    }
    return c.url
}
