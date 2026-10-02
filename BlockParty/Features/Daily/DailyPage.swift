//
//  DailyPage.swift
//  Block Party — the Daily tab: the neighbour's own page for today.
//
//  Top to bottom (`docs/plans/daily-tab/SPEC.md` in the BP app folder): the Spotlight,
//  under its label, on the yellow. Event of the day, Agenda, Suggestions and Following
//  join below, one at a time. A section with nothing in it is left out.
//

import CoreMotion
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
/// The yellow, the low sun and the tilt are the depth page Jesse picked on 2026-10-01
/// (ideas "Yellow cover", "Low sun" and "Tilt"); their values were picked there, in a
/// browser mockup, not measured from another app. Its CSS blurs are halved here: a
/// SwiftUI shadow radius blurs about as much as a CSS blur twice its size.
private nonisolated enum DailyMetric {
    static let side: CGFloat = 18
    /// The "Spotlight" label sits where the date line was, at the date line's spacing.
    static let labelTop: CGFloat = 6
    /// From the label to the top of the round photo.
    static let labelToPortrait: CGFloat = 22
    static let portrait: CGFloat = 120
    static let portraitRing: CGFloat = 5
    /// Card padding above the name: the photo's lower half, then 17.
    static let cardTop: CGFloat = 77
    static let cardInset: CGFloat = 18
    /// Jost's line box is taller than the mockup's 1.15; this puts the name's glyphs
    /// 6pt over the business line, as measured there.
    static let nameBottom: CGFloat = -1.5
    static let photosTop: CGFloat = 16
    static let photoGap: CGFloat = 6
    static let photoAspect: CGFloat = 4.0 / 3.0
    /// Pressed, the round photo rises toward the finger while the card sinks.
    static let portraitPressScale: CGFloat = 1.06
    static let portraitPressRise: CGFloat = 5
    /// Clears the floating tab bar: the same 96 the other tab scrollers reserve.
    static let tabBarClearance: CGFloat = 96

    /// The yellow ends this far under the business line, so the card rides its edge.
    static let yellowBelowAbout: CGFloat = 12
    /// How far up the yellow reaches from its lower edge: under the clock, and past
    /// the longest pull, so pulling down never shows paper above it.
    static let yellowReach: CGFloat = 1600
    /// The status edge reaches no further down the screen than this. While the yellow
    /// ends below it, where exactly doesn't matter, so the page stops tracking it.
    static let edgeWatch: CGFloat = 120

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

    /// A full lean is the phone tipped this far (in gravity, about 17°) from the way it
    /// is being held.
    static let tiltRange: Double = 0.3
    /// How fast "the way it is being held" catches up with the hand, per reading: at 60
    /// readings a second the lean settles back in about 1.5 s.
    static let tiltRestFollow: Double = 0.012
    static let tiltReadingsPerSecond: Double = 60
    /// A lean change smaller than this isn't drawn: it moves the shadow under a tenth
    /// of a point, it is sensor noise on a phone lying still, and redrawing for it 60
    /// times a second would cost battery.
    static let tiltStill: Double = 0.005
    /// At a full lean: the card turns this many degrees, its shadow slides this far the
    /// other way, and the round photo floats this far ahead of the card.
    static let tiltLean: Double = 8
    /// The mockup's 900pt camera for a card about 360pt wide; SwiftUI's default of 1
    /// puts the camera a card's width away, which turned a full lean into a skew.
    static let tiltPerspective: CGFloat = 0.4
    static let tiltShadowX: CGFloat = 16
    static let tiltShadowY: CGFloat = 12
    static let tiltFloatX: CGFloat = 5
    static let tiltFloatY: CGFloat = 4
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

    /// DEBUG-only: `-daily-sun-hour <h>` holds the sun at that Town hour, so morning and
    /// evening can be shot at any time of day.
    static var debugHour: Double? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-daily-sun-hour"), i + 1 < args.count {
            return Double(args[i + 1])
        }
        #endif
        return nil
    }
}

/// How the phone is held, as a lean from -1 to 1 on each axis against a rest that
/// slowly catches up with the hand, so any comfortable grip reads as level. Apple's own
/// tilt (`UIInterpolatingMotionEffect`, the wallpaper's) is UIKit-only, so this reads
/// the motion sensor directly; that needs no permission.
@Observable
final class DailyTilt {
    private(set) var lean: CGPoint = .zero
    /// Made on the first start, not with the page: `@State` builds a new `DailyTilt`
    /// every time the page view is rebuilt and keeps only the first.
    @ObservationIgnored private var motion: CMMotionManager?
    @ObservationIgnored private var rest: (x: Double, z: Double)?

    func start() {
        #if DEBUG
        if let held = Self.debugLean { lean = held; return }
        #endif
        let motion = self.motion ?? CMMotionManager()
        self.motion = motion
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1 / DailyMetric.tiltReadingsPerSecond
        motion.startDeviceMotionUpdates(to: .main) { [weak self] reading, _ in
            guard let gravity = reading?.gravity else { return }
            let x = gravity.x, z = gravity.z
            MainActor.assumeIsolated { self?.read(x: x, z: z) }
        }
    }

    func stop() {
        motion?.stopDeviceMotionUpdates()
        rest = nil
        lean = .zero
    }

    private func read(x: Double, z: Double) {
        var held = rest ?? (x, z)
        let next = Self.lean(gravity: (x, z), rest: &held)
        rest = held
        if abs(next.x - lean.x) > DailyMetric.tiltStill || abs(next.y - lean.y) > DailyMetric.tiltStill {
            lean = next
        }
    }

    /// One reading: the lean against the rest, then the rest moves a little toward it.
    nonisolated static func lean(gravity: (x: Double, z: Double),
                                 rest: inout (x: Double, z: Double)) -> CGPoint {
        let range = DailyMetric.tiltRange
        let lean = CGPoint(x: min(1, max(-1, (gravity.x - rest.x) / range)),
                           y: min(1, max(-1, (gravity.z - rest.z) / range)))
        rest.x += (gravity.x - rest.x) * DailyMetric.tiltRestFollow
        rest.z += (gravity.z - rest.z) * DailyMetric.tiltRestFollow
        return lean
    }

    #if DEBUG
    /// DEBUG-only: `-daily-tilt <x>,<y>` holds the card at that lean, since the
    /// simulator has no motion sensor.
    private static var debugLean: CGPoint? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-daily-tilt"), i + 1 < args.count else { return nil }
        let parts = args[i + 1].split(separator: ",").compactMap { Double($0) }
        return parts.count == 2 ? CGPoint(x: parts[0], y: parts[1]) : nil
    }
    #endif
}

private extension VerticalAlignment {
    /// The yellow's lower edge, set by the Spotlight's business line.
    nonisolated enum DailyYellowEdge: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[.top] }
    }
    static let dailyYellowEdge = VerticalAlignment(DailyYellowEdge.self)
}

struct DailyPage: View {
    let spotlight: DailySpotlight
    @State private var tilt = DailyTilt()
    /// How far down the screen the yellow still reaches, while that is near the clock.
    @State private var yellowEnd = DailyMetric.edgeWatch
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Hue.paper.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // SF Mono, as in the Reference's typewriter-style label (Jesse, 2026-09-30).
                    Text("Spotlight".uppercased())
                        .font(.monoMedium(11).monospaced()).tracking(1.5)
                        .foregroundStyle(Hue.onBrandDisc)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, DailyMetric.labelTop)
                    SpotlightCard(spotlight: spotlight, tilt: tilt)
                        .padding(.top, DailyMetric.labelToPortrait)
                    Color.clear.frame(height: DailyMetric.tabBarClearance)
                }
                .padding(.horizontal, DailyMetric.side)
                .background(alignment: Alignment(horizontal: .center, vertical: .dailyYellowEdge)) {
                    Hue.brandDisc
                        .frame(height: DailyMetric.yellowReach)
                        .alignmentGuide(.dailyYellowEdge) { $0[.bottom] }
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            min(max(proxy.frame(in: .global).maxY, 0), DailyMetric.edgeWatch)
                        } action: { yellowEnd = $0 }
                }
            }
        }
        // The Town feed's frosted band behind the clock, so the page blurs under it;
        // it fades in as the yellow leaves the clock, so the yellow stays exact.
        .statusEdge(coveredTo: yellowEnd)
        .onAppear(perform: followTilt)
        .onDisappear { tilt.stop() }
        .onChange(of: reduceMotion, followTilt)
        .onChange(of: scenePhase, followTilt)
    }

    /// The tilt runs only while the app is in front and Reduce Motion is off; stopping
    /// it also forgets the grip, so coming back in a new one doesn't jump to a lean.
    private func followTilt() {
        if scenePhase == .active && !reduceMotion { tilt.start() } else { tilt.stop() }
    }
}

/// The Host card: a white card lifted off the page, its round photo breaking out of the
/// top edge, then the name, what they do, and two photos.
private struct SpotlightCard: View {
    let spotlight: DailySpotlight
    let tilt: DailyTilt

    var body: some View {
        // The story page is the next piece; until then a press only squishes.
        Button {} label: { SpotlightCardFace(spotlight: spotlight, tilt: tilt) }
            .buttonStyle(SpotlightPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(spotlight.name), \(spotlight.about)")
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
    let tilt: DailyTilt
    @Environment(\.spotlightPressed) private var pressed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let lean = tilt.lean
        let float = CGSize(width: lean.x * DailyMetric.tiltFloatX, height: lean.y * DailyMetric.tiltFloatY)
        VStack(spacing: 0) {
            Text(spotlight.name)
                .font(.display(28))
                .foregroundStyle(Hue.ink)
                .multilineTextAlignment(.center)
                .padding(.bottom, DailyMetric.nameBottom)
            Text(spotlight.about)
                .font(.sans(15))
                .foregroundStyle(Hue.inkSecondary)
                .multilineTextAlignment(.center)
                .alignmentGuide(.dailyYellowEdge) { $0[.bottom] + DailyMetric.yellowBelowAbout }
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
                sunShadow(lean: lean, float: float)
                RoundedRectangle(cornerRadius: Radius.bento, style: .continuous)
                    .fill(Hue.surface)
                    .spotlightEdge()
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.bento, style: .continuous)
                            .strokeBorder(Hue.hairline, lineWidth: 0.5)
                    }
            }
        }
        .overlay(alignment: .top) {
            portrait.offset(x: float.width, y: float.height - DailyMetric.portrait / 2)
        }
        .rotation3DEffect(.degrees(lean.x * DailyMetric.tiltLean), axis: (x: 0, y: 1, z: 0),
                          perspective: DailyMetric.tiltPerspective)
        .rotation3DEffect(.degrees(-lean.y * DailyMetric.tiltLean), axis: (x: 1, y: 0, z: 0),
                          perspective: DailyMetric.tiltPerspective)
        .padding(.top, DailyMetric.portrait / 2)
    }

    /// One shadow for the card and its round photo together, thrown across the yellow by
    /// the Town's sun and slid the other way by the lean. Its shapes sit exactly under
    /// the card and the photo, so only the shadow shows.
    private func sunShadow(lean: CGPoint, float: CGSize) -> some View {
        TimelineView(.everyMinute) { context in
            let sun = DailySun.shadow(hour: DailySun.debugHour ?? DailySun.hour(at: context.date))
            let sink = pressed ? DailyMetric.sunPressed : 1
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: Radius.bento, style: .continuous)
                Circle()
                    .frame(width: DailyMetric.portrait, height: DailyMetric.portrait)
                    .offset(x: float.width, y: float.height - DailyMetric.portrait / 2)
            }
            .foregroundStyle(Hue.surface)
            .compositingGroup()
            .shadow(color: .black.opacity(DailyMetric.sunOpacity),
                    radius: sun.blur * sink,
                    x: (sun.x - lean.x * DailyMetric.tiltShadowX) * sink,
                    y: (sun.y - lean.y * DailyMetric.tiltShadowY) * sink)
            .animation(Motion.select, value: pressed)
            // Sunset and sunrise swing it a long way in one tick of the clock.
            .animation(Motion.smooth, value: sun)
        }
    }

    private var portrait: some View {
        let rises = pressed && !reduceMotion
        return FeedAuthorAvatar(url: spotlight.portrait, name: spotlight.name,
                                side: DailyMetric.portrait - 2 * DailyMetric.portraitRing)
            .padding(DailyMetric.portraitRing)
            .background(Circle().fill(Hue.surface).portraitLift(pressed: rises))
            .frame(width: DailyMetric.portrait, height: DailyMetric.portrait)
            .scaleEffect(rises ? DailyMetric.portraitPressScale : 1, anchor: .bottom)
            .offset(y: rises ? -DailyMetric.portraitPressRise : 0)
            .animation(Motion.select, value: pressed)
    }
}
