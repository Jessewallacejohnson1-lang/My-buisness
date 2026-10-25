//
//  InterestChips.swift
//  Block Party — "What do you love doing?" as Meetup's chips (BP app onboarding 20, mock v7):
//  a search that knows everyday words, Added, "Popular in St. Joseph", then the 7 groups. A
//  picked chip glides up into Added and the rest close the gap. Onboarding's step 7 and Edit
//  Profile's interests both show it.
//

import SwiftUI

struct InterestChips: View {
    /// The picks in the order they were made, which is Added's order.
    @Binding var picked: [String]
    /// The interests with the most upcoming Events, most first; empty hides the row.
    let popular: [String]
    /// Room under the last group for the bar that floats over the list.
    var bottomInset: CGFloat = 160

    @State private var query = ""
    /// Popular as it was when the list opened, or when the counts land before the first tap:
    /// once a finger is on the chips, counts landing late never push them down.
    @State private var shownPopular: [String]?
    @State private var touched = false
    @FocusState private var searching: Bool
    /// The chip just picked, whose check pops as it lands in Added.
    @State private var landing: String?
    @Namespace private var glide
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Out-quint, the mock's glide: 0.44 s for the picked chip, the rest follow on the same curve.
    private static let glideCurve: Animation = .timingCurve(0.22, 1, 0.36, 1, duration: 0.44)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            search
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) { groups }
                    .padding(.top, 4)
                    .padding(.bottom, bottomInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .onAppear { if shownPopular == nil { shownPopular = popular } }
        .onChange(of: popular) { _, new in
            guard !touched, query.isEmpty else { return }
            withAnimation(.easeOut(duration: 0.25)) { shownPopular = new }
        }
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.glyph(15, weight: .semibold))
                .foregroundStyle(Hue.inkSecondary)
            TextField("Search interests", text: $query)
                .font(.sans(15))
                .foregroundStyle(Hue.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .focused($searching)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Hue.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Hue.hairline, lineWidth: 1.5))
        // The whole 44 pt box takes the tap, not only the line of text.
        .contentShape(Rectangle())
        .onTapGesture { searching = true }
        .padding(.top, 24)
    }

    @ViewBuilder private var groups: some View {
        let open = { (ids: [String]) in ids.filter { !picked.contains($0) } }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            if !picked.isEmpty { group("Added", picked) }
            let popular = open(shownPopular ?? [])
            if !popular.isEmpty { group("Popular in St. Joseph", popular) }
            ForEach(Interests.sections, id: \.title) { section in
                let left = open(section.items.map(\.id)).filter { !(shownPopular ?? []).contains($0) }
                if !left.isEmpty { group(section.title, left) }
            }
        } else {
            // What's found comes first, so it shows above the keyboard and the Next bar riding it.
            let found = open(Interests.search(q).map(\.id))
            if found.isEmpty {
                Text("No interest matches \u{201C}\(q)\u{201D}")
                    .font(.sans(15))
                    .foregroundStyle(Hue.inkSecondary)
                    .padding(.top, 24)
            } else {
                group(nil, found)
            }
            if !picked.isEmpty { group("Added", picked) }
        }
    }

    private func group(_ title: String?, _ ids: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.sansSemibold(15))
                    .foregroundStyle(Hue.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            FlowLayout(spacing: 8) {
                ForEach(ids, id: \.self) { id in
                    InterestChip(label: Interests.labels(for: [id]).first ?? id,
                                 on: picked.contains(id), pops: landing == id && !reduceMotion) {
                        toggle(id)
                    }
                    .matchedGeometryEffect(id: id, in: glide)
                }
            }
        }
        .padding(.top, 24)
    }

    private func toggle(_ id: String) {
        touched = true
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Self.glideCurve) {
            if let i = picked.firstIndex(of: id) {
                picked.remove(at: i)
                landing = nil
            } else {
                picked.append(id)
                landing = id
            }
        }
    }
}

/// One chip: words with a + (or, picked, a yellow check on ink) on Duolingo's raised edge.
/// Sinks 2 pt on press. Its touch area reaches 44 pt tall, into half of the 8 pt gaps around it.
private struct InterestChip: View {
    let label: String
    let on: Bool
    /// Just picked: the check pops to 106% as the chip lands in Added.
    let pops: Bool
    let action: () -> Void

    @State private var check: CGFloat = 1

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(on ? "\u{2713}" : "+")
                    .font(.sansSemibold(17))
                    .foregroundStyle(on ? Hue.brandDisc : Hue.inkSecondary)
                    .frame(width: 12)
                    .scaleEffect(check)
                Text(label)
                    .font(.sansMedium(15))
                    .foregroundStyle(on ? Color.white : Hue.ink)
                    .lineLimit(1)
            }
        }
        .buttonStyle(InterestChipStyle(on: on))
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
        .onAppear {
            guard pops else { return }
            check = 0.4
            withAnimation(.easeOut(duration: 0.1).delay(0.3)) { check = 1.06 } completion: {
                withAnimation(.easeOut(duration: 0.1)) { check = 1 }
            }
        }
    }
}

private struct InterestChipStyle: ButtonStyle {
    let on: Bool

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        return configuration.label
            .padding(.horizontal, 13)
            .padding(.top, 7 + 1.5)
            .padding(.bottom, 6 + 3.5)
            .background {
                // The edge is the whole capsule; the face sits on it 1.5 pt in, 3.5 pt at the bottom.
                ZStack {
                    Capsule().fill(on ? Hue.nextEdge : Hue.edge)
                    Capsule().fill(on ? Hue.ink : Hue.surface)
                        .padding(.horizontal, 1.5)
                        .padding(.top, 1.5)
                        .padding(.bottom, 3.5)
                }
            }
            .contentShape(Rectangle().inset(by: -3))
            .scaleEffect(down ? 0.97 : 1)
            .offset(y: down ? 2 : 0)
            .animation(down ? .easeOut(duration: 0.08) : .spring(response: 0.12, dampingFraction: 0.62), value: down)
            .onChange(of: down) { _, pressed in if pressed { Haptics.light() } }
    }
}
