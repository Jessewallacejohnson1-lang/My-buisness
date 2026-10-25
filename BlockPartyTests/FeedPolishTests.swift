//
//  FeedPolishTests.swift
//  BlockPartyTests — the Today feed's Reduce Motion contract, its "no placeholder
//  values" product rule and the event-detail route.
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

    // MARK: Reduce Motion degrades EVERY feed animation to a cross-fade

    func testReduceMotionTurnsEveryFeedAnimationIntoACrossFade() {
        let specs: [(name: String, spec: FeedMotion.Spec)] = [
            ("news expand", FeedMotion.newsExpandSpec(reduceMotion: true)),
            ("quiet press", FeedMotion.quietPressSpec(reduceMotion: true)),
            ("plus press", FeedMarkPress.spec(reduceMotion: true)),
        ]

        for entry in specs {
            XCTAssertFalse(entry.spec.usesSpring, "\(entry.name) must not spring")
            XCTAssertFalse(entry.spec.usesScale, "\(entry.name) must not scale")
            XCTAssertFalse(entry.spec.usesOffset, "\(entry.name) must not move")
            XCTAssertTrue(entry.spec.isCrossFade, "\(entry.name) must be a cross-fade")
            XCTAssertEqual(entry.spec.duration, FeedMotion.crossFade)
        }
    }

    func testFullMotionKeepsTheSignatureExpandSpringy() {
        let spec = FeedMotion.newsExpandSpec(reduceMotion: false)

        XCTAssertTrue(spec.usesSpring)
        XCTAssertTrue(spec.usesOffset, "The body rises as it fades in")
        XCTAssertFalse(spec.usesScale, "The card grows; it does not zoom")
        XCTAssertEqual(spec.duration, FeedMotion.expandResponse)
        XCTAssertFalse(spec.isCrossFade)
    }

    func testReduceMotionExpandIsAPlainTimedFade() {
        XCTAssertEqual(
            FeedMotion.newsExpand(reduceMotion: true),
            .easeInOut(duration: FeedMotion.crossFade)
        )
        XCTAssertNotEqual(
            FeedMotion.newsExpand(reduceMotion: false),
            FeedMotion.newsExpand(reduceMotion: true)
        )
    }

    func testReduceMotionRemovesEveryPressScaleAndSubstitutesAFade() {
        XCTAssertEqual(FeedMotion.pressScale(isPressed: true, reduceMotion: true), 1)
        XCTAssertEqual(FeedMotion.pressScale(isPressed: false, reduceMotion: true), 1)
        XCTAssertEqual(FeedMarkPress.scale(isPressed: true, reduceMotion: true), 1)

        XCTAssertLessThan(
            FeedMotion.pressOpacity(isPressed: true, reduceMotion: true),
            1,
            "Reduce Motion carries the press with a value dip instead"
        )
        XCTAssertEqual(FeedMotion.pressOpacity(isPressed: true, reduceMotion: false), 1)
    }

    func testFeedPressStaysQuietWhileThePlusStaysEmphatic() {
        let quiet = FeedMotion.pressScale(isPressed: true, reduceMotion: false)
        let plus = FeedMarkPress.scale(isPressed: true, reduceMotion: false)

        XCTAssertEqual(quiet, FeedMotion.quietPress)
        // Jesse, 2026-10-23: at 0.985 only the photo looked pressed; the whole card moves now.
        XCTAssertGreaterThanOrEqual(quiet, 0.97, "A whole card presses in a little, never more")
        XCTAssertLessThan(plus, quiet, "Only the + press is allowed to be felt")
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
        FeedWhenLine(eventDate: date, startTime: time, fallbackDate: fallback, now: now, calendar: calendar)
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
                     goingCount: 0, goingAvatars: [], likeCount: 0, isLiked: false, isSaved: false, isJoined: false,
                     eventDate: date, startTime: time, endAt: endAt, allDay: allDay, cancelled: cancelled)
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    func testNowRunsFromTheStartToTheEnd() {
        let prints = card("2026-09-24", "8 AM", endAt: at(24, 16, 30))
        XCTAssertFalse(prints.isNow(at: at(24, 7, 59), calendar: calendar))
        XCTAssertTrue(prints.isNow(at: at(24, 8), calendar: calendar))
        XCTAssertTrue(prints.isNow(at: at(24, 16, 29), calendar: calendar))
        XCTAssertFalse(prints.isNow(at: at(24, 16, 30), calendar: calendar), "over at its end")
        XCTAssertFalse(card("2026-09-24", "8 AM", endAt: at(24, 16, 30), cancelled: true).isNow(at: at(24, 9), calendar: calendar))
    }

    /// A game is Now for three hours (game-card 02); once its final is in it is over: never Now, and its
    /// chip shows the day alone.
    func testAGameWhoseFinalIsInShowsItsDayAndIsNeverNow() throws {
        var game = card("2026-09-24", "7 PM")
        game.game = try JSONDecoder().decode(Game.self, from: Data(
            #"{"sport":"Football","teams":[{"name":"Saint John's"},{"name":"Concordia"}]}"#.utf8))
        XCTAssertTrue(game.isNow(at: at(24, 21, 30), calendar: calendar), "a game runs three hours, not two")
        XCTAssertFalse(game.isNow(at: at(24, 22), calendar: calendar))
        game.game = try JSONDecoder().decode(Game.self, from: Data(
            #"{"sport":"Football","final":[33,23],"teams":[{"name":"Saint John's"},{"name":"Concordia"}]}"#.utf8))
        XCTAssertFalse(game.isNow(at: at(24, 19, 30), calendar: calendar))
        XCTAssertEqual(game.whenLine, FeedWhenLine(eventDate: "2026-09-24", startTime: nil), "the day, no time")
    }

    func testNowLastsTwoHoursWithNoEnd() {
        let concert = card("2026-09-24", "7:30 PM")
        XCTAssertTrue(concert.isNow(at: at(24, 21, 29), calendar: calendar))
        XCTAssertFalse(concert.isNow(at: at(24, 21, 30), calendar: calendar))
    }

    func testARunOverDaysIsNowTheWholeTime() {
        let kiln = card("2026-09-16", "4 PM", endAt: at(26, 0))
        XCTAssertFalse(kiln.isNow(at: at(16, 15, 59), calendar: calendar))
        XCTAssertTrue(kiln.isNow(at: at(20, 3), calendar: calendar), "the kiln burns through the night")
        XCTAssertFalse(kiln.isNow(at: at(26, 0), calendar: calendar))
        let festival = card("2026-09-21", nil, endAt: at(27, 0), allDay: true)
        XCTAssertTrue(festival.isNow(at: at(24, 10), calendar: calendar), "an all-day run over days")
        XCTAssertFalse(festival.isNow(at: at(27, 0), calendar: calendar))
    }

    func testNowIsInTheTownsTimeWhateverThePhoneIsSetTo() {
        var pacific = calendar
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let workshop = card("2026-09-24", "10 AM", endAt: at(24, 16))
        XCTAssertTrue(workshop.isNow(at: at(24, 10)), "10 AM in St. Joseph, wherever the phone thinks it is")
        XCTAssertFalse(workshop.isNow(at: at(24, 9, 59)))
        XCTAssertFalse(workshop.isNow(at: at(24, 10), calendar: pacific), "a Pacific calendar puts its start two hours later")
    }

    func testAOneDayAllDayListingIsNeverNow() {
        XCTAssertFalse(card("2026-09-24", nil, allDay: true).isNow(at: at(24, 12), calendar: calendar))
        XCTAssertFalse(card("2026-09-24", nil, endAt: at(25, 0), allDay: true).isNow(at: at(24, 12), calendar: calendar))
        XCTAssertFalse(card("2026-09-24", "TBA").isNow(at: at(24, 12), calendar: calendar), "no time it can read")
    }

    func testTheWhereLineNeverRepeatsTheTime() {
        let timeOnly = FeedCardItem(
            id: "t", title: "T", dateChip: "", metaLine: "7 PM",
            image: .fallback, recurrence: nil,
            goingCount: 0, goingAvatars: [],
            likeCount: 0, isLiked: false, isSaved: false, isJoined: false,
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

/// A host's logo in its small circle (`LogoFit`, Jesse 2026-10-24): a round badge fills the circle,
/// anything else only loses its empty border.
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
        XCTAssertTrue(fit.round)
        XCTAssertEqual(fit.image.size.width, 120, accuracy: 6)
    }

    func testATransparentRoundBadgeIsRoundToo() {
        XCTAssertTrue(LogoFit(logo(transparent: true) { $0.fillEllipse(in: $1) }).round)
    }

    func testASquareOrAWordmarkStaysInsideTheCircle() {
        XCTAssertFalse(LogoFit(logo { $0.fill($1) }).round, "a square's corners are full")
        let word = LogoFit(logo { ctx, _ in ctx.fill(CGRect(x: 20, y: 90, width: 160, height: 20)) })
        XCTAssertFalse(word.round)
        XCTAssertEqual(word.image.size.width, 160, accuracy: 6)
        XCTAssertEqual(word.image.size.height, 20, accuracy: 6)
    }
}
