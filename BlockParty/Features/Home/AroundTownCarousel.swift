//
//  AroundTownCarousel.swift
//  Block Party — compact 3D perspective card carousel with expandable card.
//
//  Tap a card → it spring-scales up into an overlay card (no matchedGeometry —
//  cleaner and reliable across scroll views). Dismiss with ✕ or backdrop tap.
//

import SwiftUI

// MARK: - Layout constants

private let cardW: CGFloat   = 155
private let cardH: CGFloat   = 195
private let spacing: CGFloat = 10
private let step: CGFloat    = cardW + spacing
private let dragThreshold: CGFloat = 50
private let maxAngle: Double  = 28
private let maxScale: CGFloat = 0.10
private let maxFade: CGFloat  = 0.45

// MARK: - Carousel

struct AroundTownCarousel: View {
    @Binding var expanded: Place?
    var ns: Namespace.ID           // kept in signature for HomeView compat, unused now

    @State private var currentIndex = 0
    @State private var drag: CGFloat = 0

    private let places = Places.all

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Around town")
                .font(.displaySemi(22))
                .foregroundStyle(Hue.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)

            GeometryReader { _ in
                ZStack {
                    ForEach(Array(places.enumerated()), id: \.offset) { i, place in
                        cardView(place: place, index: i)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { drag = $0.translation.width }
                        .onEnded { v in
                            let committed = abs(v.translation.width) > dragThreshold
                                || abs(v.velocity.width) > 600
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                                if committed {
                                    if v.translation.width < 0 {
                                        currentIndex = min(currentIndex + 1, places.count - 1)
                                    } else {
                                        currentIndex = max(currentIndex - 1, 0)
                                    }
                                }
                                drag = 0
                            }
                        }
                )
            }
            .frame(height: cardH + 20)

            // Pagination dots
            HStack(spacing: 6) {
                ForEach(places.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == currentIndex ? Hue.ink : Hue.ink.opacity(0.18))
                        .frame(width: i == currentIndex ? 22 : 7, height: 7)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentIndex)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func cardView(place: Place, index: Int) -> some View {
        let isBeingExpanded = expanded?.id == place.id
        let rawOffset = (CGFloat(index - currentIndex) * step) + drag
        let normalized = rawOffset / step
        let yRotation = Double(normalized) * (-maxAngle)
        let scale     = max(0.82, 1 - min(abs(normalized), 1) * maxScale)
        let opacity: Double = isBeingExpanded ? 0.0 : max(0.4, 1 - min(abs(normalized), 1.4) * maxFade)

        PlaceCard(place: place)
            .frame(width: cardW, height: cardH)
            .rotation3DEffect(.degrees(yRotation), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
            .scaleEffect(scale)
            .opacity(opacity)
            .offset(x: rawOffset)
            .animation(.spring(response: 0.38, dampingFraction: 0.72), value: drag)
            .animation(.spring(response: 0.38, dampingFraction: 0.72), value: currentIndex)
            .onTapGesture {
                if index == currentIndex {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                        expanded = place
                    }
                } else {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                        currentIndex = index
                    }
                }
            }
    }
}

// MARK: - Small card

struct PlaceCard: View {
    let place: Place

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PhotoView(name: place.image)
                .scaledToFill()
                .frame(width: cardW, height: 108)
                .clipped()

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 6) {
                    Text(place.name)
                        .font(.sansBold(13))
                        .foregroundStyle(Hue.ink)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Image(systemName: placeSymbol(place))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Hue.moss700)
                }
                Text(place.tagline)
                    .font(.sans(11))
                    .foregroundStyle(Hue.ink2)
                    .lineLimit(2)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
        }
        .background(Hue.paper)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Hue.hairline, lineWidth: 1))
        .modifier(CardShadow())
    }
}

// MARK: - Expanded overlay card (rendered in MainTabsView ZStack)

struct PlaceExpandedCard: View {
    let place: Place
    var ns: Namespace.ID           // kept in signature for call-site compat
    var onClose: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero photo — GeometryReader gives the exact available width
            GeometryReader { geo in
                ZStack(alignment: .bottomLeading) {
                    PhotoView(name: place.image)
                        .scaledToFill()
                        .frame(width: geo.size.width, height: 200)
                        .clipped()

                    LinearGradient(colors: [.clear, .black.opacity(0.55)],
                                   startPoint: .center, endPoint: .bottom)
                        .frame(width: geo.size.width, height: 200)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(place.name)
                            .font(.display(24))
                            .foregroundStyle(.white)
                        Text(place.tagline)
                            .font(.sans(13))
                            .foregroundStyle(.white.opacity(0.88))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }
            }
            .frame(height: 200)

            // Scrollable content
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(place.description.prefix(2), id: \.self) { para in
                        Text(para)
                            .font(.sans(14))
                            .foregroundStyle(Hue.ink2)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !place.facts.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(place.facts.enumerated()), id: \.element.id) { i, fact in
                                HStack {
                                    Text(fact.label).font(.sans(13)).foregroundStyle(Hue.ink3)
                                    Spacer()
                                    Text(fact.value).font(.sansMedium(13)).foregroundStyle(Hue.ink)
                                }
                                .padding(.vertical, 10)
                                if i < place.facts.count - 1 {
                                    Rectangle().fill(Hue.hairline).frame(height: 1)
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .background(Hue.canvas)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Hue.hairline, lineWidth: 1))
                    }

                    if let addr = place.where_ {
                        Button {
                            let q = addr.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                            if let url = URL(string: "http://maps.apple.com/?q=\(q)") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "map").font(.system(size: 13, weight: .semibold))
                                Text("Open in Maps").font(.sansSemibold(14))
                            }
                            .foregroundStyle(Hue.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Hue.canvas)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Hue.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
                .padding(.bottom, 4)
            }
            .frame(maxHeight: 240)
        }
        .frame(maxWidth: .infinity)
        .background(Hue.paper)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .clipped()
        .shadow(color: .black.opacity(0.2), radius: 28, x: 0, y: 10)
        // Spring-scale entry/exit
        .scaleEffect(appeared ? 1.0 : 0.82)
        .opacity(appeared ? 1.0 : 0)
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Hue.ink)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(Hue.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(14)
        }
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                appeared = true
            }
        }
    }
}

// MARK: - Helpers

private func placeSymbol(_ place: Place) -> String {
    switch place.slug {
    case "downtown":             return "cup.and.saucer.fill"
    case "saint-bens":           return "book.fill"
    case "sacred-heart-chapel":  return "building.columns.fill"
    case "saint-johns":          return "book.fill"
    case "wobegon-trail":        return "figure.hiking"
    default:                     return "mappin.fill"
    }
}
