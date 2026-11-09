//
//  InterestRows.swift
//  Block Party — "What do you love doing?" as X's Add Topics (BP app onboarding 28): 9 rows, each an
//  icon, its words and at the end a + that picks at once or a chevron that opens the row in place.
//  Schools opens to the kinds of school, and each kind to its schools' Follow 3 tiles. Onboarding's
//  step and Edit Profile's interests both show it.
//
//  What's inside a row stays mounted and moves on one bool, so a tap halfway turns it around.
//

import SwiftUI

/// X's rows, measured off its Add Topics at 393 pt; the disc is the mock's. Outside the view: a generic
/// type can't store statics.
private enum Metric {
    static let row: CGFloat = 56
    static let icon: CGFloat = 24
    static let iconGap: CGFloat = 12
    static let disc: CGFloat = 26
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
                    .padding(.horizontal, gutter)
                VStack(spacing: 0) {
                    ForEach(Interests.rows) { row($0) }
                }
                .padding(.top, 12)
            }
            .padding(.top, topInset)
            .padding(.bottom, bottomInset)
        }
    }

    @ViewBuilder private func row(_ row: InterestRow) -> some View {
        switch row.kind {
        case .pick(let pick):
            pickRow(row, pick)
        case .chips(let picks):
            let shown = open.contains(row.id)
            opener(row, count: picks.filter { $0.isOn(in: picked) }.count)
            InterestOpening(open: shown, animation: opening) {
                FlowLayout(spacing: 8) {
                    ForEach(Array(picks.enumerated()), id: \.element.id) { index, pick in
                        InterestChip(label: pick.label, on: pick.isOn(in: picked)) { toggle(pick) }
                            .modifier(InterestRises(shown: shown, index: index))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, gutter)
                .padding(.top, 2)
                .padding(.bottom, 14)
            }
        case .schools:
            let shown = open.contains(row.id)
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
                    .padding(.horizontal, gutter)
                    ForEach(types) { type in
                        InterestOpening(open: shown && openType == type.id, animation: opening) {
                            if schoolsMounted {
                                tiles(type, shown: shown && openType == type.id)
                                    .padding(.top, 14)
                            }
                        }
                    }
                }
                .padding(.top, 2)
                .padding(.bottom, 14)
            }
        }
    }

    /// The icon, the words and what's at the end. The whole width takes the touch, and darkens.
    private func face<End: View>(_ row: InterestRow, @ViewBuilder end: () -> End) -> some View {
        HStack(spacing: Metric.iconGap) {
            Text(row.icon)
                .font(.glyph(21))
                .frame(width: Metric.icon, height: Metric.icon)
                .accessibilityHidden(true)
            Text(row.label)
                .font(.apple(16, weight: .semibold))
                .foregroundStyle(Hue.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Metric.iconGap) { end() }
        }
        .padding(.horizontal, gutter)
        .frame(minHeight: Metric.row)
        .contentShape(Rectangle())
    }

    private func pickRow(_ row: InterestRow, _ pick: InterestPick) -> some View {
        let on = pick.isOn(in: picked)
        return Button { Haptics.light(); toggle(pick) } label: {
            face(row) { InterestPickDisc(on: on, side: Metric.disc) }
        }
        .buttonStyle(.press(.row))
        .accessibilityLabel(row.label)
        .accessibilityIdentifier("interest-chip")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func opener(_ row: InterestRow, count: Int) -> some View {
        let shown = open.contains(row.id)
        return Button { toggleOpen(row) } label: {
            face(row) {
                if count > 0 && !shown {
                    Text("\(count)")
                        .font(.apple(13, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: Metric.disc, height: Metric.disc)
                        .background(Hue.ink, in: Circle())
                        .transition(.opacity)
                }
                Image(systemName: "chevron.right")
                    .font(.glyph(16, weight: .semibold))
                    .foregroundStyle(Hue.ink)
                    .rotationEffect(.degrees(shown ? 90 : 0))
                    .frame(width: Metric.icon / 1.5)
            }
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

    private func typeChip(_ type: Town.SchoolType) -> some View {
        let shown = openType == type.id
        let count = FollowSuggestions.tiles(type, in: schools ?? []).filter { isFollowing($0.target) }.count
        let full = count > 0 && !shown
        return Button {
            // Tries a failed read again, which the line under it says to.
            schoolsOpened()
            withAnimation(opening) { openType = shown ? nil : type.id }
        } label: {
            HStack(spacing: 6) {
                Text(type.label)
                    .font(.apple(15, weight: .medium))
                    .foregroundStyle(full ? Color.white : Hue.ink)
                    .lineLimit(1)
                    // So its touch area reaches 44 pt, as an interest chip's does.
                    .frame(minHeight: 21)
                if full {
                    Text("\(count)")
                        .font(.apple(15, weight: .bold))
                        .foregroundStyle(Color.white)
                }
                Image(systemName: "chevron.down")
                    .font(.glyph(12, weight: .semibold))
                    .foregroundStyle(full ? Color.white : shown ? Hue.ink : Hue.inkSecondary)
                    .rotationEffect(.degrees(shown ? 180 : 0))
            }
        }
        .buttonStyle(InterestChipStyle(on: full, opened: shown))
        .accessibilityLabel(type.label)
        .accessibilityValue(shown ? "Open" : count > 0 ? "Closed, \(count) followed" : "Closed")
    }

    /// One kind's schools, as Follow 3's tiles, in a row that scrolls off both edges of the screen.
    @ViewBuilder private func tiles(_ type: Town.SchoolType, shown: Bool) -> some View {
        if let schools {
            if schools.isEmpty {
                // The Town feed's words for a read that failed.
                Text("Check your connection and try again.")
                    .font(.apple(15))
                    .foregroundStyle(Hue.inkSecondary)
                    .padding(.horizontal, gutter)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: FollowGridMetric.columnGap) {
                        let list = FollowSuggestions.tiles(type, in: schools)
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, school in
                            FollowTile(suggestion: school, on: isFollowing(school.target), width: FollowMetric.listWidth) {
                                toggleFollow(school.target)
                            }
                            .modifier(InterestRises(shown: shown, index: index))
                        }
                    }
                    .padding(.horizontal, gutter)
                }
            }
        } else {
            HStack(alignment: .top, spacing: FollowGridMetric.columnGap) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(spacing: 8) {
                        SkeletonBlock(cornerRadius: FollowGridMetric.art / 2)
                            .frame(width: FollowGridMetric.art, height: FollowGridMetric.art)
                        SkeletonBlock(cornerRadius: 6)
                            .frame(width: FollowMetric.listWidth * 0.7, height: 12)
                            .frame(height: FollowGridMetric.name, alignment: .top)
                        SkeletonBlock(cornerRadius: FollowMetric.rowHeight / 2)
                            .frame(width: FollowMetric.listWidth, height: FollowMetric.rowHeight)
                    }
                    .frame(width: FollowMetric.listWidth)
                    .shimmering()
                    .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, gutter)
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

/// The disc at the end of a row that picks at once: + on grey, or a white check on ink that pops
/// to 106% as it turns.
private struct InterestPickDisc: View {
    let on: Bool
    let side: CGFloat

    @State private var pop: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: on ? "checkmark" : "plus")
            .font(.glyph(13, weight: .bold))
            .foregroundStyle(on ? Color.white : Hue.ink)
            .frame(width: side, height: side)
            .background(on ? Hue.ink : Hue.fill, in: Circle())
            .scaleEffect(pop)
            .onChange(of: on) { _, now in
                guard now, !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.1)) { pop = 1.06 } completion: {
                    withAnimation(.easeOut(duration: 0.1)) { pop = 1 }
                }
            }
    }
}

/// One chip: words with a + (or, picked, a white check on ink) on Duolingo's raised edge.
/// Sinks 2 pt on press. Its touch area reaches 44 pt tall, into half of the 8 pt gaps around it.
private struct InterestChip: View {
    let label: String
    let on: Bool
    let action: () -> Void

    @State private var check: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(on ? "\u{2713}" : "+")
                    .font(.apple(17, weight: .semibold))
                    .foregroundStyle(on ? Color.white : Hue.inkSecondary)
                    .frame(width: 12)
                    .scaleEffect(check)
                Text(label)
                    .font(.apple(15, weight: .medium))
                    .foregroundStyle(on ? Color.white : Hue.ink)
                    .lineLimit(1)
            }
        }
        .buttonStyle(InterestChipStyle(on: on))
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
        .onChange(of: on) { _, now in
            guard now, !reduceMotion else { return }
            check = 0.4
            withAnimation(.easeOut(duration: 0.1)) { check = 1.06 } completion: {
                withAnimation(.easeOut(duration: 0.1)) { check = 1 }
            }
        }
    }
}

/// The chips' raised edge, ink once on; the Birthday step's gender pills wear it too (onboarding 31).
struct InterestChipStyle: ButtonStyle {
    let on: Bool
    /// A kind of school whose schools are showing: the app's light fill, not white.
    var opened = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    Capsule().fill(on ? Hue.ink : opened ? Hue.fill : Hue.surface)
                        .padding(.horizontal, 1.5)
                        .padding(.top, 1.5)
                        .padding(.bottom, 3.5)
                }
            }
            .contentShape(Rectangle().inset(by: -3))
            .scaleEffect(down && !reduceMotion ? 0.97 : 1)
            .offset(y: down && !reduceMotion ? 2 : 0)
            .animation(Press.push(down: down), value: down)
            .onChange(of: down) { _, pressed in if pressed { Haptics.light() } }
    }
}
