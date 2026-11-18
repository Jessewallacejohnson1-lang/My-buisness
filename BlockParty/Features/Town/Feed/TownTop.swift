//
//  TownTop.swift
//  Block Party — the Town feed's top five (BP app town-feed 73).
//
//  An open after an hour or more away rolls a new top: `get_town_feed` starts the feed with five
//  big real happenings drawn by this roll, the same five for every read until the next roll. The
//  roll's first cards are kept (live ones lead, then the five), so the next roll never leads with
//  the same one again. Kept on the phone, so a relaunch inside the hour keeps the same five.
//

import Foundation

final class TownTop {
    /// Away this long, an open rolls a new top (Jesse, 2026-11-17: "let's say an hour").
    static let after: TimeInterval = 60 * 60

    private let keep: UserDefaults

    init(keep: UserDefaults = .standard) {
        self.keep = keep
    }

    /// The roll every read sends; nil until the first open rolls one.
    var seed: Int? { keep.object(forKey: "townTop.seed") as? Int }
    /// The last roll's first cards, none of which this roll leads with.
    private var previous: [String] { keep.stringArray(forKey: "townTop.previous") ?? [] }
    /// This roll's first cards, once its first read has landed: up to 3 live ones, then the five's first.
    private var first: [String]? { keep.stringArray(forKey: "townTop.first") }
    /// When the Town feed last went off screen, kept across a relaunch.
    var leftAt: Date? {
        get { keep.object(forKey: "townTop.leftAt") as? Date }
        set { keep.set(newValue, forKey: "townTop.leftAt") }
    }

    /// A new roll. Its first card is the next read's first.
    func roll() {
        if let first { keep.set(first, forKey: "townTop.previous") }
        keep.removeObject(forKey: "townTop.first")
        keep.set(Int.random(in: 1...Int(Int32.max)), forKey: "townTop.seed")
    }

    /// A read landed under this roll: its first cards, kept once.
    func landed(_ ids: [String]) {
        guard first == nil, !ids.isEmpty else { return }
        keep.set(Array(ids.prefix(4)), forKey: "townTop.first")
    }

    /// What `get_town_feed` takes: the roll, and the last roll's first cards that are the database's.
    var args: [String: Any] {
        var args: [String: Any] = [:]
        if let seed { args["p_top_seed"] = seed }
        let ids = previous.filter { UUID(uuidString: $0) != nil }
        if !ids.isEmpty { args["p_last_top"] = ids }
        return args
    }
}
