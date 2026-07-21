import Foundation

enum FeedSectionKind: String, CaseIterable, Identifiable {
    case today
    case thisWeek
    case later

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "TODAY"
        case .thisWeek: "THIS WEEK"
        case .later: "LATER"
        }
    }
}

struct FeedPostingSection: Identifiable {
    let kind: FeedSectionKind
    let postings: [FeedRecurringPosting]

    var id: FeedSectionKind { kind }
}

enum FeedSectioning {
    static func sections(
        for postings: [FeedRecurringPosting],
        today: String = DateHelpers.localDate()
    ) -> [FeedPostingSection] {
        guard let todayDate = localDate(from: today) else { return [] }

        let classified = postings.enumerated().map { index, item in
            let date = item.posting.eventDate.flatMap(localDate)
            let offset = date.map {
                localCalendar.dateComponents(
                    [.day],
                    from: localCalendar.startOfDay(for: todayDate),
                    to: localCalendar.startOfDay(for: $0)
                ).day ?? 0
            }

            let kind: FeedSectionKind
            switch offset {
            case 0?: kind = .today
            case let value? where (1...7).contains(value): kind = .thisWeek
            default: kind = .later
            }

            return ClassifiedPosting(
                item: item,
                date: date,
                minutes: DateHelpers.minutesOf(item.posting.startTime),
                originalIndex: index,
                kind: kind
            )
        }

        return FeedSectionKind.allCases.compactMap { kind in
            let items = classified
                .filter { $0.kind == kind }
                .sorted(by: postingOrder)
                .map { $0.item }
            return items.isEmpty ? nil : FeedPostingSection(kind: kind, postings: items)
        }
    }

    private struct ClassifiedPosting {
        let item: FeedRecurringPosting
        let date: Date?
        let minutes: Int
        let originalIndex: Int
        let kind: FeedSectionKind
    }

    private nonisolated static var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private nonisolated static func localDate(from value: String) -> Date? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { return nil }

        let components = DateComponents(year: year, month: month, day: day)
        guard let date = localCalendar.date(from: components) else { return nil }
        let normalized = localCalendar.dateComponents([.year, .month, .day], from: date)
        guard normalized.year == year,
              normalized.month == month,
              normalized.day == day
        else { return nil }
        return date
    }

    private nonisolated static func postingOrder(_ lhs: ClassifiedPosting, _ rhs: ClassifiedPosting) -> Bool {
        switch (lhs.date, rhs.date) {
        case let (left?, right?) where left != right:
            return left < right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            if lhs.minutes != rhs.minutes { return lhs.minutes < rhs.minutes }
            return lhs.originalIndex < rhs.originalIndex
        }
    }
}
