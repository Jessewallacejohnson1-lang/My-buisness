//
//  PlaceDetailView.swift
//  Block Party — full "Around Town" showcase for one place.
//

import SwiftUI

struct PlaceDetailView: View {
    let place: Place
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
            PhotoView(name: place.image)
                .scaledToFill()
                .frame(height: 320)
                .frame(maxWidth: .infinity)
                .clipped()

            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                .frame(height: 320)

            VStack(alignment: .leading, spacing: 4) {
                Text(place.name)
                    .font(.display(32))
                    .foregroundStyle(.white)
                Text(place.tagline)
                    .font(.sans(15))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(20)
            .shadow(color: .black.opacity(0.35), radius: 8, y: 1)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 22) {
            // About
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("ABOUT")
                ForEach(place.description, id: \.self) { para in
                    Text(para)
                        .font(.sans(15))
                        .foregroundStyle(Hue.inkSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Good to know
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("GOOD TO KNOW")
                VStack(spacing: 0) {
                    ForEach(Array(place.facts.enumerated()), id: \.element.id) { i, fact in
                        HStack {
                            Text(fact.label)
                                .font(.sans(14))
                                .foregroundStyle(Hue.inkSecondary)
                            Spacer()
                            Text(fact.value)
                                .font(isNumeric(fact.value) ? .monoMedium(14) : .sansMedium(14))
                                .monospacedDigit()
                                .foregroundStyle(Hue.ink)
                        }
                        .padding(.vertical, 12)
                        if i < place.facts.count - 1 {
                            Rectangle().fill(Hue.hairline).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .background(Hue.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(Hue.hairline, lineWidth: 1))
            }

            // Hours & contact (Google Places, New) — renders only when data exists
            VenueInfoView(query: "\(place.name) \(place.where_ ?? "St Joseph MN")",
                          header: "Hours & contact", palette: .warm)

            // Open in Maps
            if let addr = place.where_ {
                Button { openInMaps(addr) } label: {
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
        }
        .padding(20)
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

    private func isNumeric(_ s: String) -> Bool {
        s.contains { $0.isNumber }
    }

    private func openInMaps(_ address: String) {
        let q = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "http://maps.apple.com/?q=\(q)") {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    PlaceDetailView(place: Places.all[0])
}
