//
//  DailyPage.swift
//  Block Party — the Daily tab: the neighbour's own page for today.
//
//  Top to bottom (`docs/plans/daily-tab/SPEC.md` in the BP app folder): the wordmark and the
//  Town's logo, the week, the topics (daily-tab 19, `DailyTop.swift`), Event of the
//  day as the Town tab's poster, then the Spotlight under its label, Suggestions and Following,
//  on plain paper (no yellow: Jesse, 2026-10-21). Tap a day in the week and the page turns to it
//  (daily-tab 16).
//  A section with nothing in it is left out; the Spotlight is today's alone. What you're Going
//  to lives on the You tab (BP app docs/plans/you-tab).
//

import SwiftUI

/// Today's Spotlight: one local person or business and their story, the same for
/// everyone in the Town and new each day.
struct DailySpotlight {
    var name: String
    /// What they do, or their business.
    var about: String
    var portrait: URL?
    /// More photos, for the story page; the card shows `portrait` alone.
    var photos: [URL]

    /// Today's story. There is no backend for it yet, so there is none, and Daily opens on
    /// Event of the day; DEBUG `-daily-samples` gets the sample. When the read exists, this is
    /// the one property that changes.
    static var today: DailySpotlight? {
        #if DEBUG
        return DailySamples.on ? .sample : nil
        #else
        return nil
        #endif
    }

    #if DEBUG
    /// INVENTED: a made-up neighbour and business, over the warm photos from Jesse's
    /// Reference (the old onboarding interest images). A real Spotlight's photo is the
    /// person; the sample has no real face to show.
    static let sample = DailySpotlight(
        name: "Marta Reyes",
        about: "Northside Coffee",
        portrait: asset("interest-coffee"),
        photos: [asset("interest-dining"), asset("interest-books")].compactMap { $0 }
    )

    /// The card loads photos by URL and these live in the asset catalog, so each is
    /// written out once to Caches.
    private static func asset(_ name: String) -> URL? {
        let url = URL.cachesDirectory.appending(path: "daily-sample-\(name).jpg")
        if !FileManager.default.fileExists(atPath: url.path()),
           let data = UIImage(named: name)?.jpegData(compressionQuality: 0.9) {
            try? data.write(to: url)
        }
        return FileManager.default.fileExists(atPath: url.path()) ? url : nil
    }
    #endif
}

/// The Spotlight card's sizes are MEASURED from Jesse's Reference, App Store's card with
/// its words over a blurred bottom (`references/spotlight-card/SPEC.md` in the BP app
/// folder, 2026-10-19); its corner stays `Radius.bento` (Jesse, 2026-09-30). The low sun
/// and the tilt are the depth page Jesse picked on 2026-10-01 (ideas "Low sun" and
/// "Tilt"); their values were picked there, in a browser mockup, not measured from
/// another app. Its CSS blurs are halved here: a SwiftUI shadow radius blurs about as
/// much as a CSS blur twice its size.
nonisolated enum DailyMetric {
    static let side: CGFloat = 18
    /// "Spotlight" in the logo's face, and from it to the card. Picked
    /// in the Check-in mock (BP app `references/spotlight-card/mock.html`).
    static let wordSize: CGFloat = 28
    static let wordTracking: CGFloat = -0.6
    static let wordToCard: CGFloat = 14
    /// The photo is the card, 4:5 (picked on the drafts board).
    static let cardAspect: CGFloat = 4.0 / 5.0
    /// The words sit 16 in from the card's left edge, and the business line's baseline
    /// 16 over its bottom edge, as App Store's do: Jost's descent is the other 5.
    static let wordsInset: CGFloat = 16
    static let wordsBottom: CGFloat = 11
    /// The bottom fade starts this far over the name, as App Store's starts over its
    /// label. The photo's blurred copy is solid by `fadeSolid` of the way down.
    static let fadeAboveWords: CGFloat = 24
    static let fadeSolid: CGFloat = 0.75
    /// GUESSED: a still can't show App Store's blur, only that the photo's detail is gone
    /// by the card's bottom edge.
    static let fadeBlur: CGFloat = 10
    /// Black at the card's bottom edge. App Store's darkens about 37%; our photos run
    /// brighter than its art, so 45 (picked).
    static let fadeShade: Double = 0.45
    /// Clears the floating tab bar: the same 96 the other tab scrollers reserve.
    static let tabBarClearance: CGFloat = 96

    /// The first section sits this far under the week's faces, or the topics under them. Picked on
    /// the Figma drafts (2026-10-21): no Reference has a week over a page like this one. Above the
    /// week, the wordmark and the Town's logo (`DailyTopMetric`, daily-tab 19).
    static let weekToSection: CGFloat = 24
    /// Another day's page: the last one fades out this fast, then the picked one fades in
    /// (guessed; no Reference recording).
    static let dayFadeOut: Double = 0.1
    static let dayFade: Double = 0.2
    /// The reserved slot's height under the week on a day with nothing in it.
    static let emptyHeight: CGFloat = 420
    /// The clock's frosted edge comes in over this much scroll, as the week slides under the
    /// clock. At rest and pulled down it is gone. Picked.
    static let edgeFade: CGFloat = 20

    /// The low sun's shadow. Sideways it reaches `sunReach` at sunrise and sunset and
    /// nothing at midday; down it drops `sunDrop` at midday and up to `sunDropLong` more
    /// at the ends of the day, and blurs the same way.
    static let sunReach: CGFloat = 46
    static let sunDrop: CGFloat = 12
    static let sunDropLong: CGFloat = 24
    static let sunBlur: CGFloat = 4
    static let sunBlurLong: CGFloat = 4
    static let sunOpacity: Double = 0.26
    /// Pressed, the card sinks toward the page, so its shadow pulls in this much.
    static let sunPressed: CGFloat = 0.7
    /// The Town hours the sun is up; outside them the shadow is the midday one, short
    /// and straight down, like a streetlight overhead (Jesse, 2026-10-01).
    static let sunrise: Double = 6
    static let sunset: Double = 21

    /// At a full lean: the card turns this many degrees and its shadow slides this far
    /// the other way.
    static let tiltLean: Double = 8
    /// The mockup's 900pt camera for a card about 360pt wide; SwiftUI's default of 1
    /// puts the camera a card's width away, which turned a full lean into a skew.
    static let tiltPerspective: CGFloat = 0.4
    static let tiltShadowX: CGFloat = 16
    static let tiltShadowY: CGFloat = 12

    /// Between the sections, and from a section's label to what it labels: MEASURED from
    /// Airbnb's trips page (the gap between one trip's card and the next city's heading,
    /// and from that heading to its card), Daily's first Reference.
    static let eventSectionTop: CGFloat = 38
    static let eventLabelToCard: CGFloat = 15
    /// Between Event of the day's posters on a busy day; the next one's edge shows by this
    /// much less than the page margin. Picked.
    static let eventGap: CGFloat = 10

    /// Following, MEASURED from Jesse's Reference: Instagram's activity rows
    /// (`references/daily-following/instagram-activity.jpg` in the BP app folder, an
    /// @3x 393pt screen): a 44pt round photo, 13pt to the words, a 44pt photo with 8pt
    /// corners on the right, rows 64pt apart. The rows start at `side` (18) where
    /// Instagram's start at 16, as the other Daily sections do.
    static let followingPhoto: CGFloat = 44
    static let followingPhotoRadius: CGFloat = 8
    static let followingGap: CGFloat = 13
    /// Above and below each row's 44pt photos, for Instagram's 64pt rows.
    static let followingRowInset: CGFloat = 10
    /// The label sits 15pt over the first photo, as over every Daily section's content.
    static let followingLabelToRows: CGFloat = eventLabelToCard - followingRowInset
}

/// The low sun over the page: morning light from the east throws the Spotlight's
/// shadow right, dinner light throws it left, and midday drops it straight down.
nonisolated enum DailySun {
    struct Shadow: Equatable {
        var x: CGFloat
        var y: CGFloat
        var blur: CGFloat
    }

    static func shadow(hour: Double) -> Shadow {
        let up = (DailyMetric.sunrise...DailyMetric.sunset).contains(hour)
        let day = (hour - DailyMetric.sunrise) / (DailyMetric.sunset - DailyMetric.sunrise)
        let side = up ? cos(day * .pi) : 0
        return Shadow(x: side * DailyMetric.sunReach,
                      y: DailyMetric.sunDrop + abs(side) * DailyMetric.sunDropLong,
                      blur: DailyMetric.sunBlur + abs(side) * DailyMetric.sunBlurLong)
    }

    /// The hour in the Town, with minutes as a fraction, wherever the phone is.
    static func hour(at date: Date) -> Double {
        let calendar = Town.gregorian
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return Double(parts.hour ?? 12) + Double(parts.minute ?? 0) / 60
    }
}

#if DEBUG
/// `-daily-samples`: Daily's sample Spotlight, Event of the day, Suggestions and Following, for
/// design work. Without it a test build shows only what's real, as the App Store build does
/// (Jesse, 2026-10-20).
nonisolated enum DailySamples {
    static let on = LaunchFlags.has(.dailySamples)
}
#endif

/// The Town clock as Daily reads it: the low sun and Event of the day both run on it.
nonisolated enum DailyClock {
    static func now(_ date: Date) -> Date {
        #if DEBUG
        // `-daily-hour <h>` holds it at that hour of today in the Town, so morning and
        // evening can be shot at any time of day.
        if let hour = LaunchFlags.value(.dailyHour).flatMap({ Double($0) }) {
            let calendar = Town.gregorian
            return calendar.startOfDay(for: date).addingTimeInterval(hour * 3600)
        }
        #endif
        return date
    }
}

/// What one day's page shows under the week, section by section.
struct DailyLists {
    var events: [DailyEvent]
    var friendsGoing: [DailyEvent]
    var suggestions: [DailyEvent]
    var following: [DailyFollowing]

    /// Every event on the page, for its topics.
    var items: [FeedCardItem] {
        (events + friendsGoing + suggestions).map(\.item) + following.compactMap { $0.event?.item }
    }

    /// `day`'s sections, `week` being today and the six days after it. Each leaves out what one
    /// above it shows (SPEC.md); a topic keeps only its own. `picks` are the day's Event of the day
    /// picks, `cards` the Town feed's.
    static func make(day: DailyWeekDay, week: [DailyWeekDay], now: Date, picks: [DailyEvent],
                     cards: [FeedCardItem], interests: [String], topic: String?,
                     isGoing: (FeedCardItem) -> Bool, isSaved: (FeedCardItem) -> Bool) -> DailyLists {
        let isToday = day == week.first
        // Another day's sections read from its midnight, so all of that day is still to come.
        let clock = isToday ? now : day.start
        let fits = { (item: FeedCardItem) in topic.map { DailyTopic.matches(item, $0) } ?? true }
        let events = DailyEvent.showing(picks.filter { fits($0.item) }, now: clock, limit: 3)
        // Today looks a week ahead; a day picked in the week, that day (Jesse, daily-tab 21).
        let friendDays = Set(isToday ? week.map(\.id) : [day.id])
        // What you follow is Following's: what that section shows, no section above takes
        // (school-activities 03).
        let following = DailyFollowing.showing(
            DailyFollowing.today(from: cards, day: day.id, now: clock)
                .filter { row in topic.map { DailyTopic.matches(row, $0) } ?? true },
            now: clock, without: events, limit: 10)
        let followed = Set(following.compactMap(\.event?.id))
        let cards = cards.filter { !followed.contains($0.id) }
        let friendsGoing = (DailyEvent.sampleFriendsGoing(now: clock)
            ?? DailyEvent.friendsGoing(from: cards, days: friendDays, now: clock, without: events))
            .filter { fits($0.item) }
        // Suggestions never offer what you're Going to or saved (SPEC.md).
        func left(_ item: FeedCardItem) -> Bool { fits(item) && !isGoing(item) && !isSaved(item) }
        let suggestions = DailyEvent.sampleSuggestions(now: clock).map {
            DailyEvent.showing($0.filter { left($0.item) }, now: clock, without: events + friendsGoing,
                               limit: DailyRowMetric.limit)
        } ?? DailyEvent.suggestions(from: cards, day: day.id, interests: interests, now: clock,
                                    without: events + friendsGoing, left: left)
        return DailyLists(events: events, friendsGoing: friendsGoing, suggestions: suggestions, following: following)
    }
}

struct DailyPage: View {
    /// None until stories exist. It is today's story, so another day opens on Event of the day.
    let spotlight: DailySpotlight?
    /// Today's Event of the day picks as read (`EventOfTheDay`); the page leaves out what's over.
    let events: [DailyEvent]
    /// The day picked in the week, nil for today. Kept in `MainTabsView`, so it stays while you
    /// switch tabs, and a new launch opens on today.
    @Binding var picked: String?
    /// The week's other days' picks.
    let dayPicks: DailyDayPicks
    /// The friends going each day (`DailyWeek.friendsGoing`).
    let friends: [String: [FeedFriend]]
    /// The Town feed's cards, which Friends are going and Suggestions read (daily-tab 20 and 21).
    let cards: [FeedCardItem]
    @Environment(RealLifeActions.self) private var actions
    @Environment(FriendsBook.self) private var book
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilt = PhoneTilt()
    /// How far the page has scrolled, held only up to `edgeFade`.
    @State private var scrolled: CGFloat = 0
    /// The topic picked under the week (daily-tab 19), nil for "Best of": everything.
    @State private var topic: String?

    var body: some View {
        // The phone's tilt only leans the Spotlight; with none it stays off.
        if spotlight != nil {
            timeline.following(tilt)
        } else {
            timeline
        }
    }

    private var timeline: some View {
        TimelineView(.everyMinute) { context in
            let now = DailyClock.now(context.date)
            let days = DailyWeek.days(from: now)
            page(now: now, days: days, shown: DailyWeek.shown(picked: picked, today: days[0].id))
        }
    }

    private func page(now: Date, days: [DailyWeekDay], shown: String) -> some View {
        let day = days.first { $0.id == shown } ?? days[0]
        let isToday = day == days[0]
        let interests = Interests.get()
        func lists(_ topic: String?) -> DailyLists {
            DailyLists.make(day: day, week: days, now: now, picks: isToday ? events : dayPicks.picks[day.id] ?? [],
                            cards: cards, interests: interests, topic: topic,
                            isGoing: { actions.going($0).isGoing }, isSaved: { actions.saved($0) })
        }
        let all = lists(nil)
        // The day's topics come from all it has. A topic the day lacks reads as "Best of" there and
        // comes back on a day that has it: the topic stays picked across the week (picked).
        let topics = DailyTopic.topics(for: all.items, mine: interests)
        let topic = self.topic.flatMap { topics.contains($0) ? $0 : nil }
        let onPage = topic == nil ? all : lists(topic)
        // The Spotlight is a person, not an event: a topic leaves it out (picked).
        let spotlight = isToday && topic == nil ? self.spotlight : nil
        // People, not events, as the Spotlight: today only, and a topic leaves them out (daily-tab 22).
        let people = isToday && topic == nil ? book.suggested : []
        // A day whose pick is still being read shows paper, not the reserved slot.
        let loading = !isToday && dayPicks.picks[day.id] == nil
        let empty = !loading && spotlight == nil && people.isEmpty && onPage.items.isEmpty && onPage.following.isEmpty
        return ZStack {
            Hue.paper.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    DailyMasthead()
                    DailyWeekRow(days: days, shown: shown, friends: friends) { tapped in
                        withAnimation(reduceMotion ? nil : Motion.select) {
                            picked = tapped == days[0] ? nil : tapped.id
                        }
                    }
                    .padding(.top, DailyTopMetric.toWeek)
                    // The system's selection tick on a tap, and only then (not at midnight).
                    .sensoryFeedback(.selection, trigger: picked)
                    // Always there, "Best of" alone on a day with no topics, so the page under it
                    // never jumps while another day reads.
                    DailyTopicRow(topics: topics, picked: topic) { tapped in
                        withAnimation(reduceMotion ? nil : Motion.select) { self.topic = tapped }
                    }
                    .padding(.top, DailyTopMetric.toTopics - DailyTopMetric.topicTapExtra)
                    .sensoryFeedback(.selection, trigger: self.topic)
                    // The last day's page fades out, then the picked day's fades in, in the same
                    // spot, so the two never sit on top of each other.
                    ZStack(alignment: .top) {
                        // The cards' chips count from now ("In 3 days"), though the day's are
                        // picked from its midnight.
                        sections(spotlight: spotlight, lists: onPage, people: people, empty: empty, loading: loading,
                                 now: now)
                            .id("\(day.id) \(topic ?? "")")
                            .transition(reduceMotion ? .identity : .asymmetric(
                                insertion: .opacity.animation(.easeOut(duration: DailyMetric.dayFade).delay(DailyMetric.dayFadeOut)),
                                removal: .opacity.animation(.easeIn(duration: DailyMetric.dayFadeOut))))
                    }
                    Color.clear.frame(height: DailyMetric.tabBarClearance)
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                min(max(geometry.contentOffset.y + geometry.contentInsets.top, 0), DailyMetric.edgeFade)
            } action: { _, offset in scrolled = offset }
        }
        // Today's are `EventOfTheDay`'s; a picked day reads at once, and the rest of the week reads
        // behind it, one day at a time, so a tap usually finds its day already there.
        .task(id: day.id) { if !isToday { await dayPicks.refresh(day) } }
        .task { await book.refreshSuggestions() }
        // A failed Add friend or X shakes and buzzes only while a screen with it is open.
        .onAppear { book.screenOpened() }
        .onDisappear { book.screenClosed() }
        .task(id: days[0].id) {
            for other in days.dropFirst() {
                // Leaving Daily calls the rest off; they read when Daily opens again.
                guard !Task.isCancelled else { return }
                await dayPicks.refresh(other)
            }
        }
        // The Town feed's frosted band behind the clock, so the page blurs under it;
        // it comes in with the first bit of scroll.
        .statusEdge(opacity: scrolled / DailyMetric.edgeFade)
    }

    @ViewBuilder
    private func sections(spotlight: DailySpotlight?, lists: DailyLists, people: [Neighbor], empty: Bool,
                          loading: Bool, now: Date) -> some View {
        if loading {
            Color.clear.frame(height: DailyMetric.emptyHeight)
        } else if empty {
            // Nothing that day: Daily's named, reserved slot, under the week.
            BlankTab(tab: .daily)
                .frame(height: DailyMetric.emptyHeight)
        } else {
            VStack(spacing: DailyMetric.eventSectionTop) {
                // Event of the day first, Spotlight under it (Jesse, daily-tab 18).
                if !lists.events.isEmpty { EventOfTheDaySection(events: lists.events, now: now) }
                if let spotlight {
                    VStack(spacing: DailyMetric.wordToCard) {
                        // The logo's face, standing in for the small caps label (Jesse, 2026-10-19).
                        Text("Spotlight")
                            .font(.logoSerif(DailyMetric.wordSize))
                            .tracking(DailyMetric.wordTracking)
                            .foregroundStyle(Hue.ink)
                            .accessibilityAddTraits(.isHeader)
                        SpotlightCard(spotlight: spotlight, tilt: tilt)
                            .padding(.horizontal, DailyMetric.side)
                    }
                }
                if !lists.friendsGoing.isEmpty { FriendsGoingSection(events: lists.friendsGoing, now: now) }
                if !lists.suggestions.isEmpty { SuggestionsSection(events: lists.suggestions, now: now) }
                // Fades in once read, never popping (taste.md, Chrome over content).
                if !people.isEmpty { PeopleYouMayKnowSection(people: people).transition(.opacity) }
                if !lists.following.isEmpty { FollowingSection(items: lists.following, now: now) }
            }
            .padding(.top, DailyMetric.weekToSection)
        }
    }
}

/// A section's small label, centred: SF Mono, as in the Reference's typewriter-style
/// label (Jesse, 2026-09-30). The names are working names; Jesse writes the final words.
struct DailySectionLabel: View {
    let title: String
    let ink: Color

    var body: some View {
        Text(title.uppercased())
            .font(.monoMedium(11).monospaced()).tracking(1.5)
            .foregroundStyle(ink)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The Spotlight card: the photo is the card, the name and business over a bottom fade
/// where the photo blurs and darkens, as App Store's card sets its words.
private struct SpotlightCard: View {
    let spotlight: DailySpotlight
    let tilt: PhoneTilt

    var body: some View {
        // The story page is the next piece; until then a press only squishes.
        Button {} label: { SpotlightCardFace(spotlight: spotlight, tilt: tilt) }
            .buttonStyle(SpotlightPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(spotlight.name), \(spotlight.about)")
    }
}

/// The bouncier card press (the spec's "bouncy press"), telling the card inside that it
/// is pressed so its shadow can pull in as it sinks.
private struct SpotlightPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableCardStyle().makeBody(configuration: configuration)
            .environment(\.spotlightPressed, configuration.isPressed)
    }
}

private extension EnvironmentValues {
    @Entry var spotlightPressed = false
}

private struct SpotlightCardFace: View {
    let spotlight: DailySpotlight
    let tilt: PhoneTilt
    @Environment(\.spotlightPressed) private var pressed
    /// The words' height, so the fade starts `fadeAboveWords` over the name however many
    /// lines it takes.
    @State private var wordsHeight: CGFloat = 0
    /// The photo once it has decoded. The fade's blurred copy waits for it, so it draws from
    /// the cache instead of loading the same photo a second time alongside.
    @State private var shownPhoto: URL?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var photo: URL? { spotlight.portrait ?? spotlight.photos.first }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.bento, style: .continuous) }

    var body: some View {
        let lean = tilt.lean
        // Ink under the photo, as the photo's own loading fill: the white words read on it
        // while it loads, and on a Spotlight with no photo at all.
        Hue.ink
            .aspectRatio(DailyMetric.cardAspect, contentMode: .fit)
            .overlay {
                if let photo {
                    // Faded in with the photo, as the Town card brings in its photo.
                    FeedCardURLPhoto(url: photo, onReady: {
                        withAnimation(reduceMotion ? nil : Motion.smooth) { shownPhoto = photo }
                    })
                }
            }
            .overlay { if let photo, photo == shownPhoto { fade(photo) } }
            .overlay(alignment: .bottomLeading) { words }
            .clipShape(shape)
            .overlay { shape.strokeBorder(Hue.hairline, lineWidth: 0.5) }
            // Shadows go on shapes alone: on the card they would also be cast by the words.
            .background {
                ZStack {
                    sunShadow(lean: lean)
                    shape.fill(Hue.surface).spotlightEdge()
                }
            }
            .frame(maxWidth: .infinity)
            .rotation3DEffect(.degrees(lean.x * DailyMetric.tiltLean), axis: (x: 0, y: 1, z: 0),
                              perspective: DailyMetric.tiltPerspective)
            .rotation3DEffect(.degrees(-lean.y * DailyMetric.tiltLean), axis: (x: 1, y: 0, z: 0),
                              perspective: DailyMetric.tiltPerspective)
    }

    private var words: some View {
        // No spacing: BP Event Heading's tall line box alone puts the name's baseline 11
        // over the business line's capitals, as App Store's title sits over its subtitle.
        VStack(alignment: .leading, spacing: 0) {
            Text(spotlight.name)
                .font(.eventDisplay(28))
                // The Town card's title, set the same way (`FeedEventCard.imageCopy`).
                .lineSpacing(-2)
                .lineLimit(3)
                .foregroundStyle(.white)
            // Jost Medium stands in for Airbnb's Cereal, which Airbnb doesn't license
            // (Jesse picks the final face later, 2026-10-19).
            Text(spotlight.about)
                .font(.displayMedium(15))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .feedCardPhotoTypeShadow()
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { wordsHeight = $0 }
        .padding([.horizontal, .top], DailyMetric.wordsInset)
        .padding(.bottom, DailyMetric.wordsBottom)
    }

    /// App Store's bottom fade: the photo's own blurred copy faded in from over the name,
    /// and black deepening to the edge. Public SwiftUI, not the UIKit blur the Town bar
    /// stacks: that blur blurs what is behind the view, and under a mask it kept the app
    /// from going idle (`statusEdge`).
    private func fade(_ photo: URL) -> some View {
        let height = wordsHeight + DailyMetric.wordsBottom + DailyMetric.fadeAboveWords
        return ZStack(alignment: .bottom) {
            FeedCardURLPhoto(url: photo)
                .blur(radius: DailyMetric.fadeBlur, opaque: true)
                .mask(alignment: .bottom) {
                    LinearGradient(stops: [.init(color: .clear, location: 0),
                                           .init(color: .black, location: DailyMetric.fadeSolid)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: height)
                }
            LinearGradient(colors: [.black.opacity(0), .black.opacity(DailyMetric.fadeShade)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// One shadow for the card, thrown across the page by the Town's sun and slid the
    /// other way by the lean. Its shape sits exactly under the card, so only the shadow
    /// shows.
    private func sunShadow(lean: CGPoint) -> some View {
        TimelineView(.everyMinute) { context in
            let sun = DailySun.shadow(hour: DailySun.hour(at: DailyClock.now(context.date)))
            let sink = pressed ? DailyMetric.sunPressed : 1
            shape
                .fill(Hue.surface)
                .shadow(color: .black.opacity(DailyMetric.sunOpacity),
                        radius: sun.blur * sink,
                        x: (sun.x - lean.x * DailyMetric.tiltShadowX) * sink,
                        y: (sun.y - lean.y * DailyMetric.tiltShadowY) * sink)
                .animation(Motion.select, value: pressed)
                // Sunset and sunrise swing it a long way in one tick of the clock.
                .animation(Motion.smooth, value: sun)
        }
    }
}
