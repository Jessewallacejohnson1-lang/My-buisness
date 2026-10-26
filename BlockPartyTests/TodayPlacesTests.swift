//
//  TodayPlacesTests.swift
//  BlockPartyTests — which pin each of today's events is at (`TodayPlaces`, codebase-health 12):
//  an event lights exactly the pin its bubble, Today row and pin card go to.
//

import XCTest
@testable import BlockParty

@MainActor
final class TodayPlacesTests: XCTestCase {

    private let day = "2026-10-26"
    private func at(_ hour: Double) -> Date { Town.midnight(day)!.addingTimeInterval(hour * 3600) }
    private func spot(_ id: String) -> Spot { MapSpots.all.first { $0.id == id }! }
    private func event(_ id: String, _ location: String?, _ time: String? = "7 PM") -> TimelineEvent {
        TimelineEvent(id: id, title: id, startTime: time, location: location, clubName: nil, fromJoinedClub: false,
                      when: EventWhen(date: day, time: time, endAt: nil))
    }

    /// "CSB" and "chapel" both hit: before, it lit Saint Ben's and the chapel while its bubble and
    /// row went to Saint Ben's alone.
    func testAnEventThatNamesTwoPlacesLightsOnlyThePinItGoesTo() {
        let vespers = event("Vespers", "Sacred Heart Chapel, CSB")
        let places = TodayPlaces(events: [vespers])
        let pin = places.spot(for: vespers)
        XCTAssertEqual(pin?.id, "saintbens", "the first spot in MapSpots order")
        for spot in MapSpots.all {
            XCTAssertEqual(places.events(at: spot).map(\.id), spot.id == pin?.id ? ["Vespers"] : [], spot.id)
            XCTAssertEqual(places.isLive(spot, now: at(19.5)), spot.id == pin?.id, spot.id)
        }
        let bubbles = places.bubbles(now: at(18), picture: { _ in nil })
        XCTAssertEqual(bubbles.map(\.spot?.id), ["saintbens"])
    }

    func testEachEventGoesToItsOwnPinAndOnlyOnIsLive() {
        let mass = event("Mass", "Saint John's Abbey, Collegeville", "9 PM")
        let concert = event("Concert", "Millstream Park", "6 PM")
        let potluck = event("Potluck", "A backyard")
        let places = TodayPlaces(events: [mass, concert, potluck])
        XCTAssertEqual(places.spot(for: mass)?.id, "saintjohns")
        XCTAssertEqual(places.spot(for: concert)?.id, "millstream")
        XCTAssertNil(places.spot(for: potluck), "no pin for an unlisted venue")
        XCTAssertEqual(places.events(at: spot("saintjohns")).map(\.id), ["Mass"])
        XCTAssertTrue(places.isLive(spot("millstream"), now: at(18.5)))
        XCTAssertFalse(places.isLive(spot("saintjohns"), now: at(18.5)), "not started")
        XCTAssertFalse(places.isLive(spot("millstream"), now: at(20)), "two hours and over")
    }

    func testBubblesAreOnePerPlaceSoonestFirst() {
        let late = event("Late", "Millstream Park", "8 PM")
        let early = event("Early", "Millstream Park", "6 PM")
        let mass = event("Mass", "Saint John's Abbey", "7 PM")
        let bubbles = TodayPlaces(events: [late, mass, early]).bubbles(now: at(17), picture: { _ in nil })
        XCTAssertEqual(bubbles.map(\.event.id), ["Early", "Mass"], "one per place, its lead, soonest first")
        XCTAssertEqual(bubbles.map(\.order), [0, 1])
    }
}
