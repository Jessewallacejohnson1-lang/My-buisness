//
//  FeedPhaseRules.swift
//  Block Party — when the lower Today modules load, show, fail, or disappear.
//
//  These are pure so the four-state matrix is assertable in a unit test rather
//  than only by launching the app into each state. `BriefingModel.payload` and
//  `loadFailed` are `private(set)`, so a module reading them directly cannot be
//  driven from a test at all — the rule has to live outside the module.
//

import Foundation

nonisolated enum SpotlightPhaseRule {
    /// A published edition with no active spotlight row is `.empty` and renders
    /// nothing. `.failed` is reserved for the cold start with nothing cached; a
    /// refresh that fails on top of a cached briefing leaves the card on screen,
    /// which is `BriefingModel`'s contract and not something to undo here.
    static func phase(hasSpotlight: Bool, hasPayload: Bool, loadFailed: Bool) -> FeedPhase {
        if hasSpotlight { return .ready }
        if hasPayload { return .empty }
        return loadFailed ? .failed : .loading
    }
}

nonisolated enum SignOffPhaseRule {
    /// There is deliberately no `.failed`. A sign-off is the END of an edition, so
    /// when the edition never arrived there is nothing to close — signing off on a
    /// briefing the reader never saw would be a small lie, and the spotlight above
    /// already carries that failure with its retry.
    static func phase(hasPayload: Bool, loadFailed: Bool) -> FeedPhase {
        if hasPayload { return .ready }
        return loadFailed ? .empty : .loading
    }
}

nonisolated enum TriviaPhaseRule {
    /// The module hosts two independent things: today's regular touch, which comes
    /// from the briefing payload, and the trivia question, which fetches itself.
    /// Either one being present is enough to render, so a failed trivia fetch never
    /// hides a poll that arrived fine.
    static func phase(trivia: FeedPhase, hasTouch: Bool) -> FeedPhase {
        if trivia == .ready || hasTouch { return .ready }
        if trivia == .loading { return .loading }
        if trivia == .failed { return .failed }
        return .empty
    }
}
