//
//  FeedCommentState.swift
//  Block Party — a post's comments as its card and sheet hold them (BP app backlog 38): the list, oldest first; the
//  pill's count, which always agrees with it; a comment of yours on its way ("Posting…") until the check answers.
//

import Foundation
import Observation

/// What the box says after a comment didn't go up: a turned-down one's reason in red, anything else in grey. The
/// words go back in the box with it.
struct CommentRefusal: Equatable {
    let words: String
    var red = false
}

@MainActor @Observable
final class CommentThread {
    let post: TownPost
    private(set) var comments: [PostComment] = []
    private(set) var loading = false
    /// The last read failed with nothing read before it.
    private(set) var failed = false
    /// Read once: from then on the pill counts the list.
    private(set) var loaded = false
    @ObservationIgnored private let api: CommunityAPI

    init(post: TownPost, api: CommunityAPI) {
        self.post = post
        self.api = api
    }

    /// One per post while the app runs, so a card the feed lays out again, or a second card of the same post, keeps
    /// the count the sheet left.
    private static var kept: [String: CommentThread] = [:]

    static func existing(_ post: String) -> CommentThread? { kept[post] }

    static func of(_ post: TownPost, api: @autoclosure () -> CommunityAPI) -> CommentThread {
        if let thread = kept[post.id] { return thread }
        let thread = CommentThread(post: post, api: api())
        kept[post.id] = thread
        return thread
    }

    /// The pill's number: the shown ones, the feed's count until the sheet has read them.
    var count: Int { loaded ? comments.filter { !$0.posting }.count : post.comments }

    func load() async {
        loading = true
        do {
            let read = try await api.postComments(post.id)
            // Yours still on their way stay at the bottom.
            comments = read + comments.filter { $0.posting && !read.map(\.id).contains($0.id) }
            loaded = true
            failed = false
        } catch {
            failed = comments.isEmpty
            Log.network("CommentThread.load: \(error)")
        }
        loading = false
    }

    /// Your comment goes in at the bottom at once as "Posting…", then the check: shown, it stays (nil); anything
    /// else takes it out and says why.
    func send(_ body: String, names: [AtName], me: TownPost.Person, photo: URL?) async -> CommentRefusal? {
        let id = UUID().uuidString.lowercased()
        comments.append(PostComment(id: id, body: body, createdAt: Date(), author: me, authorPhoto: photo, atNames: names,
                                    mine: true, canDelete: true, posting: true))
        let check = await api.sendComment(id: id, post: post.id, body: body, atNames: names)
        switch check {
        case .shown:
            if let i = comments.firstIndex(where: { $0.id == id }) {
                comments[i].posting = false
                comments[i].createdAt = Date()
            }
            return nil
        case .declined(let why):
            comments.removeAll { $0.id == id }
            return CommentRefusal(words: CommentCopy.declined(why), red: true)
        case .busy:
            comments.removeAll { $0.id == id }
            return CommentRefusal(words: CommentCopy.busy)
        case .noAnswer:
            comments.removeAll { $0.id == id }
            return CommentRefusal(words: CommentCopy.noAnswer)
        }
    }

    /// Out at once; back where it was if the delete fails.
    func delete(_ comment: PostComment) async -> Bool {
        guard let i = comments.firstIndex(where: { $0.id == comment.id }) else { return true }
        comments.remove(at: i)
        do {
            try await api.deleteComment(comment.id)
            return true
        } catch {
            comments.insert(comment, at: min(i, comments.count))
            Log.network("CommentThread.delete: \(error)")
            return false
        }
    }

    func report(_ comment: PostComment, _ reason: ReportReason) async -> Bool {
        do {
            try await api.reportComment(comment.id, reason: reason)
            return true
        } catch {
            Log.network("CommentThread.report: \(error)")
            return false
        }
    }

    /// Who a reply's `@` offers before your friends: the poster and everyone who wrote here, newest writer first,
    /// never you.
    func people(me: String?) -> [AtCandidate] {
        var seen: Set<String> = [me ?? ""]
        var out: [AtCandidate] = []
        let writers = comments.reversed().filter { !$0.posting }.map { ($0.author, $0.authorPhoto) }
        for (person, photo) in writers + [(post.poster, post.posterPhoto)] where seen.insert(person.id).inserted {
            out.append(AtCandidate(name: AtName(kind: .user, id: person.id, name: person.name),
                                   picture: .person(photo?.absoluteString)))
        }
        return out
    }
}

/// The sheet's words (Mobbin: Instagram's, backlog 38).
enum CommentCopy {
    static let title = "Comments"
    static let empty = "No comments yet"
    static let emptyLine = "Start the conversation."
    static let posting = "Posting…"
    static let reply = "Reply"
    static let report = "Report"
    static let delete = "Delete"
    static let noAnswer = "Couldn't post that. Try again."
    static let busy = "You've hit today's limit."
    static let loadFailed = "Couldn't load comments. Tap to try again."
    static let deleteFailed = "Couldn't delete that. Try again."
    static let reported = "Reported. Thanks for telling us."
    static let reportFailed = "Couldn't send that report. Try again."

    /// "Add a comment for Marlene", or "Add a comment…" on your own post (the mock's two).
    static func placeholder(poster: String?) -> String {
        guard let first = poster?.split(separator: " ").first else { return "Add a comment…" }
        return "Add a comment for \(first)"
    }

    /// The check's one reason, after "Not posted." (the mock's "Not posted. Keep it kind: …").
    static func declined(_ why: String) -> String { "Not posted. \(why)" }
}
