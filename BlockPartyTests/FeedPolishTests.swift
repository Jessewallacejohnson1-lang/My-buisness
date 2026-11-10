//
//  FeedPolishTests.swift
//  BlockPartyTests — the Town feed's Reduce Motion contract, its "no placeholder
//  values" product rule and the Event page route.
//
//  These are the parts of the polish pass that are decidable without a screenshot.
//  Layout and feel are verified in the simulator; the rules below are verified here
//  so they cannot regress silently.
//

import SwiftUI
import UIKit
import XCTest
@testable import BlockParty

final class FeedMotionTests: XCTestCase {

    func testReduceMotionRemovesEveryPressScaleAndSubstitutesAFade() {
        XCTAssertEqual(FeedMotion.pressScale(isPressed: true, reduceMotion: true), 1)
        XCTAssertEqual(FeedMotion.pressScale(isPressed: false, reduceMotion: true), 1)

        XCTAssertLessThan(
            FeedMotion.pressOpacity(isPressed: true, reduceMotion: true),
            1,
            "Reduce Motion carries the press with a value dip instead"
        )
        XCTAssertEqual(FeedMotion.pressOpacity(isPressed: true, reduceMotion: false), 1)
    }

    func testFeedPressStaysQuietWhileASmallIconIsFelt() {
        let quiet = FeedMotion.pressScale(isPressed: true, reduceMotion: false)
        let icon = Press.depth(width: 44)

        XCTAssertEqual(quiet, FeedMotion.quietPress)
        // Jesse, 2026-10-23: at 0.985 only the photo looked pressed; the whole card moves now.
        XCTAssertGreaterThanOrEqual(quiet, 0.97, "A whole card presses in a little, never more")
        XCTAssertLessThan(icon, quiet, "A small icon sinks deeper, or it barely moves")
    }

    /// Jesse's feel check on the three press styles (codebase-health 20).
    func testThePressNumbers() {
        XCTAssertEqual(Press.depth(width: 20), 0.88, "the deepest")
        XCTAssertEqual(Press.depth(width: 44), 0.886, accuracy: 0.001, "an icon")
        XCTAssertEqual(Press.depth(width: 100), 0.95, accuracy: 0.001, "Search's logos, as drawn on Jesse's mockup")
        XCTAssertEqual(Press.depth(width: 358), 0.97, "a Town card")
        XCTAssertEqual(Press.inSeconds, 0.08)
        XCTAssertEqual(Press.backResponse, 0.28)
        XCTAssertEqual(Press.backDamping, 0.68)
        XCTAssertEqual(Press.dimmed, 0.45)
        XCTAssertEqual(Press.rowShade, 0.05)
    }
}

@MainActor
final class FeedCopyTests: XCTestCase {

    // MARK: Error copy

    func testEveryFeedErrorTitleIsCalmSentenceCaseHouseVoice() {
        let titles = [
            FeedStateCopy.townEventsUnavailable,
            FeedStateCopy.offline,
        ]

        for title in titles {
            XCTAssertFalse(title.contains("!"), "No exclamation marks: \(title)")
            XCTAssertFalse(title.lowercased().contains("error"), "No error codes: \(title)")
            XCTAssertFalse(title.lowercased().contains("failed"), "Plain verbs: \(title)")
            XCTAssertTrue(title.hasSuffix("."), "One finished sentence: \(title)")
            let first = try? XCTUnwrap(title.first)
            XCTAssertEqual(String(first ?? " "), String(first ?? " ").uppercased())
        }

        XCTAssertEqual(FeedStateCopy.retryAction, "Try again")
        XCTAssertEqual(FeedStateCopy.retryMessage, "Check your connection and try again.")
    }
}

// MARK: - Tokens: one definition each, and both appearances

@MainActor
final class HueTokenTests: XCTestCase {

    private func hex(_ color: Color, _ style: UIUserInterfaceStyle) -> String {
        let resolved = UIColor(color)
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(
            format: "#%02X%02X%02X",
            Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded())
        )
    }

    func testEveryNeutralTokenCarriesBothAppearances() {
        let tokens: [(String, Color)] = [
            ("ink", Hue.ink), ("paper", Hue.paper), ("surface", Hue.surface),
            ("inkSecondary", Hue.inkSecondary), ("hairline", Hue.hairline),
            ("fill", Hue.fill), ("edge", Hue.edge),
        ]

        for (name, color) in tokens {
            XCTAssertNotEqual(
                hex(color, .light), hex(color, .dark),
                "\(name) renders the same in both appearances — it is not dynamic"
            )
        }
    }

    func testThePageAndTheCardAreTheAgreedDarkValues() {
        XCTAssertEqual(hex(Hue.paper, .light), "#FAFAF7")
        XCTAssertEqual(hex(Hue.paper, .dark), "#141412")
        XCTAssertEqual(hex(Hue.surface, .light), "#FFFFFF")
        XCTAssertEqual(hex(Hue.surface, .dark), "#1D1D1A")
        // A card is still a lighter object sitting on the page, not a darker hole.
        XCTAssertNotEqual(hex(Hue.surface, .dark), hex(Hue.paper, .dark))
    }

    /// The map is light cartography in BOTH appearances, so anything drawn on it
    /// keeps its light value — a civic badge that followed `Hue.ink` into the dark
    /// would be white on warm paper.
    func testMarkersOverTheMapDoNotFollowTheSystemAppearance() {
        XCTAssertEqual(hex(Hue.ink.onLightCanvas, .dark), hex(Hue.ink, .light))
        XCTAssertEqual(hex(Hue.surface.onLightCanvas, .dark), hex(Hue.surface, .light))
        XCTAssertEqual(BasemapPalette.land, "#ECECF4")
        XCTAssertEqual(BasemapPalette.road, "#FFFFFF")
    }
}

// MARK: - Directions, defined once

final class DirectionsTests: XCTestCase {

    func testNoPlaceOffersNoDirections() {
        for location in [nil, "", "   "] as [String?] {
            XCTAssertNil(
                Directions.url(forPlace: location),
                "A blank location must not produce a search for the whole town"
            )
        }
    }

    func testAPlaceSearchesForItInThisTown() throws {
        let url = try XCTUnwrap(Directions.url(forPlace: "Local Blend"))

        XCTAssertEqual(url.host, "maps.apple.com")
        let query = try XCTUnwrap(url.query?.removingPercentEncoding)
        XCTAssertTrue(query.contains("Local Blend"))
        XCTAssertTrue(query.contains(Town.display))
    }
}

// MARK: - The event card's when line

final class FeedWhenLineTests: XCTestCase {

    /// Wednesday, Sep 24 2026, 10:00 in a fixed zone, so the relative words don't
    /// depend on when or where the test runs.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }()
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 10))!
    }

    private func line(_ date: String?, _ time: String?, fallback: String = "") -> FeedWhenLine? {
        FeedWhenLine(eventDate: date, startTime: time, fallbackDate: fallback, now: now)
    }

    func testCloseDatesReadAsWords() {
        XCTAssertEqual(line("2026-09-24", "11 AM")?.text, "Today · 11 AM")
        XCTAssertEqual(line("2026-09-24", "7pm")?.text, "Tonight · 7 PM")
        XCTAssertEqual(line("2026-09-24", nil)?.text, "Today")
        XCTAssertEqual(line("2026-09-25", "noon")?.text, "Tomorrow · Noon")
    }

    func testLaterDatesReadAsAWeekdayDate() {
        let later = line("2026-10-02", "7:30 PM")
        XCTAssertEqual(later?.text, "Fri, Oct 2 · 7:30 PM")
        XCTAssertEqual(later?.spoken, "Friday, October 2 at 7:30 PM")
    }

    func testDatesMoreThanSixMonthsOutCarryTheYear() {
        XCTAssertEqual(line("2027-06-05", nil)?.text, "Sat, Jun 5, 2027")
    }

    func testAnUnreadableTimeIsShownAsWrittenNotDropped() {
        let vague = line("2026-10-02", "around 6")
        XCTAssertEqual(vague?.text, "Fri, Oct 2 · around 6")
        XCTAssertEqual(vague?.spoken, "Friday, October 2, around 6")
    }

    func testMissingHalvesDropCleanly() {
        XCTAssertEqual(line(nil, "7 PM")?.text, "7 PM")
        XCTAssertEqual(line(nil, nil, fallback: "FRI JUL 24")?.text, "Fri Jul 24")
        XCTAssertNil(line(nil, "  "))
        XCTAssertNil(line("not-a-date", nil))
    }

    private func card(_ date: String, _ time: String?, endAt: Date? = nil, allDay: Bool = false,
                      cancelled: Bool = false) -> FeedCardItem {
        FeedCardItem(id: "n", title: "N", dateChip: "", metaLine: "", image: .fallback, recurrence: nil,
                     goingCount: 0, goingAvatars: [], likeCount: 0, isLiked: false, isJoined: false,
                     eventDate: date, startTime: time, endAt: endAt, allDay: allDay, cancelled: cancelled)
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    func testNowRunsFromTheStartToTheEnd() {
        let prints = card("2026-09-24", "8 AM", endAt: at(24, 16, 30))
        XCTAssertFalse(prints.isNow(at: at(24, 7, 59)))
        XCTAssertTrue(prints.isNow(at: at(24, 8)))
        XCTAssertTrue(prints.isNow(at: at(24, 16, 29)))
        XCTAssertFalse(prints.isNow(at: at(24, 16, 30)), "over at its end")
        XCTAssertFalse(card("2026-09-24", "8 AM", endAt: at(24, 16, 30), cancelled: true).isNow(at: at(24, 9)))
    }

    /// A game is Now for three hours (game-card 02); once its final is in it is over: never Now, and its
    /// chip shows the day alone.
    func testAGameWhoseFinalIsInShowsItsDayAndIsNeverNow() throws {
        var game = card("2026-09-24", "7 PM")
        game.game = try JSONDecoder().decode(Game.self, from: Data(
            #"{"sport":"Football","teams":[{"name":"Saint John's"},{"name":"Concordia"}]}"#.utf8))
        XCTAssertTrue(game.isNow(at: at(24, 21, 30)), "a game runs three hours, not two")
        XCTAssertFalse(game.isNow(at: at(24, 22)))
        game.game = try JSONDecoder().decode(Game.self, from: Data(
            #"{"sport":"Football","final":[33,23],"teams":[{"name":"Saint John's"},{"name":"Concordia"}]}"#.utf8))
        XCTAssertFalse(game.isNow(at: at(24, 19, 30)))
        XCTAssertEqual(game.whenLine, FeedWhenLine(eventDate: "2026-09-24", startTime: nil), "the day, no time")
    }

    func testNowLastsTwoHoursWithNoEnd() {
        let concert = card("2026-09-24", "7:30 PM")
        XCTAssertTrue(concert.isNow(at: at(24, 21, 29)))
        XCTAssertFalse(concert.isNow(at: at(24, 21, 30)))
    }

    @MainActor
    func testAPlaceBeingOpenIsNeverNow() {
        var gallery = card("2026-09-24", "2 PM", endAt: at(24, 20))
        gallery.liveKind = false
        XCTAssertFalse(gallery.isNow(at: at(24, 15)))
        XCTAssertEqual(TodayBubbleRules.phase(gallery, now: at(24, 15)), .untimed, "no live ring on the map")
    }

    /// The Town card's time line ends with who it's for by age when a source says it (inside-cards 30):
    /// "Thu, Sep 24 · 7 PM · 21+", read aloud the same; with no age, the time line as it was.
    func testTheCardTimeEndsWithTheAge() {
        var bash = card("2026-09-24", "7 PM")
        XCTAssertEqual(bash.cardWhen(at: at(20, 12)), bash.whenLine(at: at(20, 12)), "no age, no change")
        bash.ages = "21+"
        let line = bash.cardWhen(at: at(20, 12))
        XCTAssertEqual(line?.text, (bash.whenLine(at: at(20, 12))?.text ?? "") + " · 21+")
        XCTAssertEqual(line?.spoken, (bash.whenLine(at: at(20, 12))?.spoken ?? "") + ", 21+")
    }

    /// A place open rather than a happening on says how long, or its start reads as over.
    func testAPlaceBeingOpenSaysUntilWhen() {
        var gallery = card("2026-09-24", "2 PM", endAt: at(24, 20))
        gallery.liveKind = false
        XCTAssertEqual(gallery.whenLine(at: at(24, 15))?.text, "Until 8 PM")
        XCTAssertEqual(gallery.whenLine(at: at(24, 15))?.spoken, "Open until 8 PM")
        XCTAssertEqual(gallery.whenLine(at: at(24, 13)), gallery.whenLine, "not open yet")
        var run = card("2026-09-16", "4 PM", endAt: at(26, 0))
        run.liveKind = false
        XCTAssertEqual(run.whenLine(at: at(24, 10))?.text, "Until Fri", "its end at midnight is the day before")
        XCTAssertEqual(run.whenLine(at: at(17, 10))?.text, "Until Sep 25")
        var concert = card("2026-09-24", "7 PM")
        concert.liveKind = true
        XCTAssertEqual(concert.whenLine(at: at(24, 19, 30)), concert.whenLine, "a happening says Now, elsewhere")
    }

    func testNowIsInTheTownsTimeWhateverThePhoneIsSetTo() {
        let workshop = card("2026-09-24", "10 AM", endAt: at(24, 16))
        XCTAssertTrue(workshop.isNow(at: at(24, 10)), "10 AM in St. Joseph, wherever the phone thinks it is")
        XCTAssertFalse(workshop.isNow(at: at(24, 9, 59)))
    }

    func testAOneDayAllDayListingIsNeverNow() {
        XCTAssertFalse(card("2026-09-24", nil, allDay: true).isNow(at: at(24, 12)))
        XCTAssertFalse(card("2026-09-24", nil, endAt: at(25, 0), allDay: true).isNow(at: at(24, 12)))
        XCTAssertFalse(card("2026-09-24", "TBA").isNow(at: at(24, 12)), "no time it can read")
    }

    func testTheWhereLineNeverRepeatsTheTime() {
        let timeOnly = FeedCardItem(
            id: "t", title: "T", dateChip: "", metaLine: "7 PM",
            image: .fallback, recurrence: nil,
            goingCount: 0, goingAvatars: [],
            likeCount: 0, isLiked: false, isJoined: false,
            startTime: "7 PM"
        )
        XCTAssertNil(timeOnly.whereLine)
    }
}

// MARK: - The action row's short counts

final class FeedShortCountTests: XCTestCase {

    func testCountsReadTheWayInstagramPrintsThem() {
        let cases: [(Int, String)] = [
            (0, "0"), (999, "999"), (3_778, "3,778"), (9_999, "9,999"),
            (10_000, "10K"), (12_480, "12.4K"), (220_000, "220K"),
            (999_999, "999.9K"), (1_250_000, "1.2M"), (3_000_000, "3M"),
        ]
        for (value, expected) in cases {
            XCTAssertEqual(FeedEventCardActionRow.shortCount(value), expected, "\(value)")
        }
    }
}

/// A host's logo in its small circle (`LogoFit`, Jesse 2026-10-24, 2026-11-10): a round badge fills the
/// circle, a square or a wordmark sits wholly inside it.
final class LogoFitTests: XCTestCase {
    /// A 200-pixel picture with `draw` inside a 40-pixel empty border.
    private func logo(transparent: Bool = false, _ draw: (CGContext, CGRect) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = !transparent
        return UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200), format: format).image { ctx in
            if !transparent { UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200)) }
            UIColor(red: 0.9, green: 0.4, blue: 0.1, alpha: 1).setFill()
            draw(ctx.cgContext, CGRect(x: 40, y: 40, width: 120, height: 120))
        }
    }

    func testARoundBadgeFillsTheCircleAndLosesItsBorder() {
        let fit = LogoFit(logo { $0.fillEllipse(in: $1) })
        XCTAssertEqual(fit.reach, 0.5, accuracy: 0.03, "a badge's edge is its circle's")
        XCTAssertEqual(fit.image.size.width, 120, accuracy: 6)
    }

    func testATransparentRoundBadgeIsRoundToo() {
        XCTAssertEqual(LogoFit(logo(transparent: true) { $0.fillEllipse(in: $1) }).reach, 0.5, accuracy: 0.03)
    }

    /// The House's square logo broke out of its circle (Jesse, 2026-11-10): its corners reach half its
    /// diagonal, so it is drawn small enough for them to stay inside.
    func testASquaresCornersStayInsideTheCircle() {
        let fit = LogoFit(logo { $0.fill($1) })
        XCTAssertEqual(fit.reach, 0.5 * CGFloat(2).squareRoot(), accuracy: 0.02)
    }

    /// Sal's wide logo lost its ends under the ring: a wordmark reaches its corners too.
    func testAWordmarkKeepsItsEnds() {
        let word = LogoFit(logo { ctx, _ in ctx.fill(CGRect(x: 20, y: 90, width: 160, height: 20)) })
        XCTAssertEqual(word.image.size.width, 160, accuracy: 6)
        XCTAssertEqual(word.image.size.height, 20, accuracy: 6)
        let corner = CGFloat(80 * 80 + 10 * 10).squareRoot() / 160
        XCTAssertGreaterThanOrEqual(word.reach, corner)
    }
}
