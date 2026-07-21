import Foundation

typealias FeedRecurringPosting = (posting: FeedPosting, recurrence: String?)

/// Collapses title-matched recurring postings to the nearest upcoming event.
/// Groups without a recognized, consistent cadence remain individual postings.
func dedupeRecurring(_ postings: [FeedPosting]) -> [FeedRecurringPosting] {
    dedupeRecurring(postings, today: DateHelpers.localDate())
}

func dedupeRecurring(
    _ postings: [FeedPosting],
    today: String
) -> [FeedRecurringPosting] {
    var groupOrder: [String] = []
    var groups: [String: [(index: Int, posting: FeedPosting)]] = [:]

    for (index, posting) in postings.enumerated() {
        let key = posting.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if groups[key] == nil { groupOrder.append(key) }
        groups[key, default: []].append((index, posting))
    }

    return groupOrder.flatMap { key -> [FeedRecurringPosting] in
        guard let group = groups[key] else { return [] }
        let sorted = group.sorted(by: eventOrder)
        guard let recurrence = recurrenceLabel(for: sorted.map(\.posting)) else {
            return sorted.map { ($0.posting, nil) }
        }

        let nearest = sorted.first { entry in
            guard let date = entry.posting.eventDate,
                  let offset = DateHelpers.daysBetween(today, date)
            else { return false }
            return offset >= 0
        } ?? sorted[0]
        return [(nearest.posting, recurrence)]
    }
}

private func recurrenceLabel(for postings: [FeedPosting]) -> String? {
    guard postings.count >= 2 else { return nil }
    let dates = postings.compactMap(\.eventDate)
    guard dates.count == postings.count else { return nil }

    let gaps = zip(dates, dates.dropFirst()).compactMap(DateHelpers.daysBetween)
    guard gaps.count == dates.count - 1,
          let cadence = gaps.first,
          gaps.allSatisfy({ $0 == cadence })
    else { return nil }

    switch cadence {
    case 1:
        return "DAILY"
    case 7:
        let weekday = DateHelpers.weekdayLabel(dates[0]).uppercased()
        return weekday.isEmpty ? nil : "WEEKLY · \(weekday)"
    case 14:
        let weekday = DateHelpers.weekdayLabel(dates[0]).uppercased()
        return weekday.isEmpty ? nil : "EVERY OTHER \(weekday)"
    default:
        return nil
    }
}

private func eventOrder(
    _ lhs: (index: Int, posting: FeedPosting),
    _ rhs: (index: Int, posting: FeedPosting)
) -> Bool {
    switch (lhs.posting.eventDate, rhs.posting.eventDate) {
    case let (left?, right?) where left != right:
        return left < right
    case (_?, nil):
        return true
    case (nil, _?):
        return false
    default:
        return lhs.index < rhs.index
    }
}
