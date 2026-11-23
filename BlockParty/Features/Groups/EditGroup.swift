//
//  EditGroup.swift
//  Block Party — Edit group (BP app docs/plans/start-a-group, ticket 04; Figma frame 8, beside GroupMe's group
//  settings). The Admin opens it from the ••• on the Group page: Apple's sheet with Cancel, Edit group and Save over a
//  grouped form: photo and name, Kind, About, Private; Who can add events (Only me, Members I pick, All members); the
//  Admin row, which hands the Group to a member; and Close group. A new name, kind, About or photo goes through the
//  same two checks as a new Group before anyone sees it (`edit_group`, then moderate-post's `group` mode).
//

import SwiftUI
import PhotosUI

/// What the sheet holds, and the rules Save is held to.
nonisolated struct EditGroupDraft: Equatable {
    /// Who adds Events to the Group's Calendar (`clubs.events_by`).
    enum EventsBy: String, CaseIterable {
        case admin, picked, members

        var title: String {
            switch self {
            case .admin: "Only me"
            case .picked: "Members I pick"
            case .members: "All members"
            }
        }
    }

    var name: String
    var kind: String?
    var about: String
    var isPrivate: Bool
    var eventsBy: EventsBy
    /// The members picked to add Events, by id.
    var editors: Set<String>
    /// A new photo was picked.
    var newPhoto = false

    init(_ group: TownGroup, editors: Set<String>) {
        name = group.name
        kind = group.kind
        about = group.about ?? ""
        isPrivate = group.isPrivate
        eventsBy = group.eventsBy.flatMap(EventsBy.init(rawValue:)) ?? .admin
        self.editors = editors
    }

    /// The name as it is sent, and `start_group`'s rule for it (`edit_group` keeps the same).
    var cleanName: String { StartGroupDraft(name: name).cleanName }
    var ready: Bool { StartGroupDraft(name: name).ready }
    var cleanAbout: String { about.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// A change everyone would see: it waits on the two checks before it shows.
    func needsCheck(from start: EditGroupDraft) -> Bool {
        newPhoto || cleanName != start.cleanName || kind != start.kind || cleanAbout != start.cleanAbout
    }

    /// Save: something changed, and the name is one the server takes.
    func canSave(from start: EditGroupDraft) -> Bool {
        ready && (needsCheck(from: start) || isPrivate != start.isPrivate || eventsBy != start.eventsBy
                  || editors != start.editors)
    }

    /// "Junie, Dale", "Junie, Dale and 2 more": the first names of the members picked; nil for none.
    static func pickedLine(_ names: [String]) -> String? {
        guard !names.isEmpty else { return nil }
        let first = names.prefix(2).map { $0.split(separator: " ").first.map(String.init) ?? $0 }.joined(separator: ", ")
        return names.count > 2 ? "\(first) and \(names.count - 2) more" : first
    }
}

/// One member as the Admin's lists show them.
struct GroupMember: Identifiable, Hashable {
    let person: Neighbor
    var id: String { person.id }
}

struct EditGroupSheet: View {
    let group: TownGroup
    /// The Group as saved: the page shows it at once.
    let saved: (TownGroup) -> Void
    /// Handed to a member: you're no longer its Admin.
    let handedOver: () -> Void
    /// Closed: the page goes too.
    let closed: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var start: EditGroupDraft
    @State private var draft: EditGroupDraft
    /// The members but you, longest in first; nil until read.
    @State private var members: [GroupMember]?
    @State private var image: UIImage?
    @State private var pick: PhotosPickerItem?
    @State private var adjusting: UIImage?
    @State private var alwaysPrivate = false
    @State private var saving = false
    @State private var failures = 0
    /// Why the checks held the edit back, under the name.
    @State private var held: String?
    @State private var closing = false
    @State private var path = NavigationPath()

    init(group: TownGroup, saved: @escaping (TownGroup) -> Void, handedOver: @escaping () -> Void,
         closed: @escaping () -> Void) {
        self.group = group
        self.saved = saved
        self.handedOver = handedOver
        self.closed = closed
        let draft = EditGroupDraft(group, editors: [])
        _start = State(initialValue: draft)
        _draft = State(initialValue: draft)
    }

    enum Metric {
        /// Mock frame 8: the photo beside the name, 36 pt with 9 pt corners; the picked members' faces, 26 pt, 8 pt
        /// over each other, under Members I pick, 28 pt further in.
        static let photo: CGFloat = 36
        static let photoCorner: CGFloat = 9
        static let face: CGFloat = 26
        static let faceOverlap: CGFloat = 8
        static let subIndent: CGFloat = 28
    }

    private enum Route: Hashable { case about, pick, admin }

    var body: some View {
        NavigationStack(path: $path) {
            form
                .navigationTitle("Edit group")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.disabled(saving)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if saving {
                            ProgressView()
                        } else {
                            Button("Save") { Task { await save() } }
                                .fontWeight(.semibold)
                                .disabled(!draft.canSave(from: start))
                                .turnBackShake(failures: failures, shakes: !reduceMotion)
                        }
                    }
                }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .about: AboutEditor(about: $draft.about)
                    case .pick: PickMembersPage(members: members ?? [], picked: $draft.editors)
                    case .admin: HandOverPage(group: group, members: members) { handOver() }
                    }
                }
        }
        .interactiveDismissDisabled(saving || draft != start)
        .task { await load() }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
                    adjusting = await PhotoCrop.shrunk(ui)
                }
                pick = nil
            }
        }
        .photoAdjust($adjusting, shape: .wide(GroupPage.Metric.heroAspect)) { cut in
            image = cut
            draft.newPhoto = true
        }
    }

    private var form: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    PhotosPicker(selection: $pick, matching: .images, photoLibrary: .shared()) { photo }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Change photo")
                    TextField("Group name", text: $draft.name)
                        .textInputAutocapitalization(.words)
                        .onChange(of: draft.name) { _, name in
                            held = nil
                            if name.count > 60 { draft.name = String(name.prefix(60)) }
                        }
                }
                Picker("Kind", selection: $draft.kind) {
                    Text("None").tag(String?.none)
                    ForEach(kinds, id: \.self) { Text($0).tag(Optional($0)) }
                }
                .pickerStyle(.navigationLink)
                NavigationLink(value: Route.about) {
                    LabeledContent("About") {
                        Text(draft.cleanAbout.isEmpty ? "Add" : draft.cleanAbout).lineLimit(1)
                    }
                }
                Toggle(isOn: Binding { draft.isPrivate || alwaysPrivate } set: { draft.isPrivate = $0 }) {
                    Label("Private", systemImage: "lock")
                }
                .disabled(alwaysPrivate)
            } footer: {
                if let held {
                    Text(held.isEmpty ? "Couldn't check that. Try again." : held).foregroundStyle(Hue.ink)
                } else if alwaysPrivate {
                    Text("Groups started by teens are private.")
                }
            }

            Section("Who can add events") {
                ForEach(EditGroupDraft.EventsBy.allCases, id: \.self) { option in
                    Button {
                        Haptics.selection()
                        draft.eventsBy = option
                    } label: {
                        HStack {
                            Text(option.title).foregroundStyle(Hue.ink)
                            Spacer()
                            if draft.eventsBy == option {
                                Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Hue.ink)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(draft.eventsBy == option ? .isSelected : [])
                    if option == .picked, draft.eventsBy == .picked { pickedRow }
                }
            }

            Section {
                NavigationLink(value: Route.admin) {
                    LabeledContent("Admin", value: "You")
                }
            }

            Section {
                Button(role: .destructive) { closing = true } label: {
                    Text("Close group").frame(maxWidth: .infinity)
                }
                .confirmationDialog("Close this group?", isPresented: $closing, titleVisibility: .visible) {
                    Button("Close group", role: .destructive) { Task { await close() } }
                } message: {
                    Text("It leaves every list for everyone, and can't be opened again.")
                }
            }
        }
        .tint(Hue.ink)
        .disabled(saving)
    }

    /// The members picked, their faces and first names; opens the list to pick from.
    private var pickedRow: some View {
        let picked = (members ?? []).filter { draft.editors.contains($0.id) }
        return NavigationLink(value: Route.pick) {
            HStack(spacing: 10) {
                if !picked.isEmpty {
                    HStack(spacing: -Metric.faceOverlap) {
                        ForEach(picked.prefix(3)) { member in
                            Avatar(avatarUrl: member.person.avatarUrl, size: Metric.face)
                                .overlay { Circle().strokeBorder(Hue.surface, lineWidth: 2) }
                        }
                    }
                }
                Text(EditGroupDraft.pickedLine(picked.map(\.person.displayName)) ?? "No one yet")
                    .foregroundStyle(Hue.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(picked.isEmpty ? "Pick" : "Edit").foregroundStyle(Hue.inkSecondary)
            }
            .font(.sans(15))
        }
        .padding(.leading, Metric.subIndent)
        .disabled(members == nil)
    }

    private var photo: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let url = group.imageUrl ?? group.photos.first?.url {
                FeedCardURLPhoto(url: url, loadingFill: Hue.fill)
            } else {
                Image(systemName: "photo").foregroundStyle(Hue.inkSecondary)
            }
        }
        .frame(width: Metric.photo, height: Metric.photo)
        .background(Hue.fill)
        .clipShape(RoundedRectangle(cornerRadius: Metric.photoCorner, style: .continuous))
    }

    /// New group's eight, and the Group's own kind when it isn't one of them.
    private var kinds: [String] {
        StartGroupDraft.kinds + [start.kind].compactMap { $0 }.filter { !StartGroupDraft.kinds.contains($0) }
    }

    private func load() async {
        #if DEBUG
        // `-group-admin`: the sample neighbours as its members, two picked, with no read.
        if LaunchFlags.value(.groupAdmin) != nil {
            members = Neighbor.samples.prefix(8).map(GroupMember.init)
            start.editors = Set(Neighbor.samples.dropFirst(6).prefix(2).map(\.id))  // Junie and Dale, as the mock
            start.eventsBy = .picked
            draft = start
            switch LaunchFlags.value(.groupAdmin) {
            case "hand": path.append(Route.admin)
            case "close": closing = true
            default: break
            }
            return
        }
        #endif
        let api = CommunityAPI(auth: AuthStore.shared)
        // Under 18 now or no birthday, or the Group was started by someone under 18 (SPEC decision 5).
        alwaysPrivate = group.alwaysPrivate
        if !alwaysPrivate { alwaysPrivate = await api.groupsAlwaysPrivate() }
        guard let read = try? await api.groupMembers(group.id) else { return }
        members = read.map { GroupMember(person: $0.person) }
        let picked = Set(read.filter(\.editor).map(\.person.id))
        // Picks read after a change was made still count as where it started.
        start.editors = picked
        draft.editors = draft.editors.union(picked)
    }

    /// Private and Who can add events land at once; a new name, kind, About or photo shows only once both checks say
    /// yes. A held edit keeps the sheet open with the reason under the name, and shakes Save.
    private func save() async {
        guard draft.canSave(from: start), !saving else { return }
        saving = true
        defer { saving = false }
        let api = CommunityAPI(auth: AuthStore.shared)
        do {
            var photo: URL?
            if draft.newPhoto, let image, let jpeg = ProfileModel.coverJPEG(image) {
                photo = try await api.uploadGroupEditPhoto(jpeg, id: group.id)
            }
            let checks = try await api.editGroup(group.id, draft, editors: members == nil ? nil : draft.editors,
                                                 photo: photo)
            var shown = group
            shown.isPrivate = draft.isPrivate || alwaysPrivate
            shown.eventsBy = draft.eventsBy.rawValue
            if checks, let reason = await api.checkGroupEdit(group.id) {
                saved(shown)
                start.isPrivate = draft.isPrivate
                start.eventsBy = draft.eventsBy
                start.editors = draft.editors
                held = reason
                Haptics.error()
                failures += 1
                return
            }
            shown.name = draft.cleanName
            shown.kind = draft.kind
            shown.about = draft.cleanAbout.isEmpty ? nil : draft.cleanAbout
            if let photo {
                shown.imageUrl = photo
                shown.photos = [PlacePicture(url: photo, kind: .photo)]
            }
            saved(shown)
            Haptics.success()
            dismiss()
        } catch {
            Log.network("EditGroupSheet: couldn't save \(group.id): \(error)")
            Haptics.error()
            failures += 1
        }
    }

    private func handOver() {
        dismiss()
        handedOver()
    }

    private func close() async {
        do {
            try await CommunityAPI(auth: AuthStore.shared).closeGroup(group.id)
            Haptics.success()
            dismiss()
            closed()
        } catch {
            Log.network("EditGroupSheet: couldn't close \(group.id): \(error)")
            Haptics.error()
            failures += 1
        }
    }
}

/// About, a page of its own (mock frame 8's About row opens it).
private struct AboutEditor: View {
    @Binding var about: String

    var body: some View {
        Form {
            TextField("What the group does, when and where", text: $about, axis: .vertical)
                .lineLimit(6...)
                .onChange(of: about) { _, text in if text.count > 1000 { about = String(text.prefix(1000)) } }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Members I pick: each member with a check.
private struct PickMembersPage: View {
    let members: [GroupMember]
    @Binding var picked: Set<String>

    var body: some View {
        List(members) { member in
            let on = picked.contains(member.id)
            Button {
                Haptics.selection()
                if on { picked.remove(member.id) } else { picked.insert(member.id) }
            } label: {
                HStack(spacing: 12) {
                    Avatar(avatarUrl: member.person.avatarUrl, size: InviteMetric.face, outlined: true)
                    Text(member.person.displayName).foregroundStyle(Hue.ink).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.glyph(22, weight: .light))
                        .foregroundStyle(on ? Hue.ink : Hue.inkSecondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .contentShape(Rectangle())
            }
            .accessibilityLabel(member.person.displayName)
            .accessibilityAddTraits(on ? .isSelected : [])
        }
        .navigationTitle("Members I pick")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The Admin row's page: you, then the members; a tap asks, and a yes makes them the Admin.
private struct HandOverPage: View {
    let group: TownGroup
    let members: [GroupMember]?
    let done: () -> Void

    @State private var asking: GroupMember?
    @State private var failures = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        List {
            Section {
                LabeledContent("You", value: "Admin")
            }
            Section("Make a member the Admin") {
                if let members {
                    if members.isEmpty {
                        Text("No other members yet.").foregroundStyle(Hue.inkSecondary)
                    }
                    ForEach(members) { member in
                        Button { asking = member } label: {
                            HStack(spacing: 12) {
                                Avatar(avatarUrl: member.person.avatarUrl, size: InviteMetric.face, outlined: true)
                                Text(member.person.displayName).foregroundStyle(Hue.ink).lineLimit(1)
                            }
                        }
                    }
                } else {
                    LoadingRows()
                }
            }
        }
        .turnBackShake(failures: failures, shakes: !reduceMotion)
        .navigationTitle("Admin")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(asking.map { "Make \($0.person.firstName) the Admin?" } ?? "",
                            isPresented: Binding { asking != nil } set: { if !$0 { asking = nil } },
                            titleVisibility: .visible, presenting: asking) { member in
            Button("Make \(member.person.firstName) the Admin") { Task { await handOver(member) } }
        } message: { _ in
            Text("They'll edit, run and close the group. You stay a member.")
        }
        #if DEBUG
        .task { if LaunchFlags.value(.groupAdmin) == "hand", let first = members?.first { asking = first } }
        #endif
    }

    private func handOver(_ member: GroupMember) async {
        #if DEBUG
        if LaunchFlags.value(.groupAdmin) != nil { return done() }
        #endif
        do {
            try await CommunityAPI(auth: AuthStore.shared).handOverGroup(group.id, to: member.id)
            Haptics.success()
            done()
        } catch {
            Log.network("HandOverPage: couldn't hand \(group.id) to \(member.id): \(error)")
            Haptics.error()
            failures += 1
        }
    }
}
