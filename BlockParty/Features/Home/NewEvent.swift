//
//  NewEvent.swift
//  Block Party — New event, from the Town bar's + (BP app references/town-plus, Jesse 2026-11-01):
//  Instagram's New post, step for step. A photo from Apple's own picker (or none), then the name,
//  the day and time and the place, then Share. Share posts it pending and runs the instant check
//  (`moderate-post` `submit`): live, declined with the reason under Share, or, when the check
//  can't answer, waiting for Jesse's Review.
//

import PhotosUI
import SwiftUI

// MARK: - What Share sends

/// The form as Share reads it. Pure, so a test reads what goes out without a network.
nonisolated struct NewEventDraft: Equatable {
    /// A name is a line on a card; a place, a line under it.
    static let nameLimit = 100
    static let placeLimit = 120

    var name = ""
    var when: Date
    var place = ""

    init(now: Date = Date()) { when = Self.defaultWhen(now: now) }

    var title: String { String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.nameLimit)) }
    var location: String { String(place.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.placeLimit)) }
    var ready: Bool { !title.isEmpty && !location.isEmpty }

    /// Tonight at 7 in the town, or tomorrow at 7 once that's past. PICKED: when most
    /// neighbours' evenings start.
    static func defaultWhen(now: Date) -> Date {
        let seven = Town.gregorian.date(bySettingHour: 19, minute: 0, second: 0, of: now) ?? now
        return seven > now ? seven : Town.gregorian.date(byAdding: .day, value: 1, to: seven) ?? seven
    }

    /// "19:00", the Town's clock. The feed reads 24-hour time; Apple's "7:00 PM" carries a narrow
    /// no-break space its reader doesn't take (`start_minutes`, migration 20261026182034).
    static func clock(_ date: Date) -> String {
        let c = Town.gregorian.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    func input(id: String, imageURL: String?) -> NewEventInput {
        NewEventInput(id: id, title: title, eventDate: Town.day(when), startTime: Self.clock(when),
                      location: location, imageUrl: imageURL)
    }
}

/// The instant check's answer on a new Event.
nonisolated enum NewEventCheck: Equatable {
    case live
    /// No, and why, in words the poster can act on.
    case declined(String)
    /// It couldn't answer (the day's 10 used, the model down, no network): the Event waits for
    /// Jesse's Review, and goes up once it's checked.
    case waiting
}

enum NewEventCopy {
    static let title = "New event"
    static let next = "Next"
    static let name = "Name your event…"
    static let when = "Day and time"
    static let place = "Place"
    static let addPlace = "Add"
    static let share = "Share"
    static let offline = "Couldn't share. Check your connection and try again."
    static let live = "Your event is live"
    static let waiting = "Shared. It goes up once it's checked."
    static let discard = "Discard event?"
    static let discardWhy = "If you leave now, you'll lose what you've added."
    static let discardButton = "Discard"
}

// MARK: - The model

@MainActor @Observable
final class NewEventModel {
    var draft = NewEventDraft()
    var photo: UIImage?
    private(set) var sharing = false
    /// The check's no, or why it couldn't send, under Share.
    var problem: String?
    /// Each failed Share: Share shakes once for each (buttons-and-pills.md, 2026-09-27).
    private(set) var failures = 0

    /// Something to lose: a swipe down or the X asks first.
    var edited: Bool { photo != nil || !draft.title.isEmpty || !draft.location.isEmpty }

    /// One id for every try at one Event, so a retry finishes it rather than starting another;
    /// a new one after a no, since a declined Event stays declined.
    private(set) var id = UUID().uuidString.lowercased()
    /// Where its photo went, once sent.
    private(set) var photoURL: String?
    private var posted = false

    /// Posts it once, then asks the check. nil while it couldn't send at all.
    func share(api: CommunityAPI) async -> NewEventCheck? {
        guard draft.ready, !sharing else { return nil }
        sharing = true
        problem = nil
        defer { sharing = false }
        do {
            if !posted {
                if let photo, photoURL == nil {
                    guard let data = ProfileModel.coverJPEG(photo) else { throw CocoaError(.fileReadCorruptFile) }
                    photoURL = try await Self.once { try await api.uploadEventPhoto(data, id: id) }?.absoluteString
                        ?? api.eventPhotoURL(id: id)?.absoluteString
                }
                try await Self.once { try await api.addEvent(draft.input(id: id, imageURL: photoURL)) }
                posted = true
            }
        } catch {
            fail(NewEventCopy.offline)
            return nil
        }
        let check = await api.checkNewEvent(id)
        if case .declined(let reason) = check {
            fail(reason)
            id = UUID().uuidString.lowercased()
            photoURL = nil
            posted = false
        }
        return check
    }

    /// A send that may already have landed: an answer lost on the way back leaves the photo or
    /// the Event saved, and the retry is told it already exists. That counts as sent; nil then.
    private static func once<T>(_ send: () async throws -> T) async throws -> T? {
        do { return try await send() } catch let error as SupabaseError where error.alreadyThere { return nil }
    }

    private func fail(_ words: String) {
        problem = words
        failures += 1
        Haptics.error()
        AccessibilityNotification.Announcement(words).post()
    }

    /// What the pill and the bell keep of it.
    func posted(live: Bool) -> HelloItem.Posted {
        HelloItem.Posted(eventId: id, title: draft.title, photo: photoURL.flatMap(URL.init(string:)), live: live,
                         eventDate: Town.day(draft.when), startTime: NewEventDraft.clock(draft.when), location: draft.location)
    }

    /// A new photo: the one already sent belonged to the last.
    func pick(_ image: UIImage?) {
        photo = image
        if !posted { photoURL = nil }
    }
}

// MARK: - The sheet

struct NewEventSheet: View {
    /// The town's places, from Search's read, for Place.
    let places: [SearchItem]
    /// What Share left: the shell's pill says it, and Town reads again.
    var onShared: (HelloItem.Posted) -> Void = { _ in }

    @State private var model = NewEventModel()
    @State private var pick: PhotosPickerItem?
    @State private var path: [Step] = []
    @State private var discarding = false
    @Environment(\.dismiss) private var dismiss

    enum Step: Hashable { case details, place }

    var body: some View {
        NavigationStack(path: $path) {
            // Apple's own picker, inside the sheet as Instagram's grid is; its own Cancel and Add
            // are off, so the bar's X and Next are the only buttons.
            PhotosPicker(selection: $pick, matching: .images, photoLibrary: .shared()) { EmptyView() }
                .photosPickerStyle(.inline)
                .photosPickerDisabledCapabilities(.selectionActions)
                .photosPickerAccessoryVisibility(.hidden, edges: .all)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(NewEventCopy.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { if model.edited { discarding = true } else { dismiss() } } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Close")
                            // Instagram asks before a post with edits goes.
                            .confirmationDialog(NewEventCopy.discard, isPresented: $discarding, titleVisibility: .visible) {
                                Button(NewEventCopy.discardButton, role: .destructive) { dismiss() }
                            } message: { Text(NewEventCopy.discardWhy) }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(NewEventCopy.next) { path.append(.details) }
                            .fontWeight(.semibold)
                    }
                }
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .details: NewEventDetails(model: model, share: share, choosePlace: { path.append(.place) })
                    case .place: NewEventPlace(places: places, place: $model.draft.place)
                    }
                }
        }
        .tint(Hue.ink)
        .onChange(of: pick) { _, item in
            Task {
                let data = try? await item?.loadTransferable(type: Data.self)
                model.pick(data.flatMap(UIImage.init(data:)))
            }
        }
        // A swipe down can't throw away what's typed or picked; the X asks first.
        .interactiveDismissDisabled(model.sharing || model.edited)
        #if DEBUG
        // `-new-event-photo <file>`: a bundled photo as if picked; AXe can't reach Apple's picker.
        .onAppear { if let name = LaunchFlags.value(.newEventPhoto) { model.pick(UIImage(named: name)) } }
        #endif
    }

    private func share() {
        Task {
            guard let check = await model.share(api: CommunityAPI(auth: AuthStore.shared)) else { return }
            switch check {
            case .declined: return
            case .live, .waiting:
                onShared(model.posted(live: check == .live))
                dismiss()
            }
        }
    }
}

/// Instagram's New post, after the photo: the photo, the name, the rows, Share at the foot.
private struct NewEventDetails: View {
    @Bindable var model: NewEventModel
    let share: () -> Void
    let choosePlace: () -> Void
    @FocusState private var naming: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let photo = model.photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: NewEventMetric.photoWidth(photo.size), height: NewEventMetric.photoHeight)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.newEventPhoto, style: .continuous))
                        .padding(.top, NewEventMetric.photoTop)
                        .accessibilityLabel("Your photo")
                }
                TextField(NewEventCopy.name, text: $model.draft.name, axis: .vertical)
                    .font(.apple(16))
                    .foregroundStyle(Hue.ink)
                    .lineLimit(1...3)
                    .focused($naming)
                    .submitLabel(.done)
                    .onChange(of: model.draft.name) { _, name in
                        if name.contains("\n") { model.draft.name = name.replacingOccurrences(of: "\n", with: ""); naming = false }
                        if name.count > NewEventDraft.nameLimit { model.draft.name = String(name.prefix(NewEventDraft.nameLimit)) }
                        model.problem = nil
                    }
                    .padding(.top, NewEventMetric.nameTop)
                    .padding(.bottom, NewEventMetric.nameBottom)
                row(label: NewEventCopy.when, icon: {
                    Image(systemName: "calendar").font(.glyph(NewEventMetric.symbol))
                }) {
                    DatePicker(NewEventCopy.when, selection: $model.draft.when, in: Date()...,
                               displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        // The town's clock, as Share sends it: a phone away from home picks St. Joseph's 7 PM.
                        .environment(\.timeZone, Town.timeZone)
                        // The keyboard goes at touch-down, before the calendar opens: dropped on the tap's
                        // end, iOS handed it back when the calendar closed (recorded 2026-11-01).
                        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in naming = false })
                }
                Button { naming = false; choosePlace() } label: {
                    row(label: NewEventCopy.place, icon: { MapPinGlyph(size: NewEventMetric.icon) }) {
                        HStack(spacing: 8) {
                            Text(model.draft.location.isEmpty ? NewEventCopy.addPlace : model.draft.location)
                                .font(.apple(17))
                                .foregroundStyle(model.draft.location.isEmpty ? Hue.inkSecondary : Hue.ink)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.apple(15, weight: .semibold))
                                .foregroundStyle(Hue.control)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.98))
            }
            .padding(.horizontal, NewEventMetric.side)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) { foot }
        .navigationTitle(NewEventCopy.title)
        .navigationBarTitleDisplayMode(.inline)
        .background(Hue.surface)
        .onAppear { if model.draft.name.isEmpty { naming = true } }
    }

    /// The check's no sits over Share, where the eye already is.
    private var foot: some View {
        VStack(alignment: .leading, spacing: NewEventMetric.problemGap) {
            if let problem = model.problem {
                Text(problem)
                    .font(.apple(15))
                    .foregroundStyle(Hue.declined)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            Button(action: share) {
                ZStack {
                    Text(NewEventCopy.share).opacity(model.sharing ? 0 : 1)
                    // The one spinner a control may carry: its own action in flight (design.md).
                    if model.sharing { ProgressView().tint(Hue.paper) }
                }
                .font(.apple(15, weight: .semibold))
                .foregroundStyle(model.draft.ready ? Hue.paper : Hue.inkSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: NewEventMetric.shareHeight)
                .background(model.draft.ready ? Hue.ink : Hue.fill,
                            in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.97, haptic: model.draft.ready))
            .turnBackShake(failures: model.failures, shakes: !reduceMotion)
            .disabled(!model.draft.ready || model.sharing)
            .accessibilityLabel(model.sharing ? "Sharing" : NewEventCopy.share)
        }
        .animation(.easeOut(duration: 0.18), value: model.problem)
        .padding(.horizontal, NewEventMetric.side)
        .padding(.top, NewEventMetric.problemGap)
        .padding(.bottom, NewEventMetric.shareBottom)
        .background(Hue.surface)
    }

    /// Instagram's row: a 24 pt outline icon, the label, what it's set to at the right.
    private func row<Icon: View, Trailing: View>(label: String, @ViewBuilder icon: () -> Icon,
                                                 @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: NewEventMetric.iconGap) {
            icon()
                .frame(width: NewEventMetric.icon, height: NewEventMetric.icon)
                .accessibilityHidden(true)
            Text(label).font(.apple(17))
            Spacer(minLength: 8)
            trailing()
        }
        .foregroundStyle(Hue.ink)
        .frame(minHeight: NewEventMetric.row)
    }
}

/// Facebook's Add location: Search's field over the town's places; a name not among them is used
/// as typed. Not `.searchable`: chosen while its field was still active, the search stayed up as a
/// bar over Share on the page underneath (recorded 2026-11-01).
private struct NewEventPlace: View {
    let places: [SearchItem]
    @Binding var place: String
    @State private var words = ""
    @Environment(\.dismiss) private var dismiss

    private var typed: String { words.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var matches: [SearchItem] {
        guard !typed.isEmpty else { return places }
        return places.filter { $0.name.localizedStandardContains(typed) || ($0.sub?.localizedStandardContains(typed) ?? false) }
    }

    var body: some View {
        // The list is the page's scroll, under the bar; the field rides on top of it. As a plain
        // view above the list, the bar lost its title and its back button went dark (recorded).
        list
            .safeAreaInset(edge: .top, spacing: 0) {
                FriendsSearchField(words: $words)
                    .padding(.horizontal, NewEventMetric.side)
                    .padding(.vertical, NewEventMetric.searchPad)
                    .background(Hue.surface)
            }
            .navigationTitle(NewEventCopy.place)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var list: some View {
        List {
            if !typed.isEmpty, !places.contains(where: { $0.name.localizedCaseInsensitiveCompare(typed) == .orderedSame }) {
                Button { choose(typed) } label: {
                    placeRow(name: typed, sub: "Use this name") { tile(glyph: "plus") }
                }
                .listRowInsets(NewEventMetric.placeInsets)
            }
            ForEach(matches) { item in
                Button { choose(item.name) } label: {
                    placeRow(name: item.name, sub: item.sub) {
                        if let logo = item.logo { CastLogo(logo: logo, side: NewEventMetric.placeMark) } else { tile(glyph: item.glyph) }
                    }
                }
                .listRowInsets(NewEventMetric.placeInsets)
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
    }

    private func choose(_ name: String) {
        place = String(name.prefix(NewEventDraft.placeLimit))
        dismiss()
    }

    private func placeRow<Mark: View>(name: String, sub: String?, @ViewBuilder mark: () -> Mark) -> some View {
        HStack(spacing: NewEventMetric.iconGap) {
            mark().frame(width: NewEventMetric.placeMark, height: NewEventMetric.placeMark)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.apple(16, weight: .medium)).foregroundStyle(Hue.ink).lineLimit(1)
                if let sub { Text(sub).font(.apple(14)).foregroundStyle(Hue.inkSecondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: NewEventMetric.placeRow)
        .contentShape(Rectangle())
    }

    private func tile(glyph: String) -> some View {
        Circle().fill(Hue.fill)
            .overlay { Image(systemName: glyph).font(.glyph(17)).foregroundStyle(Hue.inkSecondary) }
            .accessibilityHidden(true)
    }
}

/// Instagram's New post, MEASURED on Mobbin (2026-11-01, BP app references/town-plus/ig-new-post.jpg):
/// 16 pt sides, the photo 140 pt tall 20 pt under the bar, rows 48 pt with a 24 pt icon and the
/// label at 52, Share 43 pt tall. Facebook's Add location rows for Place.
private nonisolated enum NewEventMetric {
    static let side: CGFloat = 16
    static let photoTop: CGFloat = 20
    static let photoHeight: CGFloat = 140
    /// The photo keeps its shape at 140 tall, as Instagram's does, no wider than the page.
    static func photoWidth(_ size: CGSize) -> CGFloat {
        guard size.height > 0 else { return photoHeight }
        return min(photoHeight * size.width / size.height, 361)
    }
    static let nameTop: CGFloat = 24
    static let nameBottom: CGFloat = 28
    static let row: CGFloat = 48
    static let icon: CGFloat = 24
    /// SF's calendar at 21 fills the same 24 pt box the pin does.
    static let symbol: CGFloat = 21
    static let iconGap: CGFloat = 12
    static let shareHeight: CGFloat = 43
    static let shareBottom: CGFloat = 8
    static let problemGap: CGFloat = 12
    static let placeMark: CGFloat = 40
    static let placeRow: CGFloat = 56
    static let searchPad: CGFloat = 8
    /// Facebook's Add location rows: 16 pt in, the list's own dividers between.
    static let placeInsets = EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)
}
