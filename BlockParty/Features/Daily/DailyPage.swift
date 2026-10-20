//
//  DailyPage.swift
//  Block Party — the Daily tab: the neighbour's own page for today.
//
//  Top to bottom (`docs/plans/daily-tab/SPEC.md` in the BP app folder): the Spotlight,
//  under its label, on the yellow, then Event of the day, Suggestions and Following. A
//  section with nothing in it is left out; with no Spotlight the page opens on Event of the
//  day, the yellow fading into its card. What you're Going to lives on the You tab (BP app
//  docs/plans/you-tab).
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
    /// Reference (the onboarding interest images). A real Spotlight's photo is the
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
    /// "Spotlight" over the yellow in the logo's face, and from it to the card. Picked
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

    /// The yellow fades into the page over `yellowFade`, ending this far into the card:
    /// half the height the solid yellow took (Jesse, 2026-10-19).
    static let yellowIntoCard: CGFloat = 72
    static let yellowFade: CGFloat = 120
    /// How far up the solid yellow reaches above the fade: under the clock, and past
    /// the longest pull, so pulling down never shows paper above it.
    static let yellowReach: CGFloat = 1600
    /// The clock's frosted edge comes in over this much scroll, as the Spotlight label
    /// slides under the clock. At rest and pulled down it is gone, so the yellow under
    /// the clock stays exact. Picked: no Reference has a yellow top under a clock.
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
    /// Pressed, the card sinks toward the yellow, so its shadow pulls in this much.
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

    /// Event of the day, MEASURED from Jesse's Reference: Airbnb's "Apartment in New
    /// York" trip card (`airbnb-trip-5.jpg` in the Daily spec's reference assets, an
    /// @3x 393pt screen). Two departures, picked to match the Spotlight above it: the
    /// card's sides sit at `side` (18) where Airbnb's sit at 24, and its corner is
    /// `Radius.bento` (22) where Airbnb's is 24.
    static let eventPhotoInset: CGFloat = 8
    static let eventPhotoAspect: CGFloat = 3.0 / 2.0
    // Its chip is `PhotoChip`, which the Town card shares since 2026-10-19.
    /// The text and the divider sit this far in from the card's edges.
    static let eventTextInset: CGFloat = 21
    /// Gaps between the text's frames, set so the glyphs sit the Reference's distances
    /// apart (measured in the frames, 2026-10-02): photo to the title's capitals 24,
    /// the title's baseline to the time's capitals 16, and the time's baseline to the
    /// divider 20. Jost's tall line box is most of the difference.
    static let eventTitleTop: CGFloat = 15
    static let eventTimeTop: CGFloat = 2
    static let eventDividerTop: CGFloat = 16
    /// Attend's row, where Airbnb's grey button sits, MEASURED the same way: the button's
    /// middle 38.5 under the divider and its bottom 16 over the card's edge. Our pill is 38
    /// tall (the Town card's) where Airbnb's button is 43, so the same middle and the same
    /// gap under it put the row 19.5 under the divider and 18.5 over the edge.
    static let eventRowTop: CGFloat = 19.5
    static let eventRowBottom: CGFloat = 18.5
    /// With no Spotlight the section opens the page: its label this far under the clock.
    static let eventFirstTop: CGFloat = 8
    /// From the Spotlight card to the section's label, and from the label to the card:
    /// Airbnb's gap between one trip's card and the next city's heading, and from that
    /// heading to its card.
    static let eventSectionTop: CGFloat = 38
    static let eventLabelToCard: CGFloat = 15
    /// Between the cards on a busy day; the next card's edge shows by this much less
    /// than the page margin. Picked: Airbnb's trip card never sits in a row.
    static let eventGap: CGFloat = 10

    /// Suggestions, MEASURED from Jesse's Reference: Airbnb's "Happening today" row
    /// (`references/daily-suggestions/airbnb-happening-today.jpg` in the BP app folder,
    /// an @3x 393pt screen), copied 1:1 (Jesse, 2026-10-05). The cards start at `side`
    /// (18) where Airbnb's start at 24, as Event of the day's do. The photo's corner is
    /// `Radius.bento`: measured edge to edge against Airbnb's, it rounds the same.
    static let suggestionWidth: CGFloat = 167
    static let suggestionPhoto: CGFloat = 158
    static let suggestionGap: CGFloat = 13
    /// The time chip: 24 tall, 10 in from the photo's corner, as wide as "11 AM" there.
    /// The photo floats on the one soft card shadow, as Airbnb's does.
    static let suggestionChipInset: CGFloat = 10
    static let suggestionChipHeight: CGFloat = 24
    static let suggestionChipPadding: CGFloat = 8
    /// The bookmark sits where Airbnb's heart does, its middle 26pt in from the corner:
    /// this, plus half its 44pt tap area.
    static let suggestionSaveInset: CGFloat = 4
    /// From the photo to the title's frame: 11pt to its capitals, as measured.
    static let suggestionTitleTop: CGFloat = 8
    /// Between the title and each grey line under it.
    static let suggestionLineGap: CGFloat = 2
    /// The words sit this far in from the photo's edges, as Airbnb's do.
    static let suggestionTextInset: CGFloat = 3

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

/// The low sun over the yellow: morning light from the east throws the Spotlight's
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
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Town.timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return Double(parts.hour ?? 12) + Double(parts.minute ?? 0) / 60
    }
}

#if DEBUG
/// `-daily-samples`: Daily's sample Spotlight, Event of the day, Suggestions and Following, for
/// design work. Without it a test build shows only what's real, as the App Store build does
/// (Jesse, 2026-10-20).
nonisolated enum DailySamples {
    static let on = ProcessInfo.processInfo.arguments.contains("-daily-samples")
}
#endif

/// The Town clock as Daily reads it: the low sun and Event of the day both run on it.
nonisolated enum DailyClock {
    static func now(_ date: Date) -> Date {
        #if DEBUG
        // `-daily-hour <h>` holds it at that hour of today in the Town, so morning and
        // evening can be shot at any time of day.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-daily-hour"), i + 1 < args.count, let hour = Double(args[i + 1]) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = Town.timeZone
            return calendar.startOfDay(for: date).addingTimeInterval(hour * 3600)
        }
        #endif
        return date
    }
}

/// The yellow easing out into the page: exact BP yellow above, the page's own colour
/// below. Eased at both ends (smoothstep), since a straight ramp drew a line where it
/// started, under the clock.
private nonisolated enum DailyYellow {
    static let fade: [Gradient.Stop] = stride(from: 0.0, through: 1.0, by: 0.125).map { t in
        .init(color: Hue.brandDisc.mix(with: Hue.paper, by: t * t * (3 - 2 * t)), location: t)
    }
}

extension VerticalAlignment {
    /// The yellow fade's lower edge, set by the Spotlight card, or with none by Event of the
    /// day's first card.
    nonisolated enum DailyYellowEdge: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[.top] }
    }
    static let dailyYellowEdge = VerticalAlignment(DailyYellowEdge.self)
}

struct DailyPage: View {
    /// None until stories exist: the page opens on Event of the day.
    let spotlight: DailySpotlight?
    /// Event of the day's picks as read (`EventOfTheDay`); the page leaves out what's over.
    let events: [DailyEvent]
    @Environment(RealLifeActions.self) private var actions
    @State private var tilt = PhoneTilt()
    /// How far the page has scrolled, held only up to `edgeFade`.
    @State private var scrolled: CGFloat = 0

    var body: some View {
        // The phone's tilt only leans the Spotlight; with none it stays off.
        if spotlight != nil {
            page.following(tilt)
        } else {
            // With no Spotlight, once nothing else is left today the page is the placeholder.
            TimelineView(.everyMinute) { context in
                let now = DailyClock.now(context.date)
                if DailyEvent.showing(events, now: now, limit: 3).isEmpty
                    && DailyEvent.suggestions(now: now).isEmpty && DailyFollowing.today(now: now).isEmpty {
                    BlankTab(tab: .daily)
                } else {
                    page
                }
            }
        }
    }

    private var page: some View {
        ZStack {
            Hue.paper.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if let spotlight {
                        // The logo's face, standing in for the small caps label (Jesse, 2026-10-19).
                        Text("Spotlight")
                            .font(.logoSerif(DailyMetric.wordSize))
                            .tracking(DailyMetric.wordTracking)
                            .foregroundStyle(Hue.onBrandDisc)
                            .accessibilityAddTraits(.isHeader)
                        SpotlightCard(spotlight: spotlight, tilt: tilt)
                            .padding(.top, DailyMetric.wordToCard)
                            .padding(.horizontal, DailyMetric.side)
                    }
                    TimelineView(.everyMinute) { context in
                        let now = DailyClock.now(context.date)
                        // Each section leaves out what one above it shows (SPEC.md).
                        let events = DailyEvent.showing(self.events, now: now, limit: 3)
                        // Suggestions never offer what you're Going to or saved (SPEC.md).
                        let suggestions = DailyEvent.showing(
                            DailyEvent.suggestions(now: now).filter {
                                !actions.going($0.item).isGoing && !actions.saved($0.item)
                            }, now: now, without: events, limit: 10)
                        let following = DailyFollowing.showing(DailyFollowing.today(now: now), now: now,
                                                               without: events + suggestions, limit: 10)
                        VStack(spacing: 0) {
                            if !events.isEmpty {
                                EventOfTheDaySection(events: events, now: now, marksYellowEdge: spotlight == nil)
                                    .padding(.top, spotlight == nil ? DailyMetric.eventFirstTop : DailyMetric.eventSectionTop)
                            }
                            if !suggestions.isEmpty {
                                SuggestionsSection(events: suggestions, now: now)
                                    .padding(.top, DailyMetric.eventSectionTop)
                            }
                            if !following.isEmpty {
                                FollowingSection(items: following, now: now)
                                    .padding(.top, DailyMetric.eventSectionTop)
                            }
                        }
                    }
                    Color.clear.frame(height: DailyMetric.tabBarClearance)
                }
                .background(alignment: Alignment(horizontal: .center, vertical: .dailyYellowEdge)) {
                    VStack(spacing: 0) {
                        Hue.brandDisc.frame(height: DailyMetric.yellowReach)
                        LinearGradient(stops: DailyYellow.fade, startPoint: .top, endPoint: .bottom)
                            .frame(height: DailyMetric.yellowFade)
                    }
                    .alignmentGuide(.dailyYellowEdge) { $0[.bottom] }
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                min(max(geometry.contentOffset.y + geometry.contentInsets.top, 0), DailyMetric.edgeFade)
            } action: { _, offset in scrolled = offset }
        }
        // The Town feed's frosted band behind the clock, so the page blurs under it;
        // it comes in with the first bit of scroll, so at rest the yellow stays exact.
        .statusEdge(opacity: scrolled / DailyMetric.edgeFade)
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
            .alignmentGuide(.dailyYellowEdge) { $0[.top] + DailyMetric.yellowIntoCard }
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
