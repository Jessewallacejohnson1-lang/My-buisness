//
//  TownMenuView.swift
//  Block Party — the town menu drawer.
//
//  The content of the town-menu glass showcase that floats over the frosted app
//  from Home's top-right button (see GlassShowcaseOverlay.swift). Left-aligned —
//  header, a short list of destinations, and the wordmark pinned at the bottom.
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

            // Wordmark sits just below the menu — the panel wraps to its content,
            // so there's no trailing blank space; it grows down only as rows are added.
            Text("Block Party")
                .font(.logo(20))
                .foregroundStyle(Hue.ink3)
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
                    .foregroundStyle(Hue.ink3)
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

    /// DEBUG-only: `-menu-autoclose` fires the collapse ~1.6s after open so the
    /// close motion can be recorded headlessly. Routes through the real close.
    private func debugAutoClose() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-menu-autoclose") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { onClose() }
        #endif
    }
}
