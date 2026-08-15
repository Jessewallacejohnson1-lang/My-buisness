//
//  VenueAutocompleteField.swift
//  Block Party — a "Where" field with Google Places (New) type-ahead, biased to St. Joe.
//
//  Curated St. Joe spots are offered first (KnownVenues still match first); Google
//  suggestions follow. Picking one fills the bound text with the venue name — that
//  exact string keyword-matches a curated pin, so the map lights up.
//
//  No details() call is made here on purpose: nothing persists a coordinate yet, so
//  a billed lookup for data with no reader would violate the frugality rule. The
//  autocomplete session token still groups the keystrokes as one billed session and
//  is ready to hand to details() once a later phase has a place to store the result.
//

import SwiftUI

struct VenueAutocompleteField: View {
    struct Palette {
        let fieldBg: Color
        let ink: Color
        let label: Color
        let hairline: Color
        /// Warm composer surfaces (AddFormView).
        static let composer = Palette(fieldBg: Hue.surface, ink: Hue.ink, label: Hue.inkSecondary, hairline: Hue.hairline)
    }

    let label: String
    let placeholder: String
    @Binding var text: String
    var curated: [String] = []
    var palette: Palette = .composer

    @FocusState private var focused: Bool
    @State private var suggestions: [VenueSuggestion] = []
    @State private var sessionToken = ""
    @State private var debounce: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.sansMedium(12)).foregroundStyle(palette.label)

            TextField(placeholder, text: $text)
                .font(.sans(15)).foregroundStyle(palette.ink)
                .focused($focused)
                .autocorrectionDisabled()
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(palette.fieldBg)
                .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 1))

            if focused && !suggestions.isEmpty {
                suggestionList
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: focused) { _, isOn in
            guard isOn else { return }
            sessionToken = GooglePlacesService.shared.newSessionToken()
            let q = text
            Task { await refresh(q) }        // show curated immediately on focus
        }
        .onChange(of: text) { _, q in
            debounce?.cancel()
            debounce = Task {
                try? await Task.sleep(for: .milliseconds(250))
                if Task.isCancelled { return }
                await refresh(q)
            }
        }
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(suggestions) { s in
                Button { pick(s.name) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: s.isCurated ? "mappin.circle.fill" : "magnifyingglass")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(s.isCurated ? palette.ink : palette.label)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.name).font(.sans(14)).foregroundStyle(palette.ink).lineLimit(1)
                            if let sub = s.secondary, !sub.isEmpty {
                                Text(sub).font(.sans(11)).foregroundStyle(palette.label).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if s.id != suggestions.last?.id {
                    Divider().overlay(palette.hairline)
                }
            }
        }
        .background(Hue.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
            .stroke(palette.hairline, lineWidth: 1))
        .mapFloatShadow()
    }

    private func pick(_ name: String) {
        debounce?.cancel()
        text = name
        suggestions = []
        focused = false          // the dropdown is gated on `focused`, so this hides it
    }

    /// Curated matches first, then Google suggestions de-duplicated against the curated
    /// list AND each other (so two same-named predictions can't collide as one id).
    /// Bails if the field lost focus or the text moved on while Google was in flight.
    private func refresh(_ query: String) async {
        guard focused else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        let curatedMatches: [VenueSuggestion]
        if trimmed.isEmpty {
            curatedMatches = curated.prefix(6).map { VenueSuggestion(name: $0, secondary: nil, isCurated: true) }
        } else {
            curatedMatches = curated
                .filter { $0.localizedCaseInsensitiveContains(trimmed) }
                .prefix(4)
                .map { VenueSuggestion(name: $0, secondary: nil, isCurated: true) }
        }

        var googleMatches: [VenueSuggestion] = []
        if trimmed.count >= 2 {
            var seen = Set(curatedMatches.map { $0.name.lowercased() })
            for s in await GooglePlacesService.shared.autocomplete(trimmed, sessionToken: sessionToken) {
                let key = s.primaryText.lowercased()
                if seen.contains(key) { continue }
                seen.insert(key)
                googleMatches.append(VenueSuggestion(name: s.primaryText, secondary: s.secondaryText, isCurated: false))
                if googleMatches.count >= 5 { break }
            }
            // Drop a result that arrived after the field moved on.
            guard focused, trimmed == text.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        }

        suggestions = curatedMatches + googleMatches
    }
}

private struct VenueSuggestion: Identifiable {
    let name: String
    let secondary: String?
    let isCurated: Bool
    var id: String { (isCurated ? "c:" : "g:") + name }
}
