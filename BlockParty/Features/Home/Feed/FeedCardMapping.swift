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
            image: Self.imageSource(
                imageUrl: posting.imageUrl,
                location: location,
                title: posting.title
            ),
            recurrence: recurrence,
            goingCount: posting.goingCount,
            goingAvatars: Array(goingPreview?.avatars.prefix(3) ?? []),
            goingSummary: Self.goingSummary(
                for: posting.goingCount,
                names: goingPreview?.names ?? []
            ),
            likeCount: posting.likeCount,
            isLiked: posting.liked,
            isSaved: false,
            isJoined: posting.rsvpd,
            eventDate: posting.eventDate,
            startTime: time,
            location: location
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

    /// The same three-tier cascade Activities uses (`ActivityImage.has(event:)`):
    /// an organizer's own photo → a bundled, human-verified `KnownLocalPhoto` →
    /// the *intent* to look the venue up live (resolving here would be an async,
    /// billed Google call per posting on every feed load — see `FeedCardImageSource`).
    ///
    /// The bundled tier matters: `bestScenicPhoto` is geometry-only and can surface a
    /// poor Google match (a highway sign for the "Downtown St. Joseph" locality behind
    /// Millstream Arts Festival). `KnownLocalPhoto` is exactly the set of human-vetted
    /// overrides for that, and the feed used to skip it, so those cards went to Places
    /// and could look bad. Bundled photos carry no Google attribution, so they ride
    /// `.eventPhoto` like an organizer's photo.
    ///
    /// Which string is the venue: an event's title says what is happening, not where,
    /// so the venue name is its `location` when it has one and the title is only a hint
    /// for the KnownVenues lookup. A posting with neither is the genuinely-nothing case.
    private static func imageSource(
        imageUrl: String?,
        location: String?,
        title: String
    ) -> FeedCardImageSource {
        if let raw = nonempty(imageUrl), let url = URL(string: raw) {
            return .eventPhoto(url)
        }

        let title = nonempty(title)

        if let title,
           let slug = KnownLocalPhoto.name(forTitle: title),
           let url = Bundle.main.url(forResource: slug, withExtension: "jpg") {
            return .eventPhoto(url)
        }

        guard let venue = location ?? title else { return .fallback }
        return .venueLookup(name: venue, hint: location != nil ? title : nil)
    }

    private static func goingSummary(for count: Int, names: [String]) -> String {
        guard count > 0 else { return "Nobody's going yet — be first." }
        guard let name = names.first?.split(whereSeparator: \.isWhitespace).first.map(String.init)
        else { return "\(count) going" }

        return switch count {
        case 1: "\(name) is going"
        case 2: "\(name) and 1 other are going"
        default: "\(name) and \(count - 1) others are going"
        }
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
