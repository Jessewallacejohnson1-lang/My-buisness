//
//  SJMapView.swift
//  Hygge — Mapbox map of Saint Joseph, Minnesota.
//
//  Swap the visual style by changing MAP_STYLE_URL below to any
//  Mapbox Studio style URL or a built-in style string.
//

import SwiftUI
import MapboxMaps

// MARK: - Style (swap here)

private let MAP_STYLE_URL = "mapbox://styles/mapbox/streets-v12"

// MARK: - Pin data

private struct SJPin: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let coord: CLLocationCoordinate2D
}

private let sjPins: [SJPin] = [
    SJPin(id: "downtown",   name: "Downtown",            symbol: "cup.and.saucer.fill",   coord: .init(latitude: 45.5647, longitude: -94.3141)),
    SJPin(id: "saintbens",  name: "Saint Ben's",          symbol: "book.fill",             coord: .init(latitude: 45.5731, longitude: -94.3201)),
    SJPin(id: "chapel",     name: "Sacred Heart Chapel",  symbol: "building.columns.fill", coord: .init(latitude: 45.5728, longitude: -94.3193)),
    SJPin(id: "wobegon",    name: "Wobegon Trail",         symbol: "figure.hiking",         coord: .init(latitude: 45.5607, longitude: -94.3194)),
    SJPin(id: "saintjohns", name: "Saint John's",          symbol: "book.fill",             coord: .init(latitude: 45.5720, longitude: -94.3854)),
]

private let stJoeCenter = CLLocationCoordinate2D(latitude: 45.565, longitude: -94.317)

// MARK: - View

struct SJMapView: View {
    @State private var viewport: Viewport = .camera(
        center: stJoeCenter,
        zoom: 13.5,
        bearing: 0,
        pitch: 0
    )
    @State private var selectedPin: SJPin?

    var body: some View {
        ZStack(alignment: .top) {
            mapLayer
            headerBar
        }
    }

    private var mapLayer: some View {
        Map(viewport: $viewport) {
            annotations
        }
        .mapStyle(MapStyle(uri: StyleURI(rawValue: MAP_STYLE_URL)!))
        .ignoresSafeArea(edges: .bottom)
    }

    @MapContentBuilder
    private var annotations: some MapContent {
        ForEvery(sjPins) { pin in
            MapViewAnnotation(coordinate: pin.coord) {
                MapPinBadge(pin: pin, selected: selectedPin?.id == pin.id)
                    .onTapGesture { toggleSelection(pin) }
            }
            .allowOverlap(false)
        }
    }

    private func toggleSelection(_ pin: SJPin) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            selectedPin = (selectedPin?.id == pin.id) ? nil : pin
        }
    }

    private var headerBar: some View {
        HStack {
            Text("Saint Joseph")
                .font(.displaySemi(20))
                .foregroundStyle(Hue.ink)
            Spacer()
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    viewport = .camera(center: stJoeCenter, zoom: 13.5)
                    selectedPin = nil
                }
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Hue.moss700)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(Hue.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(Hue.hairline).frame(height: 1), alignment: .bottom)
    }
}

// MARK: - Pin badge

private struct MapPinBadge: View {
    let pin: SJPin
    let selected: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(selected ? Hue.moss700 : Hue.paper)
                    .frame(width: selected ? 46 : 38, height: selected ? 46 : 38)
                    .shadow(color: .black.opacity(selected ? 0.3 : 0.18), radius: selected ? 8 : 4, y: 2)
                    .overlay(Circle().stroke(selected ? Color.clear : Hue.hairline, lineWidth: 1))

                Image(systemName: pin.symbol)
                    .font(.system(size: selected ? 20 : 16, weight: .semibold))
                    .foregroundStyle(selected ? .white : Hue.moss700)
            }
            MapTriangle()
                .fill(selected ? Hue.moss700 : Hue.paper)
                .frame(width: 10, height: 6)

            if selected {
                Text(pin.name)
                    .font(.sansSemibold(11))
                    .foregroundStyle(Hue.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Hue.hairline, lineWidth: 1))
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    .padding(.top, 4)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
    }
}

// MARK: - Triangle shape

private struct MapTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
