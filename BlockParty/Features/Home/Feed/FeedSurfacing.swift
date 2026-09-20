//
//  FeedSurfacing.swift
//  Block Party — what the Town feed is allowed to show today.
//
//  Town is one-time news, not a standing calendar. Without this filter a thing
//  announced two months out occupies the feed for two months, and a weekly club
//  occupies it forever.
//

import Foundation

/// How many days ahead of an event Town picks it back up. Seven, so the card
/// lands in the week a neighbour is actually planning.
private let townPreviewWindowDays = 7

/// Trims the deduped feed to the postings Town should carry today.
///
/// A one-time posting earns two appearances: the day it was posted (it is news),
/// and the week running up to the event, through the event day itself. Between
/// those it goes quiet. After the event it is gone.
///
/// A recurring series earns the debut only. Yoga every Saturday is news once;
/// after that it is the calendar's job, not the feed's — otherwise the same club
/// is on the feed every week for as long as it runs.
///
/// Stateless on purpose: this is date arithmetic over what the feed already
/// fetched, so it needs no per-neighbour seen-state and behaves the same on a
/// second device. The cost is that "once the week of" means the card is there
/// for that week, not for one single day of it.
func townSurfacing(_ items: [FeedRecurringPosting]) -> [FeedRecurringPosting] {
    townSurfacing(items, today: DateHelpers.localDate())
}

func townSurfacing(
    _ items: [FeedRecurringPosting],
    today: String
) -> [FeedRecurringPosting] {
    items.filter { isTownEligible($0, today: today) }
}

private func isTownEligible(_ item: FeedRecurringPosting, today: String) -> Bool {
    if DateHelpers.localDate(item.debut) == today { return true }

    // A series never comes back after its debut, so the run-up window is for
    // one-time postings only. An undated posting has no run-up to be in.
    guard item.recurrence == nil,
          let eventDate = item.posting.eventDate,
          let daysAway = DateHelpers.daysBetween(today, eventDate)
    else { return false }

    return (0...townPreviewWindowDays).contains(daysAway)
}
