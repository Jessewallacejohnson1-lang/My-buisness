//
//  TownSearchTests.swift
//  BlockPartyTests — how typed words match a Search row (BP app search-helpful 02): the ways a name is
//  typed loosely, and the stricter typo rule that chat's name search shares.
//

import XCTest
@testable import BlockParty

@MainActor
final class TownSearchTests: XCTestCase {
    private func finds(_ words: String, _ name: String, aliases: [String] = []) -> Bool {
        TownSearch.score(words, name: name, aliases: aliases) != nil
    }

    private func typo(_ words: String, _ name: String) -> Bool {
        (TownSearch.score(words, name: name) ?? .infinity) < TownSearch.typoCeiling
    }

    /// "&" reads as "and", an apostrophe or a missing space doesn't matter, a plural finds its singular.
    func testLooseTyping() {
        XCTAssertTrue(finds("milk and honey", "Milk & Honey"))
        XCTAssertTrue(finds("sals", "Sal's Bar & Grill"))
        XCTAssertTrue(finds("kwiktrip", "Kwik Trip"))
        XCTAssertTrue(finds("bars", "Sal's Bar & Grill"))
        XCTAssertTrue(finds("churches", "Church of St. Joseph"))
        XCTAssertTrue(finds("groceries", "Grocery Outlet"))
        XCTAssertTrue(finds("clothes", "Peony White Clothing"))
        XCTAssertFalse(finds("jones", "Jon Smith"), "\"es\" comes off only after s, x, z, ch, sh, th")
        XCTAssertTrue(typo("sals", "Saturday Sale"), "a short singular counts only whole: Sale is only a typo away")
    }

    /// Another name typed whole ranks with the name, above the start of a longer name.
    func testAnotherNameTypedWhole() {
        let csb = TownSearch.score("csb", name: "College of Saint Benedict", aliases: ["CSB"])!
        let start = TownSearch.score("csb", name: "CSB Bookstore Annex")!
        XCTAssertGreaterThan(csb, start)
        XCTAssertNotNil(TownSearch.score("st bens", name: "College of Saint Benedict", aliases: ["St Bens"]))
    }

    /// One wrong letter up to 7 letters, two from 8; a typo's score sits under `typoCeiling`.
    func testTypoRule() {
        XCTAssertTrue(typo("cofee", "Coffee Shop"))
        XCTAssertTrue(typo("millstreem", "Millstream Park"))
        XCTAssertFalse(finds("hiking", "Diving Club"), "two wrong letters at 6")
        XCTAssertFalse(finds("realtor", "Realty Plus"), "two wrong letters at 7")
        XCTAssertFalse(finds("bnk", "Band"), "no typo under 4 letters")
        XCTAssertFalse(finds("&", "Andy's Garage"), "\"&\" alone finds nothing")
        XCTAssertFalse(typo("bank", "Bank of Saint Joseph"), "found without a typo")
    }
}
