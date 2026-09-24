//
//  FeedCardItem.swift
//  Block Party — normalized, data-layer-independent input for a feed card.
//

import Foundation

struct FeedCardItem: Identifiable, Hashable {
    let id: String
    let title: String
    let dateChip: String
    let metaLine: String
    let image: FeedCardImageSource
    let recurrence: String?
    /// Who is putting the event on — a business, a parish, a neighbour. The card's
    /// attribution line, sitting where a publisher's wordmark sits on an Apple News
    /// card. Empty means the source is unknown and the line is simply not drawn.
    var hostName: String = ""
    var hostAvatar: URL? = nil
    let goingCount: Int
    let goingAvatars: [URL]
    let goingSummary: String
    var likeCount: Int
    var isLiked: Bool
    var isSaved: Bool
    var isJoined: Bool
    var eventDate: String? = nil
    var startTime: String? = nil
    var location: String? = nil

    var shareTime: String? {
        if let startTime { return startTime }
        let parts = metaLine.components(separatedBy: " · ")
        guard parts.count > 1 else { return nil }
        let time = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        return time.isEmpty ? nil : time
    }

    var shareLocation: String? {
        if let location { return location }
        let parts = metaLine.components(separatedBy: " · ")
        let location = (parts.count > 1 ? parts.dropFirst().joined(separator: " · ") : metaLine)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return location.isEmpty ? nil : location
    }

    /// The when line under the headline: date and start time.
    var whenLine: FeedWhenLine? {
        FeedWhenLine(eventDate: eventDate, startTime: shareTime, fallbackDate: dateChip)
    }

    /// The where line under the when line: just the venue, because the when line
    /// owns the time now. A mapped posting with a time but no venue has nothing
    /// here. Without that check `shareLocation` would hand back the whole meta line,
    /// which is only the time.
    var whereLine: String? {
        if let location { return location }
        return startTime == nil ? shareLocation : nil
    }
}

/// When an event is, as the card prints it ("Tonight · 7 PM", "Fri, Jul 24 · 11 AM")
/// and as VoiceOver reads it ("Friday, July 24 at 11 AM").
struct FeedWhenLine: Equatable {
    let text: String
    let spoken: String

    /// `eventDate` is `yyyy-MM-dd`. `startTime` is the free-text display time that
    /// `DateHelpers.minutesOf` reads. A time it can't read is shown as written rather
    /// than dropped. `fallbackDate` is the old uppercase chip, used only when the item
    /// has no `eventDate` (fixtures). nil when there is neither a date nor a time.
    init?(
        eventDate: String?,
        startTime: String?,
        fallbackDate: String = "",
        now: Date = .now,
        calendar: Calendar = Self.localCalendar
    ) {
        let rawTime = startTime?.trimmingCharacters(in: .whitespacesAndNewlines)
        let timeRaw = (rawTime?.isEmpty ?? true) ? nil : rawTime
        let minutes = timeRaw.map { DateHelpers.minutesOf($0) }
        let parsedMinutes = minutes.flatMap { $0 < 24 * 60 ? $0 : nil }
        let timeText = parsedMinutes.map { Self.clock($0) } ?? timeRaw

        var dayText: String?
        var daySpoken: String?
        if let date = Self.day(from: eventDate, calendar: calendar) {
            let offset = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: now), to: date
            ).day ?? 0
            switch offset {
            case 0 where (parsedMinutes ?? 0) >= 17 * 60:
                dayText = "Tonight"
            case 0:
                dayText = "Today"
            case 1:
                dayText = "Tomorrow"
            default:
                let withYear = abs(offset) > 183
                dayText = Self.format(date, withYear ? "EEE, MMM d, yyyy" : "EEE, MMM d", calendar)
                daySpoken = Self.format(date, withYear ? "EEEE, MMMM d, yyyy" : "EEEE, MMMM d", calendar)
            }
        } else if !fallbackDate.isEmpty {
            dayText = fallbackDate.capitalized
        }
        daySpoken = daySpoken ?? dayText

        guard dayText != nil || timeText != nil else { return nil }
        text = [dayText, timeText].compactMap { $0 }.joined(separator: " · ")
        switch (daySpoken, timeText) {
        case let (day?, time?):
            spoken = parsedMinutes != nil ? "\(day) at \(time)" : "\(day), \(time)"
        case let (day?, nil):
            spoken = day
        default:
            spoken = timeText ?? ""
        }
    }

    static var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// "7 PM", "7:30 PM", "Noon", "Midnight".
    private static func clock(_ minutes: Int) -> String {
        switch minutes {
        case 0: return "Midnight"
        case 12 * 60: return "Noon"
        default:
            let hour = minutes / 60, minute = minutes % 60
            let hour12 = hour % 12 == 0 ? 12 : hour % 12
            let meridiem = hour < 12 ? "AM" : "PM"
            return minute == 0
                ? "\(hour12) \(meridiem)"
                : String(format: "%d:%02d %@", hour12, minute, meridiem)
        }
    }

    private static func day(from value: String?, calendar: Calendar) -> Date? {
        guard let parts = value?.split(separator: "-"), parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private static func format(_ date: Date, _ pattern: String, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

struct FeedCardActionState: Equatable {
    private(set) var likeCount: Int
    private(set) var isLiked: Bool
    private(set) var isSaved: Bool

    init(item: FeedCardItem) {
        likeCount = item.likeCount
        isLiked = item.isLiked
        isSaved = item.isSaved
    }

    /// The counts on their own, for cards that are not built from a `FeedCardItem`
    /// (the Daily feed's postings). The stored properties are `private(set)`, so
    /// there is no synthesised memberwise init to lean on.
    init(likeCount: Int, isLiked: Bool, isSaved: Bool) {
        self.likeCount = likeCount
        self.isLiked = isLiked
        self.isSaved = isSaved
    }

    @discardableResult
    mutating func toggleLike() -> Bool {
        isLiked.toggle()
        likeCount = max(0, likeCount + (isLiked ? 1 : -1))
        return isLiked
    }

    /// Like-only path for the image's double-tap. Returns whether state changed.
    @discardableResult
    mutating func like() -> Bool {
        guard !isLiked else { return false }
        isLiked = true
        likeCount += 1
        return true
    }

    @discardableResult
    mutating func toggleSave() -> Bool {
        isSaved.toggle()
        return isSaved
    }

    mutating func sync(with item: FeedCardItem) {
        likeCount = item.likeCount
        isLiked = item.isLiked
        isSaved = item.isSaved
    }
}

/// What sits behind a feed card's title.
///
/// `venueLookup` is an INTENT, not an image: no first-party photo exists, but the
/// posting names a place we can ask Google Places about. It stays unresolved here
/// because `FeedCardItem`'s init is synchronous and a Places lookup is async AND
/// billed — resolving during the feed load would spend a call on every card,
/// including the ones nobody scrolls to. The card resolves it lazily when it
/// appears (`FeedEventCard.resolveVenuePhoto`), landing on `.placesPhoto`; until
/// then — and forever if the venue can't be confidently identified — the card
/// renders the `fallback` treatment.
enum FeedCardImageSource: Hashable {
    case eventPhoto(URL)
    case placesPhoto(URL, attribution: String)
    case venueLookup(name: String, hint: String?)
    case fallback
}
