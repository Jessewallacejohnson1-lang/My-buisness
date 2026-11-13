//
//  FriendsGroups.swift
//  Block Party — the Friends tab's Groups (BP app docs/plans/five-tabs, ticket 02; mock
//  https://claude.ai/artifact/29BVrCrrQ3WeWhS3egMozR): the groups you're in as You's highlights,
//  moved here from You, then Groups to join, each with its next get-together and Join, as
//  Nextdoor's "Groups near you" (BP app references/five-tabs/refs/r2/). Joining one moves it up
//  into your own row. Plus See all: every friend, or every Group.
//

import SwiftUI

/// Your groups' row, then Groups to join.
struct FriendsGroups: View {
    let mine: [TownGroup]
    let open: [TownGroup]
    /// A Join that took: the page holds the row's Joined before moving it up.
    var joined: (TownGroup) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !mine.isEmpty { GroupCircles(groups: mine) }
            if !mine.isEmpty, !open.isEmpty {
                Text("Groups to join")
                    .font(.displaySemi(13))
                    .foregroundStyle(Hue.inkSecondary)
                    .padding(.horizontal, FriendsMetric.side)
                    .padding(.top, FriendsMetric.subTop)
                    .padding(.bottom, FriendsMetric.subBottom)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(open) { GroupJoinRow(group: $0, joined: joined) }
        }
    }
}

/// The groups you're in, as You's highlights (ticket you-tab 09), in Search's order. A tap opens
/// the Group page.
struct GroupCircles: View {
    let groups: [TownGroup]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: YouMetric.highlightGap) {
                ForEach(groups) { group in
                    NavigationLink(value: group) {
                        YouHighlight(name: group.name) { YouGroupPicture(group: group) }
                    }
                    .buttonStyle(.press(.squish))
                    .accessibilityLabel(group.name)
                }
            }
        }
        .contentMargins(.horizontal, FriendsMetric.side, for: .scrollContent)
    }
}

/// One Group to join: its picture (logo on its backdrop, else Search's group icon; never its
/// photos, which carry a credit), name, when it next meets, and Join, the charcoal of Join group.
/// Once you're in, the pill says Joined in the light face and a tap leaves (the See all page).
struct GroupJoinRow: View {
    let group: TownGroup
    var joined: (TownGroup) -> Void = { _ in }
    @Environment(RealLifeActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let member = actions.member(group)
        HStack(spacing: FriendsMetric.avatarGap) {
            NavigationLink(value: group) {
                HStack(spacing: FriendsMetric.avatarGap) {
                    Hue.fill
                        .overlay { YouGroupPicture(group: group) }
                        .frame(width: FriendsMetric.groupTile, height: FriendsMetric.groupTile)
                        .clipShape(RoundedRectangle(cornerRadius: FriendsMetric.groupTileRadius, style: .continuous))
                    VStack(alignment: .leading, spacing: FriendsMetric.lineGap) {
                        Text(group.name)
                            .font(.sansSemibold(17))
                            .foregroundStyle(Hue.ink)
                        if let line = Self.line(group, members: member.count, now: Date()) {
                            Text(line)
                                .font(.sans(13))
                                .foregroundStyle(Hue.inkSecondary)
                        }
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.press(.dim))
            Button(action: toggle) {
                ZStack {
                    Text("Join").opacity(member.isMember ? 0 : 1)
                    Text("Joined").opacity(member.isMember ? 1 : 0)
                }
                .font(.displaySemi(15))
            }
            .buttonStyle(MeetupPillStyle(height: FriendsMetric.joinPill, minWidth: 0, light: member.isMember,
                                         sidePadding: FriendsMetric.joinSide))
            .turnBackShake(failures: actions.memberFailureCount(group.id), shakes: !reduceMotion)
            .animation(.easeInOut(duration: reduceMotion ? 0.15 : RealLifeActions.flip), value: member.isMember)
            .accessibilityLabel(member.isMember ? "Joined, \(group.name)" : "Join \(group.name)")
        }
        .padding(.horizontal, FriendsMetric.side)
        .frame(height: FriendsMetric.row)
    }

    private func toggle() {
        let joining = !actions.member(group).isMember
        actions.toggleMember(group)
        if joining, actions.member(group).isMember {
            joined(group)
            // The toast asks whether its get-togethers go on your Agenda (rsvp-and-groups 09).
            GroupAgenda.shared.joined(group)
        }
    }

    /// Its next get-together still to come: a timed one before it starts, an untimed one through
    /// its day. `get_groups` can still list one from earlier today.
    static func next(_ group: TownGroup, now: Date) -> TownGroup.Meeting? {
        group.meetings.first { YouCalendar.stillToCome($0, now: now) }
    }

    /// "Meets tomorrow 6 PM · 12 members": its next get-together in the bell's short words
    /// (`EventWhen.short`), then the members once someone has joined (the Group page's rule:
    /// never a zero count). nil with neither.
    static func line(_ group: TownGroup, members: Int, now: Date) -> String? {
        let meets = next(group, now: now)
            .flatMap { EventWhen.short(date: $0.day, time: $0.time, now: now) }
            .map { when in
                // "Tonight 6 PM" reads "tonight 6 PM" after "Meets"; a weekday or a date keeps its capital.
                let word = ["Today", "Tonight", "Tomorrow"].contains { when.hasPrefix($0) }
                return "Meets " + (word ? when.prefix(1).lowercased() + when.dropFirst() : when)
            }
        let count = members > 0 ? "\(members) \(members == 1 ? "member" : "members")" : nil
        let parts = [meets, count].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// See all on the Friends tab: every friend A to Z, or every Group, soonest get-together first,
/// each with Join or Joined.
struct FriendsAllPage: View {
    let groups: Bool
    @Environment(FriendsBook.self) private var book
    @Environment(YouModel.self) private var you

    var body: some View {
        ZStack(alignment: .top) {
            Hue.paper.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if groups {
                        ForEach(FriendsHomePage.groups(you.groups ?? [], member: { _ in false }, now: Date()).open) {
                            GroupJoinRow(group: $0)
                        }
                    } else {
                        ForEach(book.friends) { PersonRow(person: $0, waiting: false) }
                    }
                }
                .padding(.top, PageMetric.bar + FriendsMetric.resultsTop)
            }
            FriendsTitleBar(title: groups ? "Groups" : "Your friends", titleUnder: true).accessibilitySortPriority(1)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
