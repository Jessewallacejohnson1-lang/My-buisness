import Foundation

struct FeedCardSection: Identifiable {
    let kind: FeedSectionKind
    let items: [FeedCardItem]

    var id: FeedSectionKind { kind }
}

extension FeedCardItem {
    init(
        from posting: FeedPosting,
        recurrence: String?,
        goingPreview: GoingPreview? = nil
    ) {
        let time = Self.nonempty(posting.startTime)
        let location = Self.nonempty(posting.location)
        let metadata = [time, location].compactMap { $0 }.joined(separator: " · ")

        self.init(
            id: posting.id,
            title: posting.title,
            dateChip: Self.dateChip(from: posting.eventDate),
            metaLine: metadata,
            image: Self.imageSource(imageUrl: posting.imageUrl, title: posting.title, place: nil),
            recurrence: recurrence,
            hostName: posting.posterName,
            hostAvatar: Self.nonempty(posting.posterAvatar).flatMap(URL.init(string:)),
            goingCount: posting.goingCount,
            goingAvatars: Array(goingPreview?.avatars.prefix(3) ?? []),
            likeCount: posting.likeCount,
            isLiked: posting.liked,
            isSaved: false,
            isJoined: posting.rsvpd,
            eventDate: posting.eventDate,
            startTime: time,
            location: location
        )
    }

    /// A Your Day event as a card item, so Town and Your Day open the one event
    /// page. Same image cascade as a posting (`imageSource`), so an event without
    /// its own photo still falls back to a venue lookup. No description:
    /// `UpcomingEvent` carries none, so the page's About hides. `.other` is the
    /// fallback for a null category column, so it maps to no category at all.
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
            goingCount: event.goingCount,
            goingAvatars: [],
            likeCount: 0,
            isLiked: false,
            isSaved: event.saved,
            isJoined: event.rsvpd,
            eventDate: event.eventDate,
            startTime: time,
            location: location,
            category: event.category == .other ? nil : event.category,
            cancelled: event.cancelled,
            place: place
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

extension FeedPostingSection {
    func mapped(
        goingPreviews: [String: GoingPreview] = [:],
        savedIDs: Set<String> = []
    ) -> FeedCardSection {
        FeedCardSection(
            kind: kind,
            items: postings.map { value in
                var item = FeedCardItem(
                    from: value.posting,
                    recurrence: value.recurrence,
                    goingPreview: goingPreviews[value.posting.id]
                )
                item.isSaved = savedIDs.contains(item.id)
                return item
            }
        )
    }
}
