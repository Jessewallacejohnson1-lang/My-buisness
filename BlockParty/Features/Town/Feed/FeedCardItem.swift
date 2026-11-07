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
    /// A place host's picture (`UpcomingEvent.hostPicture`): its logo goes on a white disc.
    var hostPicture: PlacePicture? = nil
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
    /// What you follow that it's of ("Cathedral Volleyball (girls)", "White Peony Boutique"), from the
    /// Town feed's follow reason (BP app school-activities 03, town-feed 37): what Daily's Following
    /// reads. nil otherwise.
    var followed: String? = nil
    /// Called off (`UpcomingEvent.cancelled`): the card and its page show a red Canceled pill
    /// and a black-and-white photo (Jesse, 2026-10-17), and the You tab leaves it out.
    var cancelled = false
    /// The picture of where it happens (`PlacePicture`): the card's picture when the event
    /// has no photo of its own, and the event page's second one when it has.
    var place: FeedCardImageSource? = nil
    /// The place's other photos after `place` (event-card 02).
    var placeMore: [FeedCardImageSource] = []
    /// `image` is its place's cover, not a photo of the Event: its Town card is the white card and
    /// its Event of the day is passed over; its page and every other screen still show the cover
    /// (Jesse, 2026-11-04, BP app town-feed 40).
    var coverOnly = false
    /// `image` is a flyer: the Event page and the Block Party tab's cards show it whole, over a blurred copy
    /// of itself (Jesse, 2026-11-05, BP app event-photos 16).
    var whole = false
    /// The approved group putting it on, as the Town feed names it, and whether the read said
    /// you're in it: a card shows Join beside the group's name when you aren't (rsvp-and-groups 07).
    var groupID: String? = nil
    var inGroup = false
    /// A game between two teams (game-card 01): the card draws the teams, not a photo.
    var game: Game? = nil
    /// What it is in one to three words ("Lecture"), the morning tagger's (event-card 05).
    var what: String? = nil
    /// A real happening rather than a place being open (`private.is_live_kind`, town-feed 41).
    var liveKind = true
    /// When it was added (`club_events.created_at`): the hello drop counts what's new since your
    /// last open (BP app hello-drop 01). nil on cards not read from the database.
    var createdAt: Date? = nil
    /// Read from the town's own pages, not posted by a neighbour: Report offers Wrong info on it
    /// (town-feed 22).
    var found = false
    /// The page it was found on, opened from the link under the Event page's About.
    var sourceURL: URL? = nil

    /// The words as a card shows them, beside the title: none on a game, whose title is already its
    /// sport, and none when the title already has every one of them ("Christmas Craft Sale", "Craft
    /// sale"; "City Council — regular meeting", "Council meeting"; "Group Birth Classes", "Birth class").
    var whatLine: String? {
        guard game == nil, let what else { return nil }
        return Self.stems(what).isSubset(of: Self.stems(title)) ? nil : what
    }

    /// A text's words, a plural counting as its singular and a possessive as its name.
    static func stems(_ text: String) -> Set<String> {
        let words = text.lowercased().replacing("’s", with: "").replacing("'s", with: "")
            .split { !$0.isLetter && !$0.isNumber }
        return Set(words.map { word in
            guard word.count > 3 else { return String(word) }
            if word.hasSuffix("sses") { return String(word.dropLast(2)) }
            return String(word.hasSuffix("s") && !word.hasSuffix("ss") ? word.dropLast() : word)
        })
    }

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

    /// On right now, so the card's chip says Now: from its start to its end, two hours when it gives
    /// no end (as the map's pins), and only a real happening (Jesse, 2026-11-05: the talk at the gallery
    /// could be live, the gallery shouldn't last 5 days). In the town's time, as its end is: a phone set
    /// to Pacific still sees a 10 AM class turn Now at 10 in St. Joseph.
    func isNow(at now: Date = .now) -> Bool {
        // A game whose final is in is over, whatever its hours say (game-card 02).
        guard !cancelled, game?.final == nil, liveKind else { return false }
        return when?.isOn(now) ?? false
    }

    /// When it starts and ends. A game runs three hours, as the Town feed keeps it (Jesse at
    /// game-card 02's Check-in 2).
    var when: EventWhen? {
        EventWhen(date: eventDate, time: startTime, endAt: endAt, allDay: allDay, game: game != nil)
    }

    /// On by the clock, but a place being open rather than a real happening.
    func isOpen(at now: Date) -> Bool {
        !liveKind && !cancelled && when?.isOn(now) == true
    }

    /// The when line at `now`. A place open rather than a happening on says how long it's open, or its
    /// start reads as over: "Until 9 PM", "Until Sat", "Until Dec 14" (town-feed 41).
    func whenLine(at now: Date) -> FeedWhenLine? {
        guard isOpen(at: now), let when else { return whenLine }
        let last = when.end.addingTimeInterval(-60)  // a run's end at midnight is the day before
        let until = switch Town.days(from: now, to: last) {
        case 0: Town.clock(when.end)
        case 1..<7: Town.format(last, "EEE")
        default: Town.format(last, "MMMd")
        }
        return FeedWhenLine(text: "Until \(until)", spoken: "Open until \(until)")
    }

    /// The where line under the when line: just the venue, because the when line
    /// owns the time now. A mapped posting with a time but no venue has nothing
    /// here. Without that check `shareLocation` would hand back the whole meta line,
    /// which is only the time.
    var whereLine: String? {
        if let location { return location }
        return startTime == nil ? shareLocation : nil
    }

    /// The place's photos: its Event page shows the first that loads when the event has none of its own.
    var venue: [FeedCardImageSource] {
        (place.map { [$0] } ?? []) + placeMore
    }

    /// Its page's one picture: the event's own, else the place's, skipping ones that `failed` to load.
    func photos(failed: Set<URL> = []) -> [FeedCardImageSource] {
        EventPage.photoList(event: image, venue: venue, failed: failed)
    }
}

/// When an event is, as the card prints it ("Tonight · 7 PM", "Fri, Jul 24 · 11 AM")
/// and as VoiceOver reads it ("Friday, July 24 at 11 AM").
struct FeedWhenLine: Equatable {
    let text: String
    let spoken: String

    init(text: String, spoken: String) {
        self.text = text
        self.spoken = spoken
    }

    /// `eventDate` is `yyyy-MM-dd`. `startTime` is the free-text display time that
    /// `EventWhen` reads. A time it can't read is shown as written rather
    /// than dropped. `fallbackDate` is the old uppercase chip, used only when the item
    /// has no `eventDate` (fixtures). nil when there is neither a date nor a time. `relative`
    /// false always writes the date, never "Today" or "Tomorrow", for a card whose pill already
    /// says how far off it is (You's next plan, ticket 11). In the Town's time.
    init?(
        eventDate: String?,
        startTime: String?,
        fallbackDate: String = "",
        now: Date = .now,
        relative: Bool = true
    ) {
        let rawTime = startTime?.trimmingCharacters(in: .whitespacesAndNewlines)
        let timeRaw = (rawTime?.isEmpty ?? true) ? nil : rawTime
        let minutes = EventWhen.minutes(timeRaw)
        let timeText = minutes.map { Town.clock(minutes: $0) } ?? timeRaw

        var dayText: String?
        var daySpoken: String?
        if let when = EventWhen(date: eventDate, time: timeRaw, endAt: nil) {
            if relative, let word = when.dayWord(now) {
                dayText = word
            } else {
                let withYear = abs(Town.days(from: now, to: when.start)) > 183
                dayText = Town.format(when.start, withYear ? "EEEMMMdyyyy" : "EEEMMMd")
                daySpoken = Town.format(when.start, withYear ? "EEEEMMMMdyyyy" : "EEEEMMMMd")
            }
        } else if !fallbackDate.isEmpty {
            dayText = fallbackDate.capitalized
        }
        daySpoken = daySpoken ?? dayText

        guard dayText != nil || timeText != nil else { return nil }
        text = [dayText, timeText].compactMap { $0 }.joined(separator: " · ")
        switch (daySpoken, timeText) {
        case let (day?, time?):
            spoken = minutes != nil ? "\(day) at \(time)" : "\(day), \(time)"
        case let (day?, nil):
            spoken = day
        default:
            spoken = timeText ?? ""
        }
    }
}

struct FeedCardActionState: Equatable {
    private(set) var likeCount: Int
    private(set) var isLiked: Bool
    private(set) var isSaved: Bool

    /// The stored properties are `private(set)`, so there is no synthesised memberwise
    /// init to lean on.
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
