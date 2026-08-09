//
//  TriviaModule.swift
//  Block Party — today's regular touch plus one independently fetched trivia card.
//

import Combine
import SwiftUI

@MainActor
final class TriviaModule: @MainActor FeedModule {
    let objectWillChange = ObservableObjectPublisher()
    let id: FeedModuleID = .trivia
    let order = 6
    let ownsFetch = true

    private let briefing: BriefingModel
    private let trivia: TriviaModel
    private var triviaObservation: AnyCancellable?

    init(briefing: BriefingModel, trivia: TriviaModel? = nil) {
        self.briefing = briefing
        self.trivia = trivia ?? TriviaModel()
        triviaObservation = self.trivia.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var phase: FeedPhase {
        if trivia.phase == .ready || briefing.payload?.touch != nil { return .ready }
        if trivia.phase == .loading { return .loading }
        if trivia.phase == .failed { return .failed }
        return .empty
    }

    func isVisible(_ ctx: FeedModuleContext) -> Bool { true }

    func load(_ ctx: FeedModuleContext) async {
        #if DEBUG
        if applyDebugSeedIfRequested() { return }
        #endif
        await trivia.load(TriviaAPI(auth: ctx.auth))
    }

    func makeView(_ ctx: FeedModuleContext) -> AnyView {
        AnyView(
            VStack(spacing: 16) {
                if showsRegularTouch, let touch = ctx.briefing.payload?.touch {
                    DailyTouchCard(
                        touch: touch,
                        onVote: { index in self.vote(in: ctx, touch: touch, optionIndex: index) }
                    )
                }

                switch trivia.phase {
                case .loading:
                    DailyTouchSkeleton()
                case .ready:
                    if let question = trivia.question {
                        TriviaCard(
                            question: question,
                            onAnswer: { index in
                                self.answer(in: ctx, question: question, optionIndex: index)
                            }
                        )
                    }
                case .failed:
                    TriviaUnavailableCard { Task { await self.load(ctx) } }
                case .empty:
                    EmptyView()
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .springReveal(
                3,
                revealed: ctx.contentRevealed,
                animated: ctx.revealAnimated
            )
        )
    }

    private var showsRegularTouch: Bool {
        #if DEBUG
        return TriviaDebugFixtures.question() == nil
        #else
        return true
        #endif
    }

    private func vote(in ctx: FeedModuleContext, touch: BriefingTouch, optionIndex: Int) {
        Task {
            let api = BriefingAPI(auth: ctx.auth)
            let landed = await ctx.briefing.vote(api, optionIndex: optionIndex)
            guard landed else { return }
            ctx.analytics.record(
                BriefingEventName.touchVote,
                payload: ["touch_id": touch.id, "option_idx": optionIndex],
                auth: ctx.auth
            )
        }
    }

    private func answer(in ctx: FeedModuleContext, question: TriviaQuestion, optionIndex: Int) {
        Task {
            let landed = await trivia.answer(
                optionIndex,
                using: TriviaAPI(auth: ctx.auth)
            )
            guard landed else {
                Haptics.error()
                return
            }
            ctx.analytics.record(
                BriefingEventName.touchVote,
                payload: ["touch_id": question.id, "option_idx": optionIndex],
                auth: ctx.auth
            )
        }
    }
}

private struct TriviaUnavailableCard: View {
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today’s trivia is unavailable.")
                .font(.displaySemi(20))
                .foregroundStyle(Hue.ink)

            Button("Try again", action: retry)
                .font(.sansSemibold(15))
                .foregroundStyle(Hue.ink)
                .frame(minHeight: 44)
                .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .blockPartyCard(padding: 18)
    }
}

#if DEBUG
private extension TriviaModule {
    func applyDebugSeedIfRequested() -> Bool {
        guard let question = TriviaDebugFixtures.question() else { return false }
        trivia.seed(question)
        return true
    }
}
#endif
