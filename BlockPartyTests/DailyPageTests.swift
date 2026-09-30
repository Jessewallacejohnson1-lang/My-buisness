//
//  DailyPageTests.swift
//  BlockPartyTests — the Daily tab. Its date line is `TodayHeader.eyebrow`, which
//  TodayHeaderTests already holds to the Town's midnight.
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
}
