//
//  CommunityAPI.swift
//  Hygge — the @hygge/core query layer, ported 1:1 to PostgREST over URLSession.
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
    var id: String { trail.id }
}

struct CommunityAPI {
    let auth: AuthStore

    private struct IdRow: Decodable { let id: String }

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
        guard let uid = auth.userId else { throw SupabaseError(message: "Not signed in", status: 401) }
        return uid
    }

    // MARK: - User / admin

    func currentUserId() async -> String? { auth.userId }
    func currentEmail() async -> String? { auth.email }
    func isAdmin() async -> Bool { Admin.isAdmin(auth.email) }

    // MARK: - Clubs

    func getApprovedClubs() async throws -> [ClubView] {
        let t = try await token()
        let uid = auth.userId
        let (data, _) = try await SupabaseHTTP.rest("clubs", query: "select=*&status=eq.approved&order=created_at.asc", accessToken: t)
        let clubs: [ClubRow] = try decode(data)
        let ids = clubs.map(\.id)
        var counts: [String: Int] = [:]
        var mine = Set<String>()
        if !ids.isEmpty {
            let (md, _) = try await SupabaseHTTP.rest("club_members", query: "select=club_id,user_id&club_id=in.(\(ids.joined(separator: ",")))", accessToken: t)
            let members: [MemberRow] = try decode(md)
            for m in members {
                counts[m.clubId, default: 0] += 1
                if let uid, m.userId == uid { mine.insert(m.clubId) }
            }
        }
        return clubs.map { ClubView(row: $0, memberCount: counts[$0.id] ?? 0, joined: mine.contains($0.id)) }
    }

    func joinClub(_ clubId: String) async throws {
        let t = try await token()
        let uid = try await uidOrThrow()
        _ = try await SupabaseHTTP.rest("club_members", method: "POST", query: "on_conflict=club_id,user_id",
                                        accessToken: t, body: try body(["club_id": clubId, "user_id": uid]),
                                        prefer: "resolution=merge-duplicates,return=minimal")
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
        guard let row = rows.first else { throw SupabaseError(message: "Insert returned no row", status: nil) }
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
        let t = try await token()
        let uid = auth.userId
        let (data, _) = try await SupabaseHTTP.rest("club_events",
            query: "select=*,clubs(name)&status=eq.approved&kind=eq.event&event_date=eq.\(date)&order=start_time.asc",
            accessToken: t)
        let events: [RawEvent] = try decode(data)
        let ids = events.map(\.id)
        var counts: [String: Int] = [:]
        var mine = Set<String>()
        if !ids.isEmpty {
            let (rd, _) = try await SupabaseHTTP.rest("event_rsvps",
                query: "select=event_id,user_id&event_id=in.(\(ids.joined(separator: ",")))", accessToken: t)
            let rsvps: [RsvpRow] = try decode(rd)
            for r in rsvps {
                counts[r.eventId, default: 0] += 1
                if let uid, r.userId == uid { mine.insert(r.eventId) }
            }
        }
        var joined = Set<String>()
        if let uid {
            let (jd, _) = try await SupabaseHTTP.rest("club_members",
                query: "select=club_id&user_id=eq.\(uid)", accessToken: t)
            let mem: [MemberRow] = try decode(jd)
            for m in mem { joined.insert(m.clubId) }
        }
        return events.map { e in
            TimelineEvent(id: e.id, title: e.title, startTime: e.startTime, location: e.location,
                          goingCount: counts[e.id] ?? 0, rsvpd: mine.contains(e.id),
                          clubName: e.clubs?.name,
                          fromJoinedClub: e.clubId != nil ? joined.contains(e.clubId!) : false)
        }
    }

    func getUpcomingEvents() async throws -> [UpcomingEvent] {
        let t = try await token()
        let today = DateHelpers.localDate()
        let (data, _) = try await SupabaseHTTP.rest("club_events",
            query: "select=*&status=eq.approved&kind=eq.event&event_date=gte.\(today)&order=event_date.asc",
            accessToken: t)
        let events: [RawEvent] = try decode(data)
        let counts = try await rsvpCounts(eventIds: events.map(\.id), token: t)
        return events.map {
            UpcomingEvent(id: $0.id, title: $0.title, eventDate: $0.eventDate ?? "",
                          startTime: $0.startTime, location: $0.location,
                          goingCount: counts[$0.id] ?? 0, createdAt: $0.createdAt ?? "")
        }
    }

    func getWeekEvents() async throws -> [WeekEvent] {
        let t = try await token()
        let today = DateHelpers.localDate()
        let until = DateHelpers.localDate(DateHelpers.addDays(7))
        let (data, _) = try await SupabaseHTTP.rest("club_events",
            query: "select=*&status=eq.approved&kind=eq.event&event_date=gt.\(today)&event_date=lte.\(until)&order=event_date.asc",
            accessToken: t)
        let events: [RawEvent] = try decode(data)
        let counts = try await rsvpCounts(eventIds: events.map(\.id), token: t)
        return events.map {
            WeekEvent(id: $0.id, title: $0.title, dateLabel: DateHelpers.weekdayLabel($0.eventDate ?? ""),
                      goingCount: counts[$0.id] ?? 0)
        }
    }

    /// Count-only RSVP tally for a set of event ids (no user filter).
    private func rsvpCounts(eventIds ids: [String], token t: String) async throws -> [String: Int] {
        guard !ids.isEmpty else { return [:] }
        let (rd, _) = try await SupabaseHTTP.rest("event_rsvps",
            query: "select=event_id&event_id=in.(\(ids.joined(separator: ",")))", accessToken: t)
        let rsvps: [RsvpRow] = try decode(rd)
        var counts: [String: Int] = [:]
        for r in rsvps { counts[r.eventId, default: 0] += 1 }
        return counts
    }

    func rsvpEvent(_ eventId: String) async throws {
        let t = try await token()
        let uid = try await uidOrThrow()
        _ = try await SupabaseHTTP.rest("event_rsvps", method: "POST", query: "on_conflict=event_id,user_id",
                                        accessToken: t, body: try body(["event_id": eventId, "user_id": uid]),
                                        prefer: "resolution=merge-duplicates,return=minimal")
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
                "club_id": clubId ?? NSNull(),
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
            query: "select=event_date&status=eq.approved&kind=eq.event&event_date=gte.\(from)&event_date=lte.\(to)",
            accessToken: t)
        return try decode(data)
    }

    func getEventsForRange(from: String, to: String) async throws -> [AgendaEvent] {
        let t = try await token()
        let (data, _) = try await SupabaseHTTP.rest("club_events",
            query: "select=id,title,event_date,start_time,location&status=eq.approved&kind=eq.event&event_date=gte.\(from)&event_date=lte.\(to)&order=event_date.asc,start_time.asc",
            accessToken: t)
        let rows: [AgendaRow] = try decode(data)
        return rows.map { AgendaEvent(id: $0.id, title: $0.title, eventDate: $0.eventDate, startTime: $0.startTime, location: $0.location) }
    }

    // MARK: - Quests

    func getTodayQuest() async throws -> DailyQuest? {
        let t = try await token()
        let today = DateHelpers.localDate()
        let (data, _) = try await SupabaseHTTP.rest("daily_quests",
            query: "select=id,title,description,date&date=eq.\(today)", accessToken: t)
        let quests: [DailyQuest] = try decode(data)
        return quests.first
    }

    func getQuestCompletionCount(_ questId: String) async throws -> Int {
        let t = try await token()
        let (data, _) = try await SupabaseHTTP.rest("quest_completions",
            query: "select=id&quest_id=eq.\(questId)", accessToken: t)
        let rows: [IdRow] = try decode(data)
        return rows.count
    }

    func hasUserCompletedQuest(_ questId: String, userId: String) async throws -> Bool {
        let t = try await token()
        let (data, _) = try await SupabaseHTTP.rest("quest_completions",
            query: "select=id&quest_id=eq.\(questId)&user_id=eq.\(userId)&limit=1", accessToken: t)
        let rows: [IdRow] = try decode(data)
        return !rows.isEmpty
    }

    func completeQuest(_ questId: String) async throws {
        let t = try await token()
        let uid = try await uidOrThrow()
        _ = try await SupabaseHTTP.rest("quest_completions", method: "POST", accessToken: t,
                                        body: try body(["quest_id": questId, "user_id": uid]), prefer: "return=minimal")
    }

    func setQuest(title: String, description: String, date: String) async throws {
        let t = try await token()
        let uid = try await uidOrThrow()
        _ = try await SupabaseHTTP.rest("daily_quests", method: "POST", query: "on_conflict=date", accessToken: t,
                                        body: try body(["title": title, "description": description, "date": date, "created_by": uid]),
                                        prefer: "resolution=merge-duplicates,return=minimal")
    }

    // MARK: - My activity (profile screen — per-user, real counts only)

    /// Upcoming events the signed-in user has RSVP'd to (today onward), soonest
    /// first. Two hops: their `event_rsvps` → those approved `club_events`. Empty
    /// when they've RSVP'd to nothing upcoming — never a fabricated number.
    func getMyUpcomingRsvps() async throws -> [UpcomingEvent] {
        let t = try await token()
        let uid = try await uidOrThrow()
        let (rd, _) = try await SupabaseHTTP.rest("event_rsvps",
            query: "select=event_id&user_id=eq.\(uid)", accessToken: t)
        let mine: [RsvpRow] = try decode(rd)
        let ids = Array(Set(mine.map(\.eventId)))
        guard !ids.isEmpty else { return [] }
        let today = DateHelpers.localDate()
        let (data, _) = try await SupabaseHTTP.rest("club_events",
            query: "select=*&id=in.(\(ids.joined(separator: ",")))&status=eq.approved&kind=eq.event&event_date=gte.\(today)&order=event_date.asc",
            accessToken: t)
        let events: [RawEvent] = try decode(data)
        let counts = try await rsvpCounts(eventIds: events.map(\.id), token: t)
        return events.map {
            UpcomingEvent(id: $0.id, title: $0.title, eventDate: $0.eventDate ?? "",
                          startTime: $0.startTime, location: $0.location,
                          goingCount: counts[$0.id] ?? 0, createdAt: $0.createdAt ?? "")
        }
    }

    /// Clubs the signed-in user has joined. Derives from the approved-clubs fetch,
    /// which already resolves `joined` per row — no separate endpoint needed.
    func getMyClubs() async throws -> [ClubView] {
        try await getApprovedClubs().filter { $0.joined }
    }

    /// How many daily quests the user has ever completed (all-time). Real count.
    func getMyQuestCount() async throws -> Int {
        let t = try await token()
        let uid = try await uidOrThrow()
        let (data, _) = try await SupabaseHTTP.rest("quest_completions",
            query: "select=id&user_id=eq.\(uid)", accessToken: t)
        let rows: [IdRow] = try decode(data)
        return rows.count
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
            query: "select=*&status=eq.pending&order=created_at.desc", accessToken: t)
        let rows: [RawEvent] = try decode(data)
        return rows.map { PendingPost(trail: mapTrail($0), kind: PostKind(rawValue: $0.kind ?? "event") ?? .event,
                                      eventDate: $0.eventDate, startTime: $0.startTime) }
    }

    func getPendingClubs() async throws -> [ClubRow] {
        let t = try await token()
        let (data, _) = try await SupabaseHTTP.rest("clubs",
            query: "select=*&status=eq.pending&order=created_at.desc", accessToken: t)
        return try decode(data)
    }

    func approvePost(_ id: String) async throws { try await patchStatus("club_events", id: id, status: .approved) }
    func rejectPost(_ id: String) async throws { try await patchStatus("club_events", id: id, status: .rejected) }
    func setClubStatus(_ id: String, status: ClubStatus) async throws { try await patchStatus("clubs", id: id, status: status) }

    private func patchStatus(_ table: String, id: String, status: ClubStatus) async throws {
        let t = try await token()
        _ = try await SupabaseHTTP.rest(table, method: "PATCH", query: "id=eq.\(id)", accessToken: t,
                                        body: try body(["status": status.rawValue]), prefer: "return=minimal")
    }
}
