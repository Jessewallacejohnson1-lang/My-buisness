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
    /// Going as the read gave it. What a card and its page show is
    /// `RealLifeActions.going`, which lays the neighbour's own taps over this.
    let goingCount: Int
    let goingAvatars: [URL]
    /// The neighbour's friends Going, newest first, at most three (town-feed 28): their
    /// faces and names lead the going line on the card and the Event page.
    var friendsGoing: [FeedFriend] = []
    var likeCount: Int
    var isLiked: Bool
    var isSaved: Bool
    var isJoined: Bool
    var eventDate: String? = nil
    var startTime: String? = nil
    /// When it ends (`club_events.end_at`) and whether it's listed all day: what `isNow` reads.
    var endAt: Date? = nil
    var allDay = false
    var location: String? = nil
    /// The event page's About text and its grey category line. nil hides the row;
    /// nothing fills in for a missing value.
    var description: String? = nil
    var category: EventCategory? = nil
    /// Why the Town feed shows this card, in words (`FeedCardMenu.line`). nil leaves the
    /// card without its ••• menu: only the Town feed's own cards have a reason.
    var why: String? = nil
    /// The points behind the card's place; the database sends them to the admin only.
    var score: FeedScore? = nil
    /// Called off (`UpcomingEvent.cancelled`): the card and its page show a red Canceled pill
    /// and a black-and-white photo (Jesse, 2026-10-17), and the You tab leaves it out.
    var cancelled = false
    /// The picture of where it happens (`PlacePicture`): the card's picture when the event
    /// has no photo of its own, and the event page's second one when it has.
    var place: FeedCardImageSource? = nil
    /// The place's other photos after `place` (event-card 02).
    var placeMore: [FeedCardImageSource] = []
    /// The approved group putting it on, as the Town feed names it, and whether the read said
    /// you're in it: a card shows Join beside the group's name when you aren't (rsvp-and-groups 07).
    var groupID: String? = nil
    var inGroup = false
    /// A game between two teams (game-card 01): the card draws the teams, not a photo.
    var game: Game? = nil

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
        // A game whose final is in shows its day alone, "Sat, Oct 17" (game-card 02).
        FeedWhenLine(eventDate: eventDate, startTime: game?.final == nil ? shareTime : nil, fallbackDate: dateChip)
    }

    /// On right now, so the card's chip says Now (Jesse, 2026-10-20): from its start to its end,
    /// two hours when it gives no end (as the map's pins), and the whole of something that runs
    /// over days (the Johanna Kiln, Oct 16 to 25). A one-day all-day listing gives no hours, so
    /// it never is. In the town's time, as its end is: a phone set to Pacific still sees a 10 AM
    /// class turn Now at 10 in St. Joseph.
    func isNow(at now: Date = .now, calendar: Calendar = Town.calendar) -> Bool {
        // A game whose final is in is over, whatever its hours say (game-card 02).
        guard !cancelled, game?.final == nil,
              let day = FeedWhenLine.day(from: eventDate, calendar: calendar) else { return false }
        let minutes = startTime.map { DateHelpers.minutesOf($0) }.flatMap { $0 < 24 * 60 ? $0 : nil }
        guard !allDay, let minutes,
              let start = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)
        else {
            guard let endAt, let nextDay = calendar.date(byAdding: .day, value: 1, to: day), endAt > nextDay
            else { return false }
            return now >= day && now < endAt
        }
        // A game runs three hours, as the Town feed keeps it (Jesse at game-card 02's Check-in 2).
        let lasts = game == nil ? YourDayLogic.assumedEventDuration : 3 * 60 * 60
        return now >= start && now < (endAt ?? start.addingTimeInterval(lasts))
    }

    /// The where line under the when line: just the venue, because the when line
    /// owns the time now. A mapped posting with a time but no venue has nothing
    /// here. Without that check `shareLocation` would hand back the whole meta line,
    /// which is only the time.
    var whereLine: String? {
        if let location { return location }
        return startTime == nil ? shareLocation : nil
    }

    /// The place's photos, after the event's own: what the card swipes to and its Event page
    /// shows (event-card 02).
    var venue: [FeedCardImageSource] {
        #if DEBUG
        // UI tests only: a second bundled photo, so the card and its page have two to swipe
        // with no network (`EventCardPhotoTapTests`).
        if ProcessInfo.processInfo.arguments.contains("-event-page-two-photos"),
           let url = Bundle.main.url(forResource: "centennial-park", withExtension: "jpg") {
            return [.eventPhoto(url)]
        }
        #endif
        return (place.map { [$0] } ?? []) + placeMore
    }

    /// The card's and its page's photos: the event's own first, then the place's, each once,
    /// at most three; ones that `failed` to load left out.
    func photos(failed: Set<URL> = []) -> [FeedCardImageSource] {
        FeedEventDetailDestination.photoList(event: image, venue: venue, failed: failed)
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

    static func day(from value: String?, calendar: Calendar) -> Date? {
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
}

/// What sits behind a feed card's title: the event's own photo, else the photo or logo of
/// the place it happens at (`PlacePicture`, saved once by Block Party, so a card costs no
/// lookup), else flat ink.
enum FeedCardImageSource: Hashable {
    case eventPhoto(URL)
    /// A place's photo, the chip that credits it (a site, or an author and licence), and its
    /// shape (width over height) when the database knows it.
    case placePhoto(URL, credit: String?, aspect: Double? = nil)
    /// A place we have no photo of: its logo on its Search backdrop (Jesse, 2026-10-16),
    /// drawn as `logo`.
    case placeLogo(PlacePicture)
    case fallback

    nonisolated init(_ picture: PlacePicture) {
        switch picture.kind {
        case .photo: self = .placePhoto(picture.url, credit: picture.creditLine, aspect: picture.aspect)
        case .logo: self = .placeLogo(picture)
        }
    }
}
