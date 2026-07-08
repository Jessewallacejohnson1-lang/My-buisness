//
//  VenueInfoView.swift
//  Hygge — Google Places (New) enrichment for a known place: open-now + hours,
//  Website, Call, and (only when confidently identified) a real venue photo.
//
//  Resolves name → place_id via search() once (cached), then details(). Renders
//  nothing until data arrives, and nothing if the place has no hours/website/
//  phone/photo — no fake rows, no placeholder art.
//
//  No ratings (brand rule). PHOTO — Locked Rule A: a place_id from search() is a
//  fuzzy match, so a photo is shown ONLY when `identity` is supplied AND the
//  resolved place lands within 75 m of that curated coordinate with an aligned
//  name (an "exact match" earned by construction). Attribution is displayed on
//  the image whenever Google returns one.
//

import SwiftUI
import CoreLocation

struct VenueInfoView: View {
    struct Palette {
        let card: Color
        let ink: Color
        let sub: Color
        let hairline: Color
        /// Cooler map chrome (MapSheet spot detail).
        static let map = Palette(card: Hue.bgSubtle, ink: Hue.mapInk, sub: Hue.gray, hairline: Hue.mapHairline)
        /// Warm surfaces (PlaceDetailView).
        static let warm = Palette(card: Hue.paper, ink: Hue.ink, sub: Hue.ink3, hairline: Hue.hairline)
    }

    let query: String
    var header: String? = nil
    var palette: Palette = .map
    /// Supply a curated (name, coordinate) to enable a confident-match photo. nil → no photo.
    var identity: (name: String, coordinate: CLLocationCoordinate2D)? = nil

    @State private var details: PlaceDetails?
    @State private var photo: (url: URL, attributions: [String])?
    @State private var showHours = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if let d = details {
                let hasRows = hasContent(d)
                if hasRows || photo != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        if let photo { photoView(photo) }
                        if hasRows {
                            if let header {
                                Text(header.uppercased()).font(.mono(11)).tracking(1.5).foregroundStyle(palette.sub)
                            }
                            card(d)
                        }
                    }
                }
            }
        }
        .task(id: query) {
            details = nil        // clear the previous spot's card/photo before re-resolving
            photo = nil
            await resolve(query)
        }
    }

    // MARK: Photo

    private func photoView(_ p: (url: URL, attributions: [String])) -> some View {
        ZStack(alignment: .bottomTrailing) {
            AsyncImage(url: p.url) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFill()
                } else {
                    Rectangle().fill(palette.card)
                }
            }
            .frame(height: 150).frame(maxWidth: .infinity).clipped()
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

            if !p.attributions.isEmpty {
                Text(p.attributions.joined(separator: ", "))
                    .font(.sans(9)).foregroundStyle(.white.opacity(0.95)).lineLimit(1)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.black.opacity(0.4), in: Capsule())
                    .padding(8)
            }
        }
    }

    // MARK: Hours / contact card

    private func card(_ d: PlaceDetails) -> some View {
        let rows = rows(d)
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element) { i, row in
                if i > 0 { Rectangle().fill(palette.hairline).frame(height: 1) }
                rowView(row, d)
            }
        }
        .background(palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(palette.hairline, lineWidth: 1))
    }

    @ViewBuilder
    private func rowView(_ row: InfoRow, _ d: PlaceDetails) -> some View {
        switch row {
        case .hours: hoursRow(d)
        case .web:   actionRow(icon: "globe", text: "Website") { if let w = d.website { openURL(w) } }
        case .call:  actionRow(icon: "phone.fill", text: d.phone ?? "") { call(d.phone) }
        }
    }

    private func hoursRow(_ d: PlaceDetails) -> some View {
        VStack(spacing: 0) {
            Button {
                if !d.hours.isEmpty { withAnimation(.easeInOut(duration: 0.2)) { showHours.toggle() } }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "clock").font(.system(size: 14, weight: .medium))
                        .foregroundStyle(palette.sub).frame(width: 18)
                    Text(statusText(d)).font(.sansMedium(14)).foregroundStyle(statusColor(d))
                    Spacer()
                    if !d.hours.isEmpty {
                        Image(systemName: showHours ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.sub)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(d.hours.isEmpty)

            if showHours && !d.hours.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(d.hours, id: \.self) { line in
                        Text(line).font(.sans(12)).foregroundStyle(palette.sub)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 14).padding(.bottom, 12)
            }
        }
    }

    private func actionRow(icon: String, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Hue.accent).frame(width: 18)
                Text(text).font(.sansMedium(14)).foregroundStyle(palette.ink).lineLimit(1)
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.sub)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Resolve + confidence

    private func resolve(_ query: String) async {
        guard let id = await GooglePlacesService.shared.search(query).first?.placeId,
              let d = await GooglePlacesService.shared.details(placeId: id) else {
            if !Task.isCancelled { details = nil; photo = nil }
            return
        }
        // .task(id:) cancels this when the spot changes — don't write stale data over the new one.
        guard !Task.isCancelled else { return }
        details = d
        if let identity, let ph = d.photo, confident(d, identity) {
            photo = (GooglePlacesService.shared.photoURL(name: ph.name, maxWidth: 800), ph.attributions)
        } else {
            photo = nil
        }
    }

    /// Rule A "exact match": the resolved place sits within 75 m of the curated
    /// coordinate and its name aligns — otherwise we don't trust the id enough to
    /// show its photo.
    private func confident(_ d: PlaceDetails, _ id: (name: String, coordinate: CLLocationCoordinate2D)) -> Bool {
        let a = CLLocation(latitude: d.coordinate.latitude, longitude: d.coordinate.longitude)
        let b = CLLocation(latitude: id.coordinate.latitude, longitude: id.coordinate.longitude)
        guard a.distance(from: b) <= 75 else { return false }
        return namesAlign(d.name, id.name)
    }

    private func namesAlign(_ a: String, _ b: String) -> Bool {
        let na = normalize(a), nb = normalize(b)
        guard !na.isEmpty, !nb.isEmpty else { return false }   // empty name must not "contain"-match everything
        if na.contains(nb) || nb.contains(na) { return true }
        let ta = Set(na.split(separator: " ").filter { $0.count >= 5 })
        let tb = Set(nb.split(separator: " ").filter { $0.count >= 5 })
        return !ta.isDisjoint(with: tb)
    }

    private func normalize(_ s: String) -> String {
        String(s.lowercased().map { ($0.isLetter || $0.isNumber || $0 == " ") ? $0 : " " })
    }

    // MARK: Rows / helpers

    private func rows(_ d: PlaceDetails) -> [InfoRow] {
        var r: [InfoRow] = []
        if d.openNow != nil || !d.hours.isEmpty { r.append(.hours) }
        if d.website != nil { r.append(.web) }
        if d.phone != nil { r.append(.call) }
        return r
    }

    private func hasContent(_ d: PlaceDetails) -> Bool {
        d.openNow != nil || !d.hours.isEmpty || d.website != nil || d.phone != nil
    }

    private func statusText(_ d: PlaceDetails) -> String {
        switch d.openNow {
        case true?:  return "Open now"
        case false?: return "Closed"
        default:     return "Hours"
        }
    }

    private func statusColor(_ d: PlaceDetails) -> Color {
        d.openNow == true ? Hue.accent : palette.ink
    }

    private func call(_ phone: String?) {
        guard let phone else { return }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        if let url = URL(string: "tel://\(digits)") { openURL(url) }
    }
}

private enum InfoRow: Hashable { case hours, web, call }
