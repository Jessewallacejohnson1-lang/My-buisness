//
//  ExploreSearchSuggestions.swift
//  Hygge — the Google-style recommendations dropdown under the Explore search
//  field. A floating paper card of grouped rows: real Places (open their detail),
//  Happenings (fill the search), and "Search …" concepts (filter the list). When
//  the field is focused but empty it shows Popular starter searches.
//
//  Look is cloned from VenueAutocompleteField's suggestion list (paper + hairline
//  + mapFloatShadow, the icon+title+subtitle row). Matching/ranking is TownSearch's.
//
//  Motion, on purpose: NONE on the card itself. This surface is keyboard-driven
//  and re-rendered on every keystroke — animating it would read as lag (Emil
//  Kowalski's framework: don't animate frequently-seen, keyboard-initiated UI;
//  Raycast opens its palette with no animation for exactly this reason). Rows are
//  a plain, instant swap; the only motion is each row's press "pop" (PressableStyle),
//  which is a direct response to a tap, not an entrance.
//

import SwiftUI

struct ExploreSearchSuggestions: View {
    let suggestions: [Suggestion]
    /// True when the field is focused but empty — switches the concept header to
    /// "Popular" and drops the `Search "…"` framing on concept rows.
    let isEmptyQuery: Bool
    var onPick: (Suggestion) -> Void

    private struct Section: Identifiable {
        let header: String
        let items: [Suggestion]
        var id: String { header }
    }

    private var sections: [Section] {
        let places = suggestions.filter { $0.group == .place }
        let happenings = suggestions.filter { $0.group == .happening }
        let concepts = suggestions.filter { $0.group == .concept }
        var out: [Section] = []
        if !places.isEmpty { out.append(Section(header: "Places", items: places)) }
        if !happenings.isEmpty { out.append(Section(header: "Happenings", items: happenings)) }
        if !concepts.isEmpty {
            out.append(Section(header: isEmptyQuery ? "Popular" : "Search for", items: concepts))
        }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            if suggestions.isEmpty {
                noMatchRow
            } else {
                ForEach(Array(sections.enumerated()), id: \.element.id) { si, section in
                    if si > 0 { sectionGap }
                    sectionHeader(section.header)
                    ForEach(Array(section.items.enumerated()), id: \.element.id) { ri, s in
                        row(s)
                        if ri < section.items.count - 1 {
                            Divider().overlay(Hue.hairline).padding(.leading, 48)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .background(Hue.paper)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Hue.hairline, lineWidth: 1))
        .mapFloatShadow()
        .accessibilityElement(children: .contain)
    }

    // MARK: - Rows

    private func row(_ s: Suggestion) -> some View {
        Button { onPick(s) } label: {
            HStack(spacing: 12) {
                Image(systemName: s.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(iconColor(s))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle(s))
                        .font(.sans(15.5))
                        .foregroundStyle(Hue.ink)
                        .lineLimit(1)
                    if let sub = s.subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.sans(12))
                            .foregroundStyle(Hue.ink3)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                // A chevron says "this opens something"; the up-left arrow is the
                // familiar "put this into the search box" affordance.
                Image(systemName: s.opensDetail ? "chevron.right" : "arrow.up.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Hue.grayLight)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(accessibilityLabel(s))
    }

    private var noMatchRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Hue.grayLight)
                .frame(width: 22)
            Text("No matches — try a place, event, or interest")
                .font(.sans(14))
                .foregroundStyle(Hue.gray)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    // MARK: - Section chrome

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.sansMedium(11))
            .tracking(0.6)
            .foregroundStyle(Hue.grayLight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    /// A hairline that spans the card between two groups.
    private var sectionGap: some View {
        Divider().overlay(Hue.hairline).padding(.top, 4)
    }

    // MARK: - Presentation helpers

    /// Concept rows read as `Search "Coffee shops"` while typing; in the Popular
    /// empty state they're plain starter labels.
    private func displayTitle(_ s: Suggestion) -> String {
        if s.group == .concept && !isEmptyQuery { return "Search \u{201C}\(s.title)\u{201D}" }
        return s.title
    }

    private func iconColor(_ s: Suggestion) -> Color {
        switch s.group {
        case .place:     return Hue.accent      // coral — the tappable "go there"
        case .happening: return Hue.ink2
        case .concept:   return Hue.gray
        }
    }

    private func accessibilityLabel(_ s: Suggestion) -> String {
        switch s.group {
        case .place:     return "\(s.title). Opens details."
        case .happening: return "\(s.title). Search."
        case .concept:   return isEmptyQuery ? s.title : "Search \(s.title)"
        }
    }
}
