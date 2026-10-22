//
//  FriendMenu.swift
//  Block Party — the friend sheet (BP app docs/plans/friends, ticket 04), from the ••• on a
//  friend's row, the ••• at the top right of anyone's page, and the Friends button: their
//  photo, name and since when, then Unfollow, Unfriend and Block for a friend, Block for anyone
//  else. Unfollow (follows 02) keeps the friendship and asks nothing: one tap, and the sheet
//  closes. Unfriend and Block each ask once in Apple's alert over the sheet; saying yes closes
//  the sheet and `FriendsBook` acts. Nobody is told.
//
//  Reference: Facebook's friend sheet (BP app references/friends/fb-requests-4.jpg, 375pt at
//  1:1): the photo 31pt under the sheet's top, 48pt, 13pt to a 20pt bold name over a 17pt
//  grey line, 18pt to a full-width hairline, then 40pt grey circles 16pt apart with a 17pt
//  title 13pt from the circle. Apple's sheet carries it at the height it measures, so it drags
//  down with the finger. Mock Jesse said yes to on 2026-10-13:
//  https://claude.ai/artifact/RUmoV1bdCGHEnFhh97kykH
//

import SwiftUI

extension FriendsMetric {
    static let menuHeadTop: CGFloat = 31
    static let menuFace: CGFloat = 48
    static let menuGap: CGFloat = 13
    static let menuHeadBottom: CGFloat = 18
    static let menuCircle: CGFloat = 40
    static let menuRow: CGFloat = 56
    /// Hairline to the first circle, last circle to the sheet's foot: 16, less the row's own 8.
    static let menuRowsPad: CGFloat = 8
}

struct FriendMenu: View {
    let person: Neighbor
    /// Where you stood when the sheet opened: an Unfriend shouldn't rewrite the sheet as it
    /// slides away.
    @State private var relation: Neighbor.Relation
    @Environment(FriendsBook.self) private var book
    @Environment(RealLifeActions.self) private var actions
    @Environment(\.dismiss) private var dismiss
    /// The question up, and the last one asked, kept while the alert fades so its words don't change.
    @State private var asking: FriendsBook.Action?
    @State private var asked = FriendsBook.Action.block
    @State private var height: CGFloat = 240

    init(person: Neighbor, relation: Neighbor.Relation) {
        self.person = person
        _relation = State(initialValue: relation)
    }

    /// `friend-menu`: "Friends since October 2026" (this month for a friendship made since the
    /// last read); anyone else, "Neighbor since".
    private var line: String? {
        guard relation == .friends else { return person.sinceLine }
        return ProfileModel.since(from: person.friendsSince ?? Date.now.formatted(.iso8601)).map { "Friends since \($0)" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: FriendsMetric.menuGap) {
                NeighborFace(url: person.avatarUrl, size: FriendsMetric.menuFace)
                VStack(alignment: .leading, spacing: 0) {
                    Text(person.displayName)
                        .font(.sansBold(20))
                        .foregroundStyle(Hue.ink)
                        .lineLimit(1)
                    if let line {
                        Text(line)
                            .font(.sans(17))
                            .foregroundStyle(Hue.inkSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, FriendsMetric.side)
            .padding(.top, FriendsMetric.menuHeadTop)
            .padding(.bottom, FriendsMetric.menuHeadBottom)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Rectangle().fill(Hue.hairline).frame(height: FriendsMetric.hairline)
            VStack(spacing: 0) {
                if relation == .friends { followRow }
                ForEach(FriendsBook.menuChoices(for: relation), id: \.self) { row($0) }
            }
            .padding(.vertical, FriendsMetric.menuRowsPad)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Hue.surface)
        .task { if relation == .friends { await actions.refreshFollow(follow) } }
        .onAppear { book.menuOnScreen = true }
        .onDisappear { book.menuOnScreen = false }
        // `unfriend-confirm` and `block-confirm`, in Apple's alert.
        .alert(asked == .block ? "Block \(person.firstName)?" : "Unfriend \(person.firstName)?",
               isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
               presenting: asking) { action in
            Button(action == .block ? "Block" : "Unfriend", role: .destructive) {
                book.act(action, person)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            if action == .block { Text("They won't be able to find you or add you. They won't be told.") }
        }
    }

    private var follow: FollowTarget { FollowTarget(type: .profile, id: person.id) }

    /// `friend-unfollow`: "Unfollow Sam", "Stay friends" under it, as Facebook's. Unfollowed, it
    /// offers Follow back. One tap, no question.
    private var followRow: some View {
        let following = actions.follow(follow).isFollowing
        return Button {
            actions.toggleFollow(follow)
            dismiss()
        } label: {
            HStack(spacing: FriendsMetric.menuGap) {
                Image(systemName: following ? "person.fill.badge.minus" : "person.fill.badge.plus")
                    .font(.glyph(17, weight: .semibold))
                    .foregroundStyle(Hue.ink)
                    .frame(width: FriendsMetric.menuCircle, height: FriendsMetric.menuCircle)
                    .background(Hue.fill, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(following ? "Unfollow" : "Follow") \(person.firstName)")
                        .font(.sans(17))
                        .foregroundStyle(Hue.ink)
                    if following {
                        Text("Stay friends")
                            .font(.sans(13))
                            .foregroundStyle(Hue.inkSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, FriendsMetric.side)
            .frame(height: FriendsMetric.menuRow)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .onAppear { actions.followOpened(follow) }
        .onDisappear { actions.followClosed(follow) }
    }

    /// One choice: Facebook's grey circle and title, the whole row to the finger.
    private func row(_ action: FriendsBook.Action) -> some View {
        Button {
            asked = action
            asking = action
        } label: {
            HStack(spacing: FriendsMetric.menuGap) {
                Image(systemName: action == .block ? "hand.raised.fill" : "person.fill.xmark")
                    .font(.glyph(17, weight: .semibold))
                    .foregroundStyle(Hue.ink)
                    .frame(width: FriendsMetric.menuCircle, height: FriendsMetric.menuCircle)
                    .background(Hue.fill, in: Circle())
                    .accessibilityHidden(true)
                Text(action == .block ? "Block \(person.firstName)" : "Unfriend \(person.firstName)")
                    .font(.sans(17))
                    .foregroundStyle(Hue.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, FriendsMetric.side)
            .frame(height: FriendsMetric.menuRow)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }
}
