//
//  EditPost.swift
//  Block Party — editing your own post (BP app town-feed 44, references/edit-post; Jesse at Check-in 1, 2026-11-13:
//  "i agree"): Edit in your post's ••• opens New post on it, titled Edit post. The words and the Place change; the photo,
//  who can see it and who it's with stay. Done waits in the sheet for the instant check (`moderate-post` `edit`), as an
//  Event's Share does: a yes changes the post everywhere at once, a no says why over Done and changes nothing.
//

import Foundation

/// What Done sends: the post's id, its words, its Place and the `@` names still in its words. Nothing else can change.
nonisolated struct PostEditInput: Equatable, Sendable {
    let id: String
    let words: String
    let place: String?
    let atNames: [AtName]
}

/// The check's answer to an edit.
nonisolated enum PostEditAnswer: Equatable {
    /// Up: the post has the new words and Place.
    case saved
    /// The check's no, with why. Nothing changed.
    case refused(String)
    /// The day's 10 edits are used.
    case limit
    /// The post isn't up anymore (deleted, or taken down while it was checked).
    case gone
    /// No answer, or no signal. Nothing changed.
    case noAnswer

    /// From the check's status and words. A no without words still says something the poster can act on.
    static func from(status: Int, ok: Bool?, reason: String?) -> PostEditAnswer {
        switch status {
        case 200..<300:
            guard let ok else { return .noAnswer }
            if ok { return .saved }
            let words = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .refused(words.isEmpty ? PostEditCopy.refused : words)
        case 429: return .limit
        case 403, 410: return .gone
        default: return .noAnswer
        }
    }

    /// The red line over Done; nil for a yes.
    var problem: String? {
        switch self {
        case .saved: nil
        case .refused(let why): why
        case .limit: PostEditCopy.limit
        case .gone: PostEditCopy.gone
        case .noAnswer: PostEditCopy.noAnswer
        }
    }
}

nonisolated enum PostEditCopy {
    static let title = "Edit post"
    static let done = "Done"
    static let saving = "Saving"
    static let edit = "Edit"
    static let delete = "Delete"
    static let discard = "Discard changes?"
    static let discardWhy = "If you leave now, you'll lose your changes."
    static let refused = "This can't be saved as it is. Try other words."
    static let limit = "That's 10 edits today. Try again tomorrow."
    static let gone = "This post isn't up anymore."
    static let noAnswer = "Couldn't check it. Try again."
}

extension NewPostDraft {
    /// The draft Edit opens on: the post's words, its Place and its `@` names, who can see it shown as it is.
    init(editing post: TownPost) {
        self.init()
        words = post.words
        place = post.place ?? ""
        atNames = post.atNames
        friendsOnly = post.friendsOnly
    }

    /// Done lights once the words or the Place differ from the post's (spaces at the ends don't count).
    func changed(from post: TownPost) -> Bool {
        text != post.words.trimmingCharacters(in: .whitespacesAndNewlines)
            || location != post.place.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// What Done sends for `post`: its trimmed words, its Place and the names still in the words, at most the 20 the
    /// check keeps (one past them would be refused only after the check had read it).
    func edit(of post: TownPost) -> PostEditInput {
        PostEditInput(id: post.id, words: text, place: location, atNames: Array(keptNames.prefix(Self.tagLimit)))
    }
}

extension TownPost {
    /// Only the poster sees Edit and Delete.
    func editable(by userId: String?) -> Bool {
        guard let userId, !userId.isEmpty else { return false }
        return userId.lowercased() == poster.id.lowercased()
    }

    /// The post with an edit the check let up: its words, Place and names; nothing else.
    func edited(_ edit: PostEditInput) -> TownPost {
        guard edit.id == id else { return self }
        var post = self
        post.words = edit.words
        post.place = edit.place
        post.atNames = edit.atNames
        return post
    }
}
