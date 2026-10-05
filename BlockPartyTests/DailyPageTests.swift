//
//  DailyPageTests.swift
//  BlockPartyTests — the Daily tab: its sample Spotlight, the low sun that throws the
//  card's shadow across the yellow, and the tilt.
//

import XCTest
@testable import BlockParty

final class DailyPageTests: XCTestCase {
    #if DEBUG
    /// The sample Spotlight names its photos by bundle resource; a renamed or removed
    /// image would leave a grey hole in the card instead of failing anywhere else.
    func testSampleSpotlightPhotosAreBundled() {
        XCTAssertNotNil(DailySpotlight.sample.portrait)
        XCTAssertEqual(DailySpotlight.sample.photos.count, 2)
    }
    #endif

    /// Morning throws the shadow right, dinner throws it left, both long; midday drops it
    /// short and straight down.
    func testTheSunSwingsTheShadowAcrossTheDay() {
        let sunrise = DailySun.shadow(hour: 6), midday = DailySun.shadow(hour: 13.5)
        let sunset = DailySun.shadow(hour: 21)
        XCTAssertEqual(sunrise.x, 46, accuracy: 0.001)
        XCTAssertEqual(sunset.x, -46, accuracy: 0.001)
        XCTAssertEqual(midday.x, 0, accuracy: 0.001)
        XCTAssertEqual(sunrise.y, 36, accuracy: 0.001)
        XCTAssertEqual(midday.y, 12, accuracy: 0.001)
        XCTAssertGreaterThan(sunrise.blur, midday.blur)
    }

    /// At night the shadow is the midday one, like a streetlight overhead (Jesse, 2026-10-01).
    func testNightKeepsTheMiddayShadow() {
        let midday = DailySun.shadow(hour: 13.5)
        for hour in [0.0, 3, 5.9, 21.1, 23.5] {
            let night = DailySun.shadow(hour: hour)
            XCTAssertEqual(night.x, midday.x, accuracy: 0.001, "hour \(hour)")
            XCTAssertEqual(night.y, midday.y, accuracy: 0.001, "hour \(hour)")
        }
    }

    /// The sun keeps the Town's clock, not the phone's.
    func testTheSunReadsTheTownsHour() {
        // 2026-10-01 12:30 UTC is 7:30 in the morning in St. Joseph (CDT, UTC-5).
        let date = Date(timeIntervalSince1970: 1_790_857_800)
        XCTAssertEqual(DailySun.hour(at: date), 7.5, accuracy: 0.001)
    }

    /// The lean is measured from the way the phone is held, stops at a full lean, and the
    /// rest creeps toward the hand so a new grip reads as level again.
    func testTiltLeansFromTheRestAndTheRestFollows() {
        var rest = (x: 0.0, z: -0.5)
        let lean = DailyTilt.lean(gravity: (x: 0.6, z: -0.65), rest: &rest)
        XCTAssertEqual(lean.x, 1, accuracy: 0.001, "a lean past the range stops at a full lean")
        XCTAssertEqual(lean.y, -0.5, accuracy: 0.001)
        XCTAssertGreaterThan(rest.x, 0)
        XCTAssertLessThan(rest.x, 0.6)

        for _ in 0..<600 { _ = DailyTilt.lean(gravity: (x: 0.6, z: -0.65), rest: &rest) }
        let settled = DailyTilt.lean(gravity: (x: 0.6, z: -0.65), rest: &rest)
        XCTAssertEqual(settled.x, 0, accuracy: 0.01, "held still for 10 s, the grip reads as level")
    }

    #if DEBUG
    // MARK: Event of the day

    /// 2026-10-01 in St. Joseph; the samples sit at 8–12, 16–17 and 19–21 Town time.
    private let day = Date(timeIntervalSince1970: 1_790_857_800)

    private func town(_ hour: Double) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Town.timeZone
        return calendar.startOfDay(for: day).addingTimeInterval(hour * 3600)
    }

    /// Soonest first, three at most; one that has ended gives its spot to the next, and
    /// with none left nothing shows, so the section goes.
    @MainActor
    func testEventOfTheDayKeepsWhatIsStillOnSoonestFirst() {
        let samples = DailyEvent.samples(on: day)
        let morning = DailyEvent.showing(samples.reversed(), now: town(7), limit: 3)
        XCTAssertEqual(morning.map(\.item.title), ["Farmers Market", "Abbey organ recital", "Music in Millstream Park"])
        XCTAssertEqual(DailyEvent.showing(samples, now: town(12), limit: 3).first?.item.title, "Abbey organ recital")
        XCTAssertEqual(DailyEvent.showing(samples, now: town(20), limit: 3).map(\.item.title), ["Music in Millstream Park"])
        XCTAssertTrue(DailyEvent.showing(samples, now: town(21), limit: 3).isEmpty)

        var four = samples
        four.append(samples[0])
        four[3].starts = town(22)
        four[3].ends = town(23)
        XCTAssertEqual(DailyEvent.showing(four, now: town(7), limit: 3).count, 3)
    }

    /// The pill says how soon, then "Now" once it has started.
    @MainActor
    func testEventOfTheDayPillSaysHowSoon() {
        let recital = DailyEvent.samples(on: day)[1]
        XCTAssertEqual(recital.startsLabel(now: town(14)), "In 2 hours")
        XCTAssertEqual(recital.startsLabel(now: town(16.25)), "Now")
    }

    /// The time line keeps the Town's clock, names the host, and shows minutes only when
    /// there are some ("4 – 5 PM", but "7:30 – 9:00 PM").
    @MainActor
    func testEventOfTheDayTimeLineIsInTownTime() {
        var recital = DailyEvent.samples(on: day)[1]
        XCTAssertTrue(recital.timeLine.hasPrefix("4"), recital.timeLine)
        XCTAssertFalse(recital.timeLine.contains(":"), recital.timeLine)
        XCTAssertTrue(recital.timeLine.hasSuffix(" · Hosted by Saint John's Abbey"), recital.timeLine)

        recital.starts = town(19.5)
        recital.ends = town(21)
        XCTAssertTrue(recital.timeLine.hasPrefix("7:30"), recital.timeLine)
        XCTAssertTrue(recital.timeLine.contains("9:00"), recital.timeLine)

        // Past midnight it still reads as times, never two dates written out.
        recital.starts = town(21)
        recital.ends = town(25)
        // Foundation puts a narrow no-break space before AM and PM.
        let line = recital.timeLine.replacingOccurrences(of: "\u{202F}", with: " ")
        XCTAssertTrue(line.hasPrefix("9 PM – 1 AM"), line)
    }

    // MARK: Agenda

    /// Soonest first; a finished one drops off; one Event of the day already shows
    /// never shows again. The samples sit at 7–10, 9–11, 14–15:30 and 19:30–21.
    @MainActor
    func testAgendaKeepsWhatIsStillOnAndLeavesOutEventOfTheDay() {
        let samples = DailyEvent.agendaSamples(on: day)
        func ids(_ now: Double, without shown: [DailyEvent] = []) -> [String] {
            DailyEvent.showing(samples.reversed(), now: town(now), without: shown, limit: .max).map(\.id)
        }
        XCTAssertEqual(ids(8), ["daily-a1", "daily-a2", "daily-a3", "daily-a4"])
        XCTAssertEqual(ids(10), ["daily-a2", "daily-a3", "daily-a4"])
        XCTAssertEqual(ids(8, without: [samples[1]]), ["daily-a1", "daily-a3", "daily-a4"])
        XCTAssertTrue(ids(21).isEmpty)
    }

    /// The card says "Now" once it has started, else when it starts, with minutes only
    /// when there are some.
    @MainActor
    func testAgendaCardSaysWhenItStarts() {
        let samples = DailyEvent.agendaSamples(on: day)
        // Foundation puts a narrow no-break space before AM and PM.
        func plain(_ text: String) -> String { text.replacingOccurrences(of: "\u{202F}", with: " ") }
        XCTAssertEqual(samples[0].startTime(now: town(8)), "Now")
        XCTAssertEqual(plain(samples[1].startTime(now: town(8))), "9 AM")
        XCTAssertEqual(plain(samples[3].startTime(now: town(8))), "7:30 PM")
        XCTAssertEqual(plain(DailyEvent.clock(samples[2].ends)), "3:30 PM")
    }

    // MARK: Suggestions

    /// Soonest first, ten at most, and never one a section above already shows. The
    /// samples run from 7:30 in the morning to 8:30 at night.
    @MainActor
    func testSuggestionsLeaveOutWhatIsAboveAndStopAtTen() {
        let samples = DailyEvent.suggestionSamples(on: day)
        XCTAssertEqual(DailyEvent.showing(samples.reversed(), now: town(8), without: [samples[2]], limit: 10).map(\.id),
                       ["daily-s1", "daily-s2", "daily-s4", "daily-s5", "daily-s6", "daily-s7"])
        XCTAssertEqual(DailyEvent.showing(samples, now: town(9), limit: 10).first?.id, "daily-s2")

        let many = (0..<12).map { i in
            DailyEvent.sample(id: "many-\(i)", title: "Event \(i)", host: "", photo: "", place: "Here",
                              starts: town(9 + Double(i) / 2), ends: town(10 + Double(i) / 2),
                              category: .other, description: "")
        }
        XCTAssertEqual(DailyEvent.showing(many, now: town(8), limit: 10).map(\.id),
                       (0..<10).map { "many-\($0)" })
    }
    #endif
}
