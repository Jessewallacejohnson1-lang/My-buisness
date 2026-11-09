//
//  InterestRows.swift
//  Block Party — "What do you love doing?" as X's Add Topics (BP app onboarding 28), set as Luma's white
//  card of rows on the grey canvas (onboarding 36, mock v8): each row a round icon, its words and at the
//  end a check circle that picks at once or a chevron that opens the row in place. Schools opens to the
//  kinds of school, and each kind to its schools, Follow 3's logos in rows of 3. Onboarding's step and
//  Edit Profile's interests both show it.
//
//  What's inside a row stays mounted and moves on one bool, so a tap halfway turns it around.
//

import SwiftUI

/// Mock v8's rows at 402 pt. Outside the view: a generic type can't store statics.
private enum Metric {
    static let row: CGFloat = 56
    /// The round icon at a row's start, and the space before the words.
    static let icon: CGFloat = 36
    static let iconGap: CGFloat = 12
    /// What sits before the words: the card's 12 pt, the icon and its gap. Separators and what a row
    /// opens to start here.
    static let indent: CGFloat = 12 + icon + iconGap
    static let ring: CGFloat = 24
    static let chip: CGFloat = 34
    static let corner: CGFloat = 16
    /// Logos in rows of 3 under a kind of school, 10 pt apart (mock v8 `.grid`).
    static let tileGap: CGFloat = 10
}

struct InterestRows<Heading: View>: View {
    /// The interests saved, which a chip can add two of (`InterestPick`).
    @Binding var picked: [String]
    /// What Schools can show: nil while reading, empty when the read failed.
    let schools: [FollowSuggestion]?
    let isFollowing: (FollowTarget) -> Bool
    let toggleFollow: (FollowTarget) -> Void
    /// Schools opened: onboarding's Follow 3 then leads with schools, and a failed read tries again.
    var schoolsOpened: () -> Void = {}
    var gutter: CGFloat = FollowGridMetric.gutter
    /// Where the question starts in the scroll.
    var topInset: CGFloat = 0
    /// Room under the last row for the bar that floats over the list.
    var bottomInset: CGFloat = 200
    @ViewBuilder let heading: Heading

    @State private var open: Set<String> = []
    /// The kind of school showing: one at a time, and another tap swaps it in place.
    @State private var openType: String?
    /// Schools opened once: its crests load then, so a kind's are there when it opens.
    @State private var schoolsMounted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var opening: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 1)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                heading
                VStack(spacing: 0) {
                    ForEach(Array(Interests.rows.enumerated()), id: \.element.id) { index, row in
                        self.row(row)
                            // Luma's hairline between rows, from where the words start.
                            .overlay(alignment: .top) {
                                if index > 0 {
                                    Hue.hairline.frame(height: 1).padding(.leading, Metric.indent)
                                }
                            }
                    }
                }
                .background(Hue.surface)
                .clipShape(RoundedRectangle(cornerRadius: Metric.corner, style: .continuous))
                .padding(.top, 24)
            }
            .padding(.horizontal, gutter)
            .padding(.top, topInset)
            .padding(.bottom, bottomInset)
        }
    }

    /// A row and what it opens to, one block, so the hairline sits over the row alone.
    @ViewBuilder private func row(_ row: InterestRow) -> some View {
        switch row.kind {
        case .pick(let pick):
            pickRow(row, pick)
        case .chips(let picks):
            let shown = open.contains(row.id)
            VStack(spacing: 0) {
                opener(row, count: picks.filter { $0.isOn(in: picked) }.count)
                InterestOpening(open: shown, animation: opening) {
                    FlowLayout(spacing: 8) {
                        ForEach(Array(picks.enumerated()), id: \.element.id) { index, pick in
                            InterestChip(label: pick.label, on: pick.isOn(in: picked)) { toggle(pick) }
                                .modifier(InterestRises(shown: shown, index: index))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, Metric.indent)
                    .padding(.trailing, 16)
                    .padding(.top, 2)
                    .padding(.bottom, 16)
                }
            }
        case .schools:
            let shown = open.contains(row.id)
            VStack(spacing: 0) {
                opener(row, count: FollowSuggestions.schoolTargets(in: schools ?? []).filter(isFollowing).count)
                InterestOpening(open: shown, animation: opening) {
                    VStack(alignment: .leading, spacing: 0) {
                        FlowLayout(spacing: 8) {
                            ForEach(Array(types.enumerated()), id: \.element.id) { index, type in
                                typeChip(type)
                                    .modifier(InterestRises(shown: shown, index: index))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, Metric.indent)
                        .padding(.trailing, 16)
                        ForEach(types) { type in
                            InterestOpening(open: shown && openType == type.id, animation: opening) {
                                if schoolsMounted {
                                    tiles(type, shown: shown && openType == type.id)
                                        .padding(.horizontal, 16)
                                        .padding(.top, 14)
                                }
                            }
                        }
                    }
                    .padding(.top, 2)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    /// The round icon, the words and what's at the end. The whole width takes the touch, and darkens.
    private func face<End: View>(_ row: InterestRow, @ViewBuilder end: () -> End) -> some View {
        HStack(spacing: Metric.iconGap) {
            Text(row.icon)
                .font(.glyph(19))
                .frame(width: Metric.icon, height: Metric.icon)
                .background(Hue.fill, in: Circle())
                .accessibilityHidden(true)
            Text(row.label)
                .font(.apple(16, weight: .semibold))
                .foregroundStyle(Hue.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Metric.iconGap) { end() }
        }
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .padding(.vertical, 4)
        .frame(minHeight: Metric.row)
        .contentShape(Rectangle())
    }

    private func pickRow(_ row: InterestRow, _ pick: InterestPick) -> some View {
        let on = pick.isOn(in: picked)
        return Button { Haptics.light(); toggle(pick) } label: {
            face(row) { InterestCheckCircle(on: on) }
        }
        .buttonStyle(.press(.row))
        .accessibilityLabel(row.label)
        .accessibilityValue(on ? "Picked" : "Not picked")
        .accessibilityIdentifier("interest-chip")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func opener(_ row: InterestRow, count: Int) -> some View {
        let shown = open.contains(row.id)
        return Button { toggleOpen(row) } label: {
            face(row) {
                if count > 0 {
                    Text("\(count)")
                        .font(.apple(13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Hue.inkSecondary)
                        .contentTransition(.numericText(value: Double(count)))
                        .transition(.opacity)
                }
                Image(systemName: "chevron.right")
                    .font(.glyph(14, weight: .semibold))
                    .foregroundStyle(Hue.onboardingChevron)
                    .rotationEffect(.degrees(shown ? 90 : 0))
                    .frame(width: 16)
            }
            .animation(.snappy, value: count)
        }
        .buttonStyle(.press(.row))
        .accessibilityLabel(row.label)
        .accessibilityValue(shown ? "Open" : count > 0 ? "Closed, \(count) picked" : "Closed")
    }

    /// Before the read, every kind; after it, only those with a school to show.
    private var types: [Town.SchoolType] {
        guard let schools, !schools.isEmpty else { return Town.schoolTypes }
        return Town.schoolTypes.filter { !FollowSuggestions.tiles($0, in: schools).isEmpty }
    }

    /// A kind of school: a grey chip, ink while its schools show (mock v8).
    private func typeChip(_ type: Town.SchoolType) -> some View {
        let shown = openType == type.id
        let count = FollowSuggestions.tiles(type, in: schools ?? []).filter { isFollowing($0.target) }.count
        return Button {
            // Tries a failed read again, which the line under it says to.
            schoolsOpened()
            withAnimation(opening) { openType = shown ? nil : type.id }
        } label: {
            InterestChipFace(label: type.label, on: shown, check: false)
        }
        .buttonStyle(.press(.squish, haptic: true))
        .accessibilityLabel(type.label)
        .accessibilityValue(shown ? "Open" : count > 0 ? "Closed, \(count) followed" : "Closed")
    }

    /// One kind's schools, as Follow 3's logos, in rows of 3 across the card.
    @ViewBuilder private func tiles(_ type: Town.SchoolType, shown: Bool) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: Metric.tileGap, alignment: .top), count: 3)
        if let schools {
            if schools.isEmpty {
                // The Town feed's words for a read that failed.
                Text("Check your connection and try again.")
                    .font(.apple(15))
                    .foregroundStyle(Hue.inkSecondary)
                    .padding(.leading, Metric.indent - 16)
            } else {
                LazyVGrid(columns: columns, alignment: .center, spacing: FollowGridMetric.rowGap) {
                    let list = FollowSuggestions.tiles(type, in: schools)
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, school in
                        FollowTile(suggestion: school, on: isFollowing(school.target), ring: Hue.surface) {
                            toggleFollow(school.target)
                        }
                        .modifier(InterestRises(shown: shown, index: index))
                    }
                }
            }
        } else {
            LazyVGrid(columns: columns, alignment: .center, spacing: FollowGridMetric.rowGap) {
                ForEach(0..<3, id: \.self) { _ in FollowTileSkeleton() }
            }
        }
    }

    private func toggle(_ pick: InterestPick) {
        picked = Interests.toggled(pick, in: picked)
    }

    private func toggleOpen(_ row: InterestRow) {
        Haptics.selection()
        let opens = !open.contains(row.id)
        withAnimation(opening) {
            if opens { open.insert(row.id) } else { open.remove(row.id) }
        }
        if opens, case .schools = row.kind {
            schoolsMounted = true
            schoolsOpened()
        }
    }
}

/// What a row opens to. Always mounted: its height moves on `open`, so closing it halfway turns it around.
private struct InterestOpening<Content: View>: View {
    let open: Bool
    let animation: Animation
    @ViewBuilder let content: Content

    @State private var height: CGFloat = 0

    var body: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { new in
                withAnimation(animation) { height = new }
            }
            .frame(height: open ? height : 0, alignment: .top)
            .clipped()
            .allowsHitTesting(open)
            .accessibilityHidden(!open)
    }
}

/// What's inside rises on Follow 3's spring, 44 ms apart, and goes quickly. Reduce Motion: only fades.
private struct InterestRises: ViewModifier {
    let shown: Bool
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let moves = !shown && !reduceMotion
        content
            .scaleEffect(moves ? 0.92 : 1, anchor: .topLeading)
            .offset(y: moves ? -8 : 0)
            .opacity(shown ? 1 : 0)
            .animation(animation, value: shown)
    }

    private var animation: Animation {
        guard shown else { return .easeOut(duration: 0.12) }
        if reduceMotion { return .easeOut(duration: 0.2) }
        return .spring(response: 0.42, dampingFraction: 0.72).delay(Double(index) * 0.044)
    }
}

/// Luma's check circle at the end of a row that picks at once: an empty grey ring, filled ink with a
/// white check once picked, popping .6 to 112% and back over 0.26 s as it fills (mock v8 `.ring`).
private struct InterestCheckCircle: View {
    let on: Bool

    @State private var pop: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().strokeBorder(on ? Hue.ink : Hue.onboardingRing, lineWidth: 1.5)
            Circle().fill(Hue.ink).opacity(on ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.glyph(12, weight: .bold))
                .foregroundStyle(Color.white)
                .opacity(on ? 1 : 0)
        }
        .frame(width: Metric.ring, height: Metric.ring)
        .scaleEffect(pop)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: on)
        .onChange(of: on) { _, now in
            guard now, !reduceMotion else { return }
            pop = 0.6
            withAnimation(.easeOut(duration: 0.156)) { pop = 1.12 } completion: {
                withAnimation(.easeOut(duration: 0.104)) { pop = 1 }
            }
        }
    }
}

/// One chip inside an open row: grey, ink with a white check before the word once picked (mock v8
/// `.chip`). Sinks under the finger; the check pops in. Its touch area reaches 44 pt tall.
private struct InterestChip: View {
    let label: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            InterestChipFace(label: label, on: on, check: true)
        }
        .buttonStyle(.press(.squish, haptic: true))
        .accessibilityLabel(label)
        .accessibilityValue(on ? "Picked" : "Not picked")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A chip's face: 34 pt, grey or ink, the words 14 pt medium.
private struct InterestChipFace: View {
    let label: String
    let on: Bool
    /// A check before the word once on: a pick has one, an open kind of school doesn't.
    let check: Bool

    @State private var pop: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            if check && on {
                Text("\u{2713}")
                    .font(.apple(13, weight: .bold))
                    .scaleEffect(pop)
            }
            Text(label)
                .font(.apple(14, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(on ? Color.white : Hue.ink)
        .padding(.horizontal, 13)
        .frame(minHeight: Metric.chip)
        .background(on ? Hue.ink : Hue.fill, in: Capsule())
        .contentShape(Rectangle().inset(by: -5))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: on)
        .onChange(of: on) { _, now in
            guard now, check, !reduceMotion else { return }
            pop = 0.4
            withAnimation(.easeOut(duration: 0.1)) { pop = 1.12 } completion: {
                withAnimation(.easeOut(duration: 0.1)) { pop = 1 }
            }
        }
    }
}
