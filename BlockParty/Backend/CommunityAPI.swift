//
//  CommunityAPI.swift
//  Block Party — the @hygge/core query layer, ported 1:1 to PostgREST over URLSession.
//
//  Every query mirrors packages/core/src/community.ts: same tables, same filters,
//  same client-side derivation of going_count / member_count / rsvpd / joined /
//  from_joined_club via the N+1 batch pattern. RLS is enforced server-side.
//

import Foundation

struct PendingPost: Identifiable, Hashable {
    let trail: Trail
    let kind: PostKind
    let eventDate: String?
    let startTime: String?
    var allDay = false
    /// Set for a found event (ADR-021): who announced it, and the page it came from.
    var sourceName: String? = nil
    var sourceURL: URL? = nil
    var id: String { trail.id }
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

struct CommunityAPI {
    let db: Supabase

    init(auth: any TokenProviding, send: Supabase.Send = .live) { db = Supabase(auth: auth, send: send) }

    /// "Real events only" guard, appended to every event *display* query.
    /// Every legitimate insert stamps `submitted_by` (addEvent / addTrail), and a
    /// found event (ADR-021) records where it was read instead, in `source_name`.
    /// A row with neither was never created by a person in-app nor read from a
    /// source — it's seed / demo / fabricated content — so it can never surface,
    /// even if one lands in the shared DB. The `status=eq.approved` beside this is
    /// what keeps a found event hidden until the admin approves it. Trails
    /// intentionally omit this (curated reference data). The Expo twin (@hygge/core)
    /// still filters on `submitted_by` alone, so it hides found events. A followers-only Event (a JV
    /// game, a banquet: BP app school-activities 03) reaches its followers through the Town feed alone.
    private static let realOnly: Supabase.Query = [("or", "(submitted_by.not.is.null,source_name.not.is.null)"),
                                                   ("followers_only", "is.false")]

    // MARK: - User / admin

    func isAdmin() async -> Bool { Admin.isAdmin(db.auth.email) }

    // MARK: - Places (permanent food/business POI markers)

    /// The town's permanent venues, seeded once into Supabase (see PlaceSeeder). Read
    /// once by the map — no live Google Places call per map load. RLS opens reads, to
    /// the anon role too, so signed out (sign-in is switched off) they are read with the
    /// app's public key instead of failing into an empty map and an empty Search.
    func getPlaces() async throws -> [POI] {
        try Supabase.decode(await db.rest("places", [("select", "*")], anon: true))
    }

    /// The photos Block Party keeps of each place (`public.place_photos`, live rows readable with
    /// the public key), by registry entry, cover first: Search's cards and business pages draw
    /// them, so showing one costs no lookup (MEMORY.md, 2026-10-16). Logos stay out; Search has its own.
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

    /// The page a found Event was read from (`club_events.source_url`, ADR-021), for an Event page
    /// opened from a read that doesn't send it. Signed out, it reads with the public key.
    func eventSourceURL(_ eventID: String) async throws -> URL? {
        struct Row: Decodable { let sourceUrl: String? }
        let rows: [Row] = try Supabase.decode(await db.rest("club_events", [("select", "source_url"), ("id", "eq.\(eventID)")],
                                                            anon: true))
        return rows.first?.sourceUrl.flatMap(URL.init(string:))
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

    // MARK: - Events (timeline)

    func getTodayEvents() async throws -> [TimelineEvent] {
        try await timelineEvents(forDate: Town.day(.now))
    }

    private func timelineEvents(forDate date: String) async throws -> [TimelineEvent] {
        let uid = db.auth.userId
        let events: [RawEvent] = try Supabase.decode(await db.rest("club_events", [
            ("select", "*,clubs(name)"), ("status", "eq.approved"), ("kind", "eq.event"), ("event_date", "eq.\(date)"),
        ] + Self.realOnly + [("cancelled_at", "is.null"), ("order", "start_time.asc")], anon: true))
        var joined = Set<String>()
        if let uid {
            let mem: [MemberRow] = try Supabase.decode(await db.rest("club_members", [("select", "club_id"), ("user_id", "eq.\(uid)")],
                                                                     anon: true))
            for m in mem { joined.insert(m.clubId) }
        }
        return events.map { e in
            TimelineEvent(id: e.id, title: e.title, startTime: e.startTime, location: e.location,
                          clubName: e.clubs?.name,
                          fromJoinedClub: e.clubId != nil ? joined.contains(e.clubId!) : false,
                          details: e.description,
                          category: EventCategory.from(e.category),
                          imageURL: e.imageUrl.flatMap(URL.init(string:)),
                          placeEntryId: e.placeEntryId,
                          when: EventWhen(date: date, time: e.startTime,
                                          endAt: DateHelpers.timestamp(e.endAt), allDay: e.allDay ?? false))
        }
    }

    /// The Town feed, in its order: what's in it, when each event leaves, and a series
    /// once with how it repeats, all worked out by `get_town_feed`, the one function
    /// iOS and Android both call. Signed out, it reads with the public key, as
    /// `getPlaces` does. It asks for town news too (town-feed 35); an app that doesn't
    /// gets the events alone.
    func getTownFeed() async throws -> [TownFeedLine] {
        let data = try await db.rpc("get_town_feed", ["p_news": true], anon: true)
        let lines = try Self.townFeedLines(from: data)
        TownFeedCache.save(data)
        return lines
    }

    /// Your Event of the day: today's standouts for you, one for each part of the day, worked
    /// out by `get_event_of_the_day` (BP app daily-tab 14) from the morning's picks, in the
    /// Town feed's own rows. Signed out, it reads with the public key, as the feed does.
    /// Given a moment (Daily's week, daily-tab 16), it reads that moment's Town day instead:
    /// with no morning picks written ahead, the Town's top pick there. Only today's go on disk.
    func getEventOfTheDay(at moment: Date? = nil) async throws -> [TownFeedRow] {
        let args = moment.map { ["p_now": ISO8601DateFormatter().string(from: $0)] } ?? [:]
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

    /// `get_town_feed`'s rows as Events and news, in its order. A row whose `leaves_at`
    /// doesn't parse is dropped: it would have no moment to leave; so is news with no
    /// post to open.
    static func townFeedLines(from data: Data) throws -> [TownFeedLine] {
        struct Row: Decodable {
            let id: String
            let title: String
            /// nil on a news row (town-feed 35).
            let eventDate: String?
            let startTime: String?
            let location: String?
            let imageUrl: String?
            let category: String?
            let clubName: String?
            let sourceName: String?
            let endAt: String?
            let allDay: Bool
            let createdAt: String
            let goingCount: Int
            let rsvpd: Bool
            let recurrence: String?
            let leavesAt: String
            let reason: String?
            let reasonName: String?
            let score: LenientScore?
            let heartCount: Int?
            let hearted: Bool?
            let saved: Bool?
            let cancelled: Bool?
            /// Optional, so a feed kept on disk before town-feed 28 still decodes.
            let friendsGoing: [FriendRow]?
            let placePicture: PlacePicture.Lenient?
            let description: String?
            /// Optional, so a feed kept on disk before rsvp-and-groups 07 still decodes.
            let clubId: String?
            let inClub: Bool?
            /// A game's teams (game-card 01); one that doesn't decode leaves a photo card.
            let game: Game.Lenient?
            /// What it is in one to three words (event-card 05).
            let what: String?
            /// "news" for town news, else an Event (town-feed 35), and the post it came from.
            let kind: String?
            let sourceUrl: String?
            /// Who puts it on, its logo first (Jesse, 2026-10-23).
            let hostPicture: PlacePicture.Lenient?
        }
        /// The admin's breakdown, or nil when it doesn't decode: a score never costs the
        /// feed.
        struct LenientScore: Decodable {
            let value: FeedScore?
            init(from decoder: Decoder) { value = try? FeedScore(from: decoder) }
        }
        return try Supabase.decode(data, as: [Row].self).compactMap { row -> TownFeedLine? in
            guard let leavesAt = DateHelpers.timestamp(row.leavesAt) else { return nil }
            if row.kind == "news" {
                guard let post = row.sourceUrl.flatMap(URL.init(string:)) else { return nil }
                let words = row.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return .news(TownNews(id: row.id, place: row.sourceName ?? "",
                                      words: words.isEmpty ? row.title : words, post: post,
                                      picture: row.placePicture?.value, leavesAt: leavesAt,
                                      published: DateHelpers.timestamp(row.createdAt), title: row.title,
                                      interest: row.reason == "interest" ? row.reasonName : nil))
            }
            guard let eventDate = row.eventDate else { return nil }
            let event = UpcomingEvent(id: row.id, title: row.title, eventDate: eventDate,
                                      startTime: row.startTime, location: row.location,
                                      goingCount: row.goingCount, createdAt: row.createdAt,
                                      imageUrl: row.imageUrl, rsvpd: row.rsvpd,
                                      clubName: row.clubName,
                                      category: EventCategory.from(row.category),
                                      endAt: DateHelpers.timestamp(row.endAt),
                                      isAllDay: row.allDay, sourceName: row.sourceName,
                                      cancelled: row.cancelled ?? false,
                                      placePicture: row.placePicture?.value,
                                      hostPicture: row.hostPicture?.value,
                                      description: row.description, game: row.game?.value,
                                      what: row.what, sourceURL: row.sourceUrl.flatMap(URL.init(string:)))
            return .event(TownFeedRow(event: event, recurrence: row.recurrence, leavesAt: leavesAt,
                                      reason: row.reason, reasonName: row.reasonName, score: row.score?.value,
                                      heartCount: row.heartCount ?? 0, hearted: row.hearted ?? false,
                                      saved: row.saved ?? false,
                                      friendsGoing: (row.friendsGoing ?? []).map(\.feed),
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

    /// The Town feed's views and opens (ticket 20), in one insert. Who and when are set by
    /// the database; nobody reads them back. Ids that aren't Events (samples) are skipped.
    func recordFeedActions(_ batch: [FeedAction]) async throws {
        guard !Self.isSimulator else { return }
        let rows = batch.filter { UUID(uuidString: $0.itemID) != nil }
            .map { ["item_id": $0.itemID, "action": $0.kind.rawValue] }
        guard !rows.isEmpty else { return }
        try await db.rest("feed_actions", method: "POST", body: rows, prefer: "return=minimal")
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
        if let v = input.description { b["description"] = v }
        if let v = input.imageUrl { b["image_url"] = v }
        try await db.rest("club_events", method: "POST", body: b, prefer: "return=minimal")
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

    // MARK: - Your Day (the Today rail — one day, town time)

    /// How far back an event's `event_date` may sit and still be running today.
    ///
    /// A multi-day festival is ONE row whose `event_date` is its first day, so a
    /// strict `event_date=eq.today` filter would drop it on days two through five.
    /// The window cannot be expressed as an `end_at` predicate because that column
    /// is not applied yet, and querying a missing column is a 400 — so the read
    /// casts a slightly wide net by date and the overlap rule does the real
    /// filtering client-side. Two weeks is nothing for a town whose entire
    /// calendar is ~9 rows.
    /// Internal (not private) and nonisolated: a realtime subscriber that shows this window
    /// passes it to `ClubEventRelevance.matters`, and two copies of this number would drift.
    nonisolated static let dayLookbackDays = 14

    /// Which of these ids are Events, for moving the phone's old saves up to the server
    /// (`RealLifeActions.moveUp`): the phone's saved list holds the map's Places too.
    func knownEventIDs(_ ids: [String]) async throws -> Set<String> {
        guard !ids.isEmpty else { return [] }
        struct Row: Decodable { let id: String }
        let rows: [Row] = try Supabase.decode(await db.rest("club_events", [("select", "id"), ("id", "in.(\(ids.joined(separator: ",")))")],
                                                            anon: true))
        return Set(rows.map(\.id))
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

    /// A request newer than your last visit to Friends: the dot on the friends mark.
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
        try Supabase.decode(await db.rpc("my_team_finals", ["p_since": ISO8601DateFormatter().string(from: since)]))
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

    /// The neighbour's saved Events from `from` on, a Town day as "yyyy-MM-dd", and any
    /// from before it still running: `get_my_saves`, Profile's Saved list (BP app
    /// docs/plans/you-tab, ticket 04). Each comes back saved, saying whether they're Going.
    func getMySaves(from: String) async throws -> [UpcomingEvent] {
        try Self.myGoingRows(from: await db.rpc("get_my_saves", ["p_from": from]), saved: true)
    }

    /// The caller's canceled and moved Events still to come, newest change first: `get_my_changes`,
    /// what the bell's Notifications page lists (BP app docs/plans/school-activities, ticket 04).
    func getMyChanges() async throws -> [Notice] {
        try Self.changeRows(from: await db.rpc("get_my_changes"))
    }

    /// `get_my_changes`' rows: each an Event as `get_my_going` sends one, with what changed.
    static func changeRows(from data: Data) throws -> [Notice] {
        struct Row: Decodable {
            let changedAt: String
            let movedFrom: Notice.Was?
            let followed: String?
            let followedLogo: String?
            let game: Game.LenientItem<Game>?
        }
        let rows = try Supabase.decode(data, as: [Row].self)
        return zip(try myGoingRows(from: data), rows).compactMap { event, row in
            guard let changedAt = DateHelpers.timestamp(row.changedAt) else { return nil }
            var event = event
            event.game = row.game?.value
            return Notice(event: event, changedAt: changedAt, movedFrom: row.movedFrom, followed: row.followed,
                          followedLogo: row.followedLogo.flatMap(URL.init(string:)))
        }
    }

    /// `get_my_going`'s rows as events, each one the neighbour is Going to, and
    /// `get_my_saves`' (`saved`), whose `going` says whether they are.
    static func myGoingRows(from data: Data, saved: Bool = false) throws -> [UpcomingEvent] {
        struct Row: Decodable {
            let id: String
            let title: String
            let eventDate: String
            let startTime: String?
            let location: String?
            let imageUrl: String?
            let category: String?
            let clubName: String?
            let sourceName: String?
            let endAt: String?
            let allDay: Bool
            let createdAt: String
            let goingCount: Int
            let going: Bool?
            let cancelled: Bool?
            let placePicture: PlacePicture.Lenient?
            let description: String?
            /// Optional: a read before you-tab 07 (Going) or friends-on-event-page (saves, changes) sent none.
            let friendsGoing: [FriendRow]?
        }
        return try Supabase.decode(data, as: [Row].self).map { row in
            var event = UpcomingEvent(id: row.id, title: row.title, eventDate: row.eventDate,
                          startTime: row.startTime, location: row.location,
                          goingCount: row.goingCount, createdAt: row.createdAt,
                          imageUrl: row.imageUrl, rsvpd: row.going ?? true, saved: saved,
                          clubName: row.clubName,
                          category: EventCategory.from(row.category),
                          endAt: DateHelpers.timestamp(row.endAt),
                          isAllDay: row.allDay, sourceName: row.sourceName,
                          cancelled: row.cancelled ?? false,
                          placePicture: row.placePicture?.value,
                          description: row.description)
            event.friendsGoing = (row.friendsGoing ?? []).map(\.feed)
            return event
        }
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

    private func mapTrail(_ e: RawEvent) -> Trail {
        Trail(id: e.id, title: e.title, location: e.location, length: e.length, difficulty: e.difficulty,
              description: e.description, imageUrl: e.imageUrl, status: e.status ?? .approved, createdAt: e.createdAt ?? "")
    }

    // MARK: - Moderation (admin)

    func getPendingPosts() async throws -> [PendingPost] {
        let rows: [RawEvent] = try Supabase.decode(await db.rest("club_events", [
            ("select", "*"), ("status", "eq.pending"), ("order", "event_date.asc.nullslast,created_at.desc"),
        ]))
        return rows.map { PendingPost(trail: mapTrail($0), kind: PostKind(rawValue: $0.kind ?? "event") ?? .event,
                                      eventDate: $0.eventDate, startTime: $0.startTime, allDay: $0.allDay ?? false,
                                      sourceName: $0.sourceName, sourceURL: ReviewRow.webURL($0.sourceUrl)) }
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
