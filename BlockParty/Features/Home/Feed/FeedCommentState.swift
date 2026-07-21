//
//  FeedCommentState.swift
//  Block Party — optimistic flat-comment state for the feed sheet.
//

import Foundation

struct FeedCommentState {
    private(set) var comments: [EventComment]

    init(comments: [EventComment]) {
        self.comments = comments.sorted { $0.createdAt < $1.createdAt }
    }

    @discardableResult
    mutating func appendLocal(
        body: String,
        id: String = UUID().uuidString,
        createdAt: Date = Date()
    ) -> EventComment? {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return nil }

        let comment = EventComment(
            id: id,
            body: trimmedBody,
            createdAt: createdAt,
            authorId: "local",
            authorName: "You",
            authorAvatar: nil
        )
        comments.append(comment)
        return comment
    }

    mutating func replaceAll(with loadedComments: [EventComment]) {
        comments = loadedComments.sorted { $0.createdAt < $1.createdAt }
    }

    mutating func replace(_ localID: String, with comment: EventComment) {
        guard let index = comments.firstIndex(where: { $0.id == localID }) else {
            comments.append(comment)
            comments.sort { $0.createdAt < $1.createdAt }
            return
        }
        comments[index] = comment
    }

    mutating func remove(_ id: String) {
        comments.removeAll { $0.id == id }
    }
}
