//
//  LeftOff.swift
//  Block Party — where you were when the app left the screen, so a restart doesn't show.
//
//  iOS shuts apps down to make room, often within a minute or two of leaving (BP app backlog 21:
//  32 of 35 opens on Jesse's phone in a day were full restarts). Back inside `TownFeed.awayLimit`,
//  the app opens as you left it: no launch, the same tab, the same Event page, the same feed.
//
//  Kept on the phone rather than in `@SceneStorage`: a value written on going to the background
//  didn't come back after a kill (measured, 2026-11-06). The scene's id tells the two ways an app
//  dies apart: iOS shutting it down keeps the scene; swiping it away ends it, so that's a true
//  fresh start.
//

import SwiftUI

struct LeftOff: Codable, Equatable {
    var at: Date
    /// The scene it left.
    var scene: String
    /// `Tab`'s raw value.
    var tab: Int
    /// The Event page on top, and how far down it was. A card can't be kept whole, so it comes
    /// back only if the feed still has it; else you land on the tab.
    var event: String?
    var eventY: CGFloat
    /// The Town feed's cards as they were on screen, in order.
    var feed: [String]
    /// The card at the top of the screen, and how far down the feed was.
    var top: String?
    var feedY: CGFloat
    /// The Event of the day poster on top of the feed, if any.
    var poster: String?

    /// Whether a launch at `now`, with these scenes still open, comes back to this.
    func usable(now: Date, scenes: Set<String>) -> Bool {
        scenes.contains(scene) && now >= at && now.timeIntervalSince(at) < TownFeed.awayLimit
    }

    private static let key = "app.leftOff"

    /// What this launch comes back to, read once, before anything draws. It leaves the phone as
    /// it's read, so a page that crashes on the way back can't catch the app in a loop.
    static let current: LeftOff? = {
        if AuthStore.isTestRun { return nil }
        #if DEBUG
        // A screenshot run passes flags and expects a plain launch; `-left-off` is how a proof asks.
        if CommandLine.arguments.count > 1, !LaunchFlags.has(.leftOff) { return nil }
        #endif
        let phone = UserDefaults.standard
        let saved = phone.data(forKey: key).flatMap { try? JSONDecoder().decode(LeftOff.self, from: $0) }
        phone.removeObject(forKey: key)
        let scenes = Set(UIApplication.shared.openSessions.map(\.persistentIdentifier))
        return saved?.usable(now: Date(), scenes: scenes) == true ? saved : nil
    }()

    /// The shell's one claim on `current`: its init runs on every redraw above it.
    private static var unclaimed = current
    static func claim() -> LeftOff? {
        defer { unclaimed = nil }
        return unclaimed
    }

    /// The Event page reopening, once, so the same page opened later starts at its top.
    private static var pageToReopen = current?.event
    static func reopening(_ id: String) -> Bool {
        guard pageToReopen == id else { return false }
        pageToReopen = nil
        return true
    }

    /// The Event page on screen and how far down each one opened is, kept up by the page.
    static var page: String?
    static var pageY: [String: CGFloat] = [:]

    static func save(_ left: LeftOff, to phone: UserDefaults = .standard) {
        phone.set(try? JSONEncoder().encode(left), forKey: key)
    }

    static func clear(_ phone: UserDefaults = .standard) {
        phone.removeObject(forKey: key)
    }

    static func saved(in phone: UserDefaults) -> LeftOff? {
        phone.data(forKey: key).flatMap { try? JSONDecoder().decode(LeftOff.self, from: $0) }
    }
}
