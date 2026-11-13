//
//  GroupAgenda.swift
//  Block Party — which Group get-togethers are on your Agenda (BP app docs/plans/rsvp-and-groups,
//  ticket 09). Join group asks once, with Instagram's toast ("Add to your Agenda?" and Add); letting
//  it go is the no. After that each get-together has its own green Add in You's Coming up, and a
//  long press on one on the Agenda takes it off. None of it makes you Going.
//
//  Kept on the phone, as the choice of this account: a new phone forgets it and the Group's
//  get-togethers go back to Coming up (Jesse said yes to that at Check-in 1, 2026-11-13).
//

import SwiftUI

@MainActor @Observable
final class GroupAgenda {
    static let shared = GroupAgenda()

    /// How a get-together sits: on with its whole Group (the toast's Add), on by itself (a green
    /// Add), or off.
    enum State: Equatable { case group, one, off }

    /// Groups whose toast said Add: every get-together of theirs is on.
    private(set) var groups: Set<String>
    /// Get-togethers a green Add put on, one each.
    private(set) var added: Set<String>
    /// Get-togethers of an added Group taken off with a long press.
    private(set) var removed: Set<String>
    /// The Group the toast asks about now; nil when no toast shows.
    var asking: TownGroup?

    private let defaults: UserDefaults
    private static let groupsKey = "groupAgenda.groups"
    private static let addedKey = "groupAgenda.added"
    private static let removedKey = "groupAgenda.removed"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        groups = Set(defaults.stringArray(forKey: Self.groupsKey) ?? [])
        added = Set(defaults.stringArray(forKey: Self.addedKey) ?? [])
        removed = Set(defaults.stringArray(forKey: Self.removedKey) ?? [])
    }

    /// One get-together: its Group, day and time. A get-together has no id of its own: `get_groups`
    /// works it out from the Group's meeting days.
    nonisolated static func key(_ group: TownGroup, _ meeting: TownGroup.Meeting) -> String {
        [group.id, meeting.day, meeting.time ?? ""].joined(separator: "|")
    }

    func state(_ group: TownGroup, _ meeting: TownGroup.Meeting) -> State {
        let key = Self.key(group, meeting)
        if removed.contains(key) { return .off }
        if groups.contains(group.id) { return .group }
        return added.contains(key) ? .one : .off
    }

    /// A join: the toast asks, when the Group has a get-together still to come here. A Group
    /// joined again starts over, so its last answer never comes back unasked.
    func joined(_ group: TownGroup, now: Date = Date()) {
        forget(group.id)
        guard Self.hasNext(group, now: now) else { return }
        asking = group
    }

    /// The toast's Add.
    func addGroup(_ group: TownGroup) {
        forget(group.id)
        groups.insert(group.id)
        if asking?.id == group.id { asking = nil }
        save()
    }

    /// A green Add, or its Added tapped again.
    func toggle(_ group: TownGroup, _ meeting: TownGroup.Meeting) {
        let key = Self.key(group, meeting)
        switch state(group, meeting) {
        case .group: removed.insert(key)
        case .one: added.remove(key)
        case .off:
            removed.remove(key)
            if !groups.contains(group.id) { added.insert(key) }
        }
        save()
    }

    /// The long press's "Remove from Agenda".
    func remove(_ group: TownGroup, _ meeting: TownGroup.Meeting) {
        if state(group, meeting) != .off { toggle(group, meeting) }
    }

    /// Another account: nothing of the last one's.
    func clear() {
        groups = []; added = []; removed = []; asking = nil
        save()
    }

    /// Whether the toast has anything to offer: a get-together still to come that isn't away
    /// (another town's run, which the hello leaves out too).
    static func hasNext(_ group: TownGroup, now: Date) -> Bool {
        group.meetings.contains { $0.away != true && YouCalendar.stillToCome($0, now: now) }
    }

    private func forget(_ groupID: String) {
        groups.remove(groupID)
        added = added.filter { !$0.hasPrefix(groupID + "|") }
        removed = removed.filter { !$0.hasPrefix(groupID + "|") }
    }

    private func save() {
        defaults.set(Array(groups), forKey: Self.groupsKey)
        defaults.set(Array(added), forKey: Self.addedKey)
        defaults.set(Array(removed), forKey: Self.removedKey)
    }
}

/// The toast after Join group, Instagram's (BP app references/group-agenda/ref-instagram-*-toast.jpg,
/// measured at 3x): 8 pt from each side, 57 pt tall, 16 pt corners, the Group's logo in a 32 pt
/// square 12 pt in, the words 12 pt after it, Add 20 pt from the right. It rises over the Group
/// page's bar or the tab bar, goes by itself after 6 s (it stays while VoiceOver is on), and a
/// swipe down sends it away. Letting it go is the no.
struct AgendaToast: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var drag: CGFloat = 0
    private let agenda = GroupAgenda.shared

    enum Metric {
        static let side: CGFloat = 8
        static let height: CGFloat = 57
        static let corner: CGFloat = 16
        static let logo: CGFloat = 32
        static let logoCorner: CGFloat = 8
        static let logoInset: CGFloat = 12
        static let actionInset: CGFloat = 20
        /// Over the Group page's glass bar and the tab bar alike (the mock's 102 pt from the
        /// screen's bottom, less the home bar's 34). Picked.
        static let bottom: CGFloat = 68
        /// Instagram's go in about 4 s; this one asks a question (Jesse picked 6 s, 2026-11-13).
        static let stays: Duration = .seconds(6)
        /// How far down a swipe sends it away.
        static let dismiss: CGFloat = 24
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let group = agenda.asking {
                toast(group)
                    .id(group.id)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .task(id: group.id) {
                        AccessibilityNotification.Announcement("Add \(group.name) to your Agenda?").post()
                        guard !voiceOver else { return }
                        try? await Task.sleep(for: Metric.stays)
                        dismiss(group)
                    }
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.sheet, value: agenda.asking?.id)
        .padding(.horizontal, Metric.side)
        .padding(.bottom, Metric.bottom)
    }

    private func toast(_ group: TownGroup) -> some View {
        HStack(spacing: Metric.logoInset) {
            Hue.fill
                .overlay { YouGroupPicture(group: group, logoSide: Metric.logo * 0.75, glyph: 15) }
                .frame(width: Metric.logo, height: Metric.logo)
                .clipShape(RoundedRectangle(cornerRadius: Metric.logoCorner, style: .continuous))
                .accessibilityHidden(true)
            // A working line; Jesse picked it on the mock (2026-11-13).
            Text("Add to your Agenda?")
                .font(.apple(17))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Add") {
                Haptics.light()
                agenda.addGroup(group)
            }
            .font(.apple(17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(minWidth: PageMetric.tapMin, minHeight: PageMetric.tapMin)
            .buttonStyle(.press(.dim))
            .accessibilityLabel("Add \(group.name) to your Agenda")
        }
        .padding(.leading, Metric.logoInset)
        .padding(.trailing, Metric.actionInset - (PageMetric.tapMin - 30) / 2)
        .frame(height: Metric.height)
        .background(Hue.toast, in: RoundedRectangle(cornerRadius: Metric.corner, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Metric.corner, style: .continuous))
        .offset(y: max(0, drag))
        .gesture(DragGesture(minimumDistance: 4)
            .onChanged { drag = $0.translation.height }
            .onEnded { value in
                if value.translation.height > Metric.dismiss { dismiss(group) }
                withAnimation(Motion.snappy) { drag = 0 }
            })
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape) { dismiss(group) }
    }

    private func dismiss(_ group: TownGroup) {
        if agenda.asking?.id == group.id { agenda.asking = nil }
    }
}
