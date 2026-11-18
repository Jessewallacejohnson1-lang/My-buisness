//
//  TownTop.swift
//  Block Party — the Town feed's top five (BP app town-feed 73).
//
//  An open after an hour or more away rolls a new top: `get_town_feed` starts the feed with five
//  big real happenings drawn by this roll, the same five for every read until the next roll. The
//  roll's first card is kept, so the next roll never leads with it again. Kept on the phone, so a
//  relaunch inside the hour keeps the same five.
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
    /// The last roll's first card, which this roll never leads with.
    private var previous: String? { keep.string(forKey: "townTop.previous") }
    /// This roll's first card, once its first read has landed.
    private var first: String? { keep.string(forKey: "townTop.first") }
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

    /// A read landed under this roll: its first card, kept once.
    func landed(first id: String?) {
        guard first == nil, let id else { return }
        keep.set(id, forKey: "townTop.first")
    }

    /// What `get_town_feed` takes: the roll, and the last roll's first card when it is the database's.
    var args: [String: Any] {
        var args: [String: Any] = [:]
        if let seed { args["p_top_seed"] = seed }
        if let previous, UUID(uuidString: previous) != nil { args["p_last_top"] = previous }
        return args
    }
}
