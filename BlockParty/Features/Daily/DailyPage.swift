//
//  DailyPage.swift
//  Block Party — the Daily tab: the neighbour's own page for today.
//
//  Top to bottom (`docs/plans/daily-tab/SPEC.md` in the BP app folder): a date line,
//  then the Spotlight. Event of the day, Agenda, Suggestions and Following join below,
//  one at a time. A section with nothing in it is left out.
//

import SwiftUI

/// Today's Spotlight: one local person or business and their story, the same for
/// everyone in the Town and new each day.
struct DailySpotlight: Equatable {
    var name: String
    /// What they do, or their business.
    var about: String
    var portrait: URL?
    /// The photos under the name; the card shows the first two.
    var photos: [URL]

    /// Today's story. There is no backend for it yet, so a release build gets nil and the
    /// tab keeps its placeholder, which is the truth. DEBUG gets the sample. When the
    /// read exists, this is the one property that changes.
    static var today: DailySpotlight? {
        #if DEBUG
        return .sample
        #else
        return nil
        #endif
    }

    #if DEBUG
    /// INVENTED: a made-up neighbour and business over the app's bundled St. Joe photos.
    static let sample = DailySpotlight(
        name: "Marta Reyes",
        about: "Northside Coffee",
        portrait: bundled("the-local-blend"),
        photos: [bundled("downtown"), bundled("farmers-market")].compactMap { $0 }
    )

    private static func bundled(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "jpg")
    }
    #endif
}

/// Sizes MEASURED from Jesse's Reference: the Host card, layout 02 of the Daily Layouts
/// mockup (`references/daily-tab/spotlight-host-card-pick.png` in the BP app folder).
/// The card's corner is the one departure: 26 there, `Radius.bento` here (Jesse, 2026-09-30).
private nonisolated enum DailyMetric {
    static let side: CGFloat = 18
    static let dateTop: CGFloat = 6
    /// From the date line to the top of the round photo.
    static let dateToPortrait: CGFloat = 22
    static let portrait: CGFloat = 120
    static let portraitRing: CGFloat = 5
    /// Card padding above the label: the photo's lower half, then 12.
    static let cardTop: CGFloat = 72
    static let cardInset: CGFloat = 18
    static let nameTop: CGFloat = 6
    static let nameBottom: CGFloat = 2
    static let photosTop: CGFloat = 16
    static let photoGap: CGFloat = 6
    static let photoAspect: CGFloat = 4.0 / 3.0
    /// Clears the floating tab bar: the same 96 the other tab scrollers reserve.
    static let tabBarClearance: CGFloat = 96
}

struct DailyPage: View {
    let spotlight: DailySpotlight

    var body: some View {
        ZStack {
            Hue.paper.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    DailyDateLine()
                        .padding(.top, DailyMetric.dateTop)
                    SpotlightCard(spotlight: spotlight)
                        .padding(.top, DailyMetric.dateToPortrait)
                    Color.clear.frame(height: DailyMetric.tabBarClearance)
                }
                .padding(.horizontal, DailyMetric.side)
            }
        }
        // The Town feed's frosted band behind the clock, so the page blurs under it.
        .overlay(alignment: .top) {
            Color.clear
                .frame(height: StatusEdge.tail)
                .background(StatusEdge().ignoresSafeArea(edges: .top))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// A small, centred date line: today in the Town, so it turns over at the Town's
/// midnight wherever the phone is.
struct DailyDateLine: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(Self.label(for: context.date))
                .font(.mono(11)).tracking(1.5)
                .foregroundStyle(Hue.inkSecondary)
                .frame(maxWidth: .infinity)
        }
    }

    static func label(for date: Date, locale: Locale = .current) -> String {
        var style = Date.FormatStyle(locale: locale, timeZone: WeatherService.townTZ)
        style = style.weekday(.wide).month(.wide).day()
        return date.formatted(style).uppercased()
    }
}

/// The Host card: a white card lifted off the page, its round photo breaking out of the
/// top edge, then the label, the name, what they do, and two photos.
private struct SpotlightCard: View {
    let spotlight: DailySpotlight

    var body: some View {
        // The story page is the next piece; until then a press only squishes.
        Button {} label: { card }
            .buttonStyle(FeedCardPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Spotlight: \(spotlight.name), \(spotlight.about)")
    }

    private var card: some View {
        VStack(spacing: 0) {
            // SF Mono, as in the Reference's typewriter-style label (Jesse, 2026-09-30).
            Text("Spotlight".uppercased())
                .font(.monoMedium(11).monospaced()).tracking(1.5)
                .foregroundStyle(Hue.inkSecondary)
            Text(spotlight.name)
                .font(.display(28))
                .foregroundStyle(Hue.ink)
                .multilineTextAlignment(.center)
                .padding(.top, DailyMetric.nameTop)
                .padding(.bottom, DailyMetric.nameBottom)
            Text(spotlight.about)
                .font(.sans(15))
                .foregroundStyle(Hue.inkSecondary)
                .multilineTextAlignment(.center)
            if !spotlight.photos.isEmpty {
                HStack(spacing: DailyMetric.photoGap) {
                    ForEach(spotlight.photos.prefix(2), id: \.self) { url in
                        Hue.fill
                            .aspectRatio(DailyMetric.photoAspect, contentMode: .fit)
                            .overlay(FeedCardURLPhoto(url: url))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                    }
                }
                .padding(.top, DailyMetric.photosTop)
            }
        }
        .padding(.top, DailyMetric.cardTop)
        .padding([.horizontal, .bottom], DailyMetric.cardInset)
        .frame(maxWidth: .infinity)
        // The lift goes on the card's shape alone: on the stack it would also be cast
        // by each photo and line of text, greying the card under them.
        .background {
            RoundedRectangle(cornerRadius: Radius.bento, style: .continuous)
                .fill(Hue.surface)
                .spotlightLift()
        }
        .overlay(alignment: .top) {
            portrait.offset(y: -DailyMetric.portrait / 2)
        }
        .padding(.top, DailyMetric.portrait / 2)
    }

    private var portrait: some View {
        Circle()
            .fill(Hue.fill)
            .overlay {
                if let url = spotlight.portrait { FeedCardURLPhoto(url: url) }
            }
            .clipShape(Circle())
            .padding(DailyMetric.portraitRing)
            .background(Circle().fill(Hue.surface).portraitLift())
            .frame(width: DailyMetric.portrait, height: DailyMetric.portrait)
    }
}
