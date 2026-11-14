//
//  ModerationView.swift
//  Block Party — the admin review queue. Pending club_events and clubs wait here for
//  the admin's yes: neighbour posts the composer held back, and found events the
//  registry read from a town's own sources (ADR-021 in the registry's decision
//  records). RLS remains the real boundary (`AuthStore.isAdmin` is a product gate).
//
//  Each item reads like Reddit's mod queue (BP app launch-ready 07, references/review-queue-details/):
//  who posted it and when, the title, its day and place, two lines of its words, its card's picture on
//  the right, and a grey tag saying why it waits. A tap opens its Event page, where nothing acts.
//  Approve (or Keep) and × follow Yubo's requests list (references/review-queue/): × on an event asks
//  what was wrong, because the misread share of found events decides when they may publish on their
//  own. Decisions answer at once and a write that fails puts the item back with a shake, like Join on
//  the event page.
//

import SwiftUI
import Combine

/// Pure row wording, kept apart so it can be tested without a view.
enum ReviewRow {
    /// "Mon, Nov 9 · 5:30 PM · Episcopal House of Prayer": the day, the time (or All day), then where.
    static func when(eventDate: String?, startTime: String?, allDay: Bool, location: String?) -> String {
        let day = DateHelpers.townDay(eventDate)?.formatted(townStyle.weekday(.abbreviated).month(.abbreviated).day())
        return [day, allDay ? "All day" : startTime, location].compactMap { $0 }.filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// How long ago it was posted ("2h"), or for a found Event when it was found ("found today",
    /// "found Oct 19"). Nil when the card doesn't say.
    static func age(createdAt: String?, found: Bool, now: Date) -> String? {
        guard let at = DateHelpers.timestamp(createdAt) else { return nil }
        guard found else { return PostingCard.relativeLabel(for: at, now: now) }
        return Town.gregorian.isDate(at, inSameDayAs: now) ? "found today" : "found \(short(at))"
    }

    /// Why a waiting item waits. A found Event needs no tag: its top line says where it was found. A
    /// neighbour's waits because the instant check gave no answer (it was asked), or because it never
    /// ran: the day's 10 were used, or the post holds something the check doesn't read.
    static func heldTag(found: Bool, checkedAt: String?) -> String? {
        found ? nil : checkedAt == nil ? "Held: not checked" : "Held: the check didn't answer"
    }

    /// "Reported Oct 26: Wrong info", or with several "3 reports: Scam, fraud or spam, Wrong info".
    static func reportTag(reasons: [String], reports: Int, firstAt: String?) -> String {
        let words = reasons.map { ReportReason(rawValue: $0)?.label ?? $0 }.joined(separator: ", ")
        if reports > 1 { return "\(reports) reports: \(words)" }
        return DateHelpers.timestamp(firstAt).map { "Reported \(short($0)): \(words)" } ?? "Reported: \(words)"
    }

    /// A reporter's note as the queue shows it (BP app backlog 26): their words, in quotes.
    static func quoted(_ note: String) -> String { "\u{201C}\(note)\u{201D}" }

    /// "Oct 26", on the Town's clock.
    private static func short(_ date: Date) -> String {
        date.formatted(townStyle.month(.abbreviated).day())
    }

    private static var townStyle: Date.FormatStyle {
        Date.FormatStyle(locale: Locale(identifier: "en_US_POSIX"), calendar: Town.gregorian, timeZone: Town.gregorian.timeZone)
    }
}

/// What a queue item shows of its Event card (`private.event_cards`, BP app launch-ready 07), read field by
/// field: an everyday post has no date, so it makes no `UpcomingEvent` and opens no page.
struct ReviewCard: Hashable {
    var title = ""
    var eventDate: String? = nil
    var startTime: String? = nil
    var allDay = false
    var location: String? = nil
    var description: String? = nil
    var sourceName: String? = nil
    var createdAt: String? = nil
    var imageUrl: String? = nil
    /// The Event its page opens; nil for an everyday post.
    var event: UpcomingEvent? = nil

    /// Found on a town's own source (ADR-021) rather than posted by a neighbour.
    var found: Bool { sourceName != nil }

    /// The picture its Town card shows: its own photo, else its place's (or its logo). An everyday
    /// post's own photo.
    @MainActor var picture: URL? {
        guard let event else { return imageUrl.flatMap(URL.init(string:)) }
        switch FeedCardItem(event).image {
        case .eventPhoto(let url), .placePhoto(let url, _, _): return url
        case .placeLogo(let picture): return picture.url
        case .fallback: return nil
        }
    }
}

extension ReviewCard: Decodable {
    private enum Keys: String, CodingKey {
        case title, eventDate, startTime, allDay, location, description, sourceName, createdAt, imageUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        func text(_ key: Keys) -> String? { (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil }
        self.init(title: text(.title) ?? "", eventDate: text(.eventDate), startTime: text(.startTime),
                  allDay: (try? c.decodeIfPresent(Bool.self, forKey: .allDay)) ?? false, location: text(.location),
                  description: text(.description), sourceName: text(.sourceName), createdAt: text(.createdAt),
                  imageUrl: text(.imageUrl), event: try? UpcomingEvent(from: decoder))
    }
}

/// Who posted a queue item (`private.post_poster`): first name and photo. Nil for a found Event.
struct ReviewPoster: Decodable, Hashable {
    let name: String?
    let photo: String?
}

/// An Event neighbours reported (town-feed 22): its reasons and how many reports, never who sent them.
struct ReportedEvent: Identifiable, Equatable, Decodable {
    let eventId: String
    let title: String
    let eventDate: String?
    let reasons: [String]
    let reports: Int
    /// When the first report came, its card and who posted it (launch-ready 07).
    var firstAt: String? = nil
    let card: ReviewCard
    var poster: ReviewPoster? = nil
    /// What reporters said with Wrong info, once the post check kept it: the 3 newest, newest first (backlog 26).
    var notes: [String]? = nil
    var id: String { eventId }

    var tag: String { ReviewRow.reportTag(reasons: reasons, reports: reports, firstAt: firstAt) }
}

@MainActor
final class ModerationModel: ObservableObject {
    @Published var posts: [PendingPost] = []
    @Published var clubs: [ClubRow] = []
    @Published var reports: [ReportedEvent] = []
    /// Reported chat messages, as their reports kept them (BP app five-tabs 05). Nobody else's chats show here.
    @Published var messages: [ReportedMessage] = []
    @Published var loading = true
    @Published var failed = false
    /// Bumped when a decision fails and its row comes back, so that row shakes.
    @Published var rollbacks: [String: Int] = [:]
    private var acting: Set<String> = []   // in-flight guard so a double-tap can't double-patch
    private let preview: Bool

    init(preview: Bool = false) { self.preview = preview }

    func load(_ api: CommunityAPI) async {
        #if DEBUG
        if preview { posts = Self.fixtures; reports = Self.reportFixtures; messages = Self.messageFixtures; loading = false; return }
        #endif
        if posts.isEmpty && clubs.isEmpty && reports.isEmpty && messages.isEmpty { loading = true }
        do {
            async let p = api.getPendingPosts()
            async let c = api.getPendingClubs()
            async let r = api.reportedEvents()
            async let m = ChatAPI(api.db).reportedMessages()
            // A row mid-decision stays gone even if this fetch raced its write.
            posts = try await p.filter { !acting.contains($0.id) }
            clubs = try await c.filter { !acting.contains($0.id) }
            // Reports never blank the rest of the queue.
            reports = ((try? await r) ?? []).filter { !acting.contains($0.id) }
            messages = ((try? await m) ?? []).filter { !acting.contains($0.id) }
            failed = false
        } catch {
            if posts.isEmpty && clubs.isEmpty && reports.isEmpty { failed = true }
            Log.network("Moderation.load: \(error)")
        }
        loading = false
    }

    /// `reason` nil approves. The row leaves at once; a failed write brings it back.
    func decidePost(_ api: CommunityAPI, _ post: PendingPost, reason: DeclineReason?) async {
        guard !acting.contains(post.id), let i = posts.firstIndex(of: post) else { return }
        acting.insert(post.id); defer { acting.remove(post.id) }
        withAnimation(Self.leave) { _ = posts.remove(at: i) }
        do {
            try await write {
                if let reason { try await api.declinePost(post.id, reason: reason) }
                else { try await api.approvePost(post.id) }
            }
        } catch {
            withAnimation(Self.leave) { posts.insert(post, at: min(i, posts.count)) }
                completion: { self.rollback(post.id) }
            Log.network("Moderation.decidePost: \(error)")
        }
    }

    func decideClub(_ api: CommunityAPI, _ club: ClubRow, approve: Bool) async {
        guard !acting.contains(club.id), let i = clubs.firstIndex(where: { $0.id == club.id }) else { return }
        acting.insert(club.id); defer { acting.remove(club.id) }
        withAnimation(Self.leave) { _ = clubs.remove(at: i) }
        do {
            try await write { try await api.setClubStatus(club.id, status: approve ? .approved : .rejected) }
        } catch {
            withAnimation(Self.leave) { clubs.insert(club, at: min(i, clubs.count)) }
                completion: { self.rollback(club.id) }
            Log.network("Moderation.decideClub: \(error)")
        }
    }

    /// Keep (the reports go) or take down. The row leaves at once; a failed write brings it back.
    func decideReport(_ api: CommunityAPI, _ report: ReportedEvent, takeDown: Bool) async {
        guard !acting.contains(report.id), let i = reports.firstIndex(of: report) else { return }
        acting.insert(report.id); defer { acting.remove(report.id) }
        withAnimation(Self.leave) { _ = reports.remove(at: i) }
        do {
            try await write { try await api.resolveReports(report.id, takeDown: takeDown) }
        } catch {
            withAnimation(Self.leave) { reports.insert(report, at: min(i, reports.count)) }
                completion: { self.rollback(report.id) }
            Log.network("Moderation.decideReport: \(error)")
        }
    }

    /// A reported chat message: keep it (the report goes) or hide it from the chat. The row leaves at once;
    /// a failed write brings it back.
    func decideMessage(_ api: CommunityAPI, _ report: ReportedMessage, hide: Bool) async {
        guard !acting.contains(report.id), let i = messages.firstIndex(of: report) else { return }
        acting.insert(report.id); defer { acting.remove(report.id) }
        withAnimation(Self.leave) { _ = messages.remove(at: i) }
        do {
            try await write { try await ChatAPI(api.db).resolve(report: report.id, hide: hide) }
        } catch {
            withAnimation(Self.leave) { messages.insert(report, at: min(i, messages.count)) }
                completion: { self.rollback(report.id) }
            Log.network("Moderation.decideMessage: \(error)")
        }
    }

    /// Flip back first, then shake (taste.md): runs once the row has landed.
    private func rollback(_ id: String) {
        Haptics.error()
        rollbacks[id, default: 0] += 1
    }

    private func write(_ op: () async throws -> Void) async throws {
        #if DEBUG
        if preview {
            try await Task.sleep(for: .milliseconds(400))
            if LaunchFlags.has(.reviewQueueFail) {
                throw SupabaseError(message: "preview failure", status: 500)
            }
            return
        }
        #endif
        try await op()
    }

    /// Guessed: no Reference recording for a row leaving a requests list.
    static let leave = Animation.spring(response: 0.35, dampingFraction: 0.86)

    #if DEBUG
    /// Live pictures from the places bucket, so the preview shows what the queue shows.
    private static let photos = "https://lxdgwhvqjqmqliobwjpi.supabase.co/storage/v1/object/public/places/st-joseph/"

    /// A fixture's card, with the Event its page opens when it has a day.
    private static func card(_ id: String, _ title: String, _ date: String?, _ time: String?, allDay: Bool = false,
                             place: String? = nil, words: String? = nil, source: String? = nil, photo: String? = nil,
                             created: String) -> ReviewCard {
        ReviewCard(title: title, eventDate: date, startTime: time, allDay: allDay, location: place, description: words,
                   sourceName: source, createdAt: created, imageUrl: photo.map { photos + $0 },
                   event: date.map {
                       UpcomingEvent(id: id, title: title, eventDate: $0, startTime: time, location: place, goingCount: 0,
                                     createdAt: created, imageUrl: photo.map { photos + $0 }, isAllDay: allDay,
                                     sourceName: source, description: words)
                   })
    }

    /// Two reported Events (`-review-queue-preview`): a made-up scam, and the first real report (Oct 26).
    static let reportFixtures = [
        ReportedEvent(eventId: "report-0", title: "Free iPhone giveaway", eventDate: "2026-11-12",
                      reasons: ["scam"], reports: 3, firstAt: "2026-11-06T14:00:00Z",
                      card: card("report-0", "Free iPhone giveaway", "2026-11-12", "3 PM", place: "Centennial Park",
                                 words: "First 50 people get a free iPhone. Bring your bank card to sign up.",
                                 created: "2026-11-06T12:00:00Z"),
                      poster: ReviewPoster(name: "Sam", photo: nil)),
        ReportedEvent(eventId: "report-1", title: "Embodied Spirit Chi Kung", eventDate: "2026-11-09",
                      reasons: ["wrong_info"], reports: 1, firstAt: "2026-10-26T14:00:00Z",
                      card: card("report-1", "Embodied Spirit Chi Kung", "2026-11-09", "5:30 PM",
                                 place: "Episcopal House of Prayer",
                                 words: "Chi Kung (energy work), in its many forms, dates back at least 2500 years. At its core is Chi, the energy that animates and drives us.",
                                 source: "CSB SJU Campus Events",
                                 photo: "events/event-place-retreat-group-gathered-in-chairs-around-a-teacher-by-the-3f8586a512.webp",
                                 created: "2026-10-19T17:00:00Z"),
                      notes: ["Starts at 6 now, not 5:30. Their Facebook moved it."]),
    ]

    static let messageFixtures = [
        ReportedMessage(id: "fixture-message", senderName: "Sam Rivera", kind: "text", body: "Sample reported message",
                        photoPath: nil, eventTitle: nil, reason: "bullying"),
    ]

    /// A neighbour's Event the check didn't answer, an everyday post it never checked, and found Events
    /// (`-review-queue-preview`).
    static let fixtures: [PendingPost] = [
        PendingPost(id: "fixture-held", kind: .event, checkedAt: "2026-11-07T19:00:00Z",
                    card: card("fixture-held", "Bingo night for the neighbourhood", "2026-11-10", "6:30 PM",
                               place: "Sal's Bar and Grill",
                               words: "Grab a few friends and come play! $15 a packet, 11 games, prizes for every round.",
                               photo: "events/event-games-two-smiling-women-hold-up-their-bingo-cards-at-sal-s-bar-d226c1a4a8.webp",
                               created: "2026-11-07T19:00:00Z"),
                    poster: ReviewPoster(name: "Maya", photo: nil)),
        PendingPost(id: "fixture-post", kind: .post, checkedAt: nil,
                    card: card("fixture-post", "Lost cat near 3rd Ave, grey with a white chest. Call if you see her!",
                               nil, nil, created: "2026-11-07T17:00:00Z"),
                    poster: ReviewPoster(name: "Jordan", photo: nil)),
        PendingPost(id: "fixture-fare", kind: .event, checkedAt: nil,
                    card: card("fixture-fare", "Fare for All", "2026-11-09", nil, allDay: true, place: "610 County Rd 2",
                               words: "Fare for All sells packages of fresh produce and frozen meat once a month at Resurrection Lutheran Church.",
                               source: "City of St. Joseph",
                               photo: "resurrection-lutheran-church/scene-dinner-volunteers-packing-food-into-a-cooler-in-the-church-kitchen-befe541ab3.webp",
                               created: "2026-11-07T13:00:00Z"),
                    poster: nil),
        PendingPost(id: "fixture-planning", kind: .event, checkedAt: nil,
                    card: card("fixture-planning", "Planning Commission", "2026-11-12", "6 PM", place: "City Hall",
                               source: "City of St. Joseph", created: "2026-11-06T13:00:00Z"),
                    poster: nil),
    ]
    #endif
}

struct ModerationView: View {
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model: ModerationModel
    @Environment(\.dismiss) private var dismiss
    @State private var link: SafariLink?
    /// The Event page a tap opened, pushed inside the queue's own stack.
    @State private var opened: FeedCardItem?

    init(preview: Bool = false) {
        _model = StateObject(wrappedValue: ModerationModel(preview: preview))
    }

    private var api: CommunityAPI { CommunityAPI(auth: auth) }
    private var pendingCount: Int { model.posts.count + model.clubs.count + model.reports.count + model.messages.count }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                // Lazy: each item loads its picture only as it nears the screen.
                LazyVStack(alignment: .leading, spacing: 0) {
                    if model.loading && pendingCount == 0 {
                        ModerationQueueSkeleton()
                    } else if model.failed {
                        emptyState(icon: "wifi.slash", title: "Couldn't load the queue",
                                   detail: "Check your connection, then pull to refresh.")
                    } else if pendingCount == 0 {
                        emptyState(icon: "checkmark.circle", title: "All caught up",
                                   detail: "Nothing is waiting for review.")
                    } else {
                        if !model.reports.isEmpty {
                            ModerationSectionLabel(text: "Reported")
                            ForEach(Array(model.reports.enumerated()), id: \.element.id) { i, report in
                                let card = report.card
                                ReviewQueueRow(
                                    who: who(card, report.poster), title: card.title.isEmpty ? report.title : card.title,
                                    when: when(card), words: card.description, picture: card.picture,
                                    notes: report.notes ?? [],
                                    tag: .init(symbol: "flag", text: report.tag), line: i > 0,
                                    shakes: model.rollbacks[report.id, default: 0],
                                    onOpen: open(card),
                                    approveLabel: "Keep",
                                    onApprove: { Task { await model.decideReport(api, report, takeDown: false) } },
                                    asksWhy: false,
                                    declineLabel: "Take down",
                                    onDecline: { _ in Task { await model.decideReport(api, report, takeDown: true) } })
                                .transition(Self.rowTransition)
                            }
                        }
                        if !model.messages.isEmpty {
                            ModerationSectionLabel(text: "Reported messages")
                            ForEach(Array(model.messages.enumerated()), id: \.element.id) { i, report in
                                ReviewQueueRow(
                                    who: .init(face: .person(nil), name: report.senderName ?? "A neighbour"),
                                    title: report.body ?? "Photo", titleLines: nil,
                                    when: report.eventTitle.map { "In the Going chat of \($0)" },
                                    tag: .init(symbol: "flag",
                                               text: "Reported: \(ReportReason(rawValue: report.reason)?.label ?? report.reason)"),
                                    line: i > 0,
                                    shakes: model.rollbacks[report.id, default: 0],
                                    onOpen: report.photoPath.map { path in { openPhoto(path) } },
                                    approveLabel: "Keep",
                                    onApprove: { Task { await model.decideMessage(api, report, hide: false) } },
                                    asksWhy: false,
                                    declineLabel: "Hide",
                                    onDecline: { _ in Task { await model.decideMessage(api, report, hide: true) } })
                                .transition(Self.rowTransition)
                            }
                        }
                        if !model.posts.isEmpty {
                            ModerationSectionLabel(text: "Events & trails")
                            ForEach(Array(model.posts.enumerated()), id: \.element.id) { i, post in
                                let card = post.card
                                ReviewQueueRow(
                                    who: who(card, post.poster),
                                    // A neighbour's post (town-feed 29): its words, or that it's a photo.
                                    title: post.kind == .post && card.title.isEmpty ? "Photo" : card.title,
                                    titleLines: card.event == nil ? nil : 2,
                                    when: when(card), words: card.description, picture: card.picture,
                                    tag: ReviewRow.heldTag(found: card.found, checkedAt: post.checkedAt)
                                        .map { .init(symbol: "clock", text: $0) },
                                    line: i > 0,
                                    shakes: model.rollbacks[post.id, default: 0],
                                    onOpen: open(card),
                                    onApprove: { Task { await model.decidePost(api, post, reason: nil) } },
                                    asksWhy: true,
                                    onDecline: { reason in Task { await model.decidePost(api, post, reason: reason) } })
                                .transition(Self.rowTransition)
                            }
                        }
                        if !model.clubs.isEmpty {
                            ModerationSectionLabel(text: "Clubs")
                            ForEach(Array(model.clubs.enumerated()), id: \.element.id) { i, club in
                                ReviewQueueRow(
                                    who: .init(face: .host(club.host ?? club.name), name: club.host ?? club.name),
                                    title: club.name,
                                    when: [club.schedule, club.location].compactMap { $0 }
                                        .filter { !$0.isEmpty }.joined(separator: " · "),
                                    words: club.description,
                                    tag: .init(symbol: "person.3", text: "New group"),
                                    line: i > 0,
                                    shakes: model.rollbacks[club.id, default: 0],
                                    onOpen: nil,
                                    onApprove: { Task { await model.decideClub(api, club, approve: true) } },
                                    asksWhy: false,
                                    onDecline: { _ in Task { await model.decideClub(api, club, approve: false) } })
                                .transition(Self.rowTransition)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .background(Hue.paper)
            .navigationTitle("Review queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Hue.inkSecondary)
                }
            }
            .navigationDestination(item: $opened) { EventPage(item: $0, reviewing: true) }
            .sheet(item: $link) { SafariView(url: $0.url).ignoresSafeArea() }
            .task { await model.load(api) }
            .refreshable { await model.load(api) }
        }
    }

    /// Leaves to the left and, when a write fails, comes back from the left.
    private static let rowTransition = AnyTransition.move(edge: .leading).combined(with: .opacity)

    /// A found Event's host and when it was found, else the neighbour and how long ago they posted.
    private func who(_ card: ReviewCard, _ poster: ReviewPoster?) -> ReviewQueueRow.Who {
        let age = ReviewRow.age(createdAt: card.createdAt, found: card.found, now: Date())
        if let host = card.sourceName {
            return .init(face: .host(host, card.event?.hostPicture?.url), name: host, age: age)
        }
        return .init(face: .person(poster?.photo.flatMap(URL.init(string:))),
                     name: poster?.name.flatMap { $0.isEmpty ? nil : $0 } ?? "A neighbour", age: age)
    }

    private func when(_ card: ReviewCard) -> String {
        ReviewRow.when(eventDate: card.eventDate, startTime: card.startTime, allDay: card.allDay, location: card.location)
    }

    /// An Event opens its page; an everyday post its photo; anything else nothing.
    private func open(_ card: ReviewCard) -> (() -> Void)? {
        if let event = card.event { return { opened = FeedCardItem(event) } }
        guard let photo = card.picture else { return nil }
        return { link = SafariLink(url: photo) }
    }

    /// A reported photo, through a link signed for the admin.
    private func openPhoto(_ path: String) {
        Task {
            if let url = try? await ChatAPI(api.db).signedLinks([path])[path] { link = SafariLink(url: url) }
        }
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.sansLight(30)).foregroundStyle(Hue.inkSecondary)
            Text(title).font(.displaySemi(16)).foregroundStyle(Hue.ink)
            Text(detail).font(.sans(15)).foregroundStyle(Hue.inkSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 60).padding(.horizontal, 24)
    }
}

/// The mono section label, shared by the queue and its skeleton so they line up.
struct ModerationSectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.mono(11)).tracking(1.5).foregroundStyle(Hue.inkSecondary)
            .padding(.leading, 16).padding(.top, 14).padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Sizes off Reddit's mod queue (Mobbin, `references/review-queue-details/mobbin/reddit-2.jpg`, measured on
/// its scaled frame, ±1 pt), and the pill and × off Yubo's requests list (references/review-queue/).
enum ReviewMetric {
    static let side: CGFloat = 16
    static let top: CGFloat = 12
    static let bottom: CGFloat = 6
    static let face: CGFloat = 24
    static let faceGap: CGFloat = 8
    /// The poster line to the title.
    static let whoGap: CGFloat = 8
    static let picture: CGFloat = 68
    static let pictureCorner: CGFloat = 8
    static let pictureGap: CGFloat = 12
    /// The words to the tag, and the tag's own shape.
    static let tagTop: CGFloat = 10
    static let tagCorner: CGFloat = 6
    static let tagPadH: CGFloat = 8
    static let tagPadV: CGFloat = 5
    static let pill: CGFloat = 36
    static let tap: CGFloat = 44
    /// The × sits in its 44 pt box this far from the edge, as on the requests list.
    static let xTrailing: CGFloat = 6
}

/// One queue item: who posted it and when, the title, its day and place, two lines of its words, its
/// picture, then a tag saying why it waits beside Approve (or Keep) and ×.
struct ReviewQueueRow: View {
    struct Who {
        /// A host's logo when its card has one, else its first letter.
        enum Face { case person(URL?), host(String, URL? = nil) }
        let face: Face
        let name: String
        var age: String? = nil
    }

    /// Why it waits: an SF Symbol and the tag's words.
    struct Tag {
        let symbol: String
        let text: String
    }

    let who: Who
    let title: String
    /// Two lines, as Reddit's; nil for what has no page to read the rest on (an everyday post, a chat message).
    var titleLines: Int? = 2
    var when: String? = nil
    var words: String? = nil
    var picture: URL? = nil
    /// Reporters' notes (backlog 26), each on its own line above the tag (Jesse's pick at Check-in 1).
    var notes: [String] = []
    var tag: Tag? = nil
    /// The hairline above every item but a section's first.
    var line = false
    let shakes: Int
    let onOpen: (() -> Void)?
    /// "Keep" on a reported Event (town-feed 22).
    var approveLabel = "Approve"
    let onApprove: () -> Void
    /// Events ask what was wrong (the reason is the measurement); clubs just go.
    let asksWhy: Bool
    /// "Take down" on a reported Event.
    var declineLabel = "Decline"
    let onDecline: (DeclineReason?) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var asking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Only the poster line and the words open it: the tag and the buttons sit outside the press.
            if let onOpen {
                Button(action: onOpen) { summary }
                    .buttonStyle(.press(.row))
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Opens it")
            } else {
                summary.accessibilityElement(children: .combine)
            }

            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                        Text(ReviewRow.quoted(note)).font(.sans(15)).foregroundStyle(Hue.ink).lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ReviewMetric.side)
                .padding(.top, 8)
                .accessibilityElement(children: .combine)
            }

            HStack(spacing: ReviewMetric.faceGap) {
                if let tag {
                    // The symbol beside the first line, so a reason on two lines keeps it at the top.
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: tag.symbol).font(.sans(12))
                        Text(tag.text).font(.sans(14))
                    }
                    .foregroundStyle(Hue.ink)
                    .accessibilityElement(children: .combine)
                    .padding(.horizontal, ReviewMetric.tagPadH).padding(.vertical, ReviewMetric.tagPadV)
                    .background(Hue.fill, in: RoundedRectangle(cornerRadius: ReviewMetric.tagCorner, style: .continuous))
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)

                Button { Haptics.light(); onApprove() } label: {
                    Text(approveLabel).font(.displaySemi(15)).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(height: ReviewMetric.pill)
                        .background(Hue.ink, in: Capsule())
                        .frame(height: ReviewMetric.tap).contentShape(Rectangle())
                }
                .buttonStyle(.press(.squish))

                Button { Haptics.light(); if asksWhy { asking = true } else { onDecline(nil) } } label: {
                    Image(systemName: "xmark").font(.sans(15)).foregroundStyle(Hue.inkSecondary)
                        .frame(width: ReviewMetric.tap, height: ReviewMetric.tap).contentShape(Rectangle())
                }
                .buttonStyle(.press(.squish))
                .accessibilityLabel(declineLabel)
                // On the × itself, so iOS 26 points the dialog at the row it is about.
                .confirmationDialog("What was wrong?", isPresented: $asking, titleVisibility: .visible) {
                    ForEach(DeclineReason.allCases) { reason in
                        Button(reason.label) { onDecline(reason) }
                    }
                }
            }
            .padding(.leading, ReviewMetric.side).padding(.trailing, ReviewMetric.xTrailing)
            .padding(.top, ReviewMetric.tagTop)
        }
        .padding(.bottom, ReviewMetric.bottom)
        .overlay(alignment: .top) {
            if line { Hue.hairline.frame(height: 1).padding(.leading, ReviewMetric.side) }
        }
        .keyframeAnimator(initialValue: CGFloat.zero, trigger: shakes) { [reduceMotion] row, x in
            row.offset(x: reduceMotion ? 0 : x)
        } keyframes: { _ in
            // Join's shake on the event page (guessed there too): out 6 pt, dying away, 0.32 s.
            KeyframeTrack {
                CubicKeyframe(6, duration: 0.06)
                CubicKeyframe(-5, duration: 0.08)
                CubicKeyframe(3, duration: 0.07)
                CubicKeyframe(-1.5, duration: 0.06)
                CubicKeyframe(0, duration: 0.05)
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: ReviewMetric.faceGap) {
                face
                Text("\(Text(who.name).font(.sansSemibold(15)).foregroundStyle(Hue.ink))\(who.age.map { " · \($0)" } ?? "")")
                    .font(.sans(15)).foregroundStyle(Hue.inkSecondary).lineLimit(1)
            }
            HStack(alignment: .top, spacing: ReviewMetric.pictureGap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.sansSemibold(17)).foregroundStyle(Hue.ink).lineLimit(titleLines)
                    if let when, !when.isEmpty {
                        Text(when).font(.sans(15)).foregroundStyle(Hue.inkSecondary).lineLimit(1)
                    }
                    if let words, !words.isEmpty {
                        Text(words).font(.sans(15)).foregroundStyle(Hue.inkSecondary).lineLimit(2).padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let picture {
                    FeedCardURLPhoto(url: picture, loadingFill: Hue.fill)
                        .frame(width: ReviewMetric.picture, height: ReviewMetric.picture)
                        .clipShape(RoundedRectangle(cornerRadius: ReviewMetric.pictureCorner, style: .continuous))
                        .accessibilityHidden(true)
                }
            }
            .padding(.top, ReviewMetric.whoGap)
        }
        .padding(.horizontal, ReviewMetric.side)
        .padding(.top, ReviewMetric.top)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var face: some View {
        switch who.face {
        case .person(let url): Avatar(url, size: ReviewMetric.face)
        case .host(let name, let logo): Avatar(logo, size: ReviewMetric.face, blank: .initial(name, font: 11))
        }
    }
}

/// Items under the real section label, at the items' own shape, so the queue
/// resolves without the list shifting. An emptier queue collapses to "All caught up"
/// the moment the fetch lands, which the skeleton cannot avoid and should not fake.
struct ModerationQueueSkeleton: View {
    var body: some View {
        FeedSkeletonSection(spacing: 0) {
            ModerationSectionLabel(text: "Events & trails")
        } content: {
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { _ in item }
            }
        }
    }

    private var item: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: ReviewMetric.faceGap) {
                SkeletonCircle().frame(width: ReviewMetric.face, height: ReviewMetric.face)
                SkeletonLine(widthFraction: 0.4, height: 12)
            }
            HStack(alignment: .top, spacing: ReviewMetric.pictureGap) {
                VStack(alignment: .leading, spacing: 8) {
                    SkeletonLine(widthFraction: 0.8, height: 15)
                    SkeletonLine(widthFraction: 0.6, height: 12)
                    SkeletonLine(widthFraction: 0.9, height: 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                SkeletonBlock(cornerRadius: ReviewMetric.pictureCorner)
                    .frame(width: ReviewMetric.picture, height: ReviewMetric.picture)
            }
            .padding(.top, ReviewMetric.whoGap)
            HStack(spacing: ReviewMetric.faceGap) {
                SkeletonBlock(cornerRadius: ReviewMetric.tagCorner).frame(width: 150, height: 28)
                Spacer(minLength: 0)
                SkeletonBlock(cornerRadius: ReviewMetric.pill / 2).frame(width: 92, height: ReviewMetric.pill)
                Color.clear.frame(width: ReviewMetric.tap, height: ReviewMetric.tap)
            }
            .padding(.top, ReviewMetric.tagTop - (ReviewMetric.tap - ReviewMetric.pill) / 2)
        }
        .padding(.horizontal, ReviewMetric.side)
        .padding(.top, ReviewMetric.top)
        .padding(.bottom, ReviewMetric.bottom)
    }
}
