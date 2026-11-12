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
    /// Nothing these tests do reads; a read would reach this fake, never the network.
    private var supabase: Supabase { Supabase(auth: FakeTokenProvider(), send: FakeServer().send) }

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

    /// Businesses show on the row with their logo, or their letter disc while they have none (place-pages
    /// 01); one whose logo is already on the wall stays off; food splits into coffee and the rest; names
    /// lose what only repeats the kind of place.
    func testPlacesSplitIntoRows() {
        let model = SearchModel(supabase: supabase, defaults: defaults)
        model.show([
            poi("stjoe-bruno-press", "Bruno Press", .business, "print_shop", logo: logo()),
            poi("stjoe-no-logo", "Plain Shop", .business, "store"),
            poi("ChIJ-bSQp6VZtFIRsrFXg1RYwFs", "Coborn's Pharmacy", .business, "pharmacy", logo: logo(wall: false)),
            poi("stjoe-blend", "The Local Blend", .food, "coffee_shop"),
            poi("stjoe-flour", "Flour & Flower", .food, "bakery"),
            poi("stjoe-krewe", "Krewe Restaurant", .food, "cajun_restaurant"),
            poi("stjoe-centennial", "Centennial Park", .business, "park", entry: "centennial-park"),
        ])
        XCTAssertEqual(model.row(.business).map(\.name), ["Bruno Press", "Plain Shop"],
                       "its logo is on the wall already; a city park's row isn't listed beside the park itself")
        XCTAssertEqual(model.row(.business).last?.initial, "P", "a place with no logo shows its first letter")
        XCTAssertEqual(Set(model.row(.coffee).map(\.name)), ["The Local Blend", "Flour & Flower"])
        XCTAssertEqual(model.row(.restaurant).map(\.name), ["Krewe"])
        XCTAssertEqual(model.row(.restaurant).first?.sub, "Cajun")
        XCTAssertEqual(SearchModel.label("print_shop"), "Print shop")
        XCTAssertTrue(model.chips.contains(.businesses))
    }

    /// A cidery reads as one and stays with the town's drink places: onboarding's Bars pick, the
    /// wineglass on the map and a search for "brewery" (BP app backlog 23).
    func testCidery() {
        let item = SearchModel.places(from: [poi("stjoe-milk-honey-ciders", "Milk & Honey Ciders", .food, "cidery")])[0]
        XCTAssertEqual(item.sub, "Cidery")
        XCTAssertEqual(item.kind, .restaurant)
        XCTAssertTrue(item.keywords.contains("brewery"))
        XCTAssertEqual(PlaceCategoryMap.family(primaryType: "cidery"), .food)
        XCTAssertEqual(PlaceCategoryMap.glyph(primaryType: "cidery", family: .food), "wineglass.fill")
        XCTAssertEqual(FollowSuggestions.interests(ofKind: "cidery"), ["bars"])
    }

    /// Restaurants and coffee shops open their page as a business does, with a logo or, until one is
    /// made, their letter disc (Jesse, 2026-11-08).
    func testWhatOpens() {
        let items = SearchModel.places(from: [
            poi("ChIJmTKJ0M9ZtFIRm7FAmBzwApc", "The Local Blend", .food, "coffee_shop", logo: logo()),
            poi("stjoe-krewe", "Krewe Restaurant", .food, "cajun_restaurant"),
        ])
        XCTAssertEqual(items.first { $0.name == "The Local Blend" }?.opens, true)
        XCTAssertEqual(items.first { $0.name == "Krewe" }?.opens, true, "no logo: its letter disc flies")
        XCTAssertEqual(items.first { $0.name == "Krewe" }?.initial, "K")
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
        let model = SearchModel(supabase: supabase, defaults: defaults)
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
        let model = SearchModel(supabase: supabase, defaults: defaults)
        model.show([
            poi("stjoe-aaa", "Aardvark", .business, "store"),
            poi("stjoe-white-peony-boutique", "White Peony Boutique", .business, "clothing_store",
                logo: SearchLogo.Row(url: URL(string: "https://example.com/w.webp")!, hue: 0, chroma: false, rank: 1)),
            poi("stjoe-bruno-press", "Bruno Press", .business, "print_shop",
                logo: SearchLogo.Row(url: URL(string: "https://example.com/b.webp")!, hue: 354, chroma: true, rank: 0)),
        ])
        // Aardvark has no logo: its letter disc comes after the logos (place-pages 01).
        XCTAssertEqual(model.row(.business).map(\.name), ["Bruno Press", "White Peony Boutique", "Aardvark"])
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
        let model = SearchModel(supabase: supabase, defaults: defaults)
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
        XCTAssertEqual(model.results(for: "book", in: .all).first?.items.first?.name, "Book Discussion Group",
                       "typing still finds a Group under All (five-tabs 04)")
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
        let model = SearchModel(supabase: supabase, defaults: defaults)
        model.show([
            poi("stjoe-her-hair-studio", "Her Hair Studio", .business, "hair_salon"),
            poi("stjoe-gary", "Gary's Pizza", .food, "pizza_restaurant"),
        ])
        XCTAssertEqual(model.results(for: "hair", in: .all).first?.items.first?.name, "Her Hair Studio")
        XCTAssertEqual(model.results(for: "pizza", in: .businesses).map(\.kind), [.restaurant])
        XCTAssertTrue(model.results(for: "pizza", in: .parks).isEmpty)
        XCTAssertTrue(model.results(for: "   ", in: .all).isEmpty)
    }

    // MARK: Schools (BP app school-search 01)

    private func school(_ id: String, _ short: String, _ full: String? = nil, nickname: String? = nil,
                        aliases: [String]? = nil) -> LocalSchool {
        LocalSchool(id: id, uuid: "u-\(id)", name: short, schoolName: full, logoUrl: "https://x/\(id).webp",
                    shortName: short, nickname: nickname, aliases: aliases)
    }

    /// The Schools row: the Town's own Kennedy first, then the mock's order whatever the read's, and the
    /// co-op team left out. Each crest opens its school's page, not a business page.
    func testSchoolsRowLeadsWithKennedy() {
        let model = SearchModel(supabase: supabase, defaults: defaults)
        XCTAssertTrue(model.isLoading(.school), "a skeleton row until they're read")
        model.show(schools: [school("saint-johns", "Saint John's"), school("apollo-cathedral", "Apollo-Cathedral"),
                             school("tech", "Tech"), school("apollo", "Apollo"),
                             school("kennedy", "Kennedy", "Kennedy Community School", nickname: "Colts")],
                   activities: [SchoolActivity(id: "k1", teamId: "kennedy", name: "Girls Volleyball 7-8")])
        XCTAssertFalse(model.isLoading(.school))
        let row = model.row(.school)
        XCTAssertEqual(row.map(\.name), ["Kennedy Community School", "Apollo", "Tech", "Saint John's"],
                       "no activity on the row")
        XCTAssertEqual(row[0].team?.id, "u-kennedy", "it opens Kennedy's page")
        XCTAssertEqual(row[0].team?.short, "Kennedy")
        XCTAssertEqual(row[0].team?.nickname, "Colts")
        XCTAssertEqual(row[0].logo?.url.absoluteString, "https://x/kennedy.webp", "its crest, bare as a business logo")
        XCTAssertFalse(row[0].opens, "not the business page")
    }

    /// Typing finds a school by its name, its teams' nickname or another name, and by its activities' names:
    /// the schools named first, then each activity under its school's place in the row, Kennedy's first, in the
    /// school's own order. An activity opens its school's page and its star follows that activity.
    func testTypedSchoolsAndActivities() {
        let model = SearchModel(supabase: supabase, defaults: defaults)
        model.show(schools: [school("apollo", "Apollo", "Apollo High School", nickname: "Eagles"),
                             school("kennedy", "Kennedy", "Kennedy Community School", nickname: "Colts"),
                             school("saint-johns", "Saint John's", "Saint John's University", aliases: ["SJU"])],
                   activities: [SchoolActivity(id: "a1", teamId: "apollo", name: "Volleyball (girls)"),
                                SchoolActivity(id: "a2", teamId: "apollo", name: "Band"),
                                SchoolActivity(id: "k1", teamId: "kennedy", name: "Girls Volleyball 7-8"),
                                SchoolActivity(id: "k2", teamId: "kennedy", name: "Boys Volleyball 7-8"),
                                SchoolActivity(id: "x1", teamId: "apollo-cathedral", name: "Volleyball")])
        let schools = { (words: String) in model.results(for: words, in: .all).first { $0.kind == .school }?.items ?? [] }
        XCTAssertEqual(schools("kennedy").map(\.name), ["Kennedy Community School"], "its name, not every activity it has")
        XCTAssertEqual(schools("eagles").map(\.name), ["Apollo High School"])
        XCTAssertEqual(schools("sju").map(\.name), ["Saint John's University"])
        let volleyball = schools("volleyball")
        XCTAssertEqual(volleyball.map(\.name), ["Volleyball (girls)", "Girls Volleyball 7-8", "Boys Volleyball 7-8"],
                       "the closest match first, then the row's order, Kennedy's first; a team off the row has none")
        XCTAssertEqual(volleyball.map(\.sub), ["Apollo", "Kennedy", "Kennedy"], "its school's name under it")
        XCTAssertEqual(volleyball[1].team?.id, "u-kennedy", "a tap opens the school's page")
        XCTAssertEqual(volleyball[1].activity, FollowTarget(type: .activity, id: "k1"), "its star follows the activity")
        XCTAssertEqual(schools("girls volleyball").map(\.name), ["Girls Volleyball 7-8", "Volleyball (girls)"],
                       "every word matched, the closer first")
        XCTAssertNil(schools("kennedy")[0].activity, "a school has no star: its page has Follow")
        XCTAssertEqual(schools("apollo band").map(\.name), [], "an activity is found by its own name")
        XCTAssertEqual(model.results(for: "volleyball", in: .all).first?.kind, .school, "Schools lead under All")
        XCTAssertTrue(model.results(for: "volleyball", in: .businesses).isEmpty)
    }

    // MARK: Sports (BP app school-search 04)

    /// The Sports chip's discs: every school on the Schools row, the colleges first, then the high schools A to Z,
    /// then Kennedy (K-8) last, whatever order the read comes in; the co-op team stays out. A disc is its school
    /// with no activity, opening the school's page.
    func testSportsListsCollegesThenHighSchoolsThenKennedy() {
        let model = SearchModel(supabase: supabase, defaults: defaults)
        XCTAssertTrue(model.chips.contains(.sports), "its chip shows while the schools are read")
        model.show(schools: [school("kennedy", "Kennedy", "Kennedy Community School"), school("tech", "Tech"),
                             school("saint-johns", "Saint John's"), school("sauk-rapids-rice", "Sauk Rapids-Rice"),
                             school("apollo-cathedral", "Apollo-Cathedral"), school("rocori", "ROCORI"),
                             school("saint-benedict", "Saint Ben's", "College of Saint Benedict"),
                             school("sartell", "Sartell"), school("cathedral", "Cathedral"), school("apollo", "Apollo")],
                   activities: [SchoolActivity(id: "k1", teamId: "kennedy", name: "Girls Volleyball 7-8")])
        XCTAssertEqual(model.schoolDiscs.map { $0.team?.short }, ["Saint Ben's", "Saint John's", "Apollo", "Cathedral", "ROCORI",
                                                             "Sartell", "Sauk Rapids-Rice", "Tech", "Kennedy"])
        XCTAssertEqual(model.schoolDiscs.last?.team?.id, "u-kennedy", "a disc opens its school's page")
        XCTAssertEqual(model.schoolDiscs.last?.name, "Kennedy Community School", "its full name for VoiceOver and recents")
        XCTAssertTrue(model.schoolDiscs.allSatisfy { $0.activity == nil }, "no activity on the grid")
        XCTAssertTrue(model.chips.contains(.sports))
    }

    /// Typing on the Sports chip finds what All finds of the schools, by the same match (school-search 01), and
    /// nothing else: a business named alike stays under All.
    func testSearchInsideSportsFindsSchoolsAndActivities() {
        let model = SearchModel(supabase: supabase, defaults: defaults)
        model.show([poi("stjoe-eagles-nest", "Eagles Nest", .business, "store", logo: logo())])
        model.show(schools: [school("apollo", "Apollo", "Apollo High School", nickname: "Eagles"),
                             school("kennedy", "Kennedy", "Kennedy Community School", nickname: "Colts")],
                   activities: [SchoolActivity(id: "a1", teamId: "apollo", name: "Volleyball (girls)"),
                                SchoolActivity(id: "k1", teamId: "kennedy", name: "Girls Volleyball 7-8")])
        let sports = { (words: String) in model.results(for: words, in: .sports) }
        XCTAssertEqual(sports("volleyball").map(\.kind), [.school], "one list, no headings")
        XCTAssertEqual(sports("volleyball").first?.items.map(\.name), ["Volleyball (girls)", "Girls Volleyball 7-8"])
        XCTAssertEqual(sports("volleyball").first?.items.last?.activity, FollowTarget(type: .activity, id: "k1"),
                       "its star follows the activity")
        XCTAssertEqual(sports("eagles").first?.items.map(\.name), ["Apollo High School"], "not the Eagles Nest")
        XCTAssertEqual(model.results(for: "eagles", in: .all).map(\.kind), [.school, .business])
    }

    /// A starred activity fills in the school page's star colour, unless that one is too light for Search's paper.
    func testSearchStarTakesTheSchoolsColour() {
        XCTAssertEqual(ActivityStar.onPaper([0x1B2859, 0x1C532F, 0xCDCECF]), 0x1C532F, "Kennedy's green, as the mock")
        XCTAssertEqual(ActivityStar.onPaper([0xFEE291, 0x01447E]), 0x01447E, "Cathedral's gold would vanish on paper")
        XCTAssertEqual(ActivityStar.onPaper([0x135432, 0xFDCD30, 0xA8AFB0]), 0x135432, "so would Sauk Rapids-Rice's")
        XCTAssertEqual(ActivityStar.onPaper([0x1A4EA2]), 0x1A4EA2, "Sartell has one colour")
        XCTAssertNil(ActivityStar.onPaper([]), "none read yet: ink")
    }

    /// On Sports a tap on the empty field shows only the schools and activities opened before: no business, no
    /// words typed for something else. Every other pill shows them all.
    func testSportsRecentsAreSchoolsAndActivities() {
        defaults.set([String](), forKey: SearchModel.recentsKey)
        let model = SearchModel(supabase: supabase, defaults: defaults)
        model.show([poi("stjoe-krewe", "Krewe", .business, "store", logo: logo())])
        model.show(schools: [school("kennedy", "Kennedy", "Kennedy Community School")],
                   activities: [SchoolActivity(id: "k1", teamId: "kennedy", name: "Girls Volleyball 7-8")])
        for id in ["p:stjoe-krewe", "q:pumpkin", "a:k1", SearchItem.schoolID("u-kennedy")] { model.remember(id) }
        XCTAssertEqual(model.recents(in: .sports).map(\.id), ["s:u-kennedy", "a:k1"])
        XCTAssertEqual(model.recents(in: .all).map(\.id), ["s:u-kennedy", "a:k1", "q:pumpkin", "p:stjoe-krewe"])
    }

    /// The schools' read pages through every activity: Supabase answers at most 1,000 rows a request, and the Town's
    /// schools list 489 already.
    func testTheSchoolsReadPagesThroughEveryActivity() async throws {
        var offsets: [String] = []
        let send = Supabase.Send { @MainActor request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let offset = Int(query.first { $0.name == "offset" }?.value ?? "") ?? 0
            let rows = request.url!.lastPathComponent == "team_activities"
                ? (0..<5).dropFirst(offset).prefix(2).map { #"{"id": "a\#($0)", "team_id": "kennedy", "name": "A\#($0)"}"# }
                : []
            if request.url!.lastPathComponent == "team_activities" { offsets.append("\(offset)") }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data("[\(rows.joined(separator: ","))]".utf8), response)
        }
        let read = try await CommunityAPI(auth: FakeTokenProvider(), send: send).schoolsAndActivities(page: 2)
        XCTAssertEqual(read.activities.map(\.id), ["a0", "a1", "a2", "a3", "a4"])
        XCTAssertEqual(offsets, ["0", "2", "4"], "a short page is the last")
    }

    // MARK: Search at rest and its Events (five-tabs 04)

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Town.gregorian.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func card(_ id: String, day: String = "2026-11-03", time: String? = nil, allDay: Bool = false,
                      added: Date? = nil, photo: Bool = true, game: Bool = false, repeats: String? = nil,
                      cancelled: Bool = false) -> FeedCardItem {
        FeedCardItem(id: id, title: id, dateChip: "", metaLine: "",
                     image: photo ? .eventPhoto(URL(string: "https://x/\(id).webp")!) : .fallback, recurrence: repeats,
                     goingCount: 0, goingAvatars: [], likeCount: 0, isLiked: false, isJoined: false,
                     eventDate: day, startTime: time, allDay: allDay, cancelled: cancelled,
                     game: game ? Self.game : nil,
                     createdAt: added)
    }

    private static let game = try? JSONDecoder().decode(
        Game.Lenient.self, from: Data(#"{"sport":"Soccer","teams":[{"name":"CSB"},{"name":"Hamline"}]}"#.utf8)).value

    /// The pills are All, Businesses, Sports, Events and Parks: Groups and people left for Friends, Sports beside
    /// Businesses as the mock draws it (school-search 04).
    func testFivePills() {
        XCTAssertEqual(SearchChip.allCases.map(\.title), ["All", "Businesses", "Sports", "Events", "Parks"])
    }

    /// Search's Events are the Town feed's: shimmering until it's read, then what's on or still to come
    /// and not called off, soonest first, under Today, This week and Later, each opening its Event page,
    /// found by typing too. No made-up Rocktoberfest.
    func testEventsComeFromTheTownFeed() {
        let model = SearchModel(supabase: supabase, defaults: defaults)
        XCTAssertTrue(model.isLoading(.event))
        model.show(events: nil)
        XCTAssertTrue(model.isLoading(.event), "nil is the feed not read yet")
        let now = at(3, 10)
        model.show(events: [card("Later", day: "2026-11-20", time: "7 PM"), card("Over", time: "8 AM"),
                            card("Off", time: "6 PM", cancelled: true), card("Week", day: "2026-11-05", time: "7 PM"),
                            card("Bingo", time: "6:30 PM")], now: now)
        XCTAssertFalse(model.isLoading(.event))
        let row = model.row(.event)
        XCTAssertEqual(row.map(\.name), ["Bingo", "Week", "Later"])
        XCTAssertEqual(row.map(\.group), ["Today", "This week", "Later"])
        XCTAssertEqual(row.map(\.sub), ["6:30 PM", "Thu · 7 PM", "Fri · 7 PM"])
        XCTAssertEqual(row[0].card?.id, "Bingo", "it opens the Event page")
        XCTAssertEqual(row[0].photo, .card(.eventPhoto(URL(string: "https://x/Bingo.webp")!)))
        XCTAssertEqual(model.results(for: "bingo", in: .events).first?.items.first?.id, "e:Bingo")
        XCTAssertFalse(model.items.contains { $0.id == "e:Rocktoberfest" })
    }

    /// The first row's name and how long it lasts: morning from 5 to noon, afternoon to 5 PM, then
    /// tonight until 5 the next morning.
    func testPartOfTheDay() {
        XCTAssertEqual(SearchModel.dayPart(at(3, 5)).title, "This morning")
        XCTAssertEqual(SearchModel.dayPart(at(3, 11, 59)).ends, at(3, 12))
        XCTAssertEqual(SearchModel.dayPart(at(3, 12)).title, "This afternoon")
        XCTAssertEqual(SearchModel.dayPart(at(3, 17)).title, "Tonight")
        XCTAssertEqual(SearchModel.dayPart(at(3, 23)).ends, at(4, 5))
        XCTAssertEqual(SearchModel.dayPart(at(4, 2)).title, "Tonight")
        XCTAssertEqual(SearchModel.dayPart(at(4, 2)).ends, at(4, 5))
    }

    /// The part of the day's row: today's Events on now first, then those starting before it ends,
    /// all-day ones last; then the places open now with a page and a photo; ten at most.
    func testHappeningNow() {
        let model = SearchModel(supabase: supabase, defaults: defaults)
        var open = poi("stjoe-blend", "The Local Blend", .food, "coffee_shop", logo: logo(), entry: "blend")
        open.hours = PlaceHours(days: Array(repeating: [7 * 60 ..< 14 * 60], count: 7))
        var shut = poi("stjoe-bar", "Bad Habit", .food, "brewery", logo: logo(), entry: "bar")
        shut.hours = PlaceHours(days: Array(repeating: [16 * 60 ..< 22 * 60], count: 7))
        var bare = poi("stjoe-nophoto", "No Photo", .food, "restaurant", logo: logo(), entry: "none")
        bare.hours = open.hours
        model.show([open, shut, bare], photos: ["blend": [picture("blend")], "bar": [picture("bar")]])
        model.show(events: [card("Talk", time: "11 AM"), card("Class", time: "9:30 AM"), card("Vote", allDay: true),
                            card("No photo", time: "10:30 AM", photo: false),
                            card("Bingo", time: "6:30 PM"), card("Tomorrow", day: "2026-11-04", time: "9 AM")],
                   now: at(3, 10))
        let row = model.happening(at: at(3, 10))
        XCTAssertEqual(row.map(\.name), ["Class", "Talk", "Vote", "The Local Blend"])
        XCTAssertEqual(row.map(\.sub), ["Now", "11 AM", "All day", "Open till 2 PM"])
        XCTAssertEqual(row.last?.photo, .saved(picture("blend")))
        XCTAssertEqual(model.happening(at: at(3, 18)).map(\.name), ["Bingo", "Vote", "Bad Habit"],
                       "tonight: the evening's, and what's open then")
        model.show(events: (0..<12).map { card("E\($0)", time: "11 AM") }, now: at(3, 10))
        XCTAssertEqual(model.happening(at: at(3, 10)).count, SearchModel.restRowMax)
    }

    /// New in St. Joseph: the Events with a photo added in the last week, newest first, without games,
    /// a repeating series or what the part of the day's row shows, ten on the row and all on its page.
    func testNewThisWeek() {
        let model = SearchModel(supabase: supabase, defaults: defaults)
        let now = at(3, 10)
        model.show(events: [card("Old", day: "2026-11-20", added: at(1, 9) - 7 * 24 * 3600),
                            card("Concert", day: "2026-11-20", added: at(2, 9)),
                            card("Market", day: "2026-11-21", added: at(3, 8)),
                            card("Game", day: "2026-11-20", added: at(3, 8), game: true),
                            card("Yoga", day: "2026-11-20", added: at(3, 8), repeats: "Every Tuesday"),
                            card("Bare", day: "2026-11-20", added: at(3, 9), photo: false),
                            card("Unknown", day: "2026-11-20")], now: now)
        XCTAssertEqual(model.fresh(at: now).map(\.name), ["Market", "Concert"], "a row of photos")
        XCTAssertEqual(model.fresh(at: now, without: model.row(.event).filter { $0.name == "Market" }).map(\.name),
                       ["Concert"], "not what the row above shows")
        model.show(events: (0..<14).map { card("E\($0)", day: "2026-11-20", added: at(3, 9) - Double($0) * 60) }, now: now)
        XCTAssertEqual(model.fresh(at: now).map(\.name), (0..<10).map { "E\($0)" })
        XCTAssertEqual(model.fresh(at: now, all: true).count, 14)
    }

    /// Around town: every Event with a photo and every place with a page, by its cover, whole blocks
    /// of five; the same seed deals the same grid (back from an Event page), another seed reshuffles.
    func testAroundTown() {
        let model = SearchModel(supabase: supabase, defaults: defaults)
        model.show([poi("stjoe-blend", "The Local Blend", .food, "coffee_shop", logo: logo(), entry: "blend"),
                    poi("stjoe-shop", "Lee's Ace", .business, "hardware_store", logo: logo(), entry: "shop"),
                    poi("stjoe-nophoto", "No Photo Place", .food, "restaurant", entry: "nophoto")],
                   photos: ["blend": [picture("blend")], "shop": [picture("shop"), picture("shop2")]])
        // Eight Events and two places: exactly two blocks, so no shuffle can cut the one looked for below.
        model.show(events: (0..<8).map { card("E\($0)", day: "2026-11-20") } + [card("No photo", day: "2026-11-20", photo: false)],
                   now: at(3, 10))
        let grid = model.aroundTown(seed: 7)
        XCTAssertEqual(grid.count, 10, "8 Events and 2 places with a page")
        XCTAssertFalse(grid.contains { $0.name == "No photo" || $0.name == "No Photo Place" }, "never a tile with nothing to show")
        XCTAssertEqual(grid.first { $0.name == "Lee's Ace" }.map(\.photo) ?? nil, .saved(picture("shop")), "a business by its cover")
        XCTAssertEqual(model.aroundTown(seed: 7).map(\.id), grid.map(\.id))
        XCTAssertNotEqual(model.aroundTown(seed: 8).map(\.id), grid.map(\.id))
        // One more leaves a block short: only whole blocks show.
        model.show(events: (0..<9).map { card("E\($0)", day: "2026-11-20") }, now: at(3, 10))
        XCTAssertEqual(model.aroundTown(seed: 7).count, 10, "11 to deal, two whole blocks")
    }

    /// Newest first, no repeats, eight at most, and kept between launches.
    func testRecents() {
        defaults.set([String](), forKey: SearchModel.recentsKey)
        let model = SearchModel(supabase: supabase, defaults: defaults)
        for i in 0..<10 { model.remember("q:\(i)") }
        model.remember("q:3")
        XCTAssertEqual(model.recentIDs.count, SearchModel.recentsMax)
        XCTAssertEqual(model.recentIDs.first, "q:3")
        XCTAssertEqual(model.recentIDs.filter { $0 == "q:3" }.count, 1)
        model.forget("q:3")
        XCTAssertFalse(model.recentIDs.contains("q:3"))
        XCTAssertEqual(SearchModel(supabase: supabase, defaults: defaults).recentIDs, model.recentIDs)
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
