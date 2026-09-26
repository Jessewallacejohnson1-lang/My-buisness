//
//  TodayHeaderTests.swift
//  BlockPartyTests — the Today tab's compact fixed header bar.
//
//  The 34pt wordmark + date line that used to scroll away with the content
//  (`Masthead`) becomes a fixed 44pt bar — block glyph leading, town name centered,
//  the existing menu button trailing — and today's date moved into the feed
//  as a small uppercase eyebrow.
//
//  Two things in that rework are pure logic and therefore testable, and both have a
//  history of going wrong elsewhere in this app:
//
//  1. The eyebrow is a DATE, so it must read `Town`'s clock (America/Chicago), not
//     the device's — the same trap `TownTimezoneTests` locks down for the Utility
//     Row formatters. The old `Masthead.dateLine` used a bare `DateFormatter` with
//     no timezone and no locale pin, so it printed the phone's day in the phone's
//     language. The replacement must not.
//  2. The chrome fades and the bar collapses off ONE scroll number, and the
//     interesting input is the NEGATIVE one: a rubber-banded overscroll (pull to
//     refresh) must not drive either past its rest state.
//
//  Reference weekdays (2026): Aug 1 = Sat, Jan 15 = Thu, Jan 16 = Fri, Nov 3 = Tue.
//

import XCTest
import SwiftUI   // ColorScheme, for the appearance-switch tests at the bottom
import UIKit     // UIUserInterfaceStyle, ditto
@testable import BlockParty

@MainActor
final class TodayHeaderTests: XCTestCase {

    // MARK: Fixtures

    /// Builds the test instants unambiguously — an explicit wall-clock in Chicago,
    /// independent of whatever ambient zone the test has forced.
    private func chicagoCalendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_US_POSIX")
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        c.firstWeekday = 1
        return c
    }

    private func chicagoInstant(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d; comps.hour = h; comps.minute = min
        return chicagoCalendar().date(from: comps)!
    }

    /// The device calendar re-pointed at a foreign zone — the *only* difference from
    /// `Calendar.current` is the timezone, so a differing answer isolates the bug.
    private func deviceCalendar(zone identifier: String) -> Calendar {
        var c = Calendar.current
        c.timeZone = TimeZone(identifier: identifier)!
        return c
    }

    // MARK: - Eyebrow formatting

    func testEyebrowIsUppercaseWeekdayAndDate() {
        // Arrange — Sat Aug 1 2026, mid-morning Central so no zone within ±9h can
        // slide the day. The shape is "EEEE, MMMM d" uppercased.
        let instant = chicagoInstant(2026, 8, 1, 9)

        // Act
        let eyebrow = TodayHeader.eyebrow(for: instant)

        // Assert — exact string: the comma, the full weekday, the full month.
        XCTAssertEqual(eyebrow, "SATURDAY, AUGUST 1")
    }

    func testEyebrowUsesTownTimeNotDeviceTime() {
        // Arrange — a traveling user, phone on Central European time.
        //
        // A zone AHEAD of Central is what discriminates: at 23:30 Central the Berlin
        // phone has already rolled over to the next calendar day, so a formatter that
        // leaks the device zone prints tomorrow's date on today's feed.
        let saved = NSTimeZone.default
        defer { NSTimeZone.default = saved }
        NSTimeZone.default = TimeZone(identifier: "Europe/Berlin")!

        // Thu Jan 15 2026 23:30 Central == Fri Jan 16 2026 06:30 Berlin.
        let instant = chicagoInstant(2026, 1, 15, 23, 30)

        // Act
        let eyebrow = TodayHeader.eyebrow(for: instant)

        // Assert — the town's Thursday, not Berlin's Friday.
        XCTAssertEqual(eyebrow, "THURSDAY, JANUARY 15")
        // …and the instant genuinely discriminates, so the check above has teeth:
        // a Berlin calendar really does report day 16 / weekday 6 (Friday).
        XCTAssertEqual(deviceCalendar(zone: "Europe/Berlin").component(.day, from: instant), 16)
        XCTAssertEqual(deviceCalendar(zone: "Europe/Berlin").component(.weekday, from: instant), 6)
    }

    func testEyebrowHasNoLeadingZeroOnTheDay() {
        // Arrange — Tue Nov 3 2026, a single-digit day in a different month than the
        // shape test, so "d" (not "dd") is what's actually pinned.
        let instant = chicagoInstant(2026, 11, 3, 7, 5)

        // Act
        let eyebrow = TodayHeader.eyebrow(for: instant)

        // Assert
        XCTAssertEqual(eyebrow, "TUESDAY, NOVEMBER 3")
        XCTAssertFalse(eyebrow.contains("NOVEMBER 03"), "The day must not be zero-padded")
    }

    // MARK: - Geometry constants

    func testBarGeometryConstants() {
        // Arrange / Act / Assert — a guard so a later tweak to the bar is deliberate
        // rather than an accidental drift back toward the old scrolling masthead.
        // Grown on 2026-09-18 with the larger map disc (50pt). The guard stays a
        // guard — it just guards the new numbers.
        XCTAssertEqual(TodayHeader.contentHeight, 58)

        // The bar clears the 50pt map disc it carries. `maxHeight` and
        // `collapsedHeight` are gone with the collapse itself (2026-09-19).
        XCTAssertGreaterThan(TodayHeader.contentHeight, 50)
    }

    // MARK: - The chrome leaves on a downward scroll and comes back on an upward one

    /// The rule Jesse asked for, in one function: down hides, up shows, wherever
    /// you are in the feed. This is the part a distance-keyed fade could not do —
    /// it could only bring the bar back by scrolling all the way home.
    func testScrollingDownHidesTheChromeAndScrollingUpBringsItBack() {
        // Down, well past the threshold, deep in the feed.
        XCTAssertTrue(TodayHeader.chromeHidden(wasHidden: false, anchor: 300, offset: 360))
        // Up again, without going anywhere near the top.
        XCTAssertFalse(TodayHeader.chromeHidden(wasHidden: true, anchor: 360, offset: 300))
    }

    /// The top always shows the bar, including through a rubber-band pull past it —
    /// a bounce must not read as "scrolling down" and take the chrome with it.
    func testTheChromeIsAlwaysHomeAtTheTopOfTheFeed() {
        XCTAssertFalse(TodayHeader.chromeHidden(wasHidden: true, anchor: 40, offset: 0))
        XCTAssertFalse(TodayHeader.chromeHidden(wasHidden: true, anchor: 0, offset: -80),
                       "a rubber-band pull past the top is not a downward scroll")
        XCTAssertFalse(TodayHeader.chromeHidden(wasHidden: false, anchor: 0, offset: 20),
                       "the first 24pt belong to the top of the feed")
    }

    /// Travel under `flipDistance` holds whatever the bar was doing. Without this
    /// the bar flickers: a finger resting on the glass and the last millimetres of
    /// inertia both deliver a stream of sub-point deltas in both directions.
    func testTinyMovementsDoNotFlipTheChrome() {
        XCTAssertTrue(TodayHeader.chromeHidden(wasHidden: true, anchor: 300, offset: 302))
        XCTAssertFalse(TodayHeader.chromeHidden(wasHidden: false, anchor: 300, offset: 298))
        XCTAssertTrue(TodayHeader.chromeHidden(wasHidden: true, anchor: 300, offset: 300))
    }

    // MARK: - Any speed: slow drags count, jitter does not (taste.md, 2026-09-24)

    /// Feeds a run of scroll offsets through the rule exactly as `FeedView` does,
    /// frame by frame, and returns whether the bar is hidden after each frame.
    private func drive(_ offsets: [CGFloat], startHidden: Bool) -> [Bool] {
        var hidden = startHidden
        var previous = offsets[0]
        var anchor = offsets[0]
        var states: [Bool] = []
        for offset in offsets.dropFirst() {
            anchor = TodayHeader.directionAnchor(anchor: anchor, previousOffset: previous, offset: offset)
            hidden = TodayHeader.chromeHidden(wasHidden: hidden, anchor: anchor, offset: offset)
            previous = offset
            states.append(hidden)
        }
        return states
    }

    /// A slow drag moves 1–3pt a frame. Measured per frame, none of those steps
    /// ever passed the threshold, so a slow drag never took the bar away.
    func testSlowDragAccumulatesToHide() {
        let down = stride(from: CGFloat(300), through: 400, by: 2).map { $0 }
        XCTAssertEqual(drive(down, startHidden: false).last, true,
                       "50 frames of 2pt down must hide the bar")
    }

    func testSlowDragAccumulatesToShow() {
        let up = stride(from: CGFloat(400), through: 300, by: -2).map { $0 }
        XCTAssertEqual(drive(up, startHidden: true).last, false,
                       "50 frames of 2pt up must bring the bar back")
    }

    /// A finger resting on the glass: ±3pt forever, never a direction.
    func testJitterUnderThresholdDoesNotFlip() {
        let jitter = (0..<60).map { CGFloat(300 + ($0 % 2 == 0 ? 0 : 3)) }
        XCTAssertFalse(drive(jitter, startHidden: false).contains(true), "jitter must not hide the bar")
        XCTAssertFalse(drive(jitter, startHidden: true).contains(false), "jitter must not show the bar")
    }

    // MARK: - The bar's height still does not follow the scroll

    /// The bar's height is a CONSTANT, and this is the guard on that.
    ///
    /// `TodayHeader` deliberately exposes nothing derived from the scroll at all now
    /// — the fade went with the lock (2026-09-21) and no height function preceded
    /// it. The bar is a `safeAreaInset` on the feed's scroll, so its height IS that
    /// scroll's top inset: anything read back off that scroll and fed to the height
    /// rang instead of settling (1420 direction reversals in 1422 samples; the feed
    /// would not scroll at all). If a height is ever derived from scroll again, it
    /// has to be driven by something the scroll does not read back.
    func testTheBarsHeightDoesNotFollowTheScroll() {
        XCTAssertEqual(TodayHeader.contentHeight, 58)
    }

    // MARK: - What the bar carries

    /// The leading lane stays quiet. The old coral bP glyph lived there, and the
    /// current header deliberately puts nothing on that side — the mark is centred
    /// and the map disc is trailing.
    func testBrandLockupLeavesTheLeadingHeaderAreaBlank() throws {
        let bitmap = try renderedHeaderBitmap()

        let colouredPixelCount = bitmap.countPixels(
            xFraction: 0.00..<0.18,
            yFraction: 0.00..<1.00,
            where: isBrandColour
        )

        XCTAssertLessThan(
            colouredPixelCount,
            20,
            "The Today header must not render the old coral bP glyph at leading"
        )
    }

    /// INVERTED on 2026-09-19. This used to assert the centre was empty, from the
    /// round where the Joetown lockup had just been torn out. The header now carries
    /// the real brand mark there on purpose (Jesse: "the actual logo, not just a
    /// font"), so the guard is that the mark is PRESENT — a silent revert to a bare
    /// or text-only centre is what would now be the regression.
    ///
    /// Counted as INK, not as the mark's yellow: since 2026-09-19 the header carries
    /// `BlockPartyWordmark`, the letterforms lifted off their yellow field and tinted
    /// `Hue.ink`, so the yellow is no longer on this part of the screen at all. A
    /// missing asset or a bare centre still fails — paper is not ink.
    func testTheCentreOfTheBarCarriesTheBrandMark() throws {
        let bitmap = try renderedHeaderBitmap()

        let inkPixelCount = bitmap.countPixels(
            xFraction: 0.18..<0.82,
            yFraction: 0.00..<1.00,
            where: isInk
        )

        XCTAssertGreaterThan(
            inkPixelCount,
            400,
            "The centred Block Party wordmark must render in the Today bar"
        )
    }

    /// The map disc is EXACTLY the brand yellow, `#FCE804` (taste.md, 2026-09-24:
    /// never a near-yellow, never a tint). It used to be Liquid Glass tinted with
    /// the yellow at 68%, which read as mustard over photos. A tint or a second
    /// yellow coming back fails here.
    ///
    /// The disc sits `rowInset 4 + glyphTap 44 + controlGap 8` in from the trailing
    /// edge and is 50pt wide, so on a 390pt bar its centre is (309, 29). The ring
    /// sampled is 19pt out: clear of the ~12pt pin and of the rim's antialiasing.
    func testMapDiscIsExactBrandYellow() throws {
        let bitmap = try renderedHeaderBitmap()
        let scale = 2.0
        let centre = (x: 309.0, y: Double(TodayHeader.contentHeight) / 2)

        for step in 0..<8 {
            let angle = Double(step) * .pi / 4
            let x = Int((centre.x + 19 * cos(angle)) * scale)
            let y = Int((centre.y + 19 * sin(angle)) * scale)
            let (r, g, b, a) = bitmap.pixel(x: x, y: y)
            XCTAssertEqual(a, 255, "disc must be opaque at (\(x), \(y))")
            XCTAssertLessThanOrEqual(abs(Int(r) - 0xFC), 2, "red off at (\(x), \(y)): \(r)")
            XCTAssertLessThanOrEqual(abs(Int(g) - 0xE8), 2, "green off at (\(x), \(y)): \(g)")
            XCTAssertLessThanOrEqual(abs(Int(b) - 0x04), 2, "blue off at (\(x), \(y)): \(b)")
        }
    }

    private func renderedHeaderBitmap() throws -> HeaderBitmap {
        let renderer = ImageRenderer(
            content: TodayTopBar()
                .frame(width: 390, height: TodayHeader.contentHeight)
                .background(Hue.paper)
        )
        renderer.scale = 2
        return try HeaderBitmap(cgImage: XCTUnwrap(renderer.cgImage))
    }

    private func isInk(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) -> Bool {
        alpha > 200 && max(red, green, blue) < 90
    }

    private func isBrandColour(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) -> Bool {
        guard alpha > 200 else { return false }
        let high = max(red, green, blue)
        let low = min(red, green, blue)
        return high > 110 && high - low > 55
    }

    // MARK: - Signed-in profile photo

    /// The compact menu control must receive the avatar stored in `town_profiles`.
    /// Before this regression fix the Today bar never loaded a profile at all and
    /// always rendered the hard-coded person glyph, even when this field was set.
    func testHeaderProfileRefreshPublishesTheSavedAvatar() async {
        let savedAvatar = "https://example.com/avatars/neighbor.jpg"
        let model = TodayHeaderProfileModel {
            TownProfile(
                userId: "neighbor-1",
                displayName: "Taylor",
                avatarUrl: savedAvatar,
                interests: ["trails"],
                onboardedAt: "2026-08-01T12:00:00Z"
            )
        }

        XCTAssertNil(model.avatarUrl)

        await model.refresh()

        XCTAssertEqual(model.avatarUrl, savedAvatar)
    }
}

private struct HeaderBitmap {
    let width: Int
    let height: Int
    private let rgba: [UInt8]

    init(cgImage: CGImage) throws {
        let pixelWidth = cgImage.width
        let pixelHeight = cgImage.height

        var bytes = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        let rendered = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(
                data: storage.baseAddress,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: pixelWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(
                cgImage,
                in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
            )
            return true
        }
        guard rendered else { throw HeaderBitmapError.contextCreationFailed }
        width = pixelWidth
        height = pixelHeight
        rgba = bytes
    }

    func pixel(x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let offset = (y * width + x) * 4
        return (rgba[offset], rgba[offset + 1], rgba[offset + 2], rgba[offset + 3])
    }

    func countPixels(
        xFraction: Range<Double>,
        yFraction: Range<Double>,
        where predicate: (_ red: UInt8, _ green: UInt8, _ blue: UInt8, _ alpha: UInt8) -> Bool
    ) -> Int {
        let xStart = max(0, Int(Double(width) * xFraction.lowerBound))
        let xEnd = min(width, Int(Double(width) * xFraction.upperBound))
        let yStart = max(0, Int(Double(height) * yFraction.lowerBound))
        let yEnd = min(height, Int(Double(height) * yFraction.upperBound))

        var count = 0
        for y in yStart..<yEnd {
            for x in xStart..<xEnd {
                let offset = (y * width + x) * 4
                if predicate(rgba[offset], rgba[offset + 1], rgba[offset + 2], rgba[offset + 3]) {
                    count += 1
                }
            }
        }
        return count
    }
}

private enum HeaderBitmapError: Error {
    case contextCreationFailed
}

// MARK: - The appearance switch behind the bar's ⋮ button

/// System / Light / Dark, the app's one preference. It lives in the town menu, which
/// is what this bar's trailing ⋮ opens — so its rules are locked down beside the
/// bar's, in a file the test target already compiles.
///
/// (A NEW file under `BlockPartyTests/` does not run until it is registered in four
/// places in `project.pbxproj`; that has silently swallowed a suite here before. See
/// CLAUDE.md.)
@MainActor
final class AppearancePreferenceTests: XCTestCase {

    /// A throwaway `UserDefaults` suite per test, so nothing here can touch the
    /// simulator's real `bp.appearance` and change what a screenshot run sees.
    private func makeDefaults(_ name: String = #function) throws -> (UserDefaults, String) {
        let suite = "bp.appearance.tests.\(name).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (defaults, suite)
    }

    // MARK: The three states

    /// System is NOT Light. `nil` is the absence of a request, which is what lets
    /// the phone keep deciding — mapping it to `.light` would pin the app light for
    /// everyone who never opened the menu.
    func testSystemMapsToNoRequestWhileLightAndDarkAreRequests() {
        XCTAssertNil(AppearanceChoice.system.colorScheme)
        XCTAssertEqual(AppearanceChoice.light.colorScheme, .light)
        XCTAssertEqual(AppearanceChoice.dark.colorScheme, .dark)
    }

    /// The same distinction in the UIKit spelling used by `ShareCenter`'s own
    /// window, which the root's `.preferredColorScheme` cannot reach.
    func testSystemIsUnspecifiedInTheUIKitSpellingToo() {
        XCTAssertEqual(AppearanceChoice.system.interfaceStyle, .unspecified)
        XCTAssertEqual(AppearanceChoice.light.interfaceStyle, .light)
        XCTAssertEqual(AppearanceChoice.dark.interfaceStyle, .dark)
    }

    func testTheControlOffersExactlyThreeOptionsInMenuOrder() {
        XCTAssertEqual(AppearanceChoice.allCases, [.system, .light, .dark])
        XCTAssertEqual(AppearanceChoice.allCases.map(\.label), ["System", "Light", "Dark"])
    }

    // MARK: Persistence

    /// The `bp.*` namespace is required and a `hygge.*` key must never come back —
    /// see the rename section of CLAUDE.md.
    func testTheStoredKeyIsInTheBPNamespace() {
        XCTAssertEqual(AppearanceStore.defaultsKey, "bp.appearance")
        XCTAssertFalse(AppearanceStore.defaultsKey.hasPrefix("hygge."))
    }

    func testDefaultsToSystemWhenNothingHasEverBeenStored() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(AppearanceStore(defaults: defaults).choice, .system)
    }

    /// A relaunch, simulated the way `UtilityPrefsStore`'s tests do it: a SECOND
    /// store built over the same suite, so it reads bytes that were genuinely
    /// written rather than an in-memory value handed between two references.
    func testAChoiceSurvivesARelaunch() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let firstLaunch = AppearanceStore(defaults: defaults)
        firstLaunch.choice = .dark

        XCTAssertEqual(defaults.string(forKey: AppearanceStore.defaultsKey), "dark")
        XCTAssertEqual(AppearanceStore(defaults: defaults).choice, .dark)
    }

    /// Including the way back. Choosing System again must WRITE "system", not clear
    /// the key and leave a stale "dark" behind it.
    func testChoosingSystemAgainIsPersistedAsSystem() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = AppearanceStore(defaults: defaults)
        store.choice = .dark
        store.choice = .system

        XCTAssertEqual(defaults.string(forKey: AppearanceStore.defaultsKey), "system")
        XCTAssertEqual(AppearanceStore(defaults: defaults).choice, .system)
        XCTAssertNil(AppearanceStore(defaults: defaults).choice.colorScheme)
    }

    /// Forward compat: a value this build does not know is "follow the phone", not
    /// a crash and not a guess at what the neighbour meant.
    func testAnUnreadableStoredValueFallsBackToSystem() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("sepia", forKey: AppearanceStore.defaultsKey)

        XCTAssertEqual(AppearanceStore(defaults: defaults).choice, .system)
        XCTAssertEqual(AppearanceChoice.stored(nil), .system)
    }
}
