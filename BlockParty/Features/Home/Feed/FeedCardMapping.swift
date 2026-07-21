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
            image: Self.imageSource(from: posting.imageUrl),
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

    private static func imageSource(from value: String?) -> FeedCardImageSource {
        if let raw = nonempty(value), let url = URL(string: raw) {
            return .eventPhoto(url)
        }
        // Phase 5: optional curated Places photo
        return .fallback
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
