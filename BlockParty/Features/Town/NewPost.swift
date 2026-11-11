//
//  NewPost.swift
//  Block Party — New post, from the Town bar's + (BP app references/post-screen, town-feed 29; Jesse
//  2026-11-01: draft 1, Facebook's, "yes to all and start"). A neighbour's own words, maybe one photo,
//  a Place and the friends they're with, Public or only their Friends. Post saves it pending and
//  the sheet closes; the instant check (`moderate-post` `submit`) answers on Town, where it waits faded
//  until it's up. The Event chip makes it town-plus's New event instead: a name, a day and time and a
//  Place, shared as an Event, the sheet waiting for the check.
//

import PhotosUI
import SwiftUI

// MARK: - What an Event sends

/// New post's Event (the Event chip) as Post reads it, town-plus's New event. Pure, so a test reads what goes out without a network.
nonisolated struct NewEventDraft: Equatable {
    /// A name is a line on a card; a place, a line under it.
    static let nameLimit = 100
    static let placeLimit = 120
    /// Places in all, the first one's included (BP app town-feed 54; Jesse: "yes" to 5).
    static let placesLimit = 5

    var name = ""
    var when: Date
    var place = ""
    /// The places after the first, in the order picked (BP app town-feed 54): `club_events.more_places`.
    var morePlaces: [String] = []
    /// New post's words, as its description.
    var about = ""
    /// Filter (BP app town-feed 52): who it's for, by gender and age. Nothing picked is everyone.
    var gender: EventGender?
    var ages = EventAges()

    init(now: Date = Date()) { when = Self.defaultWhen(now: now) }

    var title: String { String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.nameLimit)) }
    var location: String { String(place.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.placeLimit)) }
    var ready: Bool { !title.isEmpty && !location.isEmpty }
    /// The places after the first as they go out: trimmed, each once (the first place's name included), at most 4.
    var extraPlaces: [String] { Self.extra(after: location, morePlaces) }

    static func extra(after first: String, _ more: [String]) -> [String] {
        var seen: Set<String> = [first.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
        var out: [String] = []
        for name in more {
            let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(placeLimit))
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { continue }
            out.append(name)
        }
        return Array(out.prefix(placesLimit - 1))
    }

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
        let about = about.trimmingCharacters(in: .whitespacesAndNewlines)
        return NewEventInput(id: id, title: title, eventDate: Town.day(when), startTime: Self.clock(when),
                             location: location, description: about.isEmpty ? nil : String(about.prefix(NewPostDraft.wordsLimit)),
                             imageUrl: imageURL, forGender: gender?.rawValue, ages: ages.words, morePlaces: extraPlaces)
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
    static let when = "Day and time"
    static let place = "Place"
    static let addPlace = "Add"
    static let anotherPlace = "Add another place"
    static let offline = "Couldn't share. Check your connection and try again."
    static let live = "Your event is live"
    static let waiting = "Shared. It goes up once it's checked."
}

/// Place's list (Jesse, 2026-11-01: "Parks and places to eat or drink, then the rest"): Search's
/// parks, food, coffee and businesses, the likely ones first, A–Z inside each.
enum NewEventPlaces {
    static func ordered(_ items: [SearchItem]) -> [SearchItem] {
        items.filter { [.business, .restaurant, .coffee, .park].contains($0.kind) }
            .sorted { a, b in
                let (ea, eb) = (likely(a), likely(b))
                return ea != eb ? ea : a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
    }

    /// A park, somewhere to eat, coffee, or a business Google calls a bar, brewery, pub, winery or
    /// distillery.
    // ponytail: drink places are read off Google's type words; one typed otherwise sorts with the rest.
    static func likely(_ item: SearchItem) -> Bool {
        item.kind != .business || item.keywords.contains { !Set($0.split(separator: " ").map(String.init)).isDisjoint(with: drink) }
    }

    private static let drink: Set<String> = ["bar", "brewery", "brewpub", "pub", "taproom", "winery", "distillery"]
}

// MARK: - The Event's model

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
    static func once<T>(_ send: () async throws -> T) async throws -> T? {
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


// MARK: - What Post sends

/// New post's words, who sees it, who it's with and where, as Post reads them (BP app town-feed 29).
/// Pure, so a test reads what goes out without a network.
struct NewPostDraft: Equatable {
    /// As much as the check reads (claim_submit's 2,000).
    nonisolated static let wordsLimit = 2000
    /// Facebook's big words: while short, with no photo.
    static let bigUntil = 85
    /// claim_submit keeps 20.
    static let tagLimit = 20

    var words = ""
    var friendsOnly = false
    var tagged: [Neighbor] = []
    /// The friends and places picked from the `@` row, in the order picked (town-feed 60).
    var atNames: [AtName] = []
    var place = ""
    /// An Event's places after the first (BP app town-feed 54); a post keeps one place.
    var morePlaces: [String] = []

    /// The round + after Place: a first place is picked and there's room for another.
    var canAddPlace: Bool {
        location != nil && NewEventDraft.extra(after: location ?? "", morePlaces).count < NewEventDraft.placesLimit - 1
    }

    /// Another place picked after the + (the same Place list): a new name lands last, one already there doesn't.
    mutating func addPlace(_ name: String) {
        guard canAddPlace else { return }
        let next = NewEventDraft.extra(after: location ?? "", morePlaces + [name])
        morePlaces = next
    }

    var text: String { String(words.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.wordsLimit)) }
    var location: String? {
        let place = String(place.trimmingCharacters(in: .whitespacesAndNewlines).prefix(NewEventDraft.placeLimit))
        return place.isEmpty ? nil : place
    }

    /// Words or a photo: Post lights up.
    func ready(photo: Bool) -> Bool { photo || !text.isEmpty }

    /// A pick from the `@` row (town-feed 60): "@Name " in place of what was typed from the `@`, and the name kept
    /// once. Returns where the cursor goes, just after it.
    mutating func pick(_ name: AtName, replacing range: Range<String.Index>) -> String.Index {
        let typed = name.typed + " "
        let start = words.distance(from: words.startIndex, to: range.lowerBound)
        words.replaceSubrange(range, with: typed)
        if !atNames.contains(where: { $0.kind == name.kind && $0.id == name.id }) { atNames.append(name) }
        return words.index(words.startIndex, offsetBy: min(start + typed.count, words.count))
    }

    /// The picked names still in the words, as Post sends them.
    var keptNames: [AtName] { atNames.filter { text.contains($0.typed) } }

    /// 24 pt while short with no photo, 17 once longer or with one (round 2).
    func big(photo: Bool) -> Bool { !photo && words.count <= Self.bigUntil }

    /// The name line, Facebook's: "Jesse is with Sam Lee at Sal's."
    func line(name: String) -> String { TownPost.line(name: name, with: tagged.map(\.displayName), at: location) }

    func input(id: String, imageURL: String?, aspect: Double?) -> NewPostInput {
        NewPostInput(id: id, words: text, imageURL: imageURL, aspect: imageURL == nil ? nil : aspect, place: location,
                     friendsOnly: friendsOnly, tagged: tagged.map(\.userId), atNames: keptNames)
    }

    /// A photo's shape inside Instagram's limits: 4:5 tall to 1.91:1 wide.
    static func aspect(_ size: CGSize) -> Double {
        guard size.width > 0, size.height > 0 else { return 1 }
        return min(max(Double(size.width / size.height), 4.0 / 5.0), 1.91)
    }

    /// The part of a photo inside those limits, cut from its middle, as the card will show it.
    static func cropRect(_ size: CGSize) -> CGRect {
        let aspect = CGFloat(aspect(size))
        guard size.width > 0, size.height > 0 else { return CGRect(origin: .zero, size: size) }
        if size.width / size.height > aspect {
            let width = (size.height * aspect).rounded(.down)
            return CGRect(x: ((size.width - width) / 2).rounded(.down), y: 0, width: width, height: size.height)
        }
        let height = (size.width / aspect).rounded(.down)
        return CGRect(x: 0, y: ((size.height - height) / 2).rounded(.down), width: size.width, height: height)
    }
}

// MARK: - New post's model

@MainActor @Observable
final class NewPostModel {
    var draft = NewPostDraft()
    /// The photo, already cut to its card's shape.
    private(set) var photo: UIImage?
    /// The Event chip: Post shares an Event exactly as town-plus's Share did.
    var event = false
    /// The Event's name, day and time; its Place and photo are New post's own.
    let eventModel = NewEventModel()
    private(set) var saving = false
    /// Why it couldn't send, over Post.
    var problem: String?
    private(set) var failures = 0

    /// One id for every try at one post, so a retry finishes it rather than posting it twice.
    private(set) var id = UUID().uuidString.lowercased()

    var edited: Bool {
        photo != nil || !draft.text.isEmpty || !draft.tagged.isEmpty || draft.location != nil
            || (event && !eventModel.draft.title.isEmpty)
    }

    var ready: Bool {
        event ? eventModel.draft.ready : draft.ready(photo: photo != nil)
    }

    var busy: Bool { saving || eventModel.sharing }
    var shownProblem: String? { event ? eventModel.problem : problem }
    var shownFailures: Int { failures + eventModel.failures }

    func pick(_ image: UIImage?) {
        photo = image.map(Self.cut)
        eventModel.pick(photo)
        problem = nil
    }

    /// Event on: the Town's, never Friends-only, nobody tagged (Events are the Town's).
    func setEvent(_ on: Bool) {
        event = on
        if on { draft.friendsOnly = false }
    }

    /// A post that didn't go up: its words and photo, and why, with a new id (a declined post
    /// stays declined).
    func restore(_ back: PostOutbox.Back) {
        draft = back.draft
        photo = back.photo
        eventModel.pick(back.photo)
        problem = back.reason
    }

    /// Saves the post: the photo up, the row in, pending. nil while it couldn't (the words stay).
    func save(api: CommunityAPI) async -> NewPostInput? {
        guard ready, !saving else { return nil }
        saving = true
        problem = nil
        defer { saving = false }
        do {
            var url: String?
            if let photo {
                guard let data = ProfileModel.coverJPEG(photo) else { throw CocoaError(.fileReadCorruptFile) }
                url = try await NewEventModel.once { try await api.uploadEventPhoto(data, id: id) }?.absoluteString
                    ?? api.eventPhotoURL(id: id)?.absoluteString
            }
            let input = draft.input(id: id, imageURL: url, aspect: photo.map { NewPostDraft.aspect($0.size) })
            try await NewEventModel.once { try await api.addPost(input) }
            return input
        } catch {
            problem = NewEventCopy.offline
            failures += 1
            Haptics.error()
            AccessibilityNotification.Announcement(NewEventCopy.offline).post()
            return nil
        }
    }

    /// Event on: town-plus's Share, with New post's words as its description.
    func shareEvent(api: CommunityAPI) async -> NewEventCheck? {
        eventModel.draft.place = draft.place
        eventModel.draft.morePlaces = draft.morePlaces
        eventModel.draft.about = draft.words
        return await eventModel.share(api: api)
    }

    /// The photo cut to its card's shape, so what goes up is what the card shows.
    private static func cut(_ image: UIImage) -> UIImage {
        let rect = NewPostDraft.cropRect(image.size)
        guard rect.size != image.size else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: rect.size, format: format).image { _ in
            image.draw(at: CGPoint(x: -rect.minX, y: -rect.minY))
        }
    }
}

// MARK: - Posting…

/// A post on its way (round 2, step 9): saved, waiting on the instant check, faded at the top of Town.
/// A yes and it's the feed's own card; a no turns it "This post didn't go up", and a tap reopens New post
/// with the words kept and why; no answer (the day's 10, the check down) leaves it "Waiting for review". Nothing
/// pops up (taste.md: updates never pop up).
@MainActor @Observable
final class PostOutbox {
    static let shared = PostOutbox()

    enum State: Equatable { case posting, notPosted(String), waiting }

    struct Sent: Identifiable, Equatable {
        let id: String
        let draft: NewPostDraft
        let photo: UIImage?
        let name: String
        let picture: URL?
        var state = State.posting
    }

    /// What a tapped "This post didn't go up" hands back to New post.
    struct Back {
        let draft: NewPostDraft
        let photo: UIImage?
        let reason: String
    }

    private(set) var sent: Sent?
    /// Your post the check just let up: it stays on top of Town for the session, where its faded card was,
    /// instead of landing a card or two down out of sight (the review, 2026-11-02; Facebook's own).
    private(set) var justPosted: String?
    /// Picked up by New post as it opens.
    var back: Back?

    /// The check on a saved post. `live`: the Town reads again, and the faded card goes once it has.
    func check(_ sent: Sent, api: CommunityAPI, live: @escaping () async -> Void) {
        self.sent = sent
        Task {
            let answer = await api.checkNewEvent(sent.id)
            guard self.sent?.id == sent.id else { return }
            switch answer {
            case .live:
                Haptics.success()
                await live()
                if self.sent?.id == sent.id {
                    self.justPosted = sent.id
                    self.sent = nil
                }
            case .declined(let reason):
                self.sent?.state = .notPosted(reason)
                AccessibilityNotification.Announcement("This post didn't go up").post()
            case .waiting:
                self.sent?.state = .waiting
            }
        }
    }

    /// "This post didn't go up" tapped: back into New post.
    func reopen() {
        guard let sent, case .notPosted(let reason) = sent.state else { return }
        back = Back(draft: sent.draft, photo: sent.photo, reason: reason)
        self.sent = nil
    }

    #if DEBUG
    /// `-new-post-state posting|notposted|waiting`: the faded card as it is in each, for a screenshot.
    func sample(_ state: String) {
        var draft = NewPostDraft()
        draft.words = "Burger night at Sal's. Who's in?"
        sent = Sent(id: "sample-post", draft: draft, photo: UIImage(named: "rocktoberfest.jpg"), name: "Jesse", picture: nil,
                    state: state == "notposted" ? .notPosted("Keep it kind.") : state == "waiting" ? .waiting : .posting)
    }
    #endif
}

/// The faded card at the top of Town while a post is on its way: Card A's top (picture, name, words,
/// photo) with "Posting…", "This post didn't go up" or "Waiting for review" under the name.
struct PostingPostCard: View {
    let sent: PostOutbox.Sent
    let reopen: () -> Void

    private var notPosted: Bool { if case .notPosted = sent.state { true } else { false } }

    var body: some View {
        Button(action: reopen) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Avatar(sent.picture, size: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(sent.name).font(.sansSemibold(15)).foregroundStyle(Hue.ink)
                        HStack(spacing: 6) {
                            // The one spinner a control may carry: its own action in flight (design.md).
                            if sent.state == .posting { ProgressView().controlSize(.mini) }
                            Text(status)
                                .font(.sans(13))
                                .foregroundStyle(notPosted ? Hue.declined : Hue.inkSecondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                if !sent.draft.text.isEmpty {
                    Text(sent.draft.text)
                        .font(.sans(16))
                        .lineSpacing(3)
                        .foregroundStyle(Hue.ink)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                }
                if let photo = sent.photo {
                    Image(uiImage: photo)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .clipped()
                        .padding(.top, 10)
                }
            }
            .opacity(notPosted ? 1 : 0.5)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.press(.squish, haptic: notPosted))
        .disabled(!notPosted)
        .accessibilityElement(children: .combine)
        .accessibilityHint(notPosted ? "Opens your post again with why" : "")
    }

    private var status: String {
        switch sent.state {
        case .posting: "Posting…"
        // The words page's `post-refused` (Jesse, 2026-10-12); a tap opens it again with why.
        case .notPosted: "This post didn't go up"
        case .waiting: "Waiting for review"
        }
    }
}

// MARK: - New post

/// Facebook's New post, draft 1 round 2 (BP app references/post-screen, Figma node 10:2; Jesse 2026-11-01:
/// "yes to all and start"): your picture and name line, who can see it, the Tag friends / Place / Event
/// chips, the words big while short, one photo in its own shape, and Post over the keyboard, lit once
/// there's something to post. Post saves it and the sheet closes; the check answers on Town (`PostOutbox`).
/// Event on makes it a plain Event through town-plus's Share, which waits here for the check.
struct NewPostSheet: View {
    /// The town's places, from Search's read, for Place.
    let places: [SearchItem]
    /// Your profile: read here, so a New post opened as you sign in fills them once they're in.
    let me: ProfileModel
    /// An Event shared: the shell's pill says it, and Town reads again (town-plus).
    var onShared: (HelloItem.Posted) -> Void = { _ in }
    /// A post saved: the check runs from the shell.
    var onPosted: (PostOutbox.Sent) -> Void = { _ in }

    @State private var model = NewPostModel()
    @State private var pick: PhotosPickerItem?

    private var name: String { me.displayName }
    private var picture: URL? { me.avatarUrl.flatMap(URL.init(string:)) }
    @State private var picking = false
    @State private var path: [Step] = []
    @State private var discarding = false
    @FocusState private var focus: Field?
    /// Where the cursor is in the words: the `@` row reads what's typed before it (town-feed 60).
    @State private var selection: TextSelection?
    @Environment(FriendsBook.self) private var book
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Step: Hashable { case tag, place, anotherPlace, filter }
    private enum Field: Hashable { case words, name }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    who
                        .padding(.horizontal, NewPostMetric.side)
                        .padding(.top, NewPostMetric.whoTop)
                    chips
                        .padding(.top, NewPostMetric.chipsTop)
                    if model.event {
                        eventFields
                            .padding(.top, NewPostMetric.wordsTop)
                            .transition(.opacity)
                    }
                    words
                        .padding(.horizontal, NewPostMetric.side)
                        .padding(.top, NewPostMetric.wordsTop)
                    if let photo = model.photo {
                        photoView(photo)
                            .padding(.top, NewPostMetric.photoTop)
                            .transition(.opacity)
                    }
                }
                .padding(.bottom, NewPostMetric.side)
                .animation(reduceMotion ? nil : Motion.smooth, value: model.event)
                .animation(reduceMotion ? nil : Motion.smooth, value: model.photo)
                .animation(reduceMotion ? nil : Motion.smooth, value: model.draft.morePlaces)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if let typing, !named(typing.query).isEmpty {
                        AtRow(candidates: named(typing.query)) { pickName($0, replacing: typing.range) }
                            .transition(.opacity)
                    }
                    bar
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: typing?.query)
            }
            .background(Hue.paper)
            .navigationTitle(NewPostCopy.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { if model.edited { discarding = true } else { dismiss() } } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                        // Mid-save, closing would leave a post going up the X said was gone.
                        .disabled(model.busy)
                        .confirmationDialog(NewPostCopy.discard, isPresented: $discarding, titleVisibility: .visible) {
                            Button(NewPostCopy.discardButton, role: .destructive) { dismiss() }
                            Button(NewPostCopy.keepEditing, role: .cancel) {}
                        } message: { Text(NewPostCopy.discardWhy) }
                }
            }
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .tag: NewPostTag(tagged: $model.draft.tagged)
                case .place: NewEventPlace(places: places, place: $model.draft.place)
                // The +: the same list, its pick added after the others rather than replacing the first.
                case .anotherPlace: NewEventPlace(places: places, place: Binding { "" } set: { model.draft.addPlace($0) })
                case .filter: NewEventFilter(gender: Bindable(model.eventModel).draft.gender,
                                             ages: Bindable(model.eventModel).draft.ages)
                }
            }
            .photosPicker(isPresented: $picking, selection: $pick, matching: .images, photoLibrary: .shared())
        }
        .tint(Hue.ink)
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                // Shrunk to what goes up (`coverJPEG`'s 1290 wide) before it's cut: a 48 MP photo
                // never sits whole in memory or gets cut on the main thread.
                if let image = data.flatMap(UIImage.init(data:)) {
                    let k = min(1, NewPostMetric.upload / max(image.size.width * image.scale, 1))
                    let size = CGSize(width: image.size.width * image.scale * k, height: image.size.height * image.scale * k)
                    model.pick(await image.byPreparingThumbnail(ofSize: size) ?? image)
                }
                // The same photo picked again, after the trash, is a change.
                pick = nil
            }
        }
        // A new first place that was one of the others takes that one's row away (the review).
        .onChange(of: model.draft.place) { _, place in
            model.draft.morePlaces = NewEventDraft.extra(after: place, model.draft.morePlaces)
        }
        // A swipe down can't throw away what's typed or picked; the X asks first.
        .interactiveDismissDisabled(model.busy || model.edited)
        .task { if !me.loaded { await me.read() } }
        // Your friends for the `@` row.
        .task { if !book.loaded { await book.refresh() } }
        .onAppear {
            if let back = PostOutbox.shared.back {
                model.restore(back)
                PostOutbox.shared.back = nil
            } else {
                #if DEBUG
                // `-new-event-photo <file>`: a bundled photo as if picked; AXe can't reach Apple's picker.
                if let file = LaunchFlags.value(.newEventPhoto) { model.pick(UIImage(named: file)) }
                // `-new-post-words <words>`: typed, as AXe can't type on BP Build, the cursor at their end, so
                // words ending "@b" show the `@` row.
                if let words = LaunchFlags.value(.newPostWords) {
                    model.draft.words = words
                    selection = TextSelection(insertionPoint: model.draft.words.endIndex)
                }
                // `-new-event-places "A|B|C"`: Event on with these places picked, the first as Place.
                if let names = LaunchFlags.value(.newEventPlaces)?.split(separator: "|").map(String.init), let first = names.first {
                    model.setEvent(true)
                    model.eventModel.draft.name = "Stitch and Sip crawl"
                    model.draft.place = first
                    names.dropFirst().forEach { model.draft.addPlace($0) }
                }
                #endif
            }
            focus = .words
        }
    }

    // MARK: Who

    /// Your picture, the name line, and who can see it.
    private var who: some View {
        HStack(spacing: NewPostMetric.whoGap) {
            Avatar(picture, size: NewPostMetric.picture)
            VStack(alignment: .leading, spacing: NewPostMetric.pillTop) {
                Text(nameLine)
                    .foregroundStyle(Hue.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(nil, value: model.draft.tagged)
                audience
            }
        }
    }

    private var nameLine: AttributedString {
        var line = AttributedString(model.draft.line(name: name))
        line.font = .sans(17)
        let tagged = model.draft.tagged.map(\.displayName)
        let named = tagged.count > 2 ? [tagged[0], "\(tagged.count - 1) others"] : tagged
        for bold in [name] + named + [model.draft.location ?? ""] where !bold.isEmpty {
            if let range = line.range(of: bold) { line[range].font = .sansSemibold(17) }
        }
        return line
    }

    /// Facebook's audience pill: Public or Friends, from Apple's menu. Event on locks it to Public.
    private var audience: some View {
        Menu {
            Picker(NewPostCopy.who, selection: $model.draft.friendsOnly) {
                Label(NewPostCopy.everyone, systemImage: "globe.americas").tag(false)
                Label(NewPostCopy.friends, systemImage: "person.2").tag(true)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: model.draft.friendsOnly ? "person.2.fill" : "globe.americas.fill")
                    .font(.glyph(12, weight: .semibold))
                Text(model.draft.friendsOnly ? NewPostCopy.friends : NewPostCopy.everyone)
                    .font(.apple(13, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.glyph(10, weight: .bold))
                    .opacity(model.event ? 0 : 1)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Hue.ink)
            .padding(.leading, 9)
            .padding(.trailing, 8)
            .frame(height: NewPostMetric.pill)
            .background(Hue.fill, in: Capsule())
            // 26 pt drawn, 44 pt to tap.
            .padding(.vertical, (NewPostMetric.tap - NewPostMetric.pill) / 2)
            .contentShape(Rectangle())
        }
        .padding(.vertical, -(NewPostMetric.tap - NewPostMetric.pill) / 2)
        .disabled(model.event)
        .accessibilityLabel(NewPostCopy.who)
        .accessibilityValue(model.draft.friendsOnly ? NewPostCopy.friends : NewPostCopy.everyone)
    }

    // MARK: Chips

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: NewPostMetric.chipGap) {
                if !model.event {
                    let tagged = model.draft.tagged
                    chip(on: !tagged.isEmpty, label: tagged.isEmpty ? NewPostCopy.tag
                                                     : tagged.count == 1 ? tagged[0].displayName
                                                     : "\(tagged[0].firstName) +\(tagged.count - 1)") {
                        if let first = tagged.first {
                            Avatar(first.avatarUrl.flatMap(URL.init(string:)), size: NewPostMetric.chipFace)
                        } else {
                            Image(systemName: "tag").font(.glyph(15))
                        }
                    } action: { focus = nil; path.append(.tag) }
                    .transition(.opacity)
                }
                chip(on: model.draft.location != nil, label: model.draft.location ?? NewEventCopy.place) {
                    MapPinGlyph(size: NewPostMetric.chipIcon)
                } action: { focus = nil; path.append(.place) }
                chip(on: model.event, label: NewPostCopy.event) {
                    Image(systemName: "calendar").font(.glyph(15))
                } action: {
                    withAnimation(reduceMotion ? nil : Motion.smooth) { model.setEvent(!model.event) }
                    focus = model.event ? .name : .words
                }
                .accessibilityAddTraits(model.event ? .isSelected : [])
            }
            .padding(.horizontal, NewPostMetric.side)
        }
        .scrollClipDisabled()
    }

    /// 34 pt drawn, 44 pt to tap; picked ones fill grey with the pick inside.
    private func chip<Icon: View>(on: Bool, label: String, @ViewBuilder icon: () -> Icon,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                icon().frame(width: NewPostMetric.chipFace, height: NewPostMetric.chipFace)
                Text(label).font(.sansMedium(14)).lineLimit(1)
            }
            .foregroundStyle(Hue.ink)
            .padding(.leading, on ? 6 : 10)
            .padding(.trailing, 14)
            .frame(height: NewPostMetric.chip)
            .background {
                Capsule().fill(on ? Hue.fill : Hue.surface)
                    .overlay { Capsule().strokeBorder(Hue.hairline, lineWidth: on ? 0 : 1) }
            }
            .padding(.vertical, (NewPostMetric.tap - NewPostMetric.chip) / 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.press(.squish))
        .padding(.vertical, -(NewPostMetric.tap - NewPostMetric.chip) / 2)
    }

    // MARK: Words

    private var words: some View {
        let big = !model.event && model.draft.big(photo: model.photo != nil)
        return TextField(model.event ? NewPostCopy.about : NewPostCopy.placeholder, text: $model.draft.words,
                         selection: $selection, axis: .vertical)
            .font(.sans(big ? NewPostMetric.bigWords : NewPostMetric.words))
            .foregroundStyle(Hue.ink)
            .focused($focus, equals: .words)
            .onChange(of: model.draft.words) { was, words in
                if words.count > NewPostDraft.wordsLimit { model.draft.words = String(words.prefix(NewPostDraft.wordsLimit)) }
                // An edit clears why it wasn't posted; the words coming back with it don't.
                if !was.isEmpty { model.problem = nil }
            }
    }

    // MARK: @ names (town-feed 60)

    /// The `@` typed before the cursor in a post's words; never with Event on (an Event's About takes none).
    private var typing: (range: Range<String.Index>, query: String)? {
        guard !model.event, focus == .words, case .selection(let range)? = selection?.indices, range.isEmpty else { return nil }
        return AtTyping.typed(model.draft.words, cursor: range.upperBound)
    }

    /// Your friends, then the places with a page, matching what's typed.
    private func named(_ query: String) -> [AtCandidate] {
        AtTyping.matches(query, friends: AtCandidate.friends(book.friends), places: AtCandidate.places(places))
    }

    private func pickName(_ candidate: AtCandidate, replacing range: Range<String.Index>) {
        Haptics.light()
        let cursor = model.draft.pick(candidate.name, replacing: range)
        selection = TextSelection(insertionPoint: cursor)
    }

    /// Event on: its name, day and time and Place, town-plus's rows.
    private var eventFields: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(NewPostCopy.eventName, text: Bindable(model.eventModel).draft.name, axis: .vertical)
                .font(.eventDisplay(NewPostMetric.eventName))
                .foregroundStyle(Hue.ink)
                .lineLimit(1...3)
                .focused($focus, equals: .name)
                .submitLabel(.next)
                .onChange(of: model.eventModel.draft.name) { _, name in
                    if name.contains("\n") { model.eventModel.draft.name = name.replacingOccurrences(of: "\n", with: ""); focus = .words }
                    if name.count > NewEventDraft.nameLimit { model.eventModel.draft.name = String(name.prefix(NewEventDraft.nameLimit)) }
                    model.eventModel.problem = nil
                }
                .padding(.horizontal, NewPostMetric.side)
                .padding(.bottom, NewPostMetric.nameBottom)
            row(NewEventCopy.when, icon: { Image(systemName: "calendar").font(.glyph(NewPostMetric.symbol)) }) {
                DatePicker(NewEventCopy.when, selection: Bindable(model.eventModel).draft.when, in: Date()...,
                           displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    // The town's clock, as Share sends it.
                    .environment(\.timeZone, Town.timeZone)
            }
            let plus = model.draft.canAddPlace
            Button { focus = nil; path.append(.place) } label: {
                row(NewEventCopy.place, icon: { MapPinGlyph(size: NewPostMetric.icon) }) {
                    HStack(spacing: 8) {
                        Text(model.draft.location ?? NewEventCopy.addPlace)
                            .font(.sans(16))
                            .foregroundStyle(model.draft.location == nil ? Hue.inkSecondary : Hue.ink)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.glyph(15, weight: .semibold))
                            .foregroundStyle(Hue.control)
                    }
                    // Room for the + beside the row, which is its own button (a tap on it never opens Place).
                    .padding(.trailing, plus ? NewPostMetric.plus + NewPostMetric.plusGap : 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.press(.squish))
            .overlay(alignment: .trailing) {
                if plus {
                    // Uber's round + after the place (BP app references/event-several-places): another place.
                    Button { focus = nil; path.append(.anotherPlace) } label: {
                        Image(systemName: "plus")
                            .font(.glyph(16, weight: .semibold))
                            .foregroundStyle(Hue.ink)
                            .frame(width: NewPostMetric.plus, height: NewPostMetric.plus)
                            .background(Hue.fill, in: Circle())
                            .frame(width: NewPostMetric.tap, height: NewPostMetric.tap)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.press(.squish))
                    .accessibilityLabel(NewEventCopy.anotherPlace)
                    .padding(.trailing, NewPostMetric.side - (NewPostMetric.tap - NewPostMetric.plus) / 2)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            ForEach(model.draft.location == nil ? [] : model.draft.morePlaces, id: \.self) { name in
                morePlace(name)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            // Filter (BP app town-feed 52): Badoo's Filter, one screen deeper, as Place is.
            Button { focus = nil; path.append(.filter) } label: {
                row(NewEventFilterCopy.filter, icon: { Image(systemName: "slider.horizontal.3").font(.glyph(NewPostMetric.symbol)) }) {
                    let summary = NewEventFilterCopy.summary(gender: model.eventModel.draft.gender, ages: model.eventModel.draft.ages)
                    HStack(spacing: 8) {
                        Text(summary ?? NewEventFilterCopy.optional)
                            .font(.sans(16))
                            .foregroundStyle(summary == nil ? Hue.inkSecondary : Hue.ink)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.glyph(15, weight: .semibold))
                            .foregroundStyle(Hue.control)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.press(.squish))
        }
    }

    /// A place after the first: its name under Place's, and a grey x that takes it out.
    private func morePlace(_ name: String) -> some View {
        HStack(spacing: 12) {
            Text(name)
                .font(.sans(16))
                .foregroundStyle(Hue.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button {
                withAnimation(reduceMotion ? nil : Motion.smooth) { model.draft.morePlaces.removeAll { $0 == name } }
            } label: {
                Image(systemName: "xmark")
                    .font(.glyph(10, weight: .heavy))
                    .foregroundStyle(Hue.paper)
                    .frame(width: NewPostMetric.remove, height: NewPostMetric.remove)
                    .background(Hue.control, in: Circle())
                    .frame(width: NewPostMetric.tap, height: NewPostMetric.tap)
                    .contentShape(Circle())
            }
            .buttonStyle(.press(.squish))
            .accessibilityLabel("Remove \(name)")
            // Its middle under the +'s.
            .padding(.trailing, -(NewPostMetric.tap - NewPostMetric.plus) / 2)
        }
        .padding(.leading, NewPostMetric.side + NewPostMetric.icon + 12)
        .padding(.trailing, NewPostMetric.side)
        .frame(minHeight: NewPostMetric.morePlace)
        .overlay(alignment: .bottom) { Rectangle().fill(Hue.hairline).frame(height: 0.5) }
    }

    private func row<Icon: View, Trailing: View>(_ label: String, @ViewBuilder icon: () -> Icon,
                                                 @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            icon()
                .frame(width: NewPostMetric.icon, height: NewPostMetric.icon)
                .accessibilityHidden(true)
            Text(label).font(.sans(16))
            Spacer(minLength: 8)
            trailing()
        }
        .foregroundStyle(Hue.ink)
        .padding(.horizontal, NewPostMetric.side)
        .frame(minHeight: NewPostMetric.row)
        .overlay(alignment: .bottom) { Rectangle().fill(Hue.hairline).frame(height: 0.5) }
    }

    // MARK: Photo

    /// Edge to edge in its own shape, with Change photo and the trash on it.
    private func photoView(_ photo: UIImage) -> some View {
        Image(uiImage: photo)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Your photo")
            .overlay(alignment: .topLeading) {
                Button { picking = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle").font(.glyph(14, weight: .semibold))
                        Text(NewPostCopy.change).font(.displaySemi(15))
                    }
                    .foregroundStyle(.white)
                    .padding(.leading, 9)
                    .padding(.trailing, 11)
                    .frame(height: NewPostMetric.onPhoto)
                    .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: Radius.searchField - 1, style: .continuous))
                    .frame(minHeight: NewPostMetric.tap)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.press(.squish))
                .padding(NewPostMetric.onPhotoInset - (NewPostMetric.tap - NewPostMetric.onPhoto) / 2)
            }
            .overlay(alignment: .topTrailing) {
                Button { withAnimation(reduceMotion ? nil : Motion.smooth) { model.pick(nil) } } label: {
                    Image(systemName: "trash")
                        .font(.glyph(17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: NewPostMetric.onPhoto, height: NewPostMetric.onPhoto)
                        .background(.black.opacity(0.62), in: Circle())
                        .frame(width: NewPostMetric.tap, height: NewPostMetric.tap)
                        .contentShape(Circle())
                }
                .buttonStyle(.press(.squish))
                .accessibilityLabel("Remove photo")
                .padding(NewPostMetric.onPhotoInset - (NewPostMetric.tap - NewPostMetric.onPhoto) / 2)
            }
    }

    // MARK: Over the keyboard

    /// The photo button, then Post: the charcoal Attend pill in SF Pro Semibold, grey until there's
    /// something to post. Why it couldn't go sits over it in red (town-plus's line).
    private var bar: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let problem = model.shownProblem {
                Text(problem)
                    .font(.apple(15))
                    .foregroundStyle(Hue.declined)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, NewPostMetric.side)
                    .padding(.vertical, 10)
                    .transition(.opacity)
            }
            HStack {
                Button { focus = nil; picking = true } label: {
                    Image(systemName: "photo.on.rectangle")
                        .font(.glyph(22))
                        .foregroundStyle(Hue.ink)
                        .frame(width: NewPostMetric.tap, height: NewPostMetric.tap)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.press(.squish))
                .accessibilityLabel(model.photo == nil ? "Add a photo" : NewPostCopy.change)
                Spacer()
                Button(action: post) {
                    ZStack {
                        Text(NewPostCopy.post).opacity(model.busy ? 0 : 1)
                        if model.busy { ProgressView().tint(.white) }
                    }
                    .font(.displaySemi(16))
                    .foregroundStyle(model.ready ? .white : Hue.control)
                }
                .buttonStyle(MeetupPillStyle(height: NewPostMetric.post, minWidth: NewPostMetric.postWidth, grey: !model.ready))
                .turnBackShake(failures: model.shownFailures, shakes: !reduceMotion)
                .disabled(!model.ready || model.busy)
                .accessibilityLabel(model.busy ? "Posting" : NewPostCopy.post)
            }
            .padding(.leading, NewPostMetric.side - (NewPostMetric.tap - 26) / 2 + 2)
            .padding(.trailing, NewPostMetric.side)
            .frame(height: NewPostMetric.bar)
        }
        .animation(.easeOut(duration: 0.18), value: model.shownProblem)
        .background(Hue.paper)
        .overlay(alignment: .top) { Rectangle().fill(Hue.hairline).frame(height: 0.5) }
    }

    private func post() {
        let api = CommunityAPI(auth: AuthStore.shared)
        Task {
            if model.event {
                guard let check = await model.shareEvent(api: api) else { return }
                switch check {
                case .declined: return
                case .live, .waiting:
                    onShared(model.eventModel.posted(live: check == .live))
                    dismiss()
                }
            } else if let input = await model.save(api: api) {
                onPosted(PostOutbox.Sent(id: input.id, draft: model.draft, photo: model.photo, name: name, picture: picture))
                dismiss()
            }
        }
    }
}

enum NewPostCopy {
    static let title = "New post"
    static let placeholder = "What's on your mind?"
    static let about = "Say something about it…"
    static let eventName = "Name your event"
    static let who = "Who can see this"
    static let everyone = "Public"
    static let friends = "Friends"
    static let tag = "Tag friends"
    static let event = "Event"
    static let change = "Change photo"
    static let post = "Post"
    static let discard = "Discard post?"
    static let discardWhy = "If you leave now, you'll lose this post."
    static let discardButton = "Discard"
    static let keepEditing = "Keep editing"
    static let done = "Done"
    static let search = "Search friends"
    static let noFriends = "Add friends to tag them here."
}

// MARK: - Tag friends

/// Facebook's Tag people: your Friends, a search, the picked ones' faces on top, Done (round 2, step 5).
private struct NewPostTag: View {
    @Binding var tagged: [Neighbor]
    @State private var words = ""
    @Environment(FriendsBook.self) private var book
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var friends: [Neighbor] {
        let typed = words.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? book.friends : book.friends.filter { $0.displayName.localizedStandardContains(typed) }
    }

    var body: some View {
        List {
            if !tagged.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tagged) { friend in
                            Button { toggle(friend) } label: { face(friend) }
                                .buttonStyle(.press(.squish))
                                .accessibilityLabel("Untag \(friend.displayName)")
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, NewPostMetric.side)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowSeparator(.hidden)
            }
            ForEach(friends) { friend in
                let on = tagged.contains { $0.id == friend.id }
                Button { toggle(friend) } label: {
                    HStack(spacing: 12) {
                        Avatar(friend.avatarUrl.flatMap(URL.init(string:)), size: NewPostMetric.friendFace)
                        Text(friend.displayName)
                            .font(.sansMedium(16))
                            .foregroundStyle(Hue.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(.glyph(24))
                            .foregroundStyle(on ? Hue.ink : Hue.edge)
                            .contentTransition(.symbolEffect(.replace))
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: NewPostMetric.friendRow)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.press(.row))
                .accessibilityAddTraits(on ? .isSelected : [])
                .listRowInsets(NewEventMetric.placeInsets)
                .listRowSeparator(.hidden)
            }
            if book.loaded && book.friends.isEmpty {
                Text(NewPostCopy.noFriends)
                    .font(.sans(15))
                    .foregroundStyle(Hue.inkSecondary)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .top, spacing: 0) {
            FriendsSearchField(words: $words)
                .padding(.horizontal, NewPostMetric.side)
                .padding(.vertical, 8)
                .background(Hue.surface)
        }
        .animation(reduceMotion ? nil : Motion.smooth, value: tagged)
        .navigationTitle(NewPostCopy.tag)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(NewPostCopy.done) { dismiss() }.fontWeight(.semibold)
            }
        }
        .task { if !book.loaded { await book.refresh() } }
    }

    private func face(_ friend: Neighbor) -> some View {
        VStack(spacing: 6) {
            Avatar(friend.avatarUrl.flatMap(URL.init(string:)), size: NewPostMetric.pickedFace)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "xmark")
                        .font(.glyph(9, weight: .heavy))
                        .foregroundStyle(Hue.paper)
                        .frame(width: 20, height: 20)
                        .background(Hue.ink, in: Circle())
                        .overlay { Circle().strokeBorder(Hue.paper, lineWidth: 2) }
                        .offset(x: 2)
                }
            Text(friend.firstName)
                .font(.sansMedium(12))
                .foregroundStyle(Hue.ink)
                .lineLimit(1)
        }
        .frame(width: 64)
    }

    private func toggle(_ friend: Neighbor) {
        Haptics.light()
        if let i = tagged.firstIndex(where: { $0.id == friend.id }) {
            tagged.remove(at: i)
        } else if tagged.count < NewPostDraft.tagLimit {
            tagged.append(friend)
        }
    }
}

/// Round 2's measurements (BP app references/post-screen/round2.py), at 1 CSS px = 1 pt.
private nonisolated enum NewPostMetric {
    static let side: CGFloat = 16
    /// Under the bar to your picture.
    static let whoTop: CGFloat = 4
    static let picture: CGFloat = 60
    static let whoGap: CGFloat = 12
    static let pillTop: CGFloat = 5
    static let pill: CGFloat = 26
    static let chipsTop: CGFloat = 18
    static let chip: CGFloat = 34
    static let chipGap: CGFloat = 8
    static let chipIcon: CGFloat = 17
    static let chipFace: CGFloat = 22
    /// Apple's tap target.
    static let tap: CGFloat = 44
    static let wordsTop: CGFloat = 16
    static let bigWords: CGFloat = 24
    static let words: CGFloat = 17
    static let photoTop: CGFloat = 14
    static let onPhoto: CGFloat = 32
    static let onPhotoInset: CGFloat = 12
    static let eventName: CGFloat = 26
    static let nameBottom: CGFloat = 8
    static let row: CGFloat = 54
    /// Uber's round + (Plan your ride, about 30 pt at 1 pt = 1 px), 8 pt after the chevron; its x, 22.
    static let plus: CGFloat = 30
    static let plusGap: CGFloat = 8
    static let remove: CGFloat = 22
    static let morePlace: CGFloat = 48
    static let icon: CGFloat = 22
    static let symbol: CGFloat = 19
    static let bar: CGFloat = 54
    static let post: CGFloat = 38
    static let postWidth: CGFloat = 74
    static let friendFace: CGFloat = 44
    /// `ProfileModel.coverJPEG`'s width, in pixels.
    static let upload: CGFloat = 1290
    static let friendRow: CGFloat = 60
    static let pickedFace: CGFloat = 56
}

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

/// Facebook's Add location rows for Place (town-plus).
private nonisolated enum NewEventMetric {
    static let side: CGFloat = 16
    static let iconGap: CGFloat = 12
    static let placeMark: CGFloat = 40
    static let placeRow: CGFloat = 56
    static let searchPad: CGFloat = 8
    /// Facebook's Add location rows: 16 pt in, the list's own dividers between.
    static let placeInsets = EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)
}
