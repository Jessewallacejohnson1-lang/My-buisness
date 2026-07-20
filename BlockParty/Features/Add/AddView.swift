//
//  AddView.swift
//  Block Party — post composer. This pass ships the kind chooser; the forms and the
//  Supabase writes land in the backend phase.
//

import SwiftUI

struct AddView: View {
    private struct Kind: Identifiable {
        let addKind: AddKind
        let symbol: String
        let title: String
        let subtitle: String
        var id: String { addKind.rawValue }
    }

    private let kinds = [
        Kind(addKind: .event, symbol: "calendar", title: "Event", subtitle: "An event with a date and time"),
        Kind(addKind: .club, symbol: "person.2", title: "Club", subtitle: "A group that meets again and again"),
        Kind(addKind: .trail, symbol: "figure.walk", title: "Trail", subtitle: "A walk, ride, or run worth sharing"),
    ]

    @State private var selected: AddKind?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Add to St. Joe")
                        .font(.display(30))
                        .foregroundStyle(Hue.ink)
                    Text("What would you like to share with the town?")
                        .font(.sans(15))
                        .foregroundStyle(Hue.inkSecondary)
                }
                .padding(.top, 8)

                VStack(spacing: 12) {
                    ForEach(kinds) { kind in
                        Button { selected = kind.addKind } label: { kindRow(kind) }
                            .buttonStyle(.plain)
                    }
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 18)
        }
        .background(Hue.paper)
        .sheet(item: $selected) { kind in
            AddFormView(kind: kind)
        }
    }

    private func kindRow(_ kind: Kind) -> some View {
        HStack(spacing: 14) {
            Image(systemName: kind.symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Hue.ink)
                .frame(width: 46, height: 46)
                .background(Hue.fill)
                .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title)
                    .font(.sansBold(16))
                    .foregroundStyle(Hue.ink)
                Text(kind.subtitle)
                    .font(.sans(13))
                    .foregroundStyle(Hue.inkSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Hue.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .blockPartyCard(padding: 14)
    }
}

#Preview { AddView() }
