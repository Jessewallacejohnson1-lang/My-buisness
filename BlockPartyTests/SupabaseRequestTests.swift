//
//  SupabaseRequestTests.swift
//  BlockPartyTests — what the app sends Supabase, request by request, through the one client and
//  a fake server (codebase-health 16): exact URLs, encoded query values, headers, bodies, the 401
//  hook and upload errors. Nothing leaves the phone.
//

import XCTest
@testable import BlockParty

@MainActor
final class SupabaseRequestTests: XCTestCase {
    private let rest = SupabaseConfig.restURL.absoluteString
    private lazy var auth = FakeTokenProvider()
    private lazy var server = FakeServer()

    private var community: CommunityAPI { CommunityAPI(auth: auth, send: server.send) }
    private var social: SocialAPI { SocialAPI(auth: auth, send: server.send) }
    private var profiles: ProfileAPI { ProfileAPI(auth: auth, send: server.send) }
    private var last: URLRequest { server.requests.last! }
    private var lastBody: [String: AnyHashable]? { server.lastBody as? [String: AnyHashable] }

    // MARK: - Query values

    func testEveryQueryValueIsEncodedAndPostgRESTsOwnMarksStay() {
        XCTAssertEqual(Supabase.encode([("host", "eq.A&B=C+D #x%y")]), "host=eq.A%26B%3DC%2BD%20%23x%25y")
        XCTAssertEqual(Supabase.encode([("select", "*,clubs(name)"), ("id", "in.(a,b)"),
                                        ("order", "event_date.asc.nullslast,created_at.desc"),
                                        ("select", "site:source_url")]),
                       "select=*,clubs(name)&id=in.(a,b)&order=event_date.asc.nullslast,created_at.desc&select=site:source_url")
        XCTAssertNil(Supabase.encode([]), "no query, no ?")
    }

    func testUnmuteSendsAnyHostSafely() async throws {
        _ = try await community.feedChoice(.unmute("Joe's Bar & Grill, St. Joseph (MN) + more"))
        XCTAssertEqual(last.httpMethod, "DELETE")
        XCTAssertEqual(last.url!.absoluteString,
                       "\(rest)/feed_mutes?host=eq.Joe's%20Bar%20%26%20Grill,%20St.%20Joseph%20(MN)%20%2B%20more")
    }

    // MARK: - Reads

    func testMapSpotsSignedOutReadWithThePublicKey() async throws {
        auth.throwOnToken = true
        auth.userId = nil
        _ = try await community.eventSpots(["a1", "b2"])
        XCTAssertEqual(server.requests.count, 1)
        XCTAssertEqual(last.httpMethod, "GET")
        XCTAssertEqual(last.url!.absoluteString, "\(rest)/club_events?select=id,lat,lng&lat=not.is.null&id=in.(a1,b2)")
        XCTAssertEqual(last.value(forHTTPHeaderField: "Authorization"), "Bearer \(SupabaseConfig.anonKey)")
        XCTAssertEqual(last.value(forHTTPHeaderField: "apikey"), SupabaseConfig.anonKey)
    }

    func testMapSpotsSignedInReadWithTheTokenAndNoneAskNothing() async throws {
        _ = try await community.eventSpots([])
        XCTAssertEqual(server.requests.count, 0, "no events today: no read")
        _ = try await community.eventSpots(["a1"])
        XCTAssertEqual(server.requests.count, 1)
        XCTAssertEqual(last.value(forHTTPHeaderField: "Authorization"), "Bearer test-access-token")
    }

    func testUpcomingTagsAndKnownEventsAskExactly() async throws {
        _ = try await community.upcomingTags()
        XCTAssertEqual(last.url!.absoluteString,
                       "\(rest)/club_events?select=interests,category,interests_tagged_at,place_entry_id,team_ids,activity_team,source_name&status=eq.approved&kind=eq.event&cancelled_at=is.null&event_date=gte.\(Town.day(Date()))&or=(submitted_by.not.is.null,source_name.not.is.null)&followers_only=is.false")
        _ = try await community.knownEventIDs(["a1", "b2"])
        XCTAssertEqual(last.url!.absoluteString, "\(rest)/club_events?select=id&id=in.(a1,b2)")
    }

    func testFunctionsPostTheirArguments() async throws {
        _ = try await community.getGroups()
        XCTAssertEqual(last.httpMethod, "POST")
        XCTAssertEqual(last.url!.absoluteString, "\(rest)/rpc/get_groups")
        XCTAssertEqual(lastBody, [:])
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        _ = try await community.getEventOfTheDay(at: moment)
        XCTAssertEqual(last.url!.absoluteString, "\(rest)/rpc/get_event_of_the_day")
        XCTAssertEqual(lastBody, ["p_now": ISO8601DateFormatter().string(from: moment)])
    }

    // MARK: - Writes

    func testLikeSaveGoingAndJoinWriteOnePresenceRow() async throws {
        try await social.likeEvent("e1")
        assertPresenceRow("event_likes", "event_id")
        try await social.saveEvent("e1")
        assertPresenceRow("event_saves", "event_id")
        try await community.rsvpEvent("e1")
        assertPresenceRow("event_rsvps", "event_id")
        try await community.joinClub("e1")
        assertPresenceRow("club_members", "club_id")
    }

    private func assertPresenceRow(_ table: String, _ key: String, line: UInt = #line) {
        XCTAssertEqual(last.httpMethod, "POST", line: line)
        XCTAssertEqual(last.url!.absoluteString, "\(rest)/\(table)?on_conflict=\(key),user_id", line: line)
        XCTAssertEqual(last.value(forHTTPHeaderField: "Prefer"), "resolution=ignore-duplicates,return=minimal", line: line)
        XCTAssertEqual(lastBody, [key: "e1", "user_id": "test-user"], line: line)
    }

    func testUndoingDeletesOnlyYourRow() async throws {
        try await social.unlikeEvent("e1")
        XCTAssertEqual(last.url!.absoluteString, "\(rest)/event_likes?event_id=eq.e1&user_id=eq.test-user")
        try await social.unsaveEvent("e1")
        XCTAssertEqual(last.url!.absoluteString, "\(rest)/event_saves?event_id=eq.e1&user_id=eq.test-user")
        try await community.unRsvpEvent("e1")
        XCTAssertEqual(last.url!.absoluteString, "\(rest)/event_rsvps?event_id=eq.e1&user_id=eq.test-user")
        try await community.leaveClub("c1")
        XCTAssertEqual(last.url!.absoluteString, "\(rest)/club_members?club_id=eq.c1&user_id=eq.test-user")
        XCTAssertTrue(server.requests.allSatisfy { $0.httpMethod == "DELETE" && $0.httpBody == nil })
    }

    func testProfileSaveSendsNullToClearANameAndLeavesTheBioAlone() async throws {
        try await profiles.upsert(displayName: nil, avatarUrl: nil, interests: ["music"], onboarded: false)
        XCTAssertEqual(last.url!.absoluteString, "\(rest)/town_profiles?on_conflict=user_id")
        XCTAssertEqual(last.value(forHTTPHeaderField: "Prefer"), "resolution=merge-duplicates,return=minimal")
        let body = try XCTUnwrap(server.lastBody as? [String: Any])
        XCTAssertTrue(body["display_name"] is NSNull)
        XCTAssertTrue(body["avatar_url"] is NSNull)
        XCTAssertEqual(body["user_id"] as? String, "test-user")
        XCTAssertNil(body["bio"])
        XCTAssertNil(body["cover_url"])
        XCTAssertNil(body["onboarded_at"])
    }

    func testASwitchPatchesOnlyThatColumnOfYourRow() async throws {
        try await profiles.setSwitch("suggest_me", false)
        XCTAssertEqual(last.httpMethod, "PATCH")
        XCTAssertEqual(last.url!.absoluteString, "\(rest)/town_profiles?user_id=eq.test-user")
        XCTAssertEqual(lastBody, ["suggest_me": false])
    }

    func testAWriteSignedOutThrowsAndSendsNothing() async {
        auth.userId = nil
        do {
            try await social.likeEvent("e1")
            XCTFail("a like with no account went through")
        } catch {
            XCTAssertEqual((error as? SupabaseError)?.status, 401)
        }
        XCTAssertTrue(server.requests.isEmpty)
    }

    // MARK: - Errors and the 401 hook

    func testA401TellsTheTokensOwnerOnceAndOtherErrorsDont() async throws {
        server.answers["rpc/get_blocked"] = .init(status: 500, body: #"{"hint":"try later"}"#)
        await XCTAssertThrowsStatus(500, message: "try later") { _ = try await self.community.getBlocked() }
        server.answers["rpc/get_blocked"] = .init(status: 401, body: #"{"message":"JWT expired"}"#)
        await XCTAssertThrowsStatus(401, message: "JWT expired") { _ = try await self.community.getBlocked() }
        try await waitWhile(self.auth.unauthorized == 0)
        // The 500's hook, had it fired, was queued first.
        XCTAssertEqual(auth.unauthorized, 1)
    }

    func testAnUnreadableRefusalStillSaysWhatHappened() async {
        server.answers["rpc/get_blocked"] = .init(status: 503, body: "<html>")
        await XCTAssertThrowsStatus(503, message: "The server couldn't complete this request. Check your connection and try again. (Code 503)") {
            _ = try await self.community.getBlocked()
        }
    }

    func testAMuteAnswerOfNullIsNoHostNotAFailure() async throws {
        let id = UUID().uuidString
        server.answers["rpc/mute_host"] = .init(body: "null")
        let host = try await community.feedChoice(.mute(id))
        XCTAssertNil(host)
        XCTAssertEqual(lastBody, ["p_item": id])
    }

    // MARK: - Photos

    func testAPhotoUploadsToYourFolderAndAnswersItsPublicURL() async throws {
        let photo = Data([0xFF, 0xD8, 0xFF])
        let url = try await profiles.uploadPhoto(photo)
        let sent = last.url!.absoluteString
        let storage = SupabaseConfig.storageURL.absoluteString
        XCTAssertTrue(sent.hasPrefix("\(storage)/object/avatars/test-user/avatar-"), sent)
        XCTAssertTrue(sent.hasSuffix(".jpg"), sent)
        XCTAssertEqual(last.httpMethod, "POST")
        XCTAssertEqual(last.httpBody, photo)
        XCTAssertEqual(last.value(forHTTPHeaderField: "Content-Type"), "image/jpeg")
        XCTAssertEqual(last.value(forHTTPHeaderField: "Authorization"), "Bearer test-access-token")
        XCTAssertEqual(url, sent.replacingOccurrences(of: "/object/avatars/", with: "/object/public/avatars/"))

        _ = try await profiles.uploadPhoto(photo, name: "cover")
        XCTAssertTrue(last.url!.absoluteString.hasPrefix("\(storage)/object/avatars/test-user/cover-"))
    }

    func testAFailedUploadThrowsItsReason() async {
        server.answers["object/avatars"] = .init(status: 400, body: #"{"statusCode":"403","error":"Unauthorized","message":"new row violates row-level security policy"}"#)
        await XCTAssertThrowsStatus(400, message: "new row violates row-level security policy") {
            _ = try await self.profiles.uploadPhoto(Data([1]))
        }

        server.failure = URLError(.notConnectedToInternet)
        do {
            _ = try await profiles.uploadPhoto(Data([1]))
            XCTFail("an upload with no signal went through")
        } catch {
            XCTAssertTrue(error is URLError)
            XCTAssertTrue(SupabaseHTTP.noAnswer(error), "no signal keeps the photo for a retry")
        }

        auth.userId = nil
        server.failure = nil
        let before = server.requests.count
        await XCTAssertThrowsStatus(401, message: "Your session ended. Sign in and try again.") {
            _ = try await self.profiles.uploadPhoto(Data([1]))
        }
        XCTAssertEqual(server.requests.count, before, "no account: nothing sent")
    }

    func testOfflineSendsNothing() async {
        do {
            _ = try await ProfileAPI(auth: auth, send: .offline).uploadPhoto(Data([1]))
            XCTFail("offline upload went through")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
    }

    // MARK: - Moderation

    func testAReportTheCheckShouldReadAgainAsksModeratePost() async throws {
        let id = UUID().uuidString
        server.answers["rpc/report_event"] = .init(body: "true")
        _ = try await community.feedChoice(.report(id, .scam))
        XCTAssertEqual(server.requests[0].url!.absoluteString, "\(rest)/rpc/report_event")
        XCTAssertEqual(server.requests[0].httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: String],
                       ["p_event": id, "p_reason": "scam"])
        try await waitWhile(self.server.requests.count < 2)
        XCTAssertEqual(last.url!.absoluteString, "\(SupabaseConfig.url.absoluteString)/functions/v1/moderate-post")
        XCTAssertEqual(last.value(forHTTPHeaderField: "Authorization"), "Bearer test-access-token")
        XCTAssertEqual(lastBody, ["recheck": id])
    }

    func testDecliningAPostSaysWhy() async throws {
        try await community.declinePost("p1", reason: .wrongWhen)
        XCTAssertEqual(last.httpMethod, "PATCH")
        XCTAssertEqual(last.url!.absoluteString, "\(rest)/club_events?id=eq.p1")
        XCTAssertEqual(lastBody, ["status": "rejected", "review_reason": "wrong_when"])
        XCTAssertEqual(last.value(forHTTPHeaderField: "Prefer"), "return=minimal")
    }

    // MARK: - Helper

    private func XCTAssertThrowsStatus(_ status: Int, message: String, file: StaticString = #filePath,
                                       line: UInt = #line, _ call: () async throws -> Void) async {
        do {
            try await call()
            XCTFail("no error", file: file, line: line)
        } catch let error as SupabaseError {
            XCTAssertEqual(error.status, status, file: file, line: line)
            XCTAssertEqual(error.message, message, file: file, line: line)
        } catch {
            XCTFail("\(error)", file: file, line: line)
        }
    }
}
