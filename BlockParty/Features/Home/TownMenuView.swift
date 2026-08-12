//
//  TownMenuView.swift
//  Block Party — the town menu drawer.
//
//  The content of the town-menu glass showcase that floats over the frosted app
//  from Home's top-right button (see GlassShowcaseOverlay.swift). Left-aligned —
//  header, a short list of destinations, the appearance switch, and the wordmark
//  pinned at the bottom.
//
//  WHY THE APPEARANCE SWITCH LIVES HERE. There is no Settings screen, and one
//  control does not earn one — nor a seventh destination row that opens one. It is
//  the only preference the app has, so it sits under the destinations behind a
//  hairline: a thing you set, below the things you go to.
//

import SwiftUI

/// What a menu row does. The host (MainTabsView) closes the drawer then routes.
enum TownMenuAction { case calendar, activities, map, compose, invite, profile }

struct TownMenuView: View {
    /// Collapse the drawer (wired by the overlay).
    var onClose: () -> Void
    /// A row was tapped — the host closes the drawer and performs the action.
    var onSelect: (TownMenuAction) -> Void

    @StateObject private var model = ProfileModel()
    /// The same object `RootView` applies at the root, so a tap here repaints the
    /// whole app on the next frame — no relaunch, no round trip.
    @StateObject private var appearance = AppearanceStore.shared

    private var name: String {
        let n = model.displayName.isEmpty ? (Interests.displayName ?? "") : model.displayName
        return n.isEmpty ? "Neighbor" : n
    }

    private struct Row: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let action: TownMenuAction
    }

    private let rows: [Row] = [
        Row(icon: "calendar",           title: "Calendar",        action: .calendar),
        Row(icon: "square.grid.2x2",    title: "Activities",      action: .activities),
        Row(icon: "map",                title: "Town map",        action: .map),
        Row(icon: "plus.circle",        title: "Add an event",    action: .compose),
        Row(icon: "person.badge.plus",  title: "Invite a neighbor", action: .invite),
        Row(icon: "person.crop.circle", title: "Your profile",    action: .profile),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.top, 20)
                .padding(.bottom, 22)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(rows) { row in
                    menuRow(row)
                }
            }

            appearanceSwitch
                .padding(.top, 16)

            // Brand lockup sits just below the menu — the panel wraps to its content,
            // so there's no trailing blank space; it grows down only as rows are added.
            HStack(spacing: 9) {
                BlockPartyMark(side: 30)
                Text("Block Party")
                    .font(.logo(20))
                    .foregroundStyle(Hue.inkSecondary)
            }
                .padding(.top, 20)
                .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .task { await model.load() }
        .onAppear(perform: debugAutoClose)
    }

    // MARK: Header — avatar + name + town

    private var header: some View {
        HStack(spacing: 12) {
            ProfileAvatar(url: model.avatarUrl, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.displaySemi(19))
                    .foregroundStyle(Hue.ink)
                    .lineLimit(1)
                Text("Saint Joseph, MN")
                    .font(.sans(13))
                    .foregroundStyle(Hue.inkSecondary)
            }
        }
    }

    // MARK: Rows

    private func menuRow(_ row: Row) -> some View {
        Button {
            Haptics.light()
            onSelect(row.action)
        } label: {
            HStack(spacing: 15) {
                Image(systemName: row.icon)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Hue.ink)
                    .frame(width: 26, alignment: .leading)
                Text(row.title)
                    .font(.sansMedium(17))
                    .foregroundStyle(Hue.ink)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Appearance — System / Light / Dark

    /// One labelled control, three options, inside a ~56%-wide panel.
    ///
    /// The hairline is the whole hierarchy statement: everything above it takes you
    /// somewhere, this sets something. No second heading, no card, no chevron.
    private var appearanceSwitch: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle()
                .fill(Hue.hairline)
                .frame(height: 1)
                .accessibilityHidden(true)

            Text("Appearance")
                .font(.sans(13))
                .foregroundStyle(Hue.inkSecondary)

            HStack(spacing: Self.segmentGap) {
                ForEach(AppearanceChoice.allCases) { option in
                    appearanceOption(option)
                }
            }
            // One control with three options: VoiceOver enters a group that names
            // itself "Appearance", then reads each option and which one is on.
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Appearance")
        }
    }

    /// THE WIDTH BUDGET, WRITTEN DOWN, because it is the whole reason these numbers
    /// are what they are. The panel is 56% of the screen and pays 22pt of padding
    /// each side, so three equal segments share ~181pt on an iPhone 17 and ~166pt on
    /// the narrowest supported phone. "System" measures 46.1pt at 13pt medium, so
    /// each segment needs 46.1 + 2×`segmentInset` ≤ (width − 2×`segmentGap`) / 3:
    /// 54.1 ≤ 57 on a 17, and 54.1 > 52 on the narrow one — which is what
    /// `minimumScaleFactor` absorbs, shrinking the word rather than truncating the
    /// default state to "Syst…".
    ///
    /// (`ViewThatFits` was the first attempt and cannot do this job: its candidates
    /// were `maxWidth: .infinity` segments, whose ideal width is whatever is
    /// proposed, so the horizontal row always "fit" and the label truncated anyway.)
    private static let segmentGap: CGFloat = 6
    private static let segmentInset: CGFloat = 4

    private func appearanceOption(_ option: AppearanceChoice) -> some View {
        let isSelected = appearance.choice == option

        return Button {
            guard !isSelected else { return }
            Haptics.light()
            appearance.choice = option
        } label: {
            Text(option.label)
                .font(.sansMedium(13))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                // The selected fill is the accent's own job description — a selected
                // state. `Hue.paper` on it measures 6.8:1 in light and 5.1:1 in dark,
                // because the token moves with the appearance and the accent does too.
                .foregroundStyle(isSelected ? Hue.paper : Hue.ink)
                .padding(.horizontal, Self.segmentInset)
                // 44pt: the tap target guideline wins over the panel's compactness.
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    // Radius.button is 12 and is a ROUNDED SQUARE. At 44pt tall a
                    // pill would be 22 — it must not become one.
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .fill(isSelected ? Hue.accent : Hue.fill)
                )
                .overlay {
                    // An unselected segment sits on ultra-thin material over a page
                    // its own fill nearly matches, so without a border it reads as
                    // nothing. `Hue.edge` is the token for a border that has to be
                    // SEEN (WCAG 1.4.11's 3:1 on a control boundary).
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .stroke(isSelected ? .clear : Hue.edge, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// DEBUG-only: `-menu-autoclose` fires the collapse ~1.6s after open so the
    /// close motion can be recorded headlessly. Routes through the real close.
    private func debugAutoClose() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-menu-autoclose") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { onClose() }
        #endif
    }
}
