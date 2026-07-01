//
//  AroundTownCarousel.swift
//  Hygge — horizontal showcase of real St. Joseph places.
//

import SwiftUI

struct AroundTownCarousel: View {
    @State private var selected: Place?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Around town")
                .font(.displaySemi(22))
                .foregroundStyle(Hue.ink)
                .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Places.all) { place in
                        PlaceTile(place: place)
                            .onTapGesture { selected = place }
                    }
                }
                .padding(.horizontal, 18)
            }
        }
        .sheet(item: $selected) { place in
            PlaceDetailView(place: place)
        }
    }
}

struct PlaceTile: View {
    let place: Place

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PhotoView(name: place.image)
                .scaledToFill()
                .frame(width: 248, height: 150)
                .clipped()

            VStack(alignment: .leading, spacing: 3) {
                Text(place.name)
                    .font(.sansBold(16))
                    .foregroundStyle(Hue.ink)
                Text(place.tagline)
                    .font(.sans(13))
                    .foregroundStyle(Hue.ink2)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(width: 248, alignment: .leading)
        }
        .background(Hue.paper)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Hue.hairline, lineWidth: 1))
        .modifier(CardShadow())
    }
}
