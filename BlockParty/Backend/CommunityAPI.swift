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
    let auth: any TokenProviding


    // MARK: - Plumbing

    private func token() async throws -> String { try await auth.validAccessToken() }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(T.self, from: data)
    }

    private func body(_ dict: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: dict)
    }

    private func uidOrThrow() async throws -> String {
        guard let uid = auth.userId else { throw SupabaseError(message: "Your session ended. Sign in and try again.", status: 401) }
        return uid
    }

    /// "Real events only" guard, appended to every event *display* query.
    /// Every legitimate insert stamps `submitted_by` (addEvent / addTrail), and a
    /// found event (ADR-021) records where it was read instead, in `source_name`.
    /// A row with neither was never created by a person in-app nor read from a
    /// source — it's seed / demo / fabricated content — so it can never surface,
    /// even if one lands in the shared DB. The `status=eq.approved` beside this is
    /// what keeps a found event hidden until the admin approves it. Trails
    /// intentionally omit this (curated reference data). The Expo twin (@hygge/core)
    /// still filters on `submitted_by` alone, so it hides found events.
    private static let realOnly = "&or=(submitted_by.not.is.null,source_name.not.is.null)"

    /// A token for a read RLS opens to everyone. Sign-in is switched off, so most
    /// neighbours have no session; they read with the app's public key, as
    /// `getPlaces` does, instead of failing into an empty screen. Approved events are
    /// readable by the anon role; RSVPs are not, so a signed-out read sees none.
    private func readToken() async -> String {
        (try? await token()) ?? SupabaseConfig.anonKey
    }

    // MARK: - User / admin

    func currentUserId() async -> String? { auth.userId }
    func isAdmin() async -> Bool { Admin.isAdmin(auth.email) }

    // MARK: - Places (permanent food/business POI markers)

    /// The town's permanent venues, seeded once into Supabase (see PlaceSeeder). Read
    /// once by the map — no live Google Places call per map load. RLS opens reads, to
    /// the anon role too, so signed out (sign-in is switched off) they are read with the
    /// app's public key instead of failing into an empty map and an empty Search.
    func getPlaces() async throws -> [POI] {
        let t = await readToken()
        let (data, _) = try await SupabaseHTTP.rest("places", query: "select=*", accessToken: t)
        return try decode(data)
    }

    /// The photos Block Party keeps of each place (`public.place_photos`, live rows readable with
    /// the public key), by registry entry, cover first: Search's cards and business pages draw
    /// them, so showing one costs no lookup (MEMORY.md, 2026-10-16). Logos stay out; Search has its own.
    func getPlacePhotos() async throws -> [String: [PlacePicture]] {
        // ponytail: one read of every town's live photos (183 on 2026-10-17); Supabase answers at
        // most 1,000 rows, so past that read this town's entries' photos, or page through them.
        let t = await readToken()
        let (data, _) = try await SupabaseHTTP.rest(
            "place_photos",
            query: "select=entry_id,url,kind,credit,site:source_url&status=eq.live&kind=eq.photo&order=position.asc",
            accessToken: t)
        return try Self.placePhotos(from: data)
    }

    /// Each place's name over its photo (`public.place_names`), by registry entry (BP app follows 02).
    func getPlaceNames() async throws -> [String: PlaceName] {
        struct Row: Decodable { let entryId: String; let url: String; let kind: String }
        let (data, _) = try await SupabaseHTTP.rest("place_names", query: "select=entry_id,url,kind",
                                                    accessToken: await readToken())
        let rows: [Row] = try decode(data)
        return Dictionary(rows.compactMap { row in
            URL(string: row.url).map { (row.entryId, PlaceName(url: $0, emblem: row.kind == "emblem")) }
        }, uniquingKeysWith: { first, _ in first })
    }

    /// The name over an Event's photo: its place's, or nil.
    func eventPlaceName(_ eventID: String) async throws -> PlaceName? {
        struct Row: Decodable { let url: String; let kind: String }
        let (data, _) = try await SupabaseHTTP.rest("rpc/event_place_name", method: "POST", accessToken: await readToken(),
                                                    body: try body(["p_event": eventID]))
        guard let row = try? decode(data) as Row, let url = URL(string: row.url) else { return nil }
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
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        var photos: [String: [PlacePicture]] = [:]
        for row in try decoder.decode([Row].self, from: data) {
            if let entry = row.entry, let picture = row.picture { photos[entry, default: []].append(picture) }
        }
        return photos
    }

    // MARK: - Clubs

    /// Every approved group, in the shelf's order, with its pictures, next get-togethers and
    /// member count (`get_groups`, BP app rsvp-and-groups 05). Signed out, it reads with the
    /// public key and every group says not joined.
    func getGroups() async throws -> [TownGroup] {
        let (data, _) = try await SupabaseHTTP.rest("rpc/get_groups", method: "POST",
                                                    accessToken: await readToken(), body: Data("{}".utf8))
        return try decode(data)
    }

    func joinClub(_ clubId: String) async throws {
        let t = try await token()
        let uid = try await uidOrThrow()
        // ignore-duplicates: membership is presence-only and club_members has no
        // UPDATE policy, so merge-duplicates (ON CONFLICT DO UPDATE) fails RLS on rejoin.
        _ = try await SupabaseHTTP.rest("club_members", method: "POST", query: "on_conflict=club_id,user_id",
                                        accessToken: t, body: try body(["club_id": clubId, "user_id": uid]),
                                        prefer: "resolution=ignore-duplicates,return=minimal")
    }

    func leaveClub(_ clubId: String) async throws {
        let t = try await token()
        let uid = try await uidOrThrow()
        _ = try await SupabaseHTTP.rest("club_members", method: "DELETE",
                                        query: "club_id=eq.\(clubId)&user_id=eq.\(uid)", accessToken: t)
    }

    func submitClub(_ input: ClubInput) async throws -> ClubRow {
        let t = try await token()
        let uid = try await uidOrThrow()
        let status: ClubStatus = Admin.isAdmin(auth.email) ? .approved : .pending
        var b: [String: Any] = ["name": input.name, "submitted_by": uid, "status": status.rawValue]
        if let v = input.host { b["host"] = v }
        if let v = input.schedule { b["schedule"] = v }
        if let v = input.location { b["location"] = v }
        if let v = input.vibe { b["vibe"] = v }
        if let v = input.description { b["description"] = v }
        if let v = input.expectations { b["expectations"] = v }
        let (data, _) = try await SupabaseHTTP.rest("clubs", method: "POST", accessToken: t,
                                                    body: try body(b), prefer: "return=representation")
        let rows: [ClubRow] = try decode(data)
        guard let row = rows.first else { throw SupabaseError(message: "The server didn't return the new group. Refresh before posting it again.", status: nil) }
        return row
    }

    // MARK: - Events (timeline)

    func getTodayEvents() async throws -> [TimelineEvent] {
        try await timelineEvents(forDate: DateHelpers.localDate())
    }

    func getEventsByDate(_ date: String) async throws -> [TimelineEvent] {
        try await timelineEvents(forDate: date)
    }

    private func timelineEvents(forDate date: String) async throws -> [TimelineEvent] {
        let t = await readToken()
        let uid = auth.userId
        let (data, _) = try await SupabaseHTTP.rest("club_events",
            query: "select=*,clubs(name)&status=eq.approved&kind=eq.event&event_date=eq.\(date)\(Self.realOnly)&cancelled_at=is.null&order=start_time.asc",
            accessToken: t)
        let events: [RawEvent] = try decode(data)
        var joined = Set<String>()
        if let uid {
            let (jd, _) = try await SupabaseHTTP.rest("club_members",
                query: "select=club_id&user_id=eq.\(uid)", accessToken: t)
            let mem: [MemberRow] = try decode(jd)
            for m in mem { joined.insert(m.clubId) }
        }
        return events.map { e in
            TimelineEvent(id: e.id, title: e.title, startTime: e.startTime, location: e.location,
                          clubName: e.clubs?.name,
                          fromJoinedClub: e.clubId != nil ? joined.contains(e.clubId!) : false,
                          details: e.description,
                          category: EventCategory.from(e.category),
                          imageURL: e.imageUrl.flatMap(URL.init(string:)),
                          placeEntryId: e.placeEntryId)
        }
    }

    /// The Town feed, in its order: what's in it, when each event leaves, and a series
    /// once with how it repeats, all worked out by `get_town_feed`, the one function
    /// iOS and Android both call. Signed out, it reads with the public key, as
    /// `getPlaces` does. It asks for town news too (town-feed 35); an app that doesn't
    /// gets the events alone.
    func getTownFeed() async throws -> [TownFeedLine] {
        let (data, _) = try await SupabaseHTTP.rest("rpc/get_town_feed", method: "POST",
                                                    accessToken: await readToken(),
                                                    body: Data(#"{"p_news":true}"#.utf8))
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
        let body = try moment.map { try JSONSerialization.data(withJSONObject: ["p_now": ISO8601DateFormatter().string(from: $0)]) }
        let (data, _) = try await SupabaseHTTP.rest("rpc/get_event_of_the_day", method: "POST",
                                                    accessToken: await readToken(),
                                                    body: body ?? Data("{}".utf8))
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
        }
        /// The admin's breakdown, or nil when it doesn't decode: a score never costs the
        /// feed.
        struct LenientScore: Decodable {
            let value: FeedScore?
            init(from decoder: Decoder) { value = try? FeedScore(from: decoder) }
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([Row].self, from: data).compactMap { row -> TownFeedLine? in
            guard let leavesAt = DateHelpers.timestamp(row.leavesAt) else { return nil }
            if row.kind == "news" {
                guard let post = row.sourceUrl.flatMap(URL.init(string:)) else { return nil }
                let words = row.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return .news(TownNews(id: row.id, place: row.sourceName ?? "",
                                      words: words.isEmpty ? row.title : words, post: post,
                                      picture: row.placePicture?.value, leavesAt: leavesAt))
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
                                      description: row.description, game: row.game?.value,
                                      what: row.what)
            return .event(TownFeedRow(event: event, recurrence: row.recurrence, leavesAt: leavesAt,
                                      reason: row.reason, reasonName: row.reasonName, score: row.score?.value,
                                      heartCount: row.heartCount ?? 0, hearted: row.hearted ?? false,
                                      saved: row.saved ?? false,
                                      friendsGoing: (row.friendsGoing ?? []).map(\.feed),
                                      groupID: row.clubId, inGroup: row.inClub ?? false))
        }
    }

    func rsvpEvent(_ eventId: String) async throws {
        let t = try await token()
        let uid = try await uidOrThrow()
        // ignore-duplicates: an RSVP is presence-only and event_rsvps has no UPDATE
        // policy, so merge-duplicates (ON CONFLICT DO UPDATE) fails RLS on re-RSVP —
        // which the feed's join button hits whenever its optimistic state drifts.
        _ = try await SupabaseHTTP.rest("event_rsvps", method: "POST", query: "on_conflict=event_id,user_id",
                                        accessToken: t, body: try body(["event_id": eventId, "user_id": uid]),
                                        prefer: "resolution=ignore-duplicates,return=minimal")
    }

    /// The Town feed's views and opens (ticket 20), in one insert. Who and when are set by
    /// the database; nobody reads them back. Ids that aren't Events (samples) are skipped.
    func recordFeedActions(_ batch: [FeedAction]) async throws {
        let rows = batch.filter { UUID(uuidString: $0.itemID) != nil }
            .map { ["item_id": $0.itemID, "action": $0.kind.rawValue] }
        guard !rows.isEmpty else { return }
        let t = try await token()
        _ = try await SupabaseHTTP.rest("feed_actions", method: "POST", accessToken: t,
                                        body: try JSONSerialization.data(withJSONObject: rows),
                                        prefer: "return=minimal")
    }

    /// Not interested, Mute and their undoing (town-feed 21), straight away. A Mute answers with
    /// the host it muted, which Unmute names. Ids that aren't Events (samples) send nothing.
    func feedChoice(_ choice: FeedChoice) async throws -> String? {
        let t = try await token()
        switch choice {
        case .notInterested(let id), .undoNotInterested(let id):
            guard UUID(uuidString: id) != nil else { return nil }
            let on = choice == .notInterested(id)
            _ = try await SupabaseHTTP.rest("rpc/set_not_interested", method: "POST", accessToken: t,
                                            body: try body(["p_item": id, "p_on": on]))
            return nil
        case .mute(let id):
            guard UUID(uuidString: id) != nil else { return nil }
            let (data, _) = try await SupabaseHTTP.rest("rpc/mute_host", method: "POST", accessToken: t,
                                                        body: try body(["p_item": id]))
            return try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String
        case .unmute(let host):
            var allowed = CharacterSet.urlQueryAllowed
            allowed.remove(charactersIn: "&=+,()")
            let value = host.addingPercentEncoding(withAllowedCharacters: allowed) ?? host
            _ = try await SupabaseHTTP.rest("feed_mutes", method: "DELETE", query: "host=eq.\(value)", accessToken: t)
            return nil
        }
    }

    /// The hosts you muted, newest first: Profile's Muted list (town-feed 21).
    func mutedHosts() async throws -> [MutedHost] {
        let (data, _) = try await SupabaseHTTP.rest("feed_mutes", query: "select=host,name&order=at.desc",
                                                    accessToken: try await token())
        return try decode(data)
    }

    func unRsvpEvent(_ eventId: String) async throws {
        let t = try await token()
        let uid = try await uidOrThrow()
        _ = try await SupabaseHTTP.rest("event_rsvps", method: "DELETE",
                                        query: "event_id=eq.\(eventId)&user_id=eq.\(uid)", accessToken: t)
    }

    func addEvent(_ input: NewEventInput, clubId: String? = nil, status: ClubStatus = .approved) async throws {
        let t = try await token()
        let uid = try await uidOrThrow()
        func makeBody(includeImage: Bool) -> [String: Any] {
            var b: [String: Any] = [
                "title": input.title, "event_date": input.eventDate, "start_time": input.startTime,
                "location": input.location, "submitted_by": uid, "status": status.rawValue,
                "club_id": clubId ?? NSNull(), "category": input.category,
            ]
            if let v = input.description { b["description"] = v }
            if includeImage, let v = input.imageUrl { b["image_url"] = v }
            return b
        }
        do {
            _ = try await SupabaseHTTP.rest("club_events", method: "POST", accessToken: t,
                                            body: try body(makeBody(includeImage: true)), prefer: "return=minimal")
        } catch let err as SupabaseError {
            // Retry once without image_url if that column doesn't exist yet.
            if input.imageUrl != nil, err.message.contains("image_url") {
                _ = try await SupabaseHTTP.rest("club_events", method: "POST", accessToken: t,
                                                body: try body(makeBody(includeImage: false)), prefer: "return=minimal")
            } else { throw err }
        }
    }

    // MARK: - Calendar

    func getMonthEventCounts(year: Int, month: Int) async throws -> [String: Int] {
        let rows = try await monthDateRows(year: year, month: month)
        var counts: [String: Int] = [:]
        for r in rows { counts[r.eventDate, default: 0] += 1 }
        return counts
    }

    func getMonthEventDates(year: Int, month: Int) async throws -> [String] {
        let rows = try await monthDateRows(year: year, month: month)
        return Array(Set(rows.map(\.eventDate)))
    }

    private func monthDateRows(year: Int, month: Int) async throws -> [DateRow] {
        let t = try await token()
        let from = String(format: "%04d-%02d-01", year, month)
        var comps = DateComponents(); comps.year = year; comps.month = month
        let cal = Calendar(identifier: .gregorian)
        let lastDay = cal.date(from: comps).flatMap { cal.range(of: .day, in: .month, for: $0)?.count } ?? 28
        let to = String(format: "%04d-%02d-%02d", year, month, lastDay)
        let (data, _) = try await SupabaseHTTP.rest("club_events",
            query: "select=event_date&status=eq.approved&kind=eq.event&event_date=gte.\(from)&event_date=lte.\(to)\(Self.realOnly)",
            accessToken: t)
        return try decode(data)
    }

    func getEventsForRange(from: String, to: String) async throws -> [AgendaEvent] {
        let t = try await token()
        let (data, _) = try await SupabaseHTTP.rest("club_events",
            query: "select=id,title,event_date,start_time,location&status=eq.approved&kind=eq.event&event_date=gte.\(from)&event_date=lte.\(to)\(Self.realOnly)&order=event_date.asc,start_time.asc",
            accessToken: t)
        let rows: [AgendaRow] = try decode(data)
        return rows.map { AgendaEvent(id: $0.id, title: $0.title, eventDate: $0.eventDate, startTime: $0.startTime, location: $0.location) }
    }

    // MARK: - Quests

    func setQuest(title: String, description: String, date: String) async throws {
        let t = try await token()
        let uid = try await uidOrThrow()
        _ = try await SupabaseHTTP.rest("daily_quests", method: "POST", query: "on_conflict=date", accessToken: t,
                                        body: try body(["title": title, "description": description, "date": date, "created_by": uid]),
                                        prefer: "resolution=merge-duplicates,return=minimal")
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
    /// Internal (not private) and nonisolated: `YourDayLogic.changeIsRelevant`
    /// filters realtime changes against this window, and two copies of this
    /// number would drift.
    nonisolated static let dayLookbackDays = 14

    /// Which of these ids are Events, for moving the phone's old saves up to the server
    /// (`RealLifeActions.moveUp`): the phone's saved list holds the map's Places too.
    func knownEventIDs(_ ids: [String]) async throws -> Set<String> {
        guard !ids.isEmpty else { return [] }
        struct Row: Decodable { let id: String }
        let (data, _) = try await SupabaseHTTP.rest("club_events",
            query: "select=id&id=in.(\(ids.joined(separator: ",")))", accessToken: await readToken())
        let rows: [Row] = try decode(data)
        return Set(rows.map(\.id))
    }

    // MARK: - Neighbours (BP app docs/plans/friends)

    /// Neighbours whose name, or a later word of it, starts with `words`: `search_neighbors`,
    /// which answers a real account only and never returns Anonymous or nameless accounts.
    func searchNeighbors(_ words: String) async throws -> [Neighbor] {
        let body = try JSONSerialization.data(withJSONObject: ["p_words": words])
        let (data, _) = try await SupabaseHTTP.rest("rpc/search_neighbors", method: "POST",
                                                    accessToken: try await token(), body: body)
        return try decode(data)
    }

    /// The Friends page (`get_friends`): accepted lines, requests newest first, friends A to
    /// Z, each as `kind` and the neighbour (ticket 03).
    func getFriends() async throws -> [(kind: String, neighbor: Neighbor)] {
        struct Kind: Decodable { let kind: String }
        let (data, _) = try await SupabaseHTTP.rest("rpc/get_friends", method: "POST",
                                                    accessToken: try await token(), body: try body([:]))
        let kinds: [Kind] = try decode(data)
        let people: [Neighbor] = try decode(data)
        return zip(kinds, people).map { ($0.kind, $1) }
    }

    /// The people you blocked, newest first: Profile's Blocked list (ticket 04).
    func getBlocked() async throws -> [Neighbor] {
        let (data, _) = try await SupabaseHTTP.rest("rpc/get_blocked", method: "POST",
                                                    accessToken: try await token(), body: try body([:]))
        return try decode(data)
    }

    /// Which of your contacts are on Block Party (`match_contacts`, friends 06): the scrambled
    /// emails and phone numbers go, each neighbour comes back with the code that found them.
    func matchContacts(emails: [String], phones: [String]) async throws -> [(code: String, neighbor: Neighbor)] {
        struct Code: Decodable { let code: String }
        let (data, _) = try await SupabaseHTTP.rest("rpc/match_contacts", method: "POST", accessToken: try await token(),
                                                    body: try body(["p_emails": emails, "p_phones": phones]))
        let codes: [Code] = try decode(data)
        let people: [Neighbor] = try decode(data)
        return zip(codes, people).map { ($0.code, $1) }
    }

    /// People you may know, strongest first, at most 20 (daily-tab 22).
    func peopleYouMayKnow() async throws -> [Neighbor] {
        let (data, _) = try await SupabaseHTTP.rest("rpc/get_people_you_may_know", method: "POST",
                                                    accessToken: try await token(), body: try body([:]))
        return try decode(data)
    }

    /// The X on a suggestion: that person never comes back on your list.
    func hideSuggestion(_ userID: String) async throws {
        try await SupabaseHTTP.rest("rpc/hide_suggestion", method: "POST",
                                    accessToken: try await token(), body: try body(["p_user": userID]))
    }

    /// A request newer than your last visit to Friends: the dot on the friends mark.
    func friendsDot() async throws -> Bool {
        let (data, _) = try await SupabaseHTTP.rest("rpc/friends_dot", method: "POST",
                                                    accessToken: try await token(), body: try body([:]))
        return try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? Bool ?? false
    }

    /// The Friends page has drawn what it read: the dot clears and accepted lines go.
    func markFriendsSeen() async throws {
        try await SupabaseHTTP.rest("rpc/mark_friends_seen", method: "POST",
                                    accessToken: try await token(), body: try body([:]))
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
        let (data, _) = try await SupabaseHTTP.rest("rpc/\(function)", method: "POST",
                                                    accessToken: try await token(), body: try body([key: userID]))
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
        try await SupabaseHTTP.rest("rpc/\(on ? "follow_target" : "unfollow_target")", method: "POST",
                                    accessToken: try await token(),
                                    body: try body(["p_type": target.type.rawValue, "p_id": target.id]))
    }

    /// What a page shows of it: the count, your friends who follow it, and whether you do.
    /// Signed out too: then the count alone.
    func followCard(_ target: FollowTarget) async throws -> FollowCard {
        let (data, _) = try await SupabaseHTTP.rest("rpc/follow_card", method: "POST", accessToken: await readToken(),
                                                    body: try body(["p_type": target.type.rawValue, "p_id": target.id]))
        let rows: [FollowCard] = try decode(data)
        guard let card = rows.first else { throw SupabaseError(message: "Unexpected answer", status: nil) }
        return card
    }

    /// Everyone and everything you follow, A to Z: Profile's Following list.
    func myFollows() async throws -> [FollowRow] {
        let (data, _) = try await SupabaseHTTP.rest("rpc/my_follows", method: "POST",
                                                    accessToken: try await token(), body: try body([:]))
        return try decode(data)
    }

    /// Who hosts an Event, for its page's host line: nil for a Group's Event or one at no known Place.
    func eventHost(_ eventID: String) async throws -> FollowRow? {
        let (data, _) = try await SupabaseHTTP.rest("rpc/event_host", method: "POST", accessToken: await readToken(),
                                                    body: try body(["p_event": eventID]))
        let rows: [FollowRow] = try decode(data)
        return rows.first
    }

    // MARK: - My Going (the You tab)

    /// The neighbour's Going from `from` to `to`, Town days as "yyyy-MM-dd", both ends
    /// included, past days too: `get_my_going`, the one function iOS and Android call
    /// (BP app docs/plans/you-tab). Ordered by day; the You page orders a day by start.
    func getMyGoing(from: String, to: String) async throws -> [UpcomingEvent] {
        let body = try JSONSerialization.data(withJSONObject: ["p_from": from, "p_to": to])
        let (data, _) = try await SupabaseHTTP.rest("rpc/get_my_going", method: "POST",
                                                    accessToken: try await token(), body: body)
        return try Self.myGoingRows(from: data)
    }

    /// The neighbour's saved Events from `from` on, a Town day as "yyyy-MM-dd", and any
    /// from before it still running: `get_my_saves`, Profile's Saved list (BP app
    /// docs/plans/you-tab, ticket 04). Each comes back saved, saying whether they're Going.
    func getMySaves(from: String) async throws -> [UpcomingEvent] {
        let body = try JSONSerialization.data(withJSONObject: ["p_from": from])
        let (data, _) = try await SupabaseHTTP.rest("rpc/get_my_saves", method: "POST",
                                                    accessToken: try await token(), body: body)
        return try Self.myGoingRows(from: data, saved: true)
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
            /// `get_my_going`'s only (you-tab 07); `get_my_saves` sends none.
            let friendsGoing: [FriendRow]?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([Row].self, from: data).map { row in
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

    func getTrails() async throws -> [Trail] {
        let t = try await token()
        let (data, _) = try await SupabaseHTTP.rest("club_events",
            query: "select=*&status=eq.approved&kind=eq.trail&order=created_at.desc", accessToken: t)
        let rows: [RawEvent] = try decode(data)
        return rows.map(mapTrail)
    }

    func addTrail(_ input: NewTrailInput, status: ClubStatus = .approved) async throws {
        let t = try await token()
        let uid = try await uidOrThrow()
        let b: [String: Any] = [
            "kind": "trail", "title": input.title, "location": input.location,
            "length": input.length ?? NSNull(), "difficulty": input.difficulty ?? NSNull(),
            "description": input.description ?? NSNull(), "image_url": input.imageUrl ?? NSNull(),
            "event_date": NSNull(), "start_time": NSNull(),
            "submitted_by": uid, "status": status.rawValue, "club_id": NSNull(),
        ]
        _ = try await SupabaseHTTP.rest("club_events", method: "POST", accessToken: t,
                                        body: try body(b), prefer: "return=minimal")
    }

    private func mapTrail(_ e: RawEvent) -> Trail {
        Trail(id: e.id, title: e.title, location: e.location, length: e.length, difficulty: e.difficulty,
              description: e.description, imageUrl: e.imageUrl, status: e.status ?? .approved, createdAt: e.createdAt ?? "")
    }

    // MARK: - Moderation (admin)

    func getPendingPosts() async throws -> [PendingPost] {
        let t = try await token()
        let (data, _) = try await SupabaseHTTP.rest("club_events",
            query: "select=*&status=eq.pending&order=event_date.asc.nullslast,created_at.desc", accessToken: t)
        let rows: [RawEvent] = try decode(data)
        return rows.map { PendingPost(trail: mapTrail($0), kind: PostKind(rawValue: $0.kind ?? "event") ?? .event,
                                      eventDate: $0.eventDate, startTime: $0.startTime, allDay: $0.allDay ?? false,
                                      sourceName: $0.sourceName, sourceURL: ReviewRow.webURL($0.sourceUrl)) }
    }

    func getPendingClubs() async throws -> [ClubRow] {
        let t = try await token()
        let (data, _) = try await SupabaseHTTP.rest("clubs",
            query: "select=*&status=eq.pending&order=created_at.desc", accessToken: t)
        return try decode(data)
    }

    func approvePost(_ id: String) async throws { try await patchStatus("club_events", id: id, status: .approved) }
    /// Decline with what was wrong. Approving never clears the reason (see the migration).
    func declinePost(_ id: String, reason: DeclineReason) async throws {
        let t = try await token()
        _ = try await SupabaseHTTP.rest("club_events", method: "PATCH", query: "id=eq.\(id)", accessToken: t,
                                        body: try body(["status": ClubStatus.rejected.rawValue,
                                                        "review_reason": reason.rawValue]),
                                        prefer: "return=minimal")
    }
    func setClubStatus(_ id: String, status: ClubStatus) async throws { try await patchStatus("clubs", id: id, status: status) }

    private func patchStatus(_ table: String, id: String, status: ClubStatus) async throws {
        let t = try await token()
        _ = try await SupabaseHTTP.rest(table, method: "PATCH", query: "id=eq.\(id)", accessToken: t,
                                        body: try body(["status": status.rawValue]), prefer: "return=minimal")
    }
}
