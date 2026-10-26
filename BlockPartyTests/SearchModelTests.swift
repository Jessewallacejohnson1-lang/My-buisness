//
//  SearchModelTests.swift
//  BlockPartyTests — the Search tab's data: the bundled logos, how the Town's places
//  split into rows and in what order, the photos Block Party saved of them and what a
//  business's page shows, the Town's groups and what a Group page says, typed search, the
//  recents, and the backdrop's colour maths.
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
                     logo: SearchLogo.Row? = nil, entry: String? = nil) -> POI {
        POI(id: UUID().uuidString, placeId: placeId, name: name, lat: 45.56, lon: -94.32, family: family,
            primaryType: type, types: [type], address: nil, logoUrl: nil, searchLogo: logo, entryId: entry)
    }

    private func picture(_ name: String, site: String = "https://www.krewemn.com/", credit: String? = nil) -> PlacePicture {
        PlacePicture(url: URL(string: "https://x.supabase.co/places/\(name).webp")!, kind: .photo, credit: credit,
                     site: URL(string: site))
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
        XCTAssertEqual(SearchModel.label("print_shop"), "Print shop")
        XCTAssertTrue(model.chips.contains(.businesses))
    }

    /// Restaurants and coffee shops with a logo open their page as a business does.
    func testWhatOpens() {
        let items = SearchModel.places(from: [
            poi("ChIJmTKJ0M9ZtFIRm7FAmBzwApc", "The Local Blend", .food, "coffee_shop", logo: logo()),
            poi("stjoe-krewe", "Krewe Restaurant", .food, "cajun_restaurant"),
        ])
        XCTAssertEqual(items.first { $0.name == "The Local Blend" }?.opens, true)
        XCTAssertEqual(items.first { $0.name == "Krewe" }?.opens, false, "no logo, nothing to fly")
    }

    /// A food card shows the cover Block Party saved of its place, found by its registry entry;
    /// a business keeps its logo on the row and its photos for its page; a place with none, or
    /// not in the registry, has no photo, so its card shows its logo (no Google lookup).
    func testSavedPhotosReachCardsAndPages() {
        let photos = ["krewe": [picture("food-1"), picture("food-2")], "bruno-press": [picture("press")]]
        let items = SearchModel.places(from: [
            poi("stjoe-krewe", "Krewe Restaurant", .food, "cajun_restaurant", entry: "krewe"),
            poi("stjoe-bruno-press", "Bruno Press", .business, "print_shop", logo: logo(), entry: "bruno-press"),
            poi("stjoe-gary", "Gary's Pizza", .food, "pizza_restaurant", logo: logo(), entry: "garys-pizza"),
            poi("stjoe-smash", "Joetown Smashburger", .food, "restaurant", logo: logo()),
        ], photos: photos)
        func named(_ name: String) -> SearchItem? { items.first { $0.name == name } }
        XCTAssertEqual(named("Krewe")?.photo, .saved(picture("food-1")), "the cover")
        XCTAssertEqual(named("Krewe")?.photos.count, 2)
        XCTAssertEqual(named("Krewe")?.photo?.credited, true)
        XCTAssertNil(named("Bruno Press")?.photo, "the row shows its logo")
        XCTAssertEqual(named("Bruno Press")?.photos, [picture("press")])
        XCTAssertNil(named("Gary's Pizza")?.photo)
        XCTAssertNil(named("Joetown Smashburger")?.photo, "not in the registry yet")
    }

    /// A park's saved photo comes first, then its bundled one; with neither it has no photo
    /// (Jesse, 2026-10-17: the tree mark until one is saved). Nothing asks Google.
    func testParksTakeSavedThenBundledPhotos() {
        let parks = SearchModel.parks(photos: ["centennial-park": [picture("centennial")]])
        func photo(_ title: String) -> SearchItem.Photo? { parks.first { $0.name == title }?.photo }
        XCTAssertEqual(photo("Centennial Park"), .saved(picture("centennial")))
        XCTAssertEqual(photo("Memorial Park"), .bundled("memorial-park"))
        XCTAssertTrue(parks.contains { $0.name == "Northland Park" })
        XCTAssertNil(photo("Northland Park"))
    }

    /// A places row carries what its page shows: its entry, its own words and its links.
    func testPlacesRowCarriesItsPage() throws {
        let json = """
        [{"id": "a", "place_id": "ChIJ-krewe", "name": "Krewe Restaurant", "lat": 45.5, "lon": -94.3,
          "family": "food", "primary_type": "cajun_restaurant", "types": [], "address": "24 College Ave N Ste 104, St Joseph, MN 56374, USA",
          "logo_url": null, "search_logo": null, "entry_id": "krewe", "about": "  Southern cooking.  ",
          "links": [{"kind": "website", "url": "https://krewemn.com/"}, {"kind": "rss", "url": "https://krewemn.com/feed"}]},
         {"id": "b", "place_id": "stjoe-plain", "name": "Plain Shop", "lat": 45.5, "lon": -94.3,
          "family": "business", "primary_type": null, "types": [], "address": null, "logo_url": null,
          "search_logo": null}]
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let items = SearchModel.places(from: try decoder.decode([POI].self, from: Data(json.utf8)))
        XCTAssertEqual(items[0].street, "24 College Ave N Ste 104")
        XCTAssertEqual(items[0].about, "Southern cooking.")
        XCTAssertEqual(items[0].links.count, 2, "kept as sent; the page picks what it can draw")
        XCTAssertNil(items[1].street)
        XCTAssertNil(items[1].about)
        XCTAssertTrue(items[1].links.isEmpty, "a row from before the page had links")
        XCTAssertNil(SearchModel.street("  , St. Joseph"))
    }

    /// The saved photos read: grouped by entry, cover first as sent, credited to their site or
    /// their author; a row that doesn't decode is only that photo gone.
    func testPlacePhotosRead() throws {
        let json = """
        [{"entry_id": "krewe", "url": "https://x/food-1.webp", "kind": "photo", "credit": null, "site": "https://www.krewemn.com/"},
         {"entry_id": "krewe", "url": "https://x/food-2.webp", "kind": "photo", "credit": null, "site": "https://www.krewemn.com/"},
         {"entry_id": "sju", "url": "https://x/abbey.webp", "kind": "photo", "credit": "Tomruen · CC BY-SA 4.0", "site": null},
         {"entry_id": "bad", "url": 7, "kind": "photo"},
         {"url": "https://x/orphan.webp", "kind": "photo"}]
        """
        let photos = try CommunityAPI.placePhotos(from: Data(json.utf8))
        XCTAssertEqual(Set(photos.keys), ["krewe", "sju"])
        XCTAssertEqual(photos["krewe"]?.map(\.url.lastPathComponent), ["food-1.webp", "food-2.webp"])
        XCTAssertEqual(photos["krewe"]?.first?.creditLine, "krewemn")
        XCTAssertEqual(photos["sju"]?.first?.creditLine, "Tomruen · CC BY-SA 4.0")
    }

    /// Places read without their photos show, and say so, so the next try reads the photos.
    func testPlacesWithoutTheirPhotos() {
        let model = SearchModel(defaults: defaults)
        model.show([poi("stjoe-krewe", "Krewe Restaurant", .food, "cajun_restaurant", entry: "krewe")], photos: nil)
        XCTAssertTrue(model.placesLoaded)
        XCTAssertFalse(model.photosLoaded)
        XCTAssertNil(model.row(.restaurant).first?.photo)
        model.show([poi("stjoe-krewe", "Krewe Restaurant", .food, "cajun_restaurant", entry: "krewe")],
                   photos: ["krewe": [picture("food-1")]])
        XCTAssertTrue(model.photosLoaded)
        XCTAssertEqual(model.row(.restaurant).first?.photo, .saved(picture("food-1")))
    }

    /// A business's page draws its website by name, then Facebook, then Instagram, one of each,
    /// and nothing it can't open.
    func testBusinessPageLinkRows() {
        let rows = BusinessPage.rows([
            PlaceLink(kind: "instagram", url: "https://www.instagram.com/krewe/"),
            PlaceLink(kind: "facebook", url: "https://www.facebook.com/krewerestaurant/"),
            PlaceLink(kind: "website", url: "https://www.krewemn.com/"),
            PlaceLink(kind: "website", url: "https://other.example/"),
            PlaceLink(kind: "rss", url: "https://krewemn.com/feed"),
        ])
        XCTAssertEqual(rows.map(\.text), ["krewemn.com", "Facebook", "Instagram"])
        XCTAssertEqual(rows.map(\.glyph), ["globe", "f.circle", "camera"])
        XCTAssertEqual(rows.first?.url.absoluteString, "https://www.krewemn.com/")
        XCTAssertTrue(BusinessPage.rows([PlaceLink(kind: "website", url: "mailto:a@b.c"),
                                         PlaceLink(kind: "facebook", url: "not a url")]).isEmpty)
    }

    /// The logo rests top right beside a photo, and with none where the Event page draws a
    /// place's logo in a hero it has no photo for: 150 pt, 101 pt down, on a 420 pt phone.
    func testWhereTheLogoRests() {
        let corner = BusinessPage.corner(width: 420, top: 68)
        XCTAssertEqual(corner, CGRect(x: 334, y: 59, width: 76, height: 76))
        let middle = BusinessPage.middle(width: 420)
        XCTAssertEqual(middle.width, 149.5, accuracy: 0.5)
        XCTAssertEqual(middle.midX, 210, accuracy: 0.01)
        XCTAssertEqual(middle.minY, 145.6, accuracy: 0.5)
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

    // MARK: Groups (BP app rsvp-and-groups 05)

    /// A `get_groups` row as Supabase sends it: a bad photo or meeting is left out, never the group.
    func testGroupsRowDecodes() throws {
        let json = """
        [{"id": "g1", "name": "St. Joseph Lions Club", "kind": "Service club", "schedule": "1st and 3rd Tuesdays at 6 PM",
          "location": "Lions Building, Millstream Park", "about": "Supper at 6.", "page_url": "https://e-clubhouse.org/sites/stjosephmn/",
          "photos": [{"url": "https://x/lions-1.webp", "kind": "photo", "credit": null, "site": "https://e-clubhouse.org/"},
                     {"kind": "photo"}],
          "logo": null,
          "meetings": [{"what": "Meeting", "day": "2026-10-20", "time": "18:00", "where": null}, {"day": "2026-11-03"}],
          "member_count": 2, "joined": true},
         {"id": "g2", "name": "Sons of the American Legion", "kind": null, "schedule": null, "location": null, "about": null,
          "page_url": null, "photos": [], "logo": {"url": "https://x/sal.webp", "kind": "logo", "hue": null},
          "meetings": [], "member_count": 0, "joined": false}]
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let groups = try decoder.decode([TownGroup].self, from: Data(json.utf8))
        XCTAssertEqual(groups[0].photos.map(\.url.lastPathComponent), ["lions-1.webp"], "the photo with no address is dropped")
        XCTAssertEqual(groups[0].photos.first?.creditLine, "e-clubhouse")
        XCTAssertEqual(groups[0].meetings, [TownGroup.Meeting(what: "Meeting", day: "2026-10-20", time: "18:00")])
        XCTAssertEqual(groups[0].pageUrl, "https://e-clubhouse.org/sites/stjosephmn/")
        XCTAssertEqual([groups[0].memberCount, groups[1].memberCount], [2, 0])
        XCTAssertTrue(groups[0].joined)
        XCTAssertEqual(groups[1].logo?.kind, .logo)
        XCTAssertNil(groups[1].kind)
    }

    /// Search's Groups row, in the server's order: the cover photo, else the logo on its backdrop
    /// (a grey one on the studio hue), else what kind of thing it is; and no made-up samples.
    func testGroupsReachTheShelf() {
        let model = SearchModel(defaults: defaults)
        XCTAssertTrue(model.isLoading(.club), "a skeleton row until they're read")
        XCTAssertTrue(model.row(.club).isEmpty, "the made-up Book Group, Morning Pages and Potluck are gone")
        model.show([
            TownGroup(id: "b", name: "Book Discussion Group", kind: "Book club", photos: [picture("church")]),
            TownGroup(id: "s", name: "Sons of the American Legion",
                      logo: PlacePicture(url: URL(string: "https://x/sal.webp")!, kind: .logo)),
            TownGroup(id: "w", name: "St. Joseph Women of Today", kind: "Service club"),
        ])
        XCTAssertFalse(model.isLoading(.club))
        let row = model.row(.club)
        XCTAssertEqual(row.map(\.name), ["Book Discussion Group", "Sons of the American Legion", "St. Joseph Women of Today"])
        XCTAssertEqual(row[0].photo, .saved(picture("church")))
        XCTAssertNil(row[0].logo)
        XCTAssertEqual(row[1].logo?.chroma, false)
        XCTAssertNil(row[1].photo)
        XCTAssertEqual(row[2].glyph, "person.2")
        XCTAssertEqual(row.map(\.id), ["g:b", "g:s", "g:w"])
        XCTAssertEqual(row[0].townGroup?.id, "b", "it opens its Group page")
        XCTAssertFalse(row[0].opens, "not the business page")
        XCTAssertTrue(model.chips.contains(.clubs))
        XCTAssertEqual(model.results(for: "book", in: .clubs).first?.items.first?.name, "Book Discussion Group")
    }

    /// What a Group page says: never "0 members", the town after the kind, when and where in one line.
    func testGroupPageWords() {
        XCTAssertNil(GroupPage.membersText(0))
        XCTAssertEqual(GroupPage.membersText(1), "1 member")
        XCTAssertEqual(GroupPage.membersText(12), "12 members")
        var group = TownGroup(id: "b", name: "Book Discussion Group", kind: "Book club")
        XCTAssertEqual(GroupPage.kindLine(group), "Book club · St. Joseph")
        XCTAssertNil(GroupPage.whenLine(group))
        group.schedule = "1st Tuesdays at 9:30 AM"
        group.location = "Fireside Room, Resurrection Lutheran"
        XCTAssertEqual(GroupPage.whenLine(group), "1st Tuesdays at 9:30 AM · Fireside Room, Resurrection Lutheran")
        group.kind = nil
        XCTAssertEqual(GroupPage.kindLine(group), "St. Joseph")
    }

    /// A Coming up row: its date tile, then the day, the time when the group says one, and a place
    /// only when it isn't the group's usual one.
    func testGroupMeetingWords() {
        XCTAssertEqual(GroupPage.meetingLine(.init(what: "Meeting", day: "2026-10-20", time: "18:00")), "Tue, Oct 20 · 6 PM")
        XCTAssertEqual(GroupPage.meetingLine(.init(what: "Book discussion", day: "2026-11-03", time: "09:30")), "Tue, Nov 3 · 9:30 AM")
        XCTAssertEqual(GroupPage.meetingLine(.init(what: "Meeting", day: "2026-11-09")), "Mon, Nov 9", "the Knights give no time")
        XCTAssertEqual(GroupPage.meetingLine(.init(what: "Parish breakfast", day: "2026-11-01", time: "08:30", place: "Heritage Hall")),
                       "Sun, Nov 1 · 8:30 AM · Heritage Hall")
        XCTAssertEqual(GroupPage.meetingLine(.init(what: "Bingo", day: "2026-10-26", time: "12:00")), "Mon, Oct 26 · Noon")
        let lions = [TownGroup.Meeting(what: "Meeting", day: "2026-10-20", time: "18:00"),
                     TownGroup.Meeting(what: "Meeting", day: "2026-11-03", time: "18:00")]
        let oct21 = Town.midnight("2026-10-21")!
        XCTAssertEqual(GroupPage.upcoming(lions, today: oct21).map(\.day), ["2026-11-03"], "one that passed while the app stayed open goes")
        XCTAssertEqual(GroupPage.upcoming(lions, today: Town.midnight("2026-10-20")!).count, 2, "today's stays")
        XCTAssertEqual(GroupPage.tile("2026-10-20").month, "OCT")
        XCTAssertEqual(GroupPage.tile("2026-10-20").day, "20")
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

    /// A logo pops in a wave from the top left, 44 ms apart, no more than ten deep, once per
    /// app open; a logo that comes on screen later starts a wave of its own.
    func testLogoPopStaggersFromTopLeftOncePerLogo() {
        let reveal = LogoReveal(), start = Date()
        let urls = (0..<12).map { URL(string: "https://example.com/logo-\($0).webp")! }
        // Asked right to left, as a sideways row does: the left one still goes first.
        let row = urls.enumerated().map { ($0.element, CGPoint(x: 400 - Double($0.offset) * 30, y: 100)) }
        let delays = reveal.delays(for: row, now: start)
        XCTAssertEqual(delays[11], 0)
        XCTAssertEqual(delays[10]!, 0.044, accuracy: 1e-9)
        XCTAssertEqual(delays[0]!, 0.44, accuracy: 1e-9)
        XCTAssertEqual(reveal.delays(for: [(urls[0], .zero)], now: start + 1), [nil])
        XCTAssertEqual(reveal.delays(for: [(URL(string: "https://example.com/late.webp")!, .zero)], now: start + 2), [0])
    }

    /// The elastic swings past its spot, back, and has settled by the pop's end.
    func testElasticSwingsAndSettles() {
        XCTAssertEqual(elasticOffset(0, from: -24, response: 0.7, damping: 0.42), -24, accuracy: 1e-9)
        let swing = stride(from: 0.0, to: 1.2, by: 0.01).map { elasticOffset($0, from: -24, response: 0.7, damping: 0.42) }
        XCTAssertGreaterThan(swing.max()!, 5)
        XCTAssertLessThan(abs(elasticOffset(1.2, from: -24, response: 0.7, damping: 0.42)), 0.5)
        XCTAssertLessThan(abs(elasticOffset(1.2, from: -0.5, response: 0.61, damping: 0.5)), 0.005)
    }
}
