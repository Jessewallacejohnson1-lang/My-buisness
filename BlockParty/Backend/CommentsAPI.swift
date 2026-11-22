//
//  CommentsAPI.swift
//  Block Party — comments on a post (BP app backlog 38; Jesse's yes at Check-in 1, 2026-11-21, mock
//  https://claude.ai/artifact/PS7c9ZLvGzf2cy44NBgCgH). A comment goes up pending, Claude's instant check
//  (`moderate-post` `comment`) shows it or turns it down with one short reason, and only shown ones reach anyone
//  else: the sheet (`get_post_comments`), the pill (the post row's `comments`) and the bell
//  (`get_my_comment_notices`).
//

import Foundation

/// One comment as a post's sheet lists it.
nonisolated struct PostComment: Identifiable, Hashable, Sendable {
    let id: String
    let body: String
    var createdAt: Date
    let author: TownPost.Person
    var authorPhoto: URL? = nil
    /// The `@` names in it still good for you, each opening its page.
    var atNames: [AtName] = []
    /// Yours: no Report on it.
    var mine = false
    /// Yours, or on your post: Delete.
    var canDelete = false
    /// Sent and still with the check: "Posting…", no Reply.
    var posting = false
}

/// What the instant check said about a comment just sent.
nonisolated enum CommentCheck: Equatable, Sendable {
    case shown
    /// Turned down, with the one sentence that says why.
    case declined(String)
    /// The day's 50 checks are used.
    case busy
    /// Nothing answered: the comment came back down.
    case noAnswer
}

/// A reported comment, as the report kept it (never who reported it), for the admin's Review queue.
nonisolated struct ReportedComment: Identifiable, Equatable, Decodable, Sendable {
    let id: String
    let writerName: String?
    let body: String
    let postWords: String?
    let reason: String
}

extension CommunityAPI {
    /// A post's shown comments, oldest first, as you may see them (no one either side blocked).
    func postComments(_ post: String) async throws -> [PostComment] {
        try Self.commentRows(from: await db.rpc("get_post_comments", ["p_post": post], anon: true))
    }

    nonisolated static func commentRows(from data: Data) throws -> [PostComment] {
        struct Row: Decodable {
            struct Author: Decodable { let id: String; let name: String; let photo: String? }
            let id: String
            let body: String
            let createdAt: String
            let author: Author?
            let atNames: [AtName.Lenient]?
            let mine: Bool?
            let canDelete: Bool?
        }
        return try Supabase.decode(data, as: [Row].self).compactMap { row in
            guard let author = row.author, !author.name.isEmpty, let at = DateHelpers.timestamp(row.createdAt) else { return nil }
            return PostComment(id: row.id, body: row.body, createdAt: at, author: .init(id: author.id, name: author.name),
                               authorPhoto: author.photo.flatMap(URL.init(string:)),
                               atNames: (row.atNames ?? []).compactMap(\.value), mine: row.mine ?? false,
                               canDelete: row.canDelete ?? false)
        }
    }

    /// Sends your comment `id` on `post`, pending, then asks the check. A comment that isn't shown or turned down
    /// comes back down, so the words can go back in the box: an insert whose answer was lost, the day's 50 used, or a
    /// check that never answered. That last one is read once first, since a lost answer may have followed a yes.
    func sendComment(id: String, post: String, body: String, atNames: [AtName]) async -> CommentCheck {
        do {
            let row: [String: Any] = [
                "id": id, "event_id": post, "user_id": try db.userID, "body": body,
                "at_names": atNames.isEmpty ? NSNull() : atNames.map { ["kind": $0.kind.rawValue, "id": $0.id, "name": $0.name] },
            ]
            try await db.rest("event_comments", method: "POST", body: row, prefer: "return=minimal")
        } catch {
            try? await deleteComment(id)
            return .noAnswer
        }
        let check: CommentCheck
        do {
            struct Answer: Decodable { let ok: Bool; let reason: String? }
            let answer = try JSONDecoder().decode(Answer.self, from: await db.invoke("moderate-post", ["comment": id]))
            check = answer.ok ? .shown : .declined(Self.declineWords(answer.reason))
        } catch let error as SupabaseError where error.status == 429 {
            check = .busy
        } catch {
            check = .noAnswer
        }
        guard check == .busy || check == .noAnswer else { return check }
        if check == .noAnswer, (try? await commentStatus(id)) == "shown" { return .shown }
        try? await deleteComment(id)
        return check
    }

    /// A no without words still says something the writer can act on.
    nonisolated static func declineWords(_ reason: String?) -> String {
        let words = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return words.isEmpty ? "This comment can't be posted as it is." : words
    }

    private func commentStatus(_ id: String) async throws -> String? {
        struct Row: Decodable { let status: String }
        let rows: [Row] = try Supabase.decode(await db.rest("event_comments", [("select", "status"), ("id", "eq.\(id)")]))
        return rows.first?.status
    }

    /// Yours, or any on your post.
    func deleteComment(_ id: String) async throws {
        try await db.rest("event_comments", method: "DELETE", [("id", "eq.\(id)")], prefer: "return=minimal")
    }

    func reportComment(_ id: String, reason: ReportReason) async throws {
        try await db.rpc("report_comment", ["p_comment": id, "p_reason": reason.rawValue])
    }

    /// The bell's comment rows, last 7 days: others on your post, and an `@` of you on someone else's.
    func getMyCommentNotices() async throws -> [NamedNotice] {
        try Self.commentNoticeRows(from: await db.rpc("get_my_comment_notices"))
    }

    /// Each a post as the Town feed sends it, how it reaches you, its newest writer, how many others wrote and when.
    /// One that doesn't read is left out, never the bell.
    nonisolated static func commentNoticeRows(from data: Data) throws -> [NamedNotice] {
        struct Row: Decodable {
            struct Who: Decodable { let id: String; let name: String; let photo: String? }
            let row: FeedRow
            let how: String?
            let who: Who?
            let others: Int?
            let at: String?
            private enum Keys: String, CodingKey { case how, who, others, at }
            init(from decoder: Decoder) throws {
                row = try FeedRow(from: decoder)
                let c = try decoder.container(keyedBy: Keys.self)
                how = try? c.decodeIfPresent(String.self, forKey: .how)
                who = try? c.decodeIfPresent(Who.self, forKey: .who)
                others = try? c.decodeIfPresent(Int.self, forKey: .others)
                at = try? c.decodeIfPresent(String.self, forKey: .at)
            }
        }
        return try Supabase.decode(data, as: [Row].self).compactMap { row in
            guard case .post(let post)? = row.row.line, let who = row.who, !who.name.isEmpty,
                  let at = row.at.flatMap({ DateHelpers.timestamp($0) }) else { return nil }
            let how: NamedNotice.How
            switch row.how {
            case "commented": how = .commented
            case "replied": how = .replied
            default: return nil
            }
            return NamedNotice(post: post, how: how, who: .init(id: who.id, name: who.name),
                               whoPhoto: who.photo.flatMap(URL.init(string:)), others: max(row.others ?? 0, 0), at: at)
        }
    }

    // MARK: The admin's review queue

    func reportedComments() async throws -> [ReportedComment] {
        try Supabase.decode(await db.rpc("get_comment_reports"))
    }

    /// Keep (the report goes) or hide (the comment leaves every read).
    func resolveCommentReport(_ id: String, hide: Bool) async throws {
        try await db.rpc("resolve_comment_report", ["p_report": id, "p_hide": hide])
    }
}
