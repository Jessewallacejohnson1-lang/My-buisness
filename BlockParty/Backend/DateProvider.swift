//
//  DateProvider.swift
//  Block Party — the injectable clock.
//
//  A view model that calls `Date()` cannot be tested: "does Your Day drop the
//  event that ended two hours ago" is only answerable if the test gets to say
//  what time it is. So every Today-tab read of *now* goes through this protocol
//  and the wall clock enters the app in exactly one place, `SystemDateProvider`.
//
//  This is the INSTANT only. Which calendar day that instant falls on is a
//  separate question, and for anything town-fixed the answer comes from
//  `Town.calendar` — see `Town.day(_:)`.
//
//  nonisolated: the module defaults to MainActor isolation, and a clock has to be
//  readable from the pure `nonisolated` date math and usable as a default
//  argument — see the CLAUDE.md MainActor-default-arg gotcha.
//

import Foundation

nonisolated protocol DateProviding: Sendable {
    var now: Date { get }
}

/// Production: the device clock, and the only place the app reads it.
nonisolated struct SystemDateProvider: DateProviding {
    init() {}
    var now: Date { Date() }
}

/// A clock pinned to one instant, for tests and DEBUG previews. Nothing in the
/// shipping path constructs one.
nonisolated struct FixedDateProvider: DateProviding {
    let now: Date

    init(_ now: Date) { self.now = now }
}
