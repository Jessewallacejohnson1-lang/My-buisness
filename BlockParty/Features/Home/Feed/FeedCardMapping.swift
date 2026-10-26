import Foundation

extension FeedCardItem {
    /// A Your Day event as a card item, so Town and Your Day open the one event
    /// page. Same image cascade as a posting (`imageSource`), so an event without
    /// its own photo still falls back to a venue lookup. Its description is the page's
    /// About. `.other` is the fallback for a null category column, so it maps to no
    /// category at all.
    /// `recurrence` is how its series repeats ("Every Tuesday"), from `get_town_feed`.
    init(_ event: UpcomingEvent, recurrence: String? = nil) {
        let time = Self.nonempty(event.startTime)
        let location = Self.nonempty(event.location)
        let place = event.placePicture.map(FeedCardImageSource.init)

        self.init(
            id: event.id,
            title: event.title,
            dateChip: Self.dateChip(from: event.eventDate),
            metaLine: [time, location].compactMap { $0 }.joined(separator: " · "),
            image: Self.imageSource(imageUrl: event.imageUrl, title: event.title, place: place),
            recurrence: recurrence,
            hostName: Self.nonempty(event.clubName) ?? Self.nonempty(event.sourceName) ?? "",
            hostPicture: event.hostPicture,
            goingCount: event.goingCount,
            goingAvatars: [],
            likeCount: 0,
            isLiked: false,
            isSaved: event.saved,
            isJoined: event.rsvpd,
            eventDate: event.eventDate,
            startTime: time,
            endAt: event.endAt,
            allDay: event.isAllDay,
            location: location,
            description: event.description,
            category: event.category == .other ? nil : event.category,
            cancelled: event.cancelled,
            place: place,
            placeMore: event.placePicture?.more.map(FeedCardImageSource.init) ?? [],
            game: event.game,
            what: Self.nonempty(event.what),
            createdAt: DateHelpers.timestamp(event.createdAt),
            found: Self.nonempty(event.sourceName) != nil
        )
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    private static func dateChip(from value: String?) -> String {
        guard let value else { return "" }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { return "" }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
        else { return "" }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "EEE MMM d"
        return formatter.string(from: date).uppercased()
    }

    /// An organizer's own photo, then a bundled, human-verified `KnownLocalPhoto` for its
    /// title, then the place's saved photo or logo (`place`), then flat ink. Nothing here
    /// asks Google: venue photos come from our own store (MEMORY.md, 2026-10-16).
    ///
    /// The bundled tier stays because it is exactly the set of human-vetted photos for
    /// events by name (Millstream Arts Festival), and bundled photos carry no credit, so
    /// they ride `.eventPhoto` like an organizer's photo.
    private static func imageSource(
        imageUrl: String?,
        title: String,
        place: FeedCardImageSource?
    ) -> FeedCardImageSource {
        if let raw = nonempty(imageUrl), let url = URL(string: raw) {
            return .eventPhoto(url)
        }

        if let title = nonempty(title),
           let slug = KnownLocalPhoto.name(forTitle: title),
           let url = Bundle.main.url(forResource: slug, withExtension: "jpg") {
            return .eventPhoto(url)
        }

        return place ?? .fallback
    }

}
