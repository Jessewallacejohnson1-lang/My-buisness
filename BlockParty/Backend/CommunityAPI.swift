//
//  CommunityAPI.swift
//  Block Party — the community query layer, PostgREST over URLSession.
//
//  Every query mirrors packages/core/src/community.ts: same tables, same filters,
//  same client-side derivation of going_count / member_count / rsvpd / joined /
//  from_joined_club via the N+1 batch pattern. RLS is enforced server-side.
//

import CoreLocation
import Foundation

/// One thing waiting for the admin's yes (`list_held`, BP app launch-ready 07): a neighbour's Event or post the
/// instant check didn't pass on, or a found Event (ADR-021).
struct PendingPost: Identifiable, Hashable, Decodable {
    let id: String
    let kind: PostKind
    /// When the instant check was asked and gave no answer; nil when it never checked.
    let checkedAt: String?
    let card: ReviewCard
    /// Nil for a found Event, or a neighbour whose account is gone.
    let poster: ReviewPoster?
}

/// Why the admin declined an event in the Review queue (`club_events.review_reason`).
/// The misread share of found events decides when they may publish on their own.
enum DeclineReason: String, CaseIterable, Identifiable {
    case notEvent = "not_event", wrongWhen = "wrong_when", wrongPlace = "wrong_place",
         wrongTitle = "wrong_title", other
    var id: String { rawValue }

    /// Placeholder words; Jesse writes the final ones.
    var label: String {
        switch self {
        case .notEvent: "Not an event"
        case .wrongWhen: "Wrong date or time"
        case .wrongPlace: "Wrong place"
        case .wrongTitle: "Wrong title"
        case .other: "Something else"
        }
    }
}

/// A friend Going as `get_town_feed` and `get_my_going` send them: first name and photo
/// (town-feed 28, you-tab 07).
private struct FriendRow: Decodable {
    let name: String
    let photo: String?
    var feed: FeedFriend { FeedFriend(name: name, photo: photo.flatMap(URL.init(string:))) }
}

/// The app's one Event decoder: an Event card (`private.event_cards`, BP app codebase-health-2), everything
/// one Event shows wherever it appears, as every Event read sends it in its `card` (the Town feed, the Event
/// of the day, Going, Liked and the bell). A new Event field is one key in the card source and one here.
extension UpcomingEvent: Decodable {
    /// A card that doesn't decode is no Event: that row is left out, never the read.
    struct Lenient: Decodable {
        let value: UpcomingEvent?
        init(from decoder: Decoder) { value = try? UpcomingEvent(from: decoder) }
    }

    private enum CardKeys: String, CodingKey {
        case id, title, eventDate, startTime, location, imageUrl, category, clubName, sourceName, endAt, allDay,
             createdAt, goingCount, going, heartCount, hearted, cancelled, placePicture, hostPicture, description, what,
             sourceUrl, game, friendsGoing, liveKind, recurrence
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CardKeys.self)
        func text(_ key: CardKeys) throws -> String? { try c.decodeIfPresent(String.self, forKey: key) }
        self.init(id: try c.decode(String.self, forKey: .id), title: try c.decode(String.self, forKey: .title),
                  eventDate: try c.decode(String.self, forKey: .eventDate), startTime: try text(.startTime),
                  location: try text(.location), goingCount: try c.decode(Int.self, forKey: .goingCount),
                  createdAt: try c.decode(String.self, forKey: .createdAt), imageUrl: try text(.imageUrl),
                  rsvpd: try c.decodeIfPresent(Bool.self, forKey: .going) ?? false, clubName: try text(.clubName),
                  category: EventCategory.from(try text(.category)), endAt: DateHelpers.timestamp(try text(.endAt)),
                  isAllDay: try c.decodeIfPresent(Bool.self, forKey: .allDay) ?? false,
                  sourceName: try text(.sourceName),
                  cancelled: try c.decodeIfPresent(Bool.self, forKey: .cancelled) ?? false,
                  placePicture: try c.decodeIfPresent(PlacePicture.Lenient.self, forKey: .placePicture)?.value,
                  hostPicture: try c.decodeIfPresent(PlacePicture.Lenient.self, forKey: .hostPicture)?.value,
                  description: try text(.description),
                  game: try c.decodeIfPresent(Game.Lenient.self, forKey: .game)?.value, what: try text(.what),
                  sourceURL: try text(.sourceUrl).flatMap(URL.init(string:)),
                  friendsGoing: (try c.decodeIfPresent([FriendRow].self, forKey: .friendsGoing) ?? []).map(\.feed),
                  liveKind: try c.decodeIfPresent(Bool.self, forKey: .liveKind) ?? false,
                  recurrence: try text(.recurrence))
        // A card kept from before it carried the heart (inside-cards 16) says none.
        heartCount = try c.decodeIfPresent(Int.self, forKey: .heartCount) ?? 0
        hearted = try c.decodeIfPresent(Bool.self, forKey: .hearted) ?? false
    }
}

struct CommunityAPI {
    let db: Supabase

    init(auth: any TokenProviding, send: Supabase.Send = .live) { db = Supabase(auth: auth, send: send) }
    /// Through a client already made: the session's one (`AppSession`).
    init(_ db: Supabase) { self.db = db }

    /// "Real events only" guard, appended to every event *display* query.
    /// Every legitimate insert stamps `submitted_by` (addEvent / addTrail), and a
    /// found event (ADR-021) records where it was read instead, in `source_name`.
    /// A row with neither was never created by a person in-app nor read from a
    /// source — it's seed / demo / fabricated content — so it can never surface,
    /// even if one lands in the shared DB. The `status=eq.approved` beside this is
    /// what keeps a found event hidden until the admin approves it. Trails
    /// intentionally omit this (curated reference data). A followers-only Event (a JV
    /// game, a banquet: BP app school-activities 03) reaches its followers through the Town feed alone.
    private static let realOnly: Supabase.Query = [("or", "(submitted_by.not.is.null,source_name.not.is.null)"),
                                                   ("followers_only", "is.false")]

    // MARK: - Places (permanent food/business POI markers)

    /// The town's permanent venues, seeded once into Supabase. Read
    /// once by the map — no live Google Places call per map load. RLS opens reads, to
    /// the anon role too, so signed out (sign-in is switched off) they are read with the
    /// app's public key instead of failing into an empty map and an empty Search.
    func getPlaces() async throws -> [POI] {
        try Supabase.decode(await db.rest("places", [("select", "*")], anon: true))
    }

    /// The photos Block Party keeps of each place (`public.place_photos`, live rows readable with
    /// the public key), by registry entry, cover first: Search's cards and business pages draw
    /// them, so showing one costs no lookup (MEMORY.md, 2026-11-01). Logos stay out; Search has its own.
    func getPlacePhotos() async throws -> [String: [PlacePicture]] {
        // ponytail: one read of every town's live photos (183 on 2026-10-17); Supabase answers at
        // most 1,000 rows, so past that read this town's entries' photos, or page through them.
        try Self.placePhotos(from: await db.rest("place_photos", [
            ("select", "entry_id,url,kind,credit,site:source_url"), ("status", "eq.live"), ("kind", "eq.photo"),
            ("order", "position.asc"),
        ], anon: true))
    }

    /// Each place's name over its photo (`public.place_names`), by registry entry (BP app follows 02).
    func getPlaceNames() async throws -> [String: PlaceName] {
        struct Row: Decodable { let entryId: String; let url: String; let kind: String }
        let rows: [Row] = try Supabase.decode(await db.rest("place_names", [("select", "entry_id,url,kind")], anon: true))
        return Dictionary(rows.compactMap { row in
            URL(string: row.url).map { (row.entryId, PlaceName(url: $0, emblem: row.kind == "emblem")) }
        }, uniquingKeysWith: { first, _ in first })
    }

    /// The name over an Event's photo: its place's, or nil.
    func eventPlaceName(_ eventID: String) async throws -> PlaceName? {
        struct Row: Decodable { let url: String; let kind: String }
        let data = try await db.rpc("event_place_name", ["p_event": eventID], anon: true)
        guard let row = try? Supabase.decode(data, as: Row.self), let url = URL(string: row.url) else { return nil }
        return PlaceName(url: url, emblem: row.kind == "emblem")
    }

    /// A row that doesn't decode is that one photo gone, never the rest.
    nonisolated static func placePhotos(from data: Data) throws -> [String: [PlacePicture]] {
        struct Row: Decodable {
            let entry: String?
            let picture: PlacePicture?
            private enum Keys: String, CodingKey { case entryId }
            init(from decoder: Decoder) throws {
                entry = try? decoder.container(keyedBy: Keys.self).decode(String.self, forKey: .entryId)
                picture = try? PlacePicture(from: decoder)
            }
        }
        var photos: [String: [PlacePicture]] = [:]
        for row in try Supabase.decode(data, as: [Row].self) {
            if let entry = row.entry, let picture = row.picture { photos[entry, default: []].append(picture) }
        }
        return photos
    }

    // MARK: - Clubs

    /// Every approved group, in the shelf's order, with its pictures, next get-togethers and
    /// member count (`get_groups`, BP app rsvp-and-groups 05). Signed out, it reads with the
    /// public key and every group says not joined.
    func getGroups() async throws -> [TownGroup] {
        try Supabase.decode(await db.rpc("get_groups", anon: true))
    }

    func joinClub(_ clubId: String) async throws {
        let uid = try db.userID
        // ignore-duplicates: membership is presence-only and club_members has no
        // UPDATE policy, so merge-duplicates (ON CONFLICT DO UPDATE) fails RLS on rejoin.
        try await db.rest("club_members", method: "POST", [("on_conflict", "club_id,user_id")],
                          body: ["club_id": clubId, "user_id": uid],
                          prefer: "resolution=ignore-duplicates,return=minimal")
    }

    func leaveClub(_ clubId: String) async throws {
        let uid = try db.userID
        try await db.rest("club_members", method: "DELETE", [("club_id", "eq.\(clubId)"), ("user_id", "eq.\(uid)")])
    }

    // MARK: - Events (the map)

    /// Where each of these Events really is (`club_events.lat,lng`, set by the morning job
    /// from the source registry), by id. One with no spot is left out. Signed out, it reads
    /// with the public key, as the Town feed does.
    func eventSpots(_ ids: [String]) async throws -> [String: CLLocationCoordinate2D] {
        guard !ids.isEmpty else { return [:] }
        struct Row: Decodable { let id: String; let lat: Double?; let lng: Double? }
        let rows: [Row] = try Supabase.decode(await db.rest("club_events", [
            ("select", "id,lat,lng"), ("lat", "not.is.null"), ("id", "in.(\(ids.joined(separator: ",")))"),
        ], anon: true))
        return Dictionary(rows.compactMap { r in
            guard let lat = r.lat, let lng = r.lng else { return nil }
            return (r.id, CLLocationCoordinate2D(latitude: lat, longitude: lng))
        }, uniquingKeysWith: { a, _ in a })
    }

    /// The Town feed, in its order: what's in it, when each event leaves, and a series
    /// once with how it repeats, all worked out by `get_town_feed`, the one function
    /// iOS and Android both call. Signed out, it reads with the public key, as
    /// `getPlaces` does. It asks for town news too (town-feed 35); an app that doesn't
    /// gets the events alone.
    func getTownFeed() async throws -> [TownFeedLine] {
        let data = try await db.rpc("get_town_feed", ["p_news": true], anon: true)
        return try await Self.unpackTownFeed(data)
    }

    /// The feed's rows, unpacked and kept on disk off the main thread: on it, they froze the
    /// launch's ball for 70 ms as they landed (Jesse's phone, 2026-11-07, BP app
    /// references/launch-glitch).
    @concurrent
    private nonisolated static func unpackTownFeed(_ data: Data) async throws -> [TownFeedLine] {
        let lines = try townFeedLines(from: data)
        TownFeedCache.save(data)
        return lines
    }

    /// Past the ranked feed (town-feed 23): the 20 soonest Events past their show-from day, in the
    /// feed's own rows, under the same rules. Never kept on disk.
    func getTownFeedLater() async throws -> [TownFeedRow] {
        let data = try await db.rpc("get_town_feed", ["p_news": false, "p_later": true], anon: true)
        return try Self.townFeedRows(from: data)
    }

    /// One round past the later Events (town-feed 23): places to try and repeats, as kinds and ids
    /// in `get_town_more`'s order. `opened`: the places whose page this phone opened, which go last;
    /// `shown`: the ids of the list on screen, the only ones a repeat can be. Ids that aren't the
    /// database's (samples) are left out, as a list of them would be refused.
    func getTownMore(round: Int, opened: [String], shown: [String]) async throws -> [TownMoreRow] {
        let ids = { (ids: [String]) in ids.filter { UUID(uuidString: $0) != nil } }
        let data = try await db.rpc("get_town_more", ["p_round": round, "p_opened": ids(opened), "p_shown": ids(shown)],
                                    anon: true)
        return try JSONDecoder().decode([TownMoreRow].self, from: data)
    }

    /// Your Event of the day: today's standouts for you, one for each part of the day, worked
    /// out by `get_event_of_the_day` (BP app daily-tab 14) from the morning's picks, in the
    /// Town feed's own rows. Signed out, it reads with the public key, as the feed does.
    /// Given a moment (Daily's week, daily-tab 16), it reads that moment's Town day instead:
    /// with no morning picks written ahead, the Town's top pick there. Only today's go on disk.
    func getEventOfTheDay(at moment: Date? = nil) async throws -> [TownFeedRow] {
        let args = moment.map { ["p_now": DateHelpers.timestampString($0)] } ?? [:]
        let data = try await db.rpc("get_event_of_the_day", args, anon: true)
        let rows = try Self.townFeedRows(from: data)
        if moment == nil { TownFeedCache.save(data, .eventOfTheDay) }
        return rows
    }

    /// `get_town_feed`'s Events, without its news.
    static func townFeedRows(from data: Data) throws -> [TownFeedRow] {
        try townFeedLines(from: data).compactMap { line -> TownFeedRow? in
            if case .event(let row) = line { return row }
            return nil
        }
    }

    /// `get_town_feed`'s rows as Events, news and posts, in its order. A row whose `leaves_at`
    /// doesn't parse is dropped: it would have no moment to leave; so is news with no
    /// post to open, and an Event whose card doesn't decode.
    nonisolated static func townFeedLines(from data: Data) throws -> [TownFeedLine] {
        /// An Event row is its card plus the feed's own; news and posts carry their own columns.
        struct Row: Decodable {
            let id: String
            /// News and posts only, as the place, words, photo and dates below: an Event's are its card's.
            let title: String?
            let location: String?
            let imageUrl: String?
            let sourceName: String?
            let createdAt: String?
            let leavesAt: String
            let reason: String?
            let reasonName: String?
            let heartCount: Int?
            let hearted: Bool?
            let placePicture: PlacePicture.Lenient?
            let description: String?
            /// Optional, so a feed kept on disk before rsvp-and-groups 07 still decodes.
            let clubId: String?
            let inClub: Bool?
            /// "news" for town news, "post" for a neighbour's post, else an Event (town-feed 35), and the post
            /// news came from.
            let kind: String?
            let sourceUrl: String?
            /// A post's neighbour, the friends they tagged and its photo's shape (town-feed 29).
            let poster: LenientPoster?
            /// The Event card (BP app codebase-health-2); nil on news and posts.
            let card: UpcomingEvent.Lenient?
        }
        /// Who posted a post, or nil when it doesn't decode: that post is left out, never the feed.
        struct LenientPoster: Decodable {
            struct Poster: Decodable {
                struct Tag: Decodable { let id: String; let name: String }
                let id: String
                let name: String
                let photo: String?
                let tagged: [Tag]?
                let aspect: Double?
                let friendsOnly: Bool?
            }
            let value: Poster?
            init(from decoder: Decoder) { value = try? Poster(from: decoder) }
        }
        return try Supabase.decode(data, as: [Row].self).compactMap { row -> TownFeedLine? in
            guard let leavesAt = DateHelpers.timestamp(row.leavesAt) else { return nil }
            if row.kind == "post" {
                guard let poster = row.poster?.value, !poster.name.isEmpty, let words = row.title,
                      let posted = DateHelpers.timestamp(row.createdAt) else { return nil }
                return .post(TownPost(id: row.id, poster: .init(id: poster.id, name: poster.name),
                                      posterPhoto: poster.photo.flatMap(URL.init(string:)), words: words,
                                      photo: row.imageUrl.flatMap(URL.init(string:)), aspect: poster.aspect,
                                      place: row.location,
                                      tagged: (poster.tagged ?? []).map { .init(id: $0.id, name: $0.name) },
                                      friendsOnly: poster.friendsOnly ?? false,
                                      posted: posted, leavesAt: leavesAt, heartCount: row.heartCount ?? 0,
                                      hearted: row.hearted ?? false))
            }
            if row.kind == "news" {
                guard let post = row.sourceUrl.flatMap(URL.init(string:)), let title = row.title else { return nil }
                let words = row.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return .news(TownNews(id: row.id, place: row.sourceName ?? "",
                                      words: words.isEmpty ? title : words, post: post,
                                      picture: row.placePicture?.value, leavesAt: leavesAt,
                                      published: DateHelpers.timestamp(row.createdAt), title: title,
                                      interest: row.reason == "interest" ? row.reasonName : nil))
            }
            guard let event = row.card?.value else { return nil }
            return .event(TownFeedRow(event: event, leavesAt: leavesAt,
                                      reason: row.reason, reasonName: row.reasonName,
                                      heartCount: row.heartCount ?? 0, hearted: row.hearted ?? false,
                                      groupID: row.clubId, inGroup: row.inClub ?? false))
        }
    }

    func rsvpEvent(_ eventId: String) async throws {
        let uid = try db.userID
        // ignore-duplicates: an RSVP is presence-only and event_rsvps has no UPDATE
        // policy, so merge-duplicates (ON CONFLICT DO UPDATE) fails RLS on re-RSVP —
        // which the feed's join button hits whenever its optimistic state drifts.
        try await db.rest("event_rsvps", method: "POST", [("on_conflict", "event_id,user_id")],
                          body: ["event_id": eventId, "user_id": uid],
                          prefer: "resolution=ignore-duplicates,return=minimal")
    }

    /// The Town feed's views and opens (ticket 20), in one insert, and which News went by (town-feed 41).
    /// Who and when are set by the database; nobody reads them back. Ids that aren't real (samples) are
    /// skipped.
    func recordFeedActions(_ batch: [FeedAction]) async throws {
        guard !Self.isSimulator else { return }
        let real = batch.filter { UUID(uuidString: $0.itemID) != nil }
        let news = real.filter { $0.kind == .news }.map(\.itemID)
        let rows = real.filter { $0.kind != .news }.map { ["item_id": $0.itemID, "action": $0.kind.rawValue] }
        if !rows.isEmpty { try await db.rest("feed_actions", method: "POST", body: rows, prefer: "return=minimal") }
        if !news.isEmpty { _ = try await db.rpc("see_news", ["p_items": news]) }
    }

    /// A simulator's views, opens and shares stay off the server: each simulator is its own quiet
    /// test account, and on 2026-10-26 they were 17 of the day's 18 opens in Jesse's weekly numbers.
    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    /// Today's first open of the app, for the weekly numbers' reach (town-feed 26). The database
    /// keeps one row per person per Town day, so calling it on every return is harmless.
    func recordOpen() async throws {
        guard !Self.isSimulator else { return }
        try await db.rpc("record_open")
    }

    /// Not interested, Mute and their undoing (town-feed 21), straight away. A Mute answers with
    /// the host it muted, which Unmute names. Ids that aren't Events (samples) send nothing.
    func feedChoice(_ choice: FeedChoice) async throws -> String? {
        switch choice {
        case .notInterested(let id), .undoNotInterested(let id):
            guard UUID(uuidString: id) != nil else { return nil }
            try await db.rpc("set_not_interested", ["p_item": id, "p_on": choice == .notInterested(id)])
            return nil
        case .mute(let id):
            guard UUID(uuidString: id) != nil else { return nil }
            let data = try await db.rpc("mute_host", ["p_item": id])
            return try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String
        case .report(let id, let reason):
            guard UUID(uuidString: id) != nil else { return nil }
            let data = try await db.rpc("report_event", ["p_event": id, "p_reason": reason.rawValue])
            // A neighbour's posting goes back through the AI check (town-feed 22), moderate-post asked to
            // read it again. The function claims it once and lets go if the model doesn't answer, so a
            // lost call is retried by the next report; the reporter never waits.
            if (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? Bool) == true {
                Task { try? await db.invoke("moderate-post", ["recheck": id]) }
            }
            return nil
        case .unmute(let host):
            try await db.rest("feed_mutes", method: "DELETE", [("host", "eq.\(host)")])
            return nil
        }
    }

    /// The hosts you muted, newest first: Profile's Muted list (town-feed 21).
    func mutedHosts() async throws -> [MutedHost] {
        try Supabase.decode(await db.rest("feed_mutes", [("select", "host,name"), ("order", "at.desc")]))
    }

    func unRsvpEvent(_ eventId: String) async throws {
        let uid = try db.userID
        try await db.rest("event_rsvps", method: "DELETE", [("event_id", "eq.\(eventId)"), ("user_id", "eq.\(uid)")])
    }

    func addEvent(_ input: NewEventInput, clubId: String? = nil, status: ClubStatus = .pending) async throws {
        let uid = try db.userID
        var b: [String: Any] = [
            "title": input.title, "event_date": input.eventDate, "start_time": input.startTime,
            "location": input.location, "submitted_by": uid, "status": status.rawValue,
            "club_id": clubId ?? NSNull(), "category": input.category,
        ]
        if let v = input.id { b["id"] = v }
        if let v = input.description { b["description"] = v }
        if let v = input.imageUrl { b["image_url"] = v }
        try await db.rest("club_events", method: "POST", body: b, prefer: "return=minimal")
    }

    /// A new Event's photo, in your own folder of `event-images` (BP app town-plus): where it can
    /// be read.
    func uploadEventPhoto(_ jpeg: Data, id: String) async throws -> URL {
        let uid = try db.userID.lowercased()
        return try await db.upload(bucket: "event-images", path: "\(uid)/\(id).jpg", jpeg, type: "image/jpeg")
    }

    /// Where that photo is, once sent: for a retry told it's already there.
    func eventPhotoURL(id: String) -> URL? {
        guard let uid = try? db.userID.lowercased() else { return nil }
        return SupabaseConfig.url.appendingPathComponent("storage/v1/object/public/event-images/\(uid)/\(id).jpg")
    }

    /// A neighbour's post (BP app town-feed 29), pending until the instant check (`checkNewEvent`) says
    /// yes: its words, maybe a photo and its shape, a Place, who can see it and the friends tagged.
    func addPost(_ post: NewPostInput) async throws {
        let uid = try db.userID
        let b: [String: Any] = [
            "id": post.id, "kind": PostKind.post.rawValue, "title": post.words, "submitted_by": uid,
            "status": ClubStatus.pending.rawValue, "location": post.place ?? NSNull(),
            "image_url": post.imageURL ?? NSNull(), "image_aspect": post.aspect ?? NSNull(),
            "friends_only": post.friendsOnly, "tagged": post.tagged.isEmpty ? NSNull() : post.tagged,
            "event_date": NSNull(), "start_time": NSNull(),
        ]
        try await db.rest("club_events", method: "POST", body: b, prefer: "return=minimal")
    }

    /// Your own post goes, its photo with it (town-feed 29). The row first: a photo left behind is
    /// only a file, a row left without its photo would be a broken card. Once the row is gone the post
    /// is, whatever the photo's answer.
    func deletePost(_ id: String, photo: Bool) async throws {
        try await db.rest("club_events", method: "DELETE", [("id", "eq.\(id)")], prefer: "return=minimal")
        guard photo, let uid = try? db.userID.lowercased() else { return }
        // ponytail: a photo whose delete fails stays in Storage; sweep orphans if they ever add up.
        do { try await db.removeFile(bucket: "event-images", path: "\(uid)/\(id).jpg") } catch {
            Log.network("CommunityAPI: post \(id)'s photo left in Storage: \(error)")
        }
    }

    /// The instant check on your own pending Event (`moderate-post` `submit`, BP app town-plus): live,
    /// or no with the reason. Anything else, the day's 10 used or no answer, leaves it waiting
    /// for Review.
    func checkNewEvent(_ id: String) async -> NewEventCheck {
        struct Answer: Decodable { let ok: Bool; let reason: String? }
        guard let data = try? await db.invoke("moderate-post", ["submit": id]),
              let answer = try? JSONDecoder().decode(Answer.self, from: data) else { return .waiting }
        return Self.check(ok: answer.ok, reason: answer.reason)
    }

    /// A no without words still says something the poster can act on.
    nonisolated static func check(ok: Bool, reason: String?) -> NewEventCheck {
        if ok { return .live }
        let words = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return .declined(words.isEmpty ? "This can't be shared as it is. Try saying what happens and when." : words)
    }

    /// Each upcoming Event's interests (its tags once tagged, else its one category), for the
    /// interest chips' "Popular in St. Joseph" (BP app onboarding 20), and whose it is, for the
    /// places Follow 3 suggests (onboarding 22).
    func upcomingTags() async throws -> [UpcomingTags] {
        struct Row: Decodable {
            let interests: [String]?; let category: String?; let interestsTaggedAt: String?
            let placeEntryId: String?; let teamIds: [String]?; let activityTeam: String?; let sourceName: String?
        }
        // Before the account exists (step 7 comes before phone sign-in lands), the public key reads.
        // ponytail: Supabase answers at most 1,000 rows (games are most of them); page through if counts matter.
        let rows: [Row] = try Supabase.decode(await db.rest("club_events", [
            ("select", "interests,category,interests_tagged_at,place_entry_id,team_ids,activity_team,source_name"),
            ("status", "eq.approved"), ("kind", "eq.event"), ("cancelled_at", "is.null"),
            ("event_date", "gte.\(Town.day(Date()))"),
        ] + Self.realOnly, anon: true))
        return rows.map {
            UpcomingTags(interests: $0.interestsTaggedAt == nil ? [$0.category].compactMap { $0 } : $0.interests ?? [],
                         place: $0.placeEntryId, teams: ($0.teamIds ?? []) + [$0.activityTeam].compactMap { $0 },
                         source: $0.sourceName)
        }
    }

    /// The Town's own schools (`teams.local`) and pages (`town_pages`), which Follow 3 suggests
    /// beside its Places (onboarding 22). Read with the public key, as there may be no account yet.
    func followableSchoolsAndPages() async throws -> (schools: [LocalSchool], pages: [TownPageRow]) {
        async let schools = db.rest("teams", [("select", "id,uuid,name,school_name,logo_url"), ("local", "eq.true")], anon: true)
        async let pages = db.rest("town_pages", [("select", "id,slug,name,kind,source_name,picture,picture_kind"),
                                                 ("town", "eq.\(Town.slug)")], anon: true)
        return (try Supabase.decode(await schools), try Supabase.decode(await pages))
    }

    // MARK: - Neighbours (BP app docs/plans/friends)

    /// One neighbour by id, as search answers them: `get_neighbor`. nil for nobody you can find.
    func getNeighbor(_ userId: String) async throws -> Neighbor? {
        let rows: [Neighbor] = try Supabase.decode(await db.rpc("get_neighbor", ["p_user": userId]))
        return rows.first
    }

    /// Neighbours whose name, or a later word of it, starts with `words`: `search_neighbors`,
    /// which answers a real account only and never returns Anonymous or nameless accounts.
    func searchNeighbors(_ words: String) async throws -> [Neighbor] {
        try Supabase.decode(await db.rpc("search_neighbors", ["p_words": words]))
    }

    /// The Friends page (`get_friends`): accepted lines, requests newest first, friends A to
    /// Z, each as `kind` and the neighbour (ticket 03).
    func getFriends() async throws -> [(kind: String, neighbor: Neighbor)] {
        struct Kind: Decodable { let kind: String }
        let data = try await db.rpc("get_friends")
        let kinds: [Kind] = try Supabase.decode(data)
        let people: [Neighbor] = try Supabase.decode(data)
        return zip(kinds, people).map { ($0.kind, $1) }
    }

    /// The people you blocked, newest first: Profile's Blocked list (ticket 04).
    func getBlocked() async throws -> [Neighbor] {
        try Supabase.decode(await db.rpc("get_blocked"))
    }

    /// Which of your contacts are on Block Party (`match_contacts`, friends 06): the scrambled
    /// emails and phone numbers go, each neighbour comes back with the code that found them.
    func matchContacts(emails: [String], phones: [String]) async throws -> [(code: String, neighbor: Neighbor)] {
        struct Code: Decodable { let code: String }
        let data = try await db.rpc("match_contacts", ["p_emails": emails, "p_phones": phones])
        let codes: [Code] = try Supabase.decode(data)
        let people: [Neighbor] = try Supabase.decode(data)
        return zip(codes, people).map { ($0.code, $1) }
    }

    /// People you may know, strongest first, at most 20 (daily-tab 22).
    func peopleYouMayKnow() async throws -> [Neighbor] {
        try Supabase.decode(await db.rpc("get_people_you_may_know"))
    }

    /// The X on a suggestion: that person never comes back on your list.
    func hideSuggestion(_ userID: String) async throws {
        try await db.rpc("hide_suggestion", ["p_user": userID])
    }

    /// A request newer than your last visit to Friends: the dot on the Friends tab.
    func friendsDot() async throws -> Bool {
        let data = try await db.rpc("friends_dot")
        return try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? Bool ?? false
    }

    /// The Friends page has drawn what it read: the dot clears and accepted lines go.
    func markFriendsSeen() async throws {
        try await db.rpc("mark_friends_seen")
    }

    /// Add friend, Cancel, Confirm, Delete, Unfriend, Block or Unblock with one person; answers
    /// where you two now stand.
    func friendWrite(_ action: FriendsBook.Action, _ userID: String) async throws -> Neighbor.Relation {
        let (function, key) = switch action {
        case .add: ("send_friend_request", "p_to")
        case .cancel: ("cancel_friend_request", "p_to")
        case .confirm: ("confirm_friend_request", "p_from")
        case .delete: ("delete_friend_request", "p_from")
        case .unfriend: ("unfriend", "p_user")
        case .block: ("block_neighbor", "p_user")
        case .unblock: ("unblock_neighbor", "p_user")
        }
        let data = try await db.rpc(function, [key: userID])
        let raw = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String
        guard let relation = raw.flatMap(Neighbor.Relation.init(rawValue:)) else {
            throw SupabaseError(message: "Unexpected answer", status: nil)
        }
        return relation
    }

    // MARK: - Follows (BP app docs/plans/follows, ticket 02)

    /// Follow or unfollow a Place or person: `follow_target` and `unfollow_target`, for a real
    /// account only. Following twice, or unfollowing twice, is fine.
    func followWrite(_ target: FollowTarget, _ on: Bool) async throws {
        try await db.rpc(on ? "follow_target" : "unfollow_target", ["p_type": target.type.rawValue, "p_id": target.id])
    }

    /// What a page shows of it: the count, your friends who follow it, and whether you do.
    /// Signed out too: then the count alone.
    func followCard(_ target: FollowTarget) async throws -> FollowCard {
        let rows: [FollowCard] = try Supabase.decode(await db.rpc("follow_card", ["p_type": target.type.rawValue,
                                                                                  "p_id": target.id], anon: true))
        guard let card = rows.first else { throw SupabaseError(message: "Unexpected answer", status: nil) }
        return card
    }

    /// A local team's page: who it is and its next games (hello-drop 03). nil for a team that
    /// isn't local.
    func teamPage(_ id: String) async throws -> TeamProfile? {
        let data = try await db.rpc("team_page", ["p_team": id], anon: true)
        return try? Supabase.decode(data)
    }

    /// One activity's coming events, soonest first: its row's arrow (school-activities 02).
    func activityEvents(_ id: String) async throws -> [TeamProfile.ActivityEvent] {
        try Supabase.decode(await db.rpc("activity_events", ["p_activity": id], anon: true))
    }

    /// The Town's own page or its City's (follows 04), or another by its id (a campus calendar's,
    /// follows 08): who it is, its coming Events and, for the City, its boards. nil when there is no
    /// such page.
    func townPage(_ kind: TownPageKind) async throws -> TownPageInfo? {
        let data = switch kind {
        case .town, .city:
            try await db.rpc("town_page", ["p_town": Town.slug, "p_slug": kind == .town ? "town" : "city"], anon: true)
        case .page(let id, _):
            try await db.rpc("town_page_by_id", ["p_id": id], anon: true)
        }
        return try? Supabase.decode(data)
    }

    /// One board's coming meetings, soonest first: its row on the City's page.
    func boardMeetings(_ id: String) async throws -> [TownPageInfo.Event] {
        try Supabase.decode(await db.rpc("board_meetings", ["p_board": id], anon: true))
    }

    /// Finals your followed teams played, read since `since`, newest first: the hello pill's
    /// "Johnnies beat Gustavus 33–23".
    func myTeamFinals(since: Date) async throws -> [TeamFinal] {
        try Supabase.decode(await db.rpc("my_team_finals", ["p_since": DateHelpers.timestampString(since)]))
    }

    /// Everyone and everything you follow, A to Z: Profile's Following list.
    func myFollows() async throws -> [FollowRow] {
        try Supabase.decode(await db.rpc("my_follows"))
    }

    /// Who hosts an Event, for its page's host line: nil for a Group's Event or one at no known Place.
    func eventHost(_ eventID: String) async throws -> FollowRow? {
        let rows: [FollowRow] = try Supabase.decode(await db.rpc("event_host", ["p_event": eventID], anon: true))
        return rows.first
    }

    // MARK: - My Going (the You tab)

    /// The neighbour's Going from `from` to `to`, Town days as "yyyy-MM-dd", both ends
    /// included, past days too: `get_my_going`, the one function iOS and Android call
    /// (BP app docs/plans/you-tab). Ordered by day; the You page orders a day by start.
    func getMyGoing(from: String, to: String) async throws -> [UpcomingEvent] {
        try Self.myGoingRows(from: await db.rpc("get_my_going", ["p_from": from, "p_to": to]))
    }

    /// The Events the neighbour hearted from `from` on, a Town day as "yyyy-MM-dd", and any
    /// from before it still running: `get_my_likes`, You's Liked list (BP app inside-cards 16).
    /// Each card says it's hearted and whether they're Going.
    func getMyLikes(from: String) async throws -> [UpcomingEvent] {
        try Self.myGoingRows(from: await db.rpc("get_my_likes", ["p_from": from]))
    }

    /// The caller's canceled and moved Events still to come, newest change first: `get_my_changes`,
    /// what the bell's Notifications page lists (BP app docs/plans/school-activities, ticket 04).
    func getMyChanges() async throws -> [Notice] {
        try Self.changeRows(from: await db.rpc("get_my_changes"))
    }

    /// `get_my_changes`' rows: each an Event card with what changed, where it moved from and what you follow
    /// that it is of. A row whose card doesn't decode is left out, never the bell.
    static func changeRows(from data: Data) throws -> [Notice] {
        struct Row: Decodable {
            let card: UpcomingEvent.Lenient?
            let changedAt: String
            let movedFrom: Notice.Was?
            let followed: String?
            let followedLogo: String?
        }
        return try Supabase.decode(data, as: [Row].self).compactMap { row in
            guard let event = row.card?.value, let changedAt = DateHelpers.timestamp(row.changedAt) else { return nil }
            return Notice(event: event, changedAt: changedAt, movedFrom: row.movedFrom, followed: row.followed,
                          followedLogo: row.followedLogo.flatMap(URL.init(string:)))
        }
    }

    /// `get_my_going`'s rows as events, each one the neighbour is Going to, and `get_my_likes`', whose
    /// card says whether they are. Each row is its Event card alone; one that doesn't decode is left
    /// out, never the read.
    static func myGoingRows(from data: Data) throws -> [UpcomingEvent] {
        struct Row: Decodable { let card: UpcomingEvent.Lenient? }
        return try Supabase.decode(data, as: [Row].self).compactMap { $0.card?.value }
    }

    // MARK: - Trails

    func addTrail(_ input: NewTrailInput, status: ClubStatus = .approved) async throws {
        let uid = try db.userID
        let b: [String: Any] = [
            "kind": "trail", "title": input.title, "location": input.location,
            "length": input.length ?? NSNull(), "difficulty": input.difficulty ?? NSNull(),
            "description": input.description ?? NSNull(), "image_url": input.imageUrl ?? NSNull(),
            "event_date": NSNull(), "start_time": NSNull(),
            "submitted_by": uid, "status": status.rawValue, "club_id": NSNull(),
        ]
        try await db.rest("club_events", method: "POST", body: b, prefer: "return=minimal")
    }

    // MARK: - Moderation (admin)

    /// What waits for the admin's yes, with its card, poster and whether the check was asked (`list_held`,
    /// BP app launch-ready 07). Admin only; anyone else gets none.
    func getPendingPosts() async throws -> [PendingPost] {
        try Supabase.decode(await db.rpc("list_held"))
    }

    func getPendingClubs() async throws -> [ClubRow] {
        try Supabase.decode(await db.rest("clubs", [("select", "*"), ("status", "eq.pending"), ("order", "created_at.desc")]))
    }

    /// Reported Events still up, newest report first (town-feed 22). Admin only; anyone else gets none.
    func reportedEvents() async throws -> [ReportedEvent] {
        try Supabase.decode(await db.rpc("list_reports"))
    }

    /// Keep a reported Event (its reports go) or take it down for everyone.
    func resolveReports(_ id: String, takeDown: Bool) async throws {
        try await db.rpc("resolve_reports", ["p_event": id, "p_take_down": takeDown])
    }

    func approvePost(_ id: String) async throws { try await patchStatus("club_events", id: id, status: .approved) }
    /// Decline with what was wrong. Approving never clears the reason (see the migration).
    func declinePost(_ id: String, reason: DeclineReason) async throws {
        try await db.rest("club_events", method: "PATCH", [("id", "eq.\(id)")],
                          body: ["status": ClubStatus.rejected.rawValue, "review_reason": reason.rawValue],
                          prefer: "return=minimal")
    }
    func setClubStatus(_ id: String, status: ClubStatus) async throws { try await patchStatus("clubs", id: id, status: status) }

    private func patchStatus(_ table: String, id: String, status: ClubStatus) async throws {
        try await db.rest(table, method: "PATCH", [("id", "eq.\(id)")], body: ["status": status.rawValue],
                          prefer: "return=minimal")
    }
}
