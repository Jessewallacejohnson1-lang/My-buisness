//
//  FeedCommentState.swift
//  Block Party — deterministic in-memory state for the Phase 2 comment sheet.
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
    ) -> Bool {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return false }

        comments.append(
            EventComment(
                id: id,
                body: trimmedBody,
                createdAt: createdAt,
                authorId: "local",
                authorName: "You",
                authorAvatar: nil
            )
        )
        return true
    }
}
