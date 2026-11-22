//
//  StartGroup.swift
//  Block Party — start a Group (BP app docs/plans/start-a-group, ticket 02; Figma frames 2, 4 and 5 Jesse said yes
//  to on 2026-11-21, beside Nextdoor's Groups, Lex's Create a Group and Instacart's Invite friends). Any real account
//  starts one from the Friends tab's Groups to join or the end of You's Groups: one sheet with a photo, the name (the
//  only must) and a kind, the Town's Groups with a like name under the name, each with Join. Create makes it pending
//  (`start_group`) and starts its two checks without waiting; Invite friends follows, then the new Group's page.
//

import SwiftUI
import PhotosUI

/// What the sheet holds before Create, and the rules it is held to.
nonisolated struct StartGroupDraft: Equatable {
    var name = ""
    var kind: String?

    /// The chips under Kind, in the mock's order. PICKED from the Town's own Groups' kinds.
    static let kinds = ["Book club", "Running", "Faith", "Service", "Crafts", "Outdoors", "Games", "Music"]

    /// The name as it is sent: runs of spaces as one, none at either end (`start_group` does the same).
    var cleanName: String { name.split(whereSeparator: \.isWhitespace).joined(separator: " ") }

    /// 3 to 60 characters with a letter among them: `start_group`'s rule.
    var ready: Bool { (3...60).contains(cleanName.count) && cleanName.contains(where: \.isLetter) }

    /// Words that say nothing about what a Group does: the town's own names among them.
    private static let plain: Set<String> = Set(["club", "clubs", "group", "groups", "the", "and", "for", "saint", "town",
                                                 "society", "team", "circle", "night"])
        .union([Town.everyday, Town.nickname, Town.townPage].flatMap { $0.lowercased().split { !$0.isLetter }.map(String.init) })

    /// Up to 3 live Groups whose name shares a word with this one, the most shared first: "Joetown Knitters" finds
    /// the Spinning and Knitting Bee ("knit" both). A word counts from 4 letters, matched on its first 4.
    static func similar(to name: String, in groups: [TownGroup]) -> [TownGroup] {
        func stems(_ words: String) -> Set<String> {
            Set(words.lowercased().split { !$0.isLetter }.map(String.init)
                .filter { $0.count >= 4 && !plain.contains($0) }.map { String($0.prefix(4)) })
        }
        let typed = stems(name)
        guard !typed.isEmpty else { return [] }
        let live = groups.filter { $0.status == "approved" }
        let shared: [Int] = live.map { stems($0.name).intersection(typed).count }
        // The Town's order breaks a tie: a stable sort over the indexes.
        let order: [Int] = live.indices.filter { shared[$0] > 0 }
            .sorted { a, b in shared[a] != shared[b] ? shared[a] > shared[b] : a < b }
        return order.prefix(3).map { live[$0] }
    }
}

/// The row that opens the sheet: a "+" in the Group tile's place, then "Start a group".
struct StartGroupRow: View {
    var tile = FriendsMetric.groupTile
    var corner = FriendsMetric.groupTileRadius
    var font = Font.sansSemibold(17)
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: FriendsMetric.avatarGap) {
                Image(systemName: "plus")
                    .font(.glyph(22, weight: .medium))
                    .foregroundStyle(Hue.ink)
                    .frame(width: tile, height: tile)
                    .background(Hue.fill, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
                Text("Start a group")
                    .font(font)
                    .foregroundStyle(Hue.ink)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.press(.dim))
    }
}

/// New group, then Invite friends, in one sheet. `started` opens the Group's page once the sheet is down.
struct StartGroupSheet: View {
    /// The Town's Groups, for the like names under the name.
    let groups: [TownGroup]
    let started: (TownGroup) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(RealLifeActions.self) private var actions
    @Environment(YouModel.self) private var you

    @State private var draft = StartGroupDraft()
    @State private var image: UIImage?
    @State private var pick: PhotosPickerItem?
    @State private var adjusting: UIImage?
    @State private var saving = false
    @State private var failures = 0
    /// Made: the sheet turns to Invite friends.
    @State private var made: TownGroup?
    @FocusState private var naming: Bool

    enum Metric {
        /// The photo well: a rounded square in the middle, the camera badge on its corner (mock frame 4).
        static let well: CGFloat = 88
        static let wellCorner: CGFloat = 20
        static let badge: CGFloat = 30
        static let fieldCorner: CGFloat = 14
        static let fieldPad: CGFloat = 16
        static let chip: CGFloat = 36
        static let gap: CGFloat = 22
        static let side: CGFloat = 20
    }

    var body: some View {
        NavigationStack {
            Group {
                if let made {
                    InviteFriendsView(group: made) { finish(made) }
                } else {
                    form
                }
            }
            .navigationDestination(for: TownGroup.self) { GroupPage(group: $0) }
        }
        .interactiveDismissDisabled(saving)
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
                    adjusting = await PhotoCrop.shrunk(ui)
                }
                pick = nil
            }
        }
        // The Group page's own shape, so the photo lands at its top as it was framed.
        .photoAdjust($adjusting, shape: .wide(GroupPage.Metric.heroAspect)) { cut in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { image = cut }
        }
    }

    private var form: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Metric.gap) {
                PhotosPicker(selection: $pick, matching: .images, photoLibrary: .shared()) { well }
                    .buttonStyle(.press(.squish))
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(image == nil ? "Add a photo" : "Change photo")
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Group name", text: $draft.name)
                        .font(.displaySemi(22))
                        .foregroundStyle(Hue.ink)
                        .focused($naming)
                        .submitLabel(.done)
                        .textInputAutocapitalization(.words)
                        .padding(Metric.fieldPad)
                        .background(Hue.surface, in: RoundedRectangle(cornerRadius: Metric.fieldCorner, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: Metric.fieldCorner, style: .continuous).strokeBorder(Hue.hairline) }
                        .onChange(of: draft.name) { _, name in if name.count > 60 { draft.name = String(name.prefix(60)) } }
                    let alike = StartGroupDraft.similar(to: draft.name, in: groups)
                    if !alike.isEmpty {
                        caption("Already in \(Town.everyday)")
                        ForEach(alike) { GroupJoinRow(group: $0).padding(.horizontal, -FriendsMetric.side) }
                    }
                }
                .animation(reduceMotion ? nil : Motion.smooth, value: StartGroupDraft.similar(to: draft.name, in: groups).map(\.id))
                VStack(alignment: .leading, spacing: 8) {
                    caption("Kind")
                    FlowLayout(spacing: 8) {
                        ForEach(StartGroupDraft.kinds, id: \.self) { kind in chip(kind) }
                    }
                }
            }
            .padding(.horizontal, Metric.side)
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Hue.paper.ignoresSafeArea())
        .navigationTitle("New group")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }.disabled(saving)
            }
            ToolbarItem(placement: .confirmationAction) {
                if saving {
                    ProgressView()
                } else {
                    Button("Create") { Task { await create() } }
                        .fontWeight(.semibold)
                        .disabled(!draft.ready)
                        .turnBackShake(failures: failures, shakes: !reduceMotion)
                }
            }
        }
        .onAppear {
            naming = true
            #if DEBUG
            // `-start-group <name>`: typed and a photo picked, as nothing types on the simulator.
            if let name = LaunchFlags.value(.startGroup), draft.name.isEmpty {
                draft.name = name
                image = UIImage(named: "interest-fun-games.jpg")
                naming = false
            }
            #endif
        }
    }

    private var well: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.glyph(28))
                        .foregroundStyle(Hue.inkSecondary)
                }
            }
            .frame(width: Metric.well, height: Metric.well)
            .background(Hue.fill)
            .clipShape(RoundedRectangle(cornerRadius: Metric.wellCorner, style: .continuous))
            Image(systemName: "camera.fill")
                .font(.glyph(13, weight: .semibold))
                .foregroundStyle(Hue.surface)
                .frame(width: Metric.badge, height: Metric.badge)
                .background(Hue.ink, in: Circle())
                .overlay { Circle().strokeBorder(Hue.paper, lineWidth: 2) }
                .offset(x: 6, y: 6)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.sans(13))
            .foregroundStyle(Hue.inkSecondary)
            .padding(.horizontal, 4)
            .padding(.top, 4)
    }

    private func chip(_ kind: String) -> some View {
        let on = draft.kind == kind
        return Button {
            Haptics.selection()
            draft.kind = on ? nil : kind
        } label: {
            Text(kind)
                .font(.sans(15))
                .foregroundStyle(on ? Hue.surface : Hue.ink)
                .padding(.horizontal, 14)
                .frame(height: Metric.chip)
                .background(on ? Hue.ink : Hue.fill, in: Capsule())
        }
        .buttonStyle(.press(.squish))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// The photo first (its name carries the Group's id), then the Group; its checks start without waiting. A
    /// failure keeps everything as it was and shakes Create. A new id each try: a photo sent before a failed
    /// start is never sent again over itself.
    private func create() async {
        guard draft.ready, !saving else { return }
        naming = false
        saving = true
        defer { saving = false }
        let api = CommunityAPI(auth: AuthStore.shared)
        let id = UUID().uuidString.lowercased()
        do {
            var photo: URL?
            if let image, let jpeg = ProfileModel.coverJPEG(image) { photo = try await api.uploadGroupPhoto(jpeg, id: id) }
            try await api.startGroup(id: id, name: draft.cleanName, kind: draft.kind, photo: photo)
            Task { await api.checkNewGroup(id) }
            var group = TownGroup(id: id, name: draft.cleanName, kind: draft.kind,
                                  photos: photo.map { [PlacePicture(url: $0, kind: .photo)] } ?? [], memberCount: 1)
            group.joined = true
            group.status = "pending"
            group.imageUrl = photo
            actions.read([group])
            Haptics.success()
            withAnimation(reduceMotion ? nil : Motion.smooth) { made = group }
        } catch {
            Log.network("StartGroupSheet: couldn't start \(id): \(error)")
            Haptics.error()
            failures += 1
        }
    }

    private func finish(_ group: TownGroup) {
        dismiss()
        Task {
            if let groups = await you.refreshGroups() { actions.read(groups) }
        }
        started(group)
    }
}

/// Invite friends, right after Create: Share link, then your friends with checks, and one pill that sends the
/// invites (or closes when none are checked).
struct InviteFriendsView: View {
    let group: TownGroup
    let done: () -> Void

    @Environment(FriendsBook.self) private var book
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var picked: Set<String> = []
    @State private var words = ""
    @State private var sending = false
    @State private var failures = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    shareRow
                    if !book.friends.isEmpty {
                        TextField("Search friends", text: $words)
                            .font(.sans(16))
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(Hue.fill, in: RoundedRectangle(cornerRadius: Radius.searchField, style: .continuous))
                            .padding(.horizontal, FriendsMetric.side)
                            .padding(.vertical, 8)
                        ForEach(shown) { friendRow($0) }
                    }
                }
                .padding(.bottom, GroupPage.Metric.pillHeight + 48)
            }
            Button(action: send) {
                Text(picked.isEmpty ? "Done" : "Invite \(picked.count)")
                    .font(.displaySemi(18))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MeetupPillStyle(height: GroupPage.Metric.pillHeight, minWidth: 0))
            .disabled(sending)
            .turnBackShake(failures: failures, shakes: !reduceMotion)
            .padding(.horizontal, GroupPage.Metric.pillSide)
            .padding(.bottom, 8)
        }
        .background(Hue.paper.ignoresSafeArea())
        .navigationTitle("Invite friends")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .task { if !book.loaded { await book.refresh() } }
    }

    private var shown: [Neighbor] {
        let w = words.trimmingCharacters(in: .whitespaces)
        return w.isEmpty ? book.friends : book.friends.filter { $0.displayName.localizedCaseInsensitiveContains(w) }
    }

    private var shareRow: some View {
        Button {
            ShareCenter.shared.present(.group(group))
        } label: {
            HStack(spacing: FriendsMetric.avatarGap) {
                Image(systemName: "square.and.arrow.up")
                    .font(.glyph(20, weight: .medium))
                    .foregroundStyle(Hue.ink)
                    .frame(width: FriendsMetric.neighborFace, height: FriendsMetric.neighborFace)
                    .background(Hue.fill, in: Circle())
                Text("Share link").font(.sansSemibold(16)).foregroundStyle(Hue.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, FriendsMetric.side)
            .frame(height: FriendsMetric.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.press(.dim))
    }

    private func friendRow(_ person: Neighbor) -> some View {
        let on = picked.contains(person.id)
        return Button {
            Haptics.selection()
            if on { picked.remove(person.id) } else { picked.insert(person.id) }
        } label: {
            HStack(spacing: FriendsMetric.avatarGap) {
                Avatar(avatarUrl: person.avatarUrl, size: FriendsMetric.neighborFace, outlined: true)
                Text(person.displayName).font(.sansSemibold(16)).foregroundStyle(Hue.ink).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.glyph(24, weight: .regular))
                    .foregroundStyle(on ? Hue.ink : Hue.hairline)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, FriendsMetric.side)
            .frame(height: FriendsMetric.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.press(.dim))
        .accessibilityLabel(person.displayName)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func send() {
        guard !picked.isEmpty else { return done() }
        sending = true
        Task {
            defer { sending = false }
            do {
                try await CommunityAPI(auth: AuthStore.shared).inviteToGroup(group.id, friends: Array(picked))
                Haptics.success()
                done()
            } catch {
                Haptics.error()
                failures += 1
            }
        }
    }
}
