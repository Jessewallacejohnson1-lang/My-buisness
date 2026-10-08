//
//  SearchModelTests.swift
//  BlockPartyTests — the Search tab's data: the bundled logos, how the Town's places
//  split into rows and in what order, typed search, the recents, and the backdrop's
//  colour maths.
//

import XCTest
@testable import BlockParty

@MainActor
final class SearchModelTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SearchModelTests")
        defaults.removePersistentDomain(forName: "SearchModelTests")
    }

    private func poi(_ placeId: String, _ name: String, _ family: PlaceFamily, _ type: String,
                     logo: SearchLogo.Row? = nil) -> POI {
        POI(id: UUID().uuidString, placeId: placeId, name: name, lat: 45.56, lon: -94.32, family: family,
            primaryType: type, types: [type], address: nil, logoUrl: nil, searchLogo: logo)
    }

    private func logo(wall: Bool? = nil) -> SearchLogo.Row {
        SearchLogo.Row(url: URL(string: "https://example.com/logo-0.webp")!, hue: 354, chroma: true, wall: wall)
    }

    /// A places row as Supabase sends it carries its Search logo: the file, the backdrop's
    /// hue, 3D, its place in the row, and whether it stays off the wall.
    func testPlacesRowCarriesItsLogo() throws {
        let json = """
        [{"id": "a", "place_id": "stjoe-bruno-press", "name": "Bruno Press", "lat": 45.5, "lon": -94.3,
          "family": "business", "primary_type": null, "types": [], "address": null, "logo_url": null,
          "search_logo": {"url": "https://x.supabase.co/storage/v1/object/public/places/st-joseph/stjoe-bruno-press/logo-1a2b3c4d.webp",
                          "hue": 354, "chroma": true, "d3": true, "rank": 2}},
         {"id": "b", "place_id": "ChIJ-pharmacy", "name": "Coborn's Pharmacy", "lat": 45.5, "lon": -94.3,
          "family": "business", "primary_type": null, "types": [], "address": null, "logo_url": null,
          "search_logo": {"url": "https://x.supabase.co/a.webp", "hue": 80, "chroma": true, "wall": false}},
         {"id": "c", "place_id": "stjoe-plain", "name": "Plain Shop", "lat": 45.5, "lon": -94.3,
          "family": "business", "primary_type": null, "types": [], "address": null, "logo_url": null,
          "search_logo": null}]
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let items = SearchModel.places(from: try decoder.decode([POI].self, from: Data(json.utf8)))
        let bruno = try XCTUnwrap(items[0].logo)
        XCTAssertEqual(bruno.url.lastPathComponent, "logo-1a2b3c4d.webp")
        XCTAssertTrue(bruno.is3D && bruno.chroma && bruno.onWall)
        XCTAssertEqual(bruno.rank, 2)
        XCTAssertEqual(items[0].rank, 2)
        XCTAssertEqual(items[1].logo?.onWall, false)
        XCTAssertEqual(items[1].logo?.is3D, false)
        XCTAssertNil(items[2].logo)
    }

    /// Businesses show on the row only with a logo; food splits into coffee and the
    /// rest; names lose what only repeats the kind of place.
    func testPlacesSplitIntoRows() {
        let model = SearchModel(defaults: defaults)
        model.show([
            poi("stjoe-bruno-press", "Bruno Press", .business, "print_shop", logo: logo()),
            poi("stjoe-no-logo", "Plain Shop", .business, "store"),
            poi("ChIJ-bSQp6VZtFIRsrFXg1RYwFs", "Coborn's Pharmacy", .business, "pharmacy", logo: logo(wall: false)),
            poi("stjoe-blend", "The Local Blend", .food, "coffee_shop"),
            poi("stjoe-flour", "Flour & Flower", .food, "bakery"),
            poi("stjoe-krewe", "Krewe Restaurant", .food, "cajun_restaurant"),
        ])
        XCTAssertEqual(model.row(.business).map(\.name), ["Bruno Press"], "no logo, or its logo is on the wall already")
        XCTAssertEqual(Set(model.row(.coffee).map(\.name)), ["The Local Blend", "Flour & Flower"])
        XCTAssertEqual(model.row(.restaurant).map(\.name), ["Krewe"])
        XCTAssertEqual(model.row(.restaurant).first?.sub, "Cajun")
        XCTAssertEqual(model.row(.restaurant).first?.fullName, "Krewe Restaurant")
        XCTAssertEqual(SearchModel.label("print_shop"), "Print shop")
        XCTAssertTrue(model.chips.contains(.businesses))
    }

    /// A local place whose Google id was found asks Google by that id; restaurants and
    /// coffee shops with a logo open their page as a business does.
    func testGoogleIdsAndWhatOpens() {
        var bruno = poi("stjoe-bruno-press", "Bruno Press", .business, "print_shop", logo: logo())
        bruno.googlePlaceId = "ChIJbruno"
        let items = SearchModel.places(from: [
            bruno,
            poi("ChIJmTKJ0M9ZtFIRm7FAmBzwApc", "The Local Blend", .food, "coffee_shop", logo: logo()),
            poi("stjoe-krewe", "Krewe Restaurant", .food, "cajun_restaurant"),
        ])
        func named(_ name: String) -> SearchItem? { items.first { $0.name == name } }
        XCTAssertEqual(named("Bruno Press")?.googleId, "ChIJbruno")
        XCTAssertEqual(named("The Local Blend")?.googleId, "ChIJmTKJ0M9ZtFIRm7FAmBzwApc")
        XCTAssertEqual(named("The Local Blend")?.opens, true)
        XCTAssertEqual(named("Krewe")?.opens, false, "no logo, nothing to fly")
    }

    /// The mockup's order first (the 3D logos lead), then by name.
    func testRowsKeepTheMockupsOrder() {
        let model = SearchModel(defaults: defaults)
        model.show([
            poi("stjoe-aaa", "Aardvark", .business, "store"),
            poi("stjoe-white-peony-boutique", "White Peony Boutique", .business, "clothing_store",
                logo: SearchLogo.Row(url: URL(string: "https://example.com/w.webp")!, hue: 0, chroma: false, rank: 1)),
            poi("stjoe-bruno-press", "Bruno Press", .business, "print_shop",
                logo: SearchLogo.Row(url: URL(string: "https://example.com/b.webp")!, hue: 354, chroma: true, rank: 0)),
        ])
        // Aardvark has no logo, so it stays off the row.
        XCTAssertEqual(model.row(.business).map(\.name), ["Bruno Press", "White Peony Boutique"])
        XCTAssertEqual(model.row(.park).first?.group, "Parks")
        XCTAssertEqual(model.row(.park).last?.group, "Trails")
    }

    /// Typing finds by name and by kind of place; the Businesses pill takes food too.
    func testTypedSearch() {
        let model = SearchModel(defaults: defaults)
        model.show([
            poi("stjoe-her-hair-studio", "Her Hair Studio", .business, "hair_salon"),
            poi("stjoe-gary", "Gary's Pizza", .food, "pizza_restaurant"),
        ])
        XCTAssertEqual(model.results(for: "hair", in: .all).first?.items.first?.name, "Her Hair Studio")
        XCTAssertEqual(model.results(for: "pizza", in: .businesses).map(\.kind), [.restaurant])
        XCTAssertTrue(model.results(for: "pizza", in: .parks).isEmpty)
        XCTAssertTrue(model.results(for: "   ", in: .all).isEmpty)
    }

    /// Newest first, no repeats, eight at most, and kept between launches.
    func testRecents() {
        defaults.set([String](), forKey: SearchModel.recentsKey)
        let model = SearchModel(defaults: defaults)
        for i in 0..<10 { model.remember("q:\(i)") }
        model.remember("q:3")
        XCTAssertEqual(model.recentIDs.count, SearchModel.recentsMax)
        XCTAssertEqual(model.recentIDs.first, "q:3")
        XCTAssertEqual(model.recentIDs.filter { $0 == "q:3" }.count, 1)
        model.forget("q:3")
        XCTAssertFalse(model.recentIDs.contains("q:3"))
        XCTAssertEqual(SearchModel(defaults: defaults).recentIDs, model.recentIDs)
        XCTAssertEqual(SearchModel.queryID("  Pumpkin "), "q:pumpkin")
    }

    /// The business page's spring turns around from wherever it is, at the speed it
    /// had, rather than jumping: a back tap halfway open sends it home from there.
    func testSpringTurnsAroundWithoutAJump() {
        let spring = LiveSpring(0)
        spring.animate(to: 1, response: SearchMetric.openResponse, damping: SearchMetric.openDamping)
        for _ in 0..<12 { spring.advance(by: 1.0 / 60) }
        let halfway = spring.value
        XCTAssertGreaterThan(halfway, 0.2)
        XCTAssertLessThan(halfway, 0.9)
        spring.animate(to: 0, response: SearchMetric.closeResponse, damping: 1)
        spring.advance(by: 1.0 / 60)
        XCTAssertEqual(spring.value, halfway, accuracy: 0.05)
        for _ in 0..<240 { spring.advance(by: 1.0 / 60) }
        XCTAssertEqual(spring.value, 0, accuracy: 0.001)
    }

    /// Reopened before it got home, the business stays; home, it is let go.
    func testReopeningMidCloseKeepsTheBusiness() {
        let opener = BusinessOpener()
        let item = SearchItem(id: "p:stjoe-bruno-press", kind: .business, name: "Bruno Press",
                              logo: SearchLogo(placeId: "stjoe-bruno-press", row: logo()))
        let source = BusinessOpener.Source(logo: .zero, box: .zero, radius: 0, shadow: .black)
        func run(_ frames: Int) { for _ in 0..<frames { opener.progress.advance(by: 1.0 / 60) } }
        opener.open(item, from: source)
        run(60)
        opener.close()
        run(6)
        opener.open(item, from: source)
        run(120)
        XCTAssertEqual(opener.item?.id, item.id)
        XCTAssertEqual(opener.progress.value, 1, accuracy: 0.001)
        opener.close()
        run(120)
        XCTAssertNil(opener.item)
    }

    /// CSS's hsl(), which the backdrops and cast shadows are written in.
    func testHSL() {
        func near(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) {
            XCTAssertEqual(a.0, b.0, accuracy: 0.002)
            XCTAssertEqual(a.1, b.1, accuracy: 0.002)
            XCTAssertEqual(a.2, b.2, accuracy: 0.002)
        }
        near(Hue.hslToRGB(0, 100, 50), (1, 0, 0))
        near(Hue.hslToRGB(120, 100, 25), (0, 0.5, 0))
        near(Hue.hslToRGB(240, 100, 50), (0, 0, 1))
        near(Hue.hslToRGB(34, 0, 94), (0.94, 0.94, 0.94))
        // The studio backdrop's top, hsl(34 9% 94%): #F1F0EE.
        near(Hue.hslToRGB(34, 9, 94), (0.9454, 0.9407, 0.9346))
    }
}
