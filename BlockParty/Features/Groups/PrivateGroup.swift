//
//  PrivateGroup.swift
//  Block Party — private Groups (BP app docs/plans/start-a-group, ticket 03; Figma frame 7 Jesse said yes to on
//  2026-11-21): to anyone not in one, its name, photo, member count and About, a Members only box and Ask to join;
//  its Admin (its starter, until ticket 04) says yes or no to each ask from Requests, the Friends tab's request rows.
//

import SwiftUI

/// Which private Groups you asked to join, shared by the Group page and Groups to join. A tap flips at once and turns
/// back, with a shake, when the server says no; every Groups read sets it again (`YouModel.refreshGroups`).
@MainActor @Observable
final class GroupAsks {
    static let shared = GroupAsks()

    private(set) var asked: Set<String> = []
    private(set) var failures: [String: Int] = [:]
    @ObservationIgnored var send: (String, Bool) async throws -> Void = { id, on in
        try await CommunityAPI(auth: AuthStore.shared).askToJoin(id, on: on)
    }

    func read(_ groups: [TownGroup]) {
        asked = Set(groups.filter(\.asked).map(\.id))
    }

    func isAsked(_ group: TownGroup) -> Bool { asked.contains(group.id) }

    /// Ask, or take the ask back.
    func toggle(_ group: TownGroup) async {
        let on = !asked.contains(group.id)
        if on { asked.insert(group.id) } else { asked.remove(group.id) }
        Haptics.selection()
        do {
            try await send(group.id, on)
        } catch {
            Log.network("GroupAsks: ask \(on) for \(group.id) failed: \(error)")
            if on { asked.remove(group.id) } else { asked.insert(group.id) }
            failures[group.id, default: 0] += 1
        }
    }

    /// A private Group you aren't in, weren't invited to and didn't start: Ask to join in Join's place.
    static func locked(_ group: TownGroup, member: Bool) -> Bool {
        group.isPrivate && !member && group.invitedBy == nil && group.requests == nil
    }
}

/// The Members only box, mock frame 7: a lock, "Members only", and why.
struct MembersOnlyBox: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "lock")
                .font(.glyph(28, weight: .light))
                .foregroundStyle(Hue.ink)
                .padding(.bottom, 4)
            Text("Members only")
                .font(.sansSemibold(17))
                .foregroundStyle(Hue.ink)
            Text("Join to see the Calendar and who's in.")
                .font(.sans(15))
                .foregroundStyle(Hue.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .background(Hue.fill, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The Admin's asks, oldest first: each person's face and name, Confirm and Delete (the Friends tab's request
/// buttons). An answer leaves the list at once; a failed one comes back with a shake.
struct JoinRequestsPage: View {
    let group: TownGroup
    /// The count on the Group page's Requests row, kept in step.
    @Binding var waiting: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var people: [Neighbor]?
    @State private var failed = false
    @State private var failures: [String: Int] = [:]

    var body: some View {
        ZStack(alignment: .top) {
            Hue.paper.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let people {
                        if people.isEmpty {
                            Text("No requests right now.")
                                .font(.sans(15))
                                .foregroundStyle(Hue.inkSecondary)
                                .padding(.horizontal, FriendsMetric.side)
                                .padding(.top, FriendsMetric.noteTop)
                        }
                        ForEach(people) { row($0) }
                    } else if failed {
                        FailedLine()
                    } else {
                        LoadingRows()
                    }
                }
                .padding(.top, PageMetric.bar + FriendsMetric.resultsTop)
                .animation(reduceMotion ? nil : Motion.smooth, value: people?.map(\.id))
            }
            FriendsTitleBar(title: "Requests", titleUnder: true).accessibilitySortPriority(1)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private func load() async {
        do {
            let read = try await CommunityAPI(auth: AuthStore.shared).joinRequests(group.id)
            people = read
            waiting = read.count
        } catch {
            failed = people == nil
        }
    }

    private func row(_ person: Neighbor) -> some View {
        HStack(spacing: FriendsMetric.avatarGap) {
            Avatar(avatarUrl: person.avatarUrl, size: FriendsMetric.requestFace, outlined: true)
            VStack(alignment: .leading, spacing: FriendsMetric.buttonTop) {
                Text(person.displayName)
                    .font(.sansSemibold(17))
                    .foregroundStyle(Hue.ink)
                    .lineLimit(1)
                HStack(spacing: FriendsMetric.buttonGap) {
                    button("Confirm", ink: true, person: person) { answer(person, yes: true) }
                    button("Delete", ink: false, person: person) { answer(person, yes: false) }
                }
                .turnBackShake(failures: failures[person.id] ?? 0, shakes: !reduceMotion)
            }
        }
        .padding(.horizontal, FriendsMetric.side)
        .padding(.vertical, FriendsMetric.requestPad)
        .transition(.opacity)
    }

    private func button(_ title: String, ink: Bool, person: Neighbor, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.displaySemi(15))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(MeetupPillStyle(height: FriendsMetric.button, minWidth: 0, light: !ink))
        .accessibilityLabel("\(title), \(person.displayName)")
    }

    private func answer(_ person: Neighbor, yes: Bool) {
        guard let at = people?.firstIndex(of: person) else { return }
        people?.remove(at: at)
        waiting = max(0, waiting - 1)
        Haptics.selection()
        Task {
            do {
                try await CommunityAPI(auth: AuthStore.shared).answerJoin(group.id, user: person.id, yes: yes)
                if yes { Haptics.success() }
            } catch {
                Log.network("JoinRequestsPage: answer \(yes) for \(person.id) failed: \(error)")
                people?.insert(person, at: min(at, people?.count ?? 0))
                waiting += 1
                failures[person.id, default: 0] += 1
            }
        }
    }
}
