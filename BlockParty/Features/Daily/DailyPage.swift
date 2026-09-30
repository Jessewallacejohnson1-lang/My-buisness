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
struct DailySpotlight {
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
    /// INVENTED: a made-up neighbour and business, over the warm photos from Jesse's
    /// Reference (the onboarding interest images). A real Spotlight's round photo is the
    /// person's face; the sample has no real face to show.
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
    /// Card padding above the label: the photo's lower half, then 17.
    static let cardTop: CGFloat = 77
    static let cardInset: CGFloat = 18
    /// Jost's line box is taller than the mockup's 1.15; these put the name's glyphs
    /// 15pt under the label and 6pt over the business line, as measured there.
    static let nameTop: CGFloat = 3
    static let nameBottom: CGFloat = -1.5
    static let photosTop: CGFloat = 16
    static let photoGap: CGFloat = 6
    static let photoAspect: CGFloat = 4.0 / 3.0
    /// The drop shadow's shape is pulled in this far from the card's sides and top, so
    /// the shadow pools under the card instead of greying all round it.
    static let dropInset: CGFloat = 16
    static let dropTop: CGFloat = 28
    /// Pressed, the round photo rises toward the finger while the card sinks.
    static let portraitPressScale: CGFloat = 1.06
    static let portraitPressRise: CGFloat = 5
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
        .statusEdge()
    }
}

/// A small, centred date line: today in the Town, the Town header's own eyebrow, so it
/// turns over at the Town's midnight wherever the phone is.
private struct DailyDateLine: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(TodayHeader.eyebrow(for: context.date))
                .font(.mono(11)).tracking(1.5)
                .foregroundStyle(Hue.inkSecondary)
                .frame(maxWidth: .infinity)
        }
    }
}

/// The Host card: a white card lifted off the page, its round photo breaking out of the
/// top edge, then the label, the name, what they do, and two photos.
private struct SpotlightCard: View {
    let spotlight: DailySpotlight

    var body: some View {
        // The story page is the next piece; until then a press only squishes.
        Button {} label: { SpotlightCardFace(spotlight: spotlight) }
            .buttonStyle(SpotlightPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Spotlight: \(spotlight.name), \(spotlight.about)")
    }
}

/// The bouncier card press (the spec's "bouncy press"), telling the card inside that it
/// is pressed so the round photo can rise while the card sinks.
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
    @Environment(\.spotlightPressed) private var pressed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
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
        // Shadows go on shapes alone: on the stack they would also be cast by each
        // photo and line of text, greying the card under them.
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.bento, style: .continuous)
                    .fill(Hue.surface)
                    .padding(.horizontal, DailyMetric.dropInset)
                    .padding(.top, DailyMetric.dropTop)
                    .spotlightDrop(pressed: pressed)
                RoundedRectangle(cornerRadius: Radius.bento, style: .continuous)
                    .fill(Hue.surface)
                    .spotlightEdge()
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.bento, style: .continuous)
                            .strokeBorder(Hue.hairline, lineWidth: 0.5)
                    }
            }
            .animation(Motion.select, value: pressed)
        }
        .overlay(alignment: .top) {
            portrait.offset(y: -DailyMetric.portrait / 2)
        }
        .padding(.top, DailyMetric.portrait / 2)
    }

    private var portrait: some View {
        let rises = pressed && !reduceMotion
        return FeedAuthorAvatar(url: spotlight.portrait, name: spotlight.name,
                                side: DailyMetric.portrait - 2 * DailyMetric.portraitRing)
            .padding(DailyMetric.portraitRing)
            .background(Circle().fill(Hue.surface).portraitLift(pressed: pressed))
            .frame(width: DailyMetric.portrait, height: DailyMetric.portrait)
            .scaleEffect(rises ? DailyMetric.portraitPressScale : 1, anchor: .bottom)
            .offset(y: rises ? -DailyMetric.portraitPressRise : 0)
            .animation(Motion.select, value: pressed)
    }
}
