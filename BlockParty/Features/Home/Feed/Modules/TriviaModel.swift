//
//  TriviaModel.swift
//  Block Party — one immutable, persisted St. Joe trivia answer per town day.
//

import Combine
import Foundation

nonisolated struct TriviaStats: Codable, Equatable, Sendable {
    let correctAnswerPercentage: Int?
    let responseCount: Int

    /// The server is the privacy boundary and returns nil below ten responses.
    /// Keep the same threshold here as defense in depth so malformed cached data
    /// can never make a small sample visible.
    var visibleCorrectAnswerPercentage: Int? {
        responseCount >= 10 ? correctAnswerPercentage : nil
    }
}

nonisolated struct TriviaQuestion: Equatable, Identifiable, Sendable {
    let id: String
    let prompt: String
    let options: [String]
    let correctIndex: Int
    let myAnswer: Int?
    let stats: TriviaStats?
    let streakCount: Int?

    var hasAnswered: Bool { myAnswer != nil }
    var isCorrect: Bool { myAnswer == correctIndex }

    func applyingAnswer(_ optionIndex: Int) -> TriviaQuestion {
        guard !hasAnswered, options.indices.contains(optionIndex) else { return self }
        return TriviaQuestion(
            id: id,
            prompt: prompt,
            options: options,
            correctIndex: correctIndex,
            myAnswer: optionIndex,
            stats: nil,
            streakCount: streakCount
        )
    }
}

/// Direct `daily_touches` wire shape. A missing `correct_idx` fails decoding
/// before malformed trivia can reach the UI; the database constraint is still
/// the authoritative write boundary.
nonisolated struct TriviaQuestionRecord: Decodable, Equatable, Sendable {
    let id: String
    let prompt: String
    let options: [String]
    let correctIdx: Int

    func question(
        myAnswer: Int?,
        stats: TriviaStats?,
        streakCount: Int?
    ) throws -> TriviaQuestion {
        guard options.count == 4,
              options.indices.contains(correctIdx),
              myAnswer.map(options.indices.contains) ?? true
        else { throw TriviaQuestionError.invalidRecord }

        return TriviaQuestion(
            id: id,
            prompt: prompt,
            options: options,
            correctIndex: correctIdx,
            myAnswer: myAnswer,
            stats: stats,
            streakCount: streakCount
        )
    }
}

nonisolated enum TriviaQuestionError: Error {
    case invalidRecord
}

@MainActor
protocol TriviaServicing {
    func today() async throws -> TriviaQuestion?
    func answer(questionID: String, optionIndex: Int) async throws -> TriviaQuestion
}

@MainActor
final class TriviaModel: ObservableObject {
    @Published private(set) var phase: FeedPhase = .loading
    @Published private(set) var question: TriviaQuestion?

    func load(_ service: TriviaServicing) async {
        phase = .loading
        do {
            question = try await service.today()
            phase = question == nil ? .empty : .ready
        } catch {
            Log.network("trivia load failed: \(error.localizedDescription)")
            question = nil
            phase = .failed
        }
    }

    #if DEBUG
    func seed(_ question: TriviaQuestion?) {
        self.question = question
        phase = question == nil ? .empty : .ready
    }
    #endif

    /// Reveals immediately, then replaces the optimistic answer with the
    /// server-authoritative own vote. A cross-device duplicate therefore restores
    /// the first persisted answer rather than pretending the later tap won.
    @discardableResult
    func answer(_ optionIndex: Int, using service: TriviaServicing) async -> Bool {
        guard let current = question, !current.hasAnswered,
              current.options.indices.contains(optionIndex)
        else { return false }

        question = current.applyingAnswer(optionIndex)
        do {
            question = try await service.answer(
                questionID: current.id,
                optionIndex: optionIndex
            )
            phase = .ready
            return true
        } catch {
            Log.network("trivia answer failed: \(error.localizedDescription)")
            question = current
            phase = .ready
            return false
        }
    }
}

/// A deliberately closed neutral palette. SwiftUI resolves these roles to the
/// shared ink tokens; correctness is encoded separately by symbol and weight.
nonisolated enum TriviaNeutralForegroundRole: Equatable, Hashable, Sendable {
    case ink
    case inkSecondary
}

nonisolated enum TriviaAnswerVisualState: Equatable, Sendable {
    case unanswered
    case selectedCorrect
    case selectedIncorrect
    case correctAnswer
    case notSelected

    static func resolve(optionIndex: Int, question: TriviaQuestion) -> Self {
        guard question.hasAnswered else { return .unanswered }
        if optionIndex == question.myAnswer {
            return optionIndex == question.correctIndex
                ? .selectedCorrect
                : .selectedIncorrect
        }
        return optionIndex == question.correctIndex ? .correctAnswer : .notSelected
    }

    var symbolName: String {
        switch self {
        case .unanswered, .notSelected: "square"
        case .selectedCorrect, .correctAnswer: "checkmark.square.fill"
        case .selectedIncorrect: "xmark.square.fill"
        }
    }

    var foregroundRole: TriviaNeutralForegroundRole {
        switch self {
        case .unanswered, .selectedCorrect, .selectedIncorrect, .correctAnswer: .ink
        case .notSelected: .inkSecondary
        }
    }
}

#if DEBUG
nonisolated enum TriviaDebugFixtures {
    static func question(arguments: [String] = ProcessInfo.processInfo.arguments) -> TriviaQuestion? {
        if arguments.contains("-trivia-streak") {
            return make(
                id: "debug-trivia-streak",
                myAnswer: 1,
                stats: TriviaStats(correctAnswerPercentage: 63, responseCount: 19),
                streakCount: 4
            )
        }
        if arguments.contains("-trivia-low-sample") {
            return make(
                id: "debug-trivia-low-sample",
                myAnswer: 0,
                stats: TriviaStats(correctAnswerPercentage: nil, responseCount: 9),
                streakCount: nil
            )
        }
        if arguments.contains("-trivia-answered") {
            return make(
                id: "debug-trivia-answered",
                myAnswer: 1,
                stats: TriviaStats(correctAnswerPercentage: 54, responseCount: 37),
                streakCount: nil
            )
        }
        if arguments.contains("-trivia-sample") {
            return make(
                id: "debug-trivia-sample",
                myAnswer: nil,
                stats: nil,
                streakCount: nil
            )
        }
        return nil
    }

    private static func make(
        id: String,
        myAnswer: Int?,
        stats: TriviaStats?,
        streakCount: Int?
    ) -> TriviaQuestion {
        TriviaQuestion(
            id: id,
            prompt: "Which river runs through Millstream Park?",
            options: ["Sauk River", "Watab River", "Mississippi River", "Rum River"],
            correctIndex: 1,
            myAnswer: myAnswer,
            stats: stats,
            streakCount: streakCount
        )
    }
}
#endif
