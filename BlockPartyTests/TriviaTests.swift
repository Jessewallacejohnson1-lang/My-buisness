//
//  TriviaTests.swift
//  BlockPartyTests — daily St. Joe trivia behavior and presentation contract.
//

import XCTest
@testable import BlockParty

@MainActor
final class TriviaTests: XCTestCase {
    func testTownPercentageIsHiddenBelowTenResponses() {
        let stats = TriviaStats(correctAnswerPercentage: 67, responseCount: 9)

        XCTAssertNil(stats.visibleCorrectAnswerPercentage)
    }

    func testTownPercentageIsShownAtTenResponses() {
        let stats = TriviaStats(correctAnswerPercentage: 60, responseCount: 10)

        XCTAssertEqual(stats.visibleCorrectAnswerPercentage, 60)
    }

    func testServerNullPercentageStaysHiddenAboveThreshold() {
        let stats = TriviaStats(correctAnswerPercentage: nil, responseCount: 24)

        XCTAssertNil(stats.visibleCorrectAnswerPercentage)
    }

    func testModelAcceptsOnlyOneAnswerForTodaysQuestion() async {
        let service = InMemoryTriviaService(question: question())
        let model = TriviaModel()
        await model.load(service)

        let firstLanded = await model.answer(1, using: service)
        let secondLanded = await model.answer(3, using: service)

        XCTAssertTrue(firstLanded)
        XCTAssertFalse(secondLanded)
        XCTAssertEqual(service.answerRequests, [1])
        XCTAssertEqual(model.question?.myAnswer, 1)
    }

    func testAnsweredStateRestoresWhenANewModelLoads() async {
        let service = InMemoryTriviaService(question: question())
        let firstModel = TriviaModel()
        await firstModel.load(service)
        _ = await firstModel.answer(1, using: service)

        let reopenedModel = TriviaModel()
        await reopenedModel.load(service)

        XCTAssertEqual(reopenedModel.phase, .ready)
        XCTAssertEqual(reopenedModel.question?.myAnswer, 1)
        XCTAssertTrue(reopenedModel.question?.isCorrect ?? false)
        XCTAssertEqual(
            reopenedModel.question?.stats?.visibleCorrectAnswerPercentage,
            75
        )
    }

    func testFailedWriteRollsBackImmediateReveal() async {
        let service = InMemoryTriviaService(question: question(), answerFails: true)
        let model = TriviaModel()
        await model.load(service)

        let landed = await model.answer(2, using: service)

        XCTAssertFalse(landed)
        XCTAssertNil(model.question?.myAnswer)
    }

    func testTriviaRecordWithoutCorrectIndexIsRejected() {
        let json = #"""
        {
          "id": "missing-answer",
          "prompt": "Which river runs through Millstream Park?",
          "options": ["Watab River", "Sauk River", "Mississippi River", "Rum River"]
        }
        """#

        XCTAssertThrowsError(
            try SupabaseCoding.decoder.decode(TriviaQuestionRecord.self, from: Data(json.utf8))
        )
    }

    func testCorrectnessUsesGlyphAndNeutralValueRolesInsteadOfHue() {
        let answeredStates: [TriviaAnswerVisualState] = [
            .selectedCorrect,
            .selectedIncorrect,
            .correctAnswer,
            .notSelected,
        ]

        XCTAssertTrue(
            answeredStates.allSatisfy {
                [.ink, .inkSecondary].contains($0.foregroundRole)
            }
        )
        XCTAssertNotEqual(
            TriviaAnswerVisualState.selectedCorrect.symbolName,
            TriviaAnswerVisualState.selectedIncorrect.symbolName
        )
    }

    func testWrongAnswerMarksTheSelectionAndTheCorrectOptionSeparately() {
        let answered = TriviaQuestion(
            id: "answered-trivia",
            prompt: "Which river runs through Millstream Park?",
            options: ["Sauk River", "Watab River", "Mississippi River", "Rum River"],
            correctIndex: 1,
            myAnswer: 0,
            stats: nil,
            streakCount: nil
        )

        XCTAssertEqual(
            TriviaAnswerVisualState.resolve(optionIndex: 0, question: answered),
            .selectedIncorrect
        )
        XCTAssertEqual(
            TriviaAnswerVisualState.resolve(optionIndex: 1, question: answered),
            .correctAnswer
        )
        XCTAssertEqual(
            TriviaAnswerVisualState.resolve(optionIndex: 2, question: answered),
            .notSelected
        )
    }

    private func question() -> TriviaQuestion {
        TriviaQuestion(
            id: "today-trivia",
            prompt: "Which river runs through Millstream Park?",
            options: ["Sauk River", "Watab River", "Mississippi River", "Rum River"],
            correctIndex: 1,
            myAnswer: nil,
            stats: nil,
            streakCount: nil
        )
    }
}

@MainActor
private final class InMemoryTriviaService: TriviaServicing {
    private(set) var answerRequests: [Int] = []
    private var storedQuestion: TriviaQuestion
    private let answerFails: Bool

    init(question: TriviaQuestion, answerFails: Bool = false) {
        storedQuestion = question
        self.answerFails = answerFails
    }

    func today() async throws -> TriviaQuestion? {
        storedQuestion
    }

    func answer(questionID: String, optionIndex: Int) async throws -> TriviaQuestion {
        answerRequests.append(optionIndex)
        if answerFails { throw TriviaTestError.writeFailed }

        if storedQuestion.myAnswer == nil {
            storedQuestion = TriviaQuestion(
                id: storedQuestion.id,
                prompt: storedQuestion.prompt,
                options: storedQuestion.options,
                correctIndex: storedQuestion.correctIndex,
                myAnswer: optionIndex,
                stats: TriviaStats(correctAnswerPercentage: 75, responseCount: 12),
                streakCount: optionIndex == storedQuestion.correctIndex ? 3 : nil
            )
        }
        return storedQuestion
    }
}

private enum TriviaTestError: Error {
    case writeFailed
}
