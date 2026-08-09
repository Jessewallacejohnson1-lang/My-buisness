//
//  TriviaAPI.swift
//  Block Party — today's trivia row, caller-owned answer, and safe aggregates.
//

import Foundation

enum TriviaAPIError: LocalizedError {
    case notSignedIn
    case answerNotRestored

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            "You need to be signed in to answer."
        case .answerNotRestored:
            "Your answer could not be confirmed."
        }
    }
}

@MainActor
struct TriviaAPI: TriviaServicing {
    let auth: AuthStore

    func today() async throws -> TriviaQuestion? {
        guard let userID = auth.userId else { throw TriviaAPIError.notSignedIn }
        let token = try await auth.validAccessToken()
        let date = BriefingModel.townToday()
        let questionQuery = [
            "select=id,prompt,options,correct_idx",
            "kind=eq.trivia",
            "used_on=eq.\(date)",
            "limit=1",
        ].joined(separator: "&")
        let (questionData, _) = try await SupabaseHTTP.rest(
            "daily_touches",
            query: questionQuery,
            accessToken: token
        )
        guard let record = try SupabaseCoding.decoder
            .decode([TriviaQuestionRecord].self, from: questionData)
            .first
        else { return nil }

        let voteQuery = [
            "select=option_idx",
            "touch_id=eq.\(record.id)",
            "user_id=eq.\(userID)",
            "limit=1",
        ].joined(separator: "&")
        let (voteData, _) = try await SupabaseHTTP.rest(
            "touch_votes",
            query: voteQuery,
            accessToken: token
        )
        let myAnswer = try SupabaseCoding.decoder
            .decode([TriviaVoteRecord].self, from: voteData)
            .first?
            .optionIdx

        var stats: TriviaStats?
        var streakCount: Int?
        if myAnswer != nil {
            do {
                stats = try await loadStats(questionID: record.id, token: token)
            } catch {
                Log.network("trivia stats failed: \(error.localizedDescription)")
            }
            do {
                streakCount = try await loadStreak(token: token)
            } catch {
                Log.network("trivia streak failed: \(error.localizedDescription)")
            }
        }

        return try record.question(
            myAnswer: myAnswer,
            stats: stats,
            streakCount: streakCount
        )
    }

    func answer(questionID: String, optionIndex: Int) async throws -> TriviaQuestion {
        guard let userID = auth.userId else { throw TriviaAPIError.notSignedIn }
        let token = try await auth.validAccessToken()
        let body = try JSONSerialization.data(withJSONObject: [
            "touch_id": questionID,
            "user_id": userID,
            "option_idx": optionIndex,
        ])
        _ = try await SupabaseHTTP.rest(
            "touch_votes",
            method: "POST",
            query: "on_conflict=touch_id,user_id",
            accessToken: token,
            body: body,
            prefer: "resolution=ignore-duplicates,return=minimal"
        )

        guard let restored = try await today(),
              restored.id == questionID,
              restored.hasAnswered
        else { throw TriviaAPIError.answerNotRestored }
        return restored
    }

    private func loadStats(questionID: String, token: String) async throws -> TriviaStats? {
        let body = try JSONSerialization.data(withJSONObject: ["p_touch_id": questionID])
        let (data, _) = try await SupabaseHTTP.rest(
            "rpc/touch_stats",
            method: "POST",
            accessToken: token,
            body: body
        )
        return try SupabaseCoding.decoder.decode([TriviaStats].self, from: data).first
    }

    private func loadStreak(token: String) async throws -> Int {
        let body = try JSONSerialization.data(withJSONObject: [
            "p_tz": Town.timeZone.identifier,
        ])
        let (data, _) = try await SupabaseHTTP.rest(
            "rpc/trivia_streak",
            method: "POST",
            accessToken: token,
            body: body
        )
        return try SupabaseCoding.decoder.decode(Int.self, from: data)
    }
}

private nonisolated struct TriviaVoteRecord: Decodable {
    let optionIdx: Int
}
