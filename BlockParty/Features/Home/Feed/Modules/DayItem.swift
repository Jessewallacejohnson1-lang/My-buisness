//
//  DayItem.swift
//  Block Party — one line of the neighbour's day, and where it came from.
//
//  This is the published contract between the Your Day data layer and the rail
//  and day sheet that render it. Everything on it is already resolved against
//  TOWN time and the injected clock, so a view never has to do date math.
//

import Foundation

/// Which of Your Day's two lanes an item arrived on.
///
/// The rail must SHOW the difference. A town-wide event the neighbour never said
/// yes to is real news — with ~9 events in the whole town, anything on today's
/// calendar genuinely is the town's day — but it may not pass itself off as a
/// personal plan.
nonisolated enum DayItemSource: String, Hashable, CaseIterable {
    /// This user personally signed up (an `event_rsvps` row of theirs).
    /// **Committed wins every tie**: if they RSVP'd to a town-wide event it is
    /// theirs, and it appears exactly once.
    case committed
    /// On the town's calendar today, with no commitment from this user.
    case wholeTown
}

nonisolated struct DayItem: Identifiable, Hashable {
    /// The `club_events` row id — also the dedup key across the two lanes.
    let id: String
    let title: String
    let source: DayItemSource

    /// The instant it starts, in town time. All-day items start at town midnight;
    /// an item whose free-text time cannot be parsed ("after dark") is placed at
    /// the end of its day, matching `DateHelpers.minutesOf`'s long-standing rule.
    let start: Date
    /// The instant it ends, when the row actually says so. Nil is the norm until
    /// `club_events.end_at` ships, and stays legitimate after — the column is
    /// nullable. Never substitute a guess here; `isComplete` owns that judgement.
    let end: Date?

    let isAllDay: Bool
    /// True when the item's own span covers more than the single day it starts on
    /// — a festival still running through today.
    let isMultiDay: Bool
    /// Whether its end has passed, stamped from the injected clock when the item
    /// was built. See `YourDayLogic.completionInstant` for the no-`end_at` rule.
    let isComplete: Bool

    /// The small line above the title: a start time, `Today · ongoing`, or
    /// `Today · all day`. Never a placeholder, never "TBD".
    let eyebrow: String

    let location: String?
    let goingCount: Int

    /// The row this came from, so a tap opens the detail screen with the facts the
    /// card already had and nothing to re-fetch.
    let event: UpcomingEvent
}
