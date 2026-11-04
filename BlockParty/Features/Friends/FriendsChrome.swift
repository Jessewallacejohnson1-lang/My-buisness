//
//  FriendsChrome.swift
//  Block Party — what the Friends pages share: their sizes, their top bar, Search's field
//  without Cancel, and the routes the shell's stack pushes for them.
//

import SwiftUI

/// Sizes in points shared by the Friends pages; each page adds its own in an extension.
nonisolated enum FriendsMetric {
    static let side: CGFloat = 16
    /// The large title's line: 34pt bold with 24pt caps.
    static let titleLine: CGFloat = 41
    static let titleToField: CGFloat = 11
    /// Facebook's friends-list row, 76pt apart.
    static let row: CGFloat = 76
    static let avatarGap: CGFloat = 12
    static let lineGap: CGFloat = 2
    static let ring: CGFloat = 0.5
    static let hairline: CGFloat = 0.5
}

/// What the shell's stack pushes for friends.
enum FriendsRoute: Hashable {
    /// Your phone's contacts on Block Party, and the rest to invite (friends 06).
    case contacts
    /// See all on the Friends tab (five-tabs 02): every friend, or every Group with its Join.
    case allFriends, groups
}

/// A pushed Friends page's own top: Search's back chevron, and the small title once the large
/// one has gone under it, and whatever the page puts at the top right (a person's •••).
/// Drawn, not Apple's bar, which drops a page pushed from a stack that hides it (Saved,
/// 2026-10-13). The Friends tab is a tab's root, so it has no chevron (`back: false`).
struct FriendsTitleBar<Trailing: View>: View {
    let title: String
    let titleUnder: Bool
    var back = true
    @ViewBuilder var trailing: Trailing
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Text(title)
                .font(.displaySemi(17))
                .foregroundStyle(Hue.ink)
                .opacity(titleUnder ? 1 : 0)
                .accessibilityHidden(true)
            HStack {
                if back { BackButton { dismiss() } }
                Spacer()
                trailing
            }
            .padding(.horizontal, PageMetric.backLead)
        }
        .frame(height: PageMetric.bar)
        .frame(maxWidth: .infinity)
        .background(Hue.paper.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Hue.hairline).frame(height: FriendsMetric.hairline).opacity(titleUnder ? 1 : 0)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: titleUnder)
    }
}

extension FriendsTitleBar where Trailing == EmptyView {
    init(title: String, titleUnder: Bool, back: Bool = true) {
        self.init(title: title, titleUnder: titleUnder, back: back) { EmptyView() }
    }
}

/// Search's field, without Cancel.
struct FriendsSearchField: View {
    @Binding var words: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.glyph(15, weight: .medium))
                .foregroundStyle(Hue.searchFaint)
                .frame(width: SearchMetric.fieldIcon, height: SearchMetric.fieldIcon)
                .padding(.leading, SearchMetric.fieldIconLead)
                .padding(.trailing, SearchMetric.fieldIconGap)
                .accessibilityHidden(true)
            TextField("Search", text: $words, prompt: Text("Search").foregroundStyle(Hue.searchFaint))
                .font(.sans(16))
                .foregroundStyle(Hue.ink)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !words.isEmpty {
                Button {
                    words = ""
                    focused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Hue.surface, Hue.searchClear)
                        .font(.glyph(17))
                        .frame(width: SearchMetric.clearSide, height: SearchMetric.clearSide)
                        .contentShape(Rectangle().inset(by: (SearchMetric.clearSide - PageMetric.tapMin) / 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .frame(height: SearchMetric.fieldHeight)
        .background(Hue.searchField, in: RoundedRectangle(cornerRadius: Radius.searchField, style: .continuous))
    }
}
