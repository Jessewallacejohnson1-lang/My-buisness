//
//  TrailsMapView.swift
//  Hygge — interactive trails map with draggable bottom sheet.
//
//  Map pinned on the real Lake Wobegon Trail trailhead in St. Joseph
//  (45.5665, -94.3161 — the trailhead park at 605 1st Ave NE, under the water
//  tower). "Map" buttons deep-link to Google Maps (falls back to Apple Maps).
//

import SwiftUI
import MapKit

// MARK: - Coordinates

// Trailhead park, 605 1st Ave NE — verified 2026-07-04 (see KnownVenues.swift)
private let wobegonCoord = CLLocationCoordinate2D(latitude: 45.5665, longitude: -94.3161)
private let stJoeCenter  = CLLocationCoordinate2D(latitude: 45.5650, longitude: -94.3180)

// MARK: - Maps helper

private func openInGoogleMaps(query: String, coord: CLLocationCoordinate2D? = nil) -> URL? {
    var components = URLComponents()
    if let coord {
        // Prefer exact coordinate so the pin lands right
        components.scheme = "https"
        components.host   = "maps.google.com"
        components.path   = "/"
        components.queryItems = [
            URLQueryItem(name: "q",      value: "\(coord.latitude),\(coord.longitude)"),
            URLQueryItem(name: "ll",     value: "\(coord.latitude),\(coord.longitude)"),
            URLQueryItem(name: "z",      value: "15"),
        ]
    } else {
        components.scheme = "https"
        components.host   = "maps.google.com"
        components.path   = "/"
        components.queryItems = [URLQueryItem(name: "q", value: query)]
    }
    return components.url
}

// MARK: - Main view

struct TrailsMapView: View {
    let trails: [Trail]
    var onBack: () -> Void

    @State private var position: MapCameraPosition = .region(MKCoordinateRegion(
        center: stJoeCenter,
        span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
    ))
    @State private var sheetH: CGFloat = 280
    @State private var dragStartH: CGFloat = 280
    @State private var dragging = false
    // Geocoded coords for community trails: trail.id → coordinate
    @State private var trailCoords: [String: CLLocationCoordinate2D] = [:]

    @Environment(\.openURL) private var openURL

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Map(position: $position) {
                    // Wobegon Trail — hardcoded verified coord
                    Annotation("Wobegon Trail", coordinate: wobegonCoord) {
                        TrailMapPin(label: "Wobegon Trail")
                    }
                    // Community trails — geocoded via Nominatim
                    ForEach(trails) { trail in
                        if let coord = trailCoords[trail.id] {
                            Annotation(trail.title, coordinate: coord) {
                                TrailMapPin(label: trail.title)
                            }
                        }
                    }
                }
                .ignoresSafeArea()

                bottomSheet(maxH: geo.size.height * 0.78)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .task {
            // Geocode each community trail in parallel
            await withTaskGroup(of: (String, CLLocationCoordinate2D?).self) { group in
                for trail in trails {
                    group.addTask {
                        let q = "\(trail.title) \(trail.location ?? "St. Joseph MN")"
                        let coord = await GeocoderService.shared.coordinate(for: q)
                        return (trail.id, coord)
                    }
                }
                for await (id, coord) in group {
                    if let coord { trailCoords[id] = coord }
                }
            }
        }
    }

    // MARK: - Sheet

    private func bottomSheet(maxH: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Drag handle + header — only this area carries the gesture
            VStack(spacing: 0) {
                Capsule()
                    .fill(Hue.ink3.opacity(0.3))
                    .frame(width: 36, height: 5)
                    .padding(.vertical, 10)

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

                    Text("Trails")
                        .font(.displaySemi(22))
                        .foregroundStyle(Hue.ink)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 14)

                Rectangle().fill(Hue.hairline).frame(height: 1)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if !dragging { dragStartH = sheetH; dragging = true }
                        sheetH = max(280, min(maxH, dragStartH - v.translation.height))
                    }
                    .onEnded { v in
                        dragging = false
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            sheetH = v.translation.height < -60 ? maxH : 280
                        }
                    }
            )

            // Scroll — gesture-free
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    WobegonAnchorCard { url in openURL(url) }

                    ForEach(trails) {
                        TrailSheetCard(trail: $0) { url in openURL(url) }
                    }

                    if trails.isEmpty {
                        Text("Community-posted trails will appear here.")
                            .font(.sans(13))
                            .foregroundStyle(Hue.ink3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 2)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 110)
            }
        }
        .frame(height: sheetH, alignment: .top)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: -8)
    }
}

// MARK: - Map pin

private struct TrailMapPin: View {
    var label: String = ""
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Hue.moss700)
                    .frame(width: 38, height: 38)
                    .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                Image(systemName: "figure.hiking")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            // Callout triangle
            Triangle()
                .fill(Hue.moss700)
                .frame(width: 10, height: 6)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Wobegon anchor card (AllTrails-style)

private struct WobegonAnchorCard: View {
    var onMap: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero photo
            ZStack(alignment: .bottomTrailing) {
                PhotoView(name: "wobegon-trail")
                    .scaledToFill()
                    .frame(height: 170)
                    .clipped()

                Button {
                    if let url = openInGoogleMaps(query: "Lake Wobegon Trail, St. Joseph, MN",
                                                   coord: wobegonCoord) {
                        onMap(url)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Map")
                            .font(.sansSemibold(13))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Hue.moss700)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .padding(12)
            }

            // Info
            VStack(alignment: .leading, spacing: 8) {
                Text("Lake Wobegon Trail")
                    .font(.sansBold(16))
                    .foregroundStyle(Hue.ink)

                Text("St. Joseph, Minnesota")
                    .font(.sans(13))
                    .foregroundStyle(Hue.ink2)

                HStack(spacing: 6) {
                    Label("Easy", systemImage: "figure.hiking")
                        .font(.mono(11))
                        .foregroundStyle(Hue.moss500)
                    dot
                    Text("Paved rail-trail")
                        .font(.mono(11))
                        .foregroundStyle(Hue.sky600)
                    dot
                    Text("Bike · Run · Walk")
                        .font(.mono(11))
                        .foregroundStyle(Hue.sky600)
                }
            }
            .padding(14)
        }
        .background(Hue.paper)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Hue.hairline, lineWidth: 1))
        .modifier(CardShadow())
    }

    private var dot: some View {
        Text("·").font(.mono(11)).foregroundStyle(Hue.ink3)
    }
}

// MARK: - Community trail card

private struct TrailSheetCard: View {
    let trail: Trail
    var onMap: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(trail.title)
                        .font(.sansBold(15))
                        .foregroundStyle(Hue.ink)

                    let meta = [trail.location, trail.length, trail.difficulty]
                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                    if !meta.isEmpty {
                        Text(meta).font(.mono(11)).foregroundStyle(Hue.sky600)
                    }
                }
                Spacer(minLength: 8)

                // Map button
                if let location = trail.location ?? Optional(trail.title),
                   let url = openInGoogleMaps(query: "\(location), St. Joseph, MN") {
                    Button { onMap(url) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "map.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Map")
                                .font(.sansSemibold(12))
                        }
                        .foregroundStyle(Hue.moss700)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Hue.moss700.opacity(0.08))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Hue.moss700.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let desc = trail.description, !desc.isEmpty {
                Text(desc)
                    .font(.sans(13))
                    .foregroundStyle(Hue.ink2)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hyggeCard(padding: 14)
    }
}
