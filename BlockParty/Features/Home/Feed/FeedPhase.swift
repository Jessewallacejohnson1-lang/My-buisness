//
//  FeedPhase.swift
//  Block Party — the rendering phase owned by each Today module.
//

nonisolated enum FeedPhase: Equatable {
    case loading
    case empty
    case failed
    case ready
}
