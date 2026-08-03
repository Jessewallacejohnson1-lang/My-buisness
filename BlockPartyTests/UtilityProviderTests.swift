//
//  UtilityProviderTests.swift
//  BlockPartyTests — Phase 3 (design + motion) provider guards for the Today
//  Utility Row. Two independent concerns, both deterministic (no network):
//
//   A. GARBAGE parity. `GarbageSchedule.isRecyclingWeek` is anchored ARITHMETIC —
//      weeks-since-anchor mod 2 — not a lookup table, so the failure mode isn't
//      "one wrong Thursday", it's "every Thursday from here on is inverted". The
//      sibling GarbageScheduleTests pins three days around the anchor; these walk
//      six consecutive Thursdays, and then six more across a YEAR boundary, so a
//      phase slip (or a within-year accident) can't pass. Ground truth: refuse
//      runs every Thursday, recycling every OTHER Thursday ("Blue Week"), anchor
//      Thu 2026-01-15 — City of St. Joseph MN 2026 Recycling Calendar, recorded in
//      docs/UTILITY_ROW.md.
//
//   B. ROADS empty state. Zero active notices already reads "All clear"; Phase 3
//      additionally requires the tile to DE-EMPHASISE (render its muted variant)
//      instead of shouting the amber warning gradient. `RoadsTileProvider.fetch`
//      needs the live backend, so the tests exercise the PURE mapping
//      (`RoadsTileProvider.value(for:)`) that fetch is expected to delegate to —
//      no test here touches TownStatusAPI, AuthStore, or the network.
//
//  Both concerns share the file because both are "what a provider produces",
//  and both are pure value assertions.
//

import XCTest
@testable import BlockParty

@MainActor
final class UtilityProviderTests: XCTestCase {

    // MARK: - Fixtures

    /// Apple weekday numbering: 1=Sun … 5=Thu … 7=Sat. St. Joseph collects Thursday.
    private static let thursday = 5

    /// Six weeks of the every-other-week cycle, starting ON a recycling week.
    private static let expectedParity: [Bool] = [true, false, true, false, true, false]

    /// Whole weeks from the 2026-01-15 anchor to Thu 2026-12-03 — an EVEN offset,
    /// so the December walk starts on a recycling week just like the anchor walk.
    /// Derived (not a literal date) so the test proves the arithmetic, not a table.
    private static let weeksFromAnchorToDecember = 46

    /// Fixed calendar: gregorian, St. Joe timezone, Sunday-first — same shape as
    /// GarbageScheduleTests, pinned so a foreign device zone can't move a pickup.
    private func chicagoCalendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_US_POSIX")
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        c.firstWeekday = 1   // Sunday
        return c
    }

    /// "Thu 2026-01-15" — readable failure messages, and the assertion that a
    /// derived date really is the day the comment claims.
    private func dayLabel(_ date: Date, _ cal: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE yyyy-MM-dd"
        return f.string(from: date)
    }

    /// `count` consecutive same-weekday days at 00:00 town time, from `start`.
    private func consecutiveWeeks(from start: Date, count: Int, _ cal: Calendar) throws -> [Date] {
        let base = cal.startOfDay(for: start)
        return try (0..<count).map { index in
            try XCTUnwrap(cal.date(byAdding: .day, value: 7 * index, to: base),
                          "Could not derive week \(index) from \(self.dayLabel(base, cal))")
        }
    }

    /// One active roads notice. Mirrors the seeded `town_status` row shape
    /// (migration 20260724120000) — `status` is provider-defined free text.
    private func roadsNotice(headline: String, updatedAt: Date) -> TownStatusNotice {
        TownStatusNotice(id: UUID().uuidString,
                         town: "st-joseph-mn",
                         kind: "roads",
                         status: "advisory",
                         headline: headline,
                         detail: nil,
                         link: nil,
                         active: true,
                         updatedAt: updatedAt)
    }

    // MARK: - A. Garbage: alternating-week parity against a real calendar

    func testRecyclingParityHoldsForSixConsecutiveUpcomingWeeks() throws {
        // Arrange — the anchor is a confirmed Blue-Week (recycling) Thursday; the
        // 2026 city calendar shows Jan 1 / 15 / 29 as recycling Thursdays.
        let cal = chicagoCalendar()
        let anchor = try XCTUnwrap(cal.date(from: GarbageSchedule.recyclingAnchor))
        XCTAssertEqual(dayLabel(anchor, cal), "Thu 2026-01-15",
                       "The recycling anchor must be the Blue-Week Thursday the city calendar shows")
        XCTAssertEqual(GarbageSchedule.defaultWeekday, Self.thursday,
                       "St. Joseph refuse runs every Thursday (stjosephmn.gov/162)")

        let expectedThursdays = try consecutiveWeeks(from: anchor,
                                                     count: Self.expectedParity.count,
                                                     cal)

        for (index, expected) in expectedThursdays.enumerated() {
            // Act — a user opening the app at midday on the pickup day itself.
            let midday = try XCTUnwrap(cal.date(byAdding: .hour, value: 12, to: expected))
            let pickup = GarbageSchedule.nextPickup(after: midday,
                                                    pickupWeekday: Self.thursday,
                                                    calendar: cal)

            // Assert — the right day, and it really is a Thursday…
            XCTAssertEqual(pickup.date, expected,
                           "week \(index): expected \(dayLabel(expected, cal)), got \(dayLabel(pickup.date, cal))")
            XCTAssertEqual(cal.component(.weekday, from: pickup.date), Self.thursday,
                           "week \(index): \(dayLabel(pickup.date, cal)) is not a Thursday")
            // …and recycling alternates true/false from the anchor.
            XCTAssertEqual(pickup.isRecyclingWeek, Self.expectedParity[index],
                           "week \(index) (\(dayLabel(expected, cal))): recycling parity is inverted")
        }
    }

    func testRecyclingParityIsStableAcrossAYearBoundary() throws {
        // Arrange — an EVEN number of weeks past the anchor, so the walk must start
        // on a recycling week for exactly the same reason the anchor week does.
        // Nothing about the parity may depend on the calendar year rolling over.
        let cal = chicagoCalendar()
        let anchor = try XCTUnwrap(cal.date(from: GarbageSchedule.recyclingAnchor))
        let december = try XCTUnwrap(cal.date(byAdding: .weekOfYear,
                                              value: Self.weeksFromAnchorToDecember,
                                              to: anchor))
        XCTAssertEqual(dayLabel(december, cal), "Thu 2026-12-03",
                       "\(Self.weeksFromAnchorToDecember) weeks past the anchor must land on Thu Dec 3 2026")

        let expectedThursdays = try consecutiveWeeks(from: december,
                                                     count: Self.expectedParity.count,
                                                     cal)

        // …and the walk genuinely straddles the boundary, so the test has teeth.
        let firstThursday = try XCTUnwrap(expectedThursdays.first)
        let lastThursday = try XCTUnwrap(expectedThursdays.last)
        XCTAssertEqual(cal.component(.year, from: firstThursday), 2026)
        XCTAssertEqual(cal.component(.year, from: lastThursday), 2027)

        for (index, expected) in expectedThursdays.enumerated() {
            // Act
            let midday = try XCTUnwrap(cal.date(byAdding: .hour, value: 12, to: expected))
            let pickup = GarbageSchedule.nextPickup(after: midday,
                                                    pickupWeekday: Self.thursday,
                                                    calendar: cal)

            // Assert
            XCTAssertEqual(pickup.date, expected,
                           "week \(index): expected \(dayLabel(expected, cal)), got \(dayLabel(pickup.date, cal))")
            XCTAssertEqual(cal.component(.weekday, from: pickup.date), Self.thursday,
                           "week \(index): \(dayLabel(pickup.date, cal)) is not a Thursday")
            XCTAssertEqual(pickup.isRecyclingWeek, Self.expectedParity[index],
                           "week \(index) (\(dayLabel(expected, cal))): parity slipped across the year boundary")
        }
    }

    // MARK: - B. Roads: the empty state is calm, not alarming

    func testRoadsIsMutedWhenThereAreNoActiveNotices() {
        // Arrange — nothing happening on the roads today.
        let notices: [TownStatusNotice] = []

        // Act
        let value = RoadsTileProvider.value(for: notices)

        // Assert — de-emphasised, and still saying the calm thing.
        XCTAssertTrue(value.isMuted,
                      "Zero notices is the nothing-to-see state: the tile must render its muted variant")
        XCTAssertTrue(value.content.isMuted,
                      "The flag must ride on the content the tile view actually renders from")
        XCTAssertEqual(value.content.primary, "All clear")
        XCTAssertNil(value.content.badge,
                     "A calm tile must not raise the warning triangle")
        XCTAssertTrue(value.content.expanded.isEmpty,
                      "Nothing to expand when there is nothing to report")
    }

    func testRoadsIsNotMutedWhenNoticesExist() {
        // Arrange — one active notice, as seeded in town_status.
        let updated = Date(timeIntervalSince1970: 1_767_000_000)
        let headline = "Minnesota St. lane closure"
        let notices = [roadsNotice(headline: headline, updatedAt: updated)]

        // Act
        let value = RoadsTileProvider.value(for: notices)

        // Assert — full gradient, full voice.
        XCTAssertFalse(value.isMuted,
                       "An active notice is exactly what the tile is for — never muted")
        XCTAssertFalse(value.content.isMuted)
        XCTAssertEqual(value.content.primary, "1 notice")
        XCTAssertEqual(value.content.secondary, headline)
        XCTAssertEqual(value.content.badge, .warning)
        XCTAssertEqual(value.content.expanded.count, 1)
        XCTAssertEqual(value.content.expanded.first?.label, headline)
        // updatedAt = newest notice → drives the ">24h → Updated Nd ago" stale note.
        XCTAssertEqual(value.updatedAt, updated)
    }

    func testRoadsStaysUnmutedWhenMultipleNoticesExist() {
        // Arrange — activeNotices() returns newest-first; the fixture matches.
        let newest = Date(timeIntervalSince1970: 1_767_000_000)
        let older = newest.addingTimeInterval(-3600)
        let notices = [roadsNotice(headline: "Minnesota St. lane closure", updatedAt: newest),
                       roadsNotice(headline: "College Ave detour", updatedAt: older)]

        // Act
        let value = RoadsTileProvider.value(for: notices)

        // Assert — muting is strictly the ZERO case, not a count threshold.
        XCTAssertFalse(value.isMuted)
        XCTAssertEqual(value.content.primary, "2 notices")
        XCTAssertEqual(value.content.secondary, "Minnesota St. lane closure")
        XCTAssertEqual(value.content.badge, .warning)
        XCTAssertEqual(value.updatedAt, newest)
    }
}
