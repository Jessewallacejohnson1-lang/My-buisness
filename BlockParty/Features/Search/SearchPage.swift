//
//  SearchPage.swift
//  Block Party — the Search tab: "BlockParty." and the pill's word, a search field and filter pills
//  over, with nothing typed, the part of the day's row, New in St. Joseph and Around town
//  (`SearchAtRest`, BP app five-tabs 04). Tapping the field shows the recent searches; typing shows
//  results, Groups and neighbours too. A row's title ("Restaurants ›") opens the whole list, a logo
//  opens its business (`BusinessPage`) and an Event its Event page.
//
//  Reference: Jesse's Search mockup v7 with all six of its tweaks on, and its Figma
//  frames (2026-10-02). The sizes in `SearchMetric` are the mockup's, which it measured
//  from Instagram (faces), Photoroom (logo squares), Airbnb (photo cards, row spacing)
//  and iOS's own search field.
//

import SwiftUI

/// Search's sizes and motion, from the mockup (393pt-wide frames). Offsets "from the
/// top" are from the safe area's top: the mockup's frame is an iPhone whose safe area
/// starts 59pt down.
nonisolated enum SearchMetric {
    static let side: CGFloat = 16

    // The field, Cancel and the pills (the field's own height and insets are `SearchHead`'s; these are Friends').
    static let fieldHeight: CGFloat = 36
    static let fieldIcon: CGFloat = 17
    static let fieldIconLead: CGFloat = 10
    static let fieldIconGap: CGFloat = 6
    static let clearSide: CGFloat = 36
    /// While searching, the field's right edge moves in this far for Cancel, which
    /// slides in from `cancelSlide` to the right.
    static let cancelReserve: CGFloat = 68
    static let cancelSlide: CGFloat = 14
    static let chipsHeight: CGFloat = 40
    static let chipHeight: CGFloat = 34
    static let chipPad: CGFloat = 15
    static let chipGap: CGFloat = 8
    static let headBottom: CGFloat = 6
    /// The rows fade out under the pills over this much (Instagram's top edge).
    static let softEdge: CGFloat = 22
    static let softEdgeHaze: Double = 0.92

    // Sideways rows. 28 over a title and 14 under it: Airbnb's, measured.
    static let titleTop: CGFloat = 28
    static let titleBottom: CGFloat = 14
    static let titleGap: CGFloat = 6
    /// Photoroom's logo squares; the logo fills 66 of 78, its centre 47% down.
    static let logoOnTile: CGFloat = 66
    /// A result row's friends going, before its line (search-helpful 08's mock): 16 pt faces tucked 5 under, 5 from the words.
    static let rowFace: CGFloat = 16
    static let rowFaceTuck: CGFloat = 5
    static let rowFacesGap: CGFloat = 5
    /// A result row with no logo or photo: its kind's glyph, bare (the mock's 22 pt drawing).
    static let rowGlyph: CGFloat = 20
    /// A sideways row's logos (the Schools row), bare on the page with no tile (Jesse, 2026-10-24): 15% under
    /// 01's 92, with the one in the middle growing as the row scrolls (BP app search-logo-size 02, 2026-11-13).
    static let logoOnRow: CGFloat = 78
    static let logoGap: CGFloat = 10
    /// The logo nearest the screen's middle grows this much and rises `popRise`, falling off to nothing
    /// `popReach` either side (Jesse picked 10% and 4 pt from the mock, search-logo-size 02).
    static let popGrow: CGFloat = 0.10
    static let popRise: CGFloat = 4
    static let popReach: CGFloat = 150
    /// Four crests fit on any iPhone (358 pt), so such a row never scrolls and a lasting grow would only read
    /// as crests out of line: the grow starts at five.
    static let popFewest = 5

    /// How much a logo whose middle is at `midX` in a scroll view `width` wide grows: 1 at the middle, easing
    /// out to 0 at `popReach` on a half cosine, so it never jumps as the row moves.
    static func middlePop(midX: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        let away = min(abs(midX - width / 2) / popReach, 1)
        return (cos(.pi * away) + 1) / 2
    }
    static let logoCenterY: CGFloat = 0.47
    /// Airbnb's photo cards.
    static let cardWidth: CGFloat = 167
    static let cardPhoto: CGFloat = 157
    static let cardGap: CGFloat = 12
    static let cardTextTop: CGFloat = 8

    // The logo wall and the pushed pages.
    static let wallTop: CGFloat = 14
    static let wallGapX: CGFloat = 8
    static let wallGapY: CGFloat = 6
    static let logoOnWall: CGFloat = 96
    static let gridTop: CGFloat = 12
    static let gridGapY: CGFloat = 20

    // List rows: results, recents, people.
    static let row: CGFloat = 60
    static let rowGap: CGFloat = 12
    static let avatar: CGFloat = 44
    static let avatarLogo: CGFloat = 36
    /// A recent's remove cross: the mockup's 36 box, with its tap area grown to 44
    /// around the same centre.
    static let removeSide: CGFloat = 44
    static let removeTrail: CGFloat = 2
    static let sectionTop: CGFloat = 14
    static let sectionBottom: CGFloat = 6
    static let noneTop: CGFloat = 90
    /// The no-match line and the word chips, from the never-a-dead-end mock (search-helpful 03).
    static let noMatchTop: CGFloat = 18
    static let noMatchBottom: CGFloat = 8
    static let wordChipsTop: CGFloat = 4
    static let wordChipsBottom: CGFloat = 6
    /// A typed activity's star before its school's crest, and its › (school-search 01): the mock's 26 pt box,
    /// its 19 pt star and its 6 by 10 pt ›, measured.
    static let star: CGFloat = 26
    static let starGlyph: CGFloat = 18
    static let chevronGlyph: CGFloat = 11

    /// Clears the floating tab bar: the same 96 the other tab scrollers reserve.
    static let tabBarClearance: CGFloat = 96

    // Motion.
    /// A new view of the results fades in, rising this far.
    static let enterRise: CGFloat = 10

    // The logo shine (`LogoShine`), from the mock Jesse picked on 2026-10-11 ("360 light").
    // Held level, the glow sits on the logo's middle, a light shining straight down (Jesse).
    /// How far a full lean (`PhoneTilt.range`, about 17°) carries the glow from the middle,
    /// either way on either axis, as a share of the logo's side. From the mock; to tune on
    /// the phone.
    static let shineTravel: CGFloat = 0.62
    /// The glow's reach either side of its middle, as a share of the logo's side: an oval
    /// wider than tall, the mock's 78% by 58% (Jesse: not round). Its white at the middle,
    /// at `shineShoulderAt` of the reach, and gone by `shineFadeAt`: 40% fainter than the
    /// mock first showed (Jesse).
    static let shineReachX: CGFloat = 0.78
    static let shineReachY: CGFloat = 0.58
    static let shinePeak: Double = 0.3
    static let shineShoulder: Double = 0.096
    static let shineShoulderAt: CGFloat = 0.36
    static let shineFadeAt: CGFloat = 0.7

    // The business page (`BusinessPage`). Laid out with the Event page's sizes
    // (`EventPage.Metric`); these are its own.
    static let openResponse: CGFloat = 0.5
    static let openDamping: CGFloat = 0.84
    static let closeResponse: CGFloat = 0.4
    static let settleResponse: CGFloat = 0.45
    static let settleDamping: CGFloat = 0.9
    static let bizLogo: CGFloat = 76
    static let bizLogoRight: CGFloat = 10
    static let bizLogoCenter: CGFloat = 29
    static let bizBackFrom: CGFloat = 0.6
    /// The band under the safe area's top that a drag down closes the page from.
    static let bizBand: CGFloat = 69
    /// A drag on the band counts once it has gone this far, so it can tell up and down from
    /// sideways.
    static let bizDragStart: CGFloat = 10
    /// A finger drag this long closes the page from fully open.
    static let bizDrag: CGFloat = 520
    static let bizOverDrag: CGFloat = 1.04
    /// Let go faster than this downward (pt/s), or under this far open, and it closes.
    static let bizFlick: CGFloat = 500
    static let bizKeepOpen: CGFloat = 0.6
    static let liftStretch: CGFloat = 1.6
    static let liftFade: Double = 0.25
    /// The address and link rows' glyph box: wide enough for the globe, so every row's words
    /// start together (picked).
    static let bizGlyphBox: CGFloat = 16
    /// Between link rows, and from the About to the first (picked).
    static let bizLinkGap: CGFloat = 10
    static let bizLinksTop: CGFloat = 24
}

/// A row's whole list, pushed from its title.
struct SearchShelf: Hashable {
    let kind: SearchItem.Kind
    let title: String
    let items: [SearchItem]
}

struct SearchPage: View {
    @Bindable var model: SearchModel
    /// The Town feed's cards once it has read them, nil before: Search's Events (five-tabs 04).
    let cards: [FeedCardItem]?
    /// The Town feed's News, which typing finds (search-helpful 07).
    var news: [TownNews] = []
    /// Around town's shuffle: a new one each visit, since the shell builds the tab again on every
    /// switch, and the same one back from an Event page, so the grid never moves under the thumb.
    @State private var seed = UInt64.random(in: 0 ... .max)
    @State private var opener = BusinessOpener()
    /// Each page follows the tilt on its own: a pushed row's page has its own.
    @State private var tilt = PhoneTilt()
    /// How far the Sports grid's scroll has carried the header (`CarriedHeader`).
    @State private var travel = BarTravel()
    @FocusState private var fieldFocused: Bool
    @Namespace private var chipNS
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var auth: AuthStore
    @Environment(FriendsBook.self) private var book

    private enum Mode: Hashable {
        case rest, wall, sports, schools, calendar, groups(SearchItem.Kind), recents, results(SearchChip)
    }

    private var mode: Mode {
        if !model.words.trimmingCharacters(in: .whitespaces).isEmpty { return .results(model.chip) }
        if model.searching { return .recents }
        switch model.chip {
        case .all: return .rest
        case .businesses: return .wall
        case .sports: return .sports
        case .schools: return .schools
        case .calendar: return .calendar
        case .events: return .groups(.event)
        }
    }

    /// The Sports and Schools chips turn the page to the app's dark colours, searching and typed results included
    /// (school-search 04): the mock Jesse picked.
    private var sports: Bool { model.chip.isDark }

    /// The grids that carry the header away with their scroll, as the mock's field and pills scroll with the discs.
    private var carries: Bool { mode == .sports || mode == .schools }

    private var head: SearchHead { .of(model.chip) }

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                // Covered by an open business, the logos stop following the tilt.
                content.environment(opener.isOpen ? nil : tilt)
                CarriedHeader(travel: travel) { header }
            }
            .environment(\.colorScheme, sports ? .dark : scheme)
            BusinessPage()
        }
        .environment(model)
        .environment(opener)
        .following(tilt)
        .navigationDestination(for: SearchShelf.self) { shelf in
            SearchShelfPage(shelf: shelf).environment(model)
        }
        .navigationDestination(for: SportShelf.self) { sport in
            SportPage(sport: sport).environment(model)
        }
        .task {
            await model.load()
            #if DEBUG
            openDebugBusiness()
            #endif
        }
        .onAppear {
            opener.reduceMotion = reduceMotion
            #if DEBUG
            if let debug = Self.debugChip { model.chip = debug }
            if let debug = Self.debugWords { model.words = debug }
            if Self.debugSearching { model.searching = true }
            if LaunchFlags.has(.pillCycle) { cyclePills(1) }
            #endif
        }
        .onChange(of: fieldFocused) { _, focused in
            if focused { model.searching = true }
        }
        .onChange(of: opener.item?.id) { _, id in
            if id != nil { fieldFocused = false }
        }
        // Neighbours are asked for as the words change, and again once an account logs in;
        // only under All, the pill that shows them.
        .onChange(of: model.words, initial: true) { searchPeople() }
        .onChange(of: model.chip) { searchPeople() }
        .onChange(of: auth.accountKey) { searchPeople() }
        // Which activities this account follows, for the stars on typed activities (school-search 01).
        .task(id: auth.accountKey) { await model.readStars() }
        .onChange(of: cards, initial: true) { model.show(events: cards) }
        .onChange(of: news, initial: true) { model.show(news: news) }
        // People rows carry the friend button; a failed tap shakes only while Search is open.
        .onScreen { book.screenOpened() } disappear: { book.screenClosed() }
    }

    // MARK: Header

    private var header: some View {
        // Every pill's header has the Sports one's sizes (search-titles 02); `SearchHead` holds what differs.
        // The field's and chips' glass blend only with each other, never across the 8 pt between chips.
        GlassEffectContainer(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                SportsTitle(word: head.word)
                fieldRow
                    .padding(.top, SearchMetric.sportsFieldTop)
                chips
                    .padding(.top, SearchMetric.sportsChipsTop)
            }
        }
        .padding(.bottom, SearchMetric.headBottom)
        // The page's own ground behind it, opaque down to its foot and fading over the rows under it
        // (Instagram's top edge): drawn from the screen's top, so on Sports it is the same slice of the fade. None
        // while the Sports grid carries the header: nothing ever passes under it.
        .background(alignment: .top) {
            if !carries {
                ground
                    .mask {
                        VStack(spacing: 0) {
                            Color.black
                            LinearGradient(colors: [.black.opacity(SearchMetric.softEdgeHaze), .clear],
                                           startPoint: .top, endPoint: .bottom)
                                .frame(height: SearchMetric.softEdge)
                        }
                    }
                    .padding(.bottom, -SearchMetric.softEdge)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    /// The page's ground, from the top of the screen: on Sports its dark warm-grey fade (the mock's); on every other
    /// pill the Event calendar's light one, the same one, so changing pills never flashes (BP app search-titles 02).
    @ViewBuilder private var ground: some View {
        if sports {
            SportsFade()
        } else {
            SportsFade.calendar
        }
    }

    private var fieldRow: some View {
        ZStack(alignment: .trailing) {
            field
                .padding(.trailing, model.searching ? SearchMetric.cancelReserve : 0)
            Button { cancel() } label: {
                Text("Cancel")
                    .font(.sans(16))
                    .foregroundStyle(Hue.ink)
                    .frame(height: PageMetric.tapMin)
                    .contentShape(Rectangle())
            }
                .buttonStyle(.press(.dim))
                .opacity(model.searching ? 1 : 0)
                .offset(x: model.searching ? 0 : SearchMetric.cancelSlide)
                .allowsHitTesting(model.searching)
                .accessibilityHidden(!model.searching)
        }
        .padding(.horizontal, SearchMetric.sportsSide)
        .frame(height: SearchMetric.sportsFieldHeight)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 1), value: model.searching)
    }

    private var field: some View {
        let head = head
        let shape = Capsule(style: .continuous)
        return HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.glyph(SearchMetric.sportsFieldGlyph, weight: .medium))
                .foregroundStyle(head.faint)
                .frame(width: SearchMetric.fieldIcon, height: SearchMetric.fieldIcon)
                .padding(.leading, SearchMetric.sportsFieldIconLead)
                .padding(.trailing, SearchMetric.sportsFieldIconGap)
                .accessibilityHidden(true)
            TextField(head.prompt, text: $model.words, prompt: Text(head.prompt).foregroundStyle(head.faint))
                .font(.sans(SearchMetric.sportsFieldGlyph))
                .foregroundStyle(Hue.ink)
                .focused($fieldFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit(submit)
            if !model.words.isEmpty {
                Button {
                    model.words = ""
                    fieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Hue.surface, Hue.searchClear)
                        .font(.glyph(17))
                        .frame(width: SearchMetric.clearSide, height: SearchMetric.clearSide)
                        .contentShape(Rectangle().inset(by: (SearchMetric.clearSide - PageMetric.tapMin) / 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .frame(height: SearchMetric.sportsFieldHeight)
        // The whole pill takes the tap, not only the text line (Clear keeps its own).
        .contentShape(shape)
        .onTapGesture { fieldFocused = true }
        // Sports' glass on every pill, ink at 7% (Jesse: "all the search bars have the glass effect the sports page
        // do", search-titles Check-in 2).
        .glassEffect(.regular.tint(Hue.ink.opacity(SearchMetric.sportsFieldGlass)), in: shape)
    }

    private var chips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SearchMetric.chipGap) {
                    ForEach(model.chips, id: \.self) { c in
                        chipButton(c).id(c)
                    }
                }
                .padding(.horizontal, SearchMetric.sportsSide)
                .frame(height: SearchMetric.chipsHeight)
            }
            .onChange(of: model.chip) { _, c in
                withAnimation(reduceMotion ? nil : .smooth) { proxy.scrollTo(c, anchor: .center) }
            }
        }
        .frame(height: SearchMetric.chipsHeight)
    }

    private func chipButton(_ c: SearchChip) -> some View {
        let on = c == model.chip
        return Button { Self.pick(c, in: model, reduceMotion: reduceMotion) } label: {
            Text(c.title)
                .font(.sansSemibold(14))
                // Selected: ink with the page's paper in it, as every selected state (on Sports, the dark ramp's).
                .foregroundStyle(on ? head.chipWordsOn : Hue.ink)
                .padding(.horizontal, SearchMetric.chipPad)
                .frame(height: SearchMetric.chipHeight)
                .background {
                    if on {
                        Capsule().fill(Hue.ink).matchedGeometryEffect(id: "chip", in: chipNS)
                    } else {
                        Capsule().strokeBorder(Hue.searchChipEdge, lineWidth: 1)
                    }
                }
                // On Sports every chip is glass, ink at 5%, the selected one under its ink.
                .glassEffect(head.chipGlass, in: Capsule())
                .contentShape(Rectangle().inset(by: (SearchMetric.chipHeight - PageMetric.tapMin) / 2))
        }
        .buttonStyle(.press(.squish))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Content

    private var content: some View {
        ZStack {
            ground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    modeBody
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, SearchMetric.sportsHeadHeight)
                .padding(.bottom, SearchMetric.tabBarClearance)
            }
            .scrollDismissesKeyboard(.immediately)
            .scrollRun()
            // The Sports grid carries the header with it; every other view keeps it pinned.
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in
                travel.points = carries ? y : 0
            }
            .id(mode)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: SearchMetric.enterRise)),
                                    removal: .identity))
        }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1), value: mode)
        .onChange(of: mode) {
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1)) { travel.points = 0 }
        }
    }

    @ViewBuilder private var modeBody: some View {
        switch mode {
        case .rest:
            SearchAtRest(seed: seed)
        case .wall:
            LogoWall(items: model.row(.business))
        case .sports:
            SportsGrid()
        case .schools:
            SchoolsGrid()
        case .calendar:
            EventCalendarView()
        case .groups(let kind):
            let items = model.row(kind)
            let title = SearchPage.sectionTitle(kind)
            let groups = items.reduce(into: [String]()) { if !$0.contains($1.group ?? title) { $0.append($1.group ?? title) } }
            ForEach(groups, id: \.self) { group in
                shelf(kind, group, items.filter { ($0.group ?? title) == group })
            }
        case .recents:
            let recents = model.recents(in: model.chip)
            // A first visit is never a blank page: Nextdoor's Trending chips, under All only (search-helpful 03).
            if model.chip == .all {
                SectionTitle(text: "Try")
                WordChips(words: model.trying()) { model.words = $0.lowercased() }
            }
            if !recents.isEmpty {
                SectionTitle(text: "Recent")
                ForEach(recents) { recent in
                    switch recent {
                    case .item(let item): ItemRow(item: item, removable: true)
                    case .query(let words): QueryRow(words: words) { model.words = words }
                    }
                }
                .transition(.opacity)
            }
        case .results(let chip):
            // One list, best first, no section titles (search-helpful 03, Instagram's typed results).
            let matches = model.matches(for: model.words, in: chip)
            // Less anyone you just blocked (ticket 04).
            let people = book.visible(chip == .all ? model.people.state : .idle)
            if matches.isEmpty && !people.hasRows {
                // Nothing here yet: wait for the neighbours' answer and the pill's rows before saying so.
                if people != .loading && !chip.resultKinds.contains(where: model.isLoading) && !model.findsMoreSoon(in: chip) {
                    NoMatch(words: model.words.trimmingCharacters(in: .whitespacesAndNewlines),
                            chips: model.nearby(in: chip),
                            week: chip == .all || chip == .events ? model.thisWeek : []) { model.words = $0.lowercased() }
                }
            } else {
                // While typing, the words are row 1: a tap, like the keyboard's Search key, puts the keyboard
                // away on the results (Instagram's words row).
                if fieldFocused {
                    QueryRow(words: model.words.trimmingCharacters(in: .whitespacesAndNewlines), glyph: "magnifyingglass",
                             removable: false) { submit() }
                }
                ForEach(matches) { ItemRow(item: $0) }
                PeopleResults(state: people)
            }
        }
    }

    /// A row: its title, real while the places load, then its tiles or their stand-ins.
    @ViewBuilder
    private func shelf(_ kind: SearchItem.Kind, _ title: String, _ items: [SearchItem]? = nil) -> some View {
        let items = items ?? model.row(kind)
        if model.isLoading(kind) {
            ShelfTitle(title: title, shelf: nil)
            ShelfSkeleton(kind: kind)
        } else if !items.isEmpty {
            ShelfTitle(title: title, shelf: SearchShelf(kind: kind, title: title, items: items))
            Shelf(kind: kind, items: items)
        }
    }

    static func sectionTitle(_ kind: SearchItem.Kind) -> String {
        switch kind {
        case .person: "People"
        case .school: "Schools"
        case .business: "Businesses"
        case .restaurant: "Restaurants"
        case .coffee: "Coffee"
        case .event: "Events"
        case .page: "Pages"
        case .news: "News"
        case .club: "Groups"
        case .park: "Parks"
        }
    }

    // MARK: Actions

    /// A pill's tap, and "Schools ›" on the Schools row, which opens the Schools chip (school-search 10).
    /// Into or out of Sports or Schools the page turns at once, as Instagram's dark Reels tab does: the whole page changes
    /// colour, glass draws where it lands rather than where it travels (swift-traps), and the ticket asks for no
    /// wait the reader can see. Between the other pills the selection slides as before.
    static func pick(_ c: SearchChip, in model: SearchModel, reduceMotion: Bool) {
        guard c != model.chip else { return }
        Haptics.selection()
        if c.isDark != model.chip.isDark {
            var turn = Transaction(animation: nil)
            turn.disablesAnimations = true
            withTransaction(turn) { model.chip = c }
        } else {
            withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86)) { model.chip = c }
        }
    }

    private func submit() {
        let q = model.words.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { model.remember(SearchModel.queryID(q)) }
        fieldFocused = false
    }

    private func searchPeople() {
        model.people.search(model.chip == .all ? model.words : "")
    }

    private func cancel() {
        model.searching = false
        model.words = ""
        fieldFocused = false
    }

    // MARK: DEBUG launch flags (docs/debug-flags.md)

    #if DEBUG
    /// `-search-words <text>`: opens with those words typed.
    private static var debugWords: String? { LaunchFlags.value(.searchWords) }
    /// Once a launch, so coming back to Search doesn't open it again.
    private static var debugBusinessOpened = false
    /// `-open-business <place id>` (with `-open-tab search`): opens that business's page once
    /// Search has read it, out of a small tile mid-screen as from a photo card, so a
    /// place-photos check needn't find it on the wall (BP app backlog 03).
    private func openDebugBusiness() {
        guard !Self.debugBusinessOpened, let id = LaunchFlags.value(.openBusiness),
              let item = model.items.first(where: { $0.id == id || $0.id == "p:\(id)" }), item.opens else { return }
        Self.debugBusinessOpened = true
        let size = SearchMetric.logoOnTile, rect = CGRect(x: 160, y: 400, width: size, height: size)
        opener.open(item, from: .tile(item, box: rect, radius: 0))
    }
    /// `-search-focus`: opens on the recents, as after a tap on the field.
    private static var debugSearching: Bool {
        LaunchFlags.has(.searchFocus) || debugWords != nil
    }
    /// `-pill-cycle`: the pills tapped in turn every 2.5 s, each timed by `-frame-gap-log` (BP app tab-lag 02).
    private func cyclePills(_ index: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            let chips = model.chips
            let chip = chips[index % chips.count]
            FrameGapLog.shared.tapped("pill-\(chip)")
            Self.pick(chip, in: model, reduceMotion: reduceMotion)
            cyclePills(index + 1)
        }
    }
    /// `-search-chip <all|calendar|businesses|sports|events>`: opens on that filter.
    private static var debugChip: SearchChip? {
        LaunchFlags.value(.searchChip).flatMap { name in SearchChip.allCases.first { $0.title.lowercased() == name || "\($0)" == name } }
    }
    #endif
}

// MARK: - Rows

struct ShelfTitle: View {
    let title: String
    let shelf: SearchShelf?
    /// The ›, real while a row loads; off for a row with no list of its own (`SearchAtRest`).
    var chevron = true
    /// What it opens when its list is somewhere other than a pushed page: the Schools row's is the Sports chip.
    var tap: (() -> Void)? = nil

    var body: some View {
        if let shelf {
            NavigationLink(value: shelf) { label }
                .buttonStyle(.press(.dim))
        } else if let tap {
            Button(action: tap) { label }
                .buttonStyle(.press(.dim))
        } else {
            label
        }
    }

    private var label: some View {
        HStack(spacing: SearchMetric.titleGap) {
            Text(title)
                .font(.displaySemi(17))
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.glyph(12, weight: .bold))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(Hue.ink)
        .padding(.top, SearchMetric.titleTop)
        .padding(.bottom, SearchMetric.titleBottom)
        .padding(.horizontal, SearchMetric.side)
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isHeader)
    }
}

struct Shelf: View {
    let kind: SearchItem.Kind
    let items: [SearchItem]
    /// New in St. Joseph's cards wear the New tag.
    var new = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: Shelf.gap(kind)) {
                ForEach(items) { item in
                    switch kind {
                    case .business:
                        RowLogo(item: item)
                    case .school:
                        RowCrest(item: item).modifier(MiddlePop(off: items.count < SearchMetric.popFewest))
                    default:
                        PhotoCard(item: item, new: new)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, SearchMetric.side, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        // A logo swings in from above its tile (`LogoPop`): the row mustn't cut its top off.
        .scrollClipDisabled(Self.showsLogos(kind))
    }

    /// A row of bare logos, the Businesses row's size and gap, rather than photo cards: a school's crests too.
    static func showsLogos(_ kind: SearchItem.Kind) -> Bool { kind == .business || kind == .school }

    static func gap(_ kind: SearchItem.Kind) -> CGFloat {
        showsLogos(kind) ? SearchMetric.logoGap : SearchMetric.cardGap
    }
}

/// A logo on a sideways row grows and rises as it nears the middle of the screen, read from its place in the
/// scroll view each frame, so it follows the finger both ways and rests the same once the row settles (Jesse:
/// "when you're scrolling, the ones in the middle pop up just a tiny bit more", search-logo-size 02). Still
/// with Reduce Motion, and on a row too short to scroll. The row doesn't clip (`scrollClipDisabled`), so the grown
/// top is never cut.
private struct MiddlePop: ViewModifier {
    var off = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let still = reduceMotion || off
        content.visualEffect { effect, proxy in
            // The row's visible bounds in this logo's own space: its middle is `size.width / 2 - minX` from
            // the row's leading edge.
            let row = proxy.bounds(of: .scrollView(axis: .horizontal)) ?? .zero
            let pop = still ? 0 : SearchMetric.middlePop(midX: proxy.size.width / 2 - row.minX, width: row.width)
            return effect
                .scaleEffect(1 + SearchMetric.popGrow * pop)
                .offset(y: -SearchMetric.popRise * pop)
        }
    }
}

/// A row still waiting on the places: its tiles' shapes, in their places.
struct ShelfSkeleton: View {
    let kind: SearchItem.Kind

    var body: some View {
        HStack(alignment: .top, spacing: Shelf.gap(kind)) {
            ForEach(0..<6, id: \.self) { _ in
                if Shelf.showsLogos(kind) {
                    SkeletonBlock(cornerRadius: Radius.logoTile)
                        .frame(width: SearchMetric.logoOnRow, height: SearchMetric.logoOnRow)
                } else {
                    VStack(alignment: .leading, spacing: SearchMetric.cardTextTop) {
                        SkeletonBlock(cornerRadius: Radius.photoCard)
                            .frame(width: SearchMetric.cardWidth, height: SearchMetric.cardPhoto)
                        SkeletonLine(widthFraction: 0.7)
                            .frame(width: SearchMetric.cardWidth)
                    }
                }
            }
        }
        .padding(.horizontal, SearchMetric.side)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .shimmering()
        .accessibilityLabel("Loading")
    }
}

private struct RowLogo: View {
    let item: SearchItem
    @Environment(SearchModel.self) private var model
    @Environment(BusinessOpener.self) private var opener
    @State private var frame = FrameBox()

    var body: some View {
        let size = SearchMetric.logoOnRow
        Button {
            // No tile to grow out of: the backdrop grows from the logo, as from the wall.
            let rect = frame.rect
            model.remember(item.id)
            opener.open(item, from: .init(logo: rect, box: rect, radius: 0, shadow: item.markShadow))
        } label: {
            PlaceMark(item: item, side: size)
                .opacity(opener.isAway(item) ? 0 : 1)
                .animation(nil, value: opener.isAway(item))
                .contentShape(Rectangle())
                .trackFrame(frame)
        }
        .buttonStyle(.press(.squish))
        .accessibilityLabel(item.name)
    }
}

/// A school's crest on the Schools row (school-search 01): bare, the Businesses row's size and shadow, pushing
/// the school's page as Search pushes a group's.
private struct RowCrest: View {
    let item: SearchItem

    var body: some View {
        OpenButton(item: item, press: .squish, tap: {}) {
            PlaceMark(item: item, side: SearchMetric.logoOnRow)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(item.name)
    }
}

/// A place's mark at `side`: its logo, cast on the page and popping in once loaded, or, with no logo yet,
/// its first letter on a disc of the light fill, as a young team's (place-pages 01).
struct PlaceMark: View {
    let item: SearchItem
    let side: CGFloat
    var shadow: Color? = nil

    var body: some View {
        if let logo = item.logo {
            CastLogo(logo: logo, side: side, shadow: shadow)
                .logoPop(logo.url, skeleton: SkeletonBlock(cornerRadius: Radius.logoTile).frame(width: side, height: side))
        } else {
            LetterDisc(initial: item.initial, side: side)
        }
    }
}

/// The first letter of a place's name on a disc of the light fill, the size a logo would be: the mark of a
/// place with no logo yet, as a young team's on the game card (`LogoDisc`, Jesse 2026-11-05 and 2026-11-08).
struct LetterDisc: View {
    let initial: String
    let side: CGFloat

    var body: some View {
        LogoDisc(logo: nil, initial: initial, logoSide: side, letter: .sansSemibold((side * 0.42).rounded()),
                 disc: false, blank: Hue.fill)
            .frame(width: side, height: side)
    }
}

/// Every business logo, cut out and bare on the page; a place with no logo yet, its letter disc.
private struct LogoWall: View {
    let items: [SearchItem]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: SearchMetric.wallGapX), count: 3),
                  spacing: SearchMetric.wallGapY) {
            ForEach(items) { item in
                WallLogo(item: item)
            }
        }
        .padding(.horizontal, SearchMetric.side)
        .padding(.top, SearchMetric.wallTop)
    }
}

private struct WallLogo: View {
    let item: SearchItem
    @Environment(SearchModel.self) private var model
    @Environment(BusinessOpener.self) private var opener
    @State private var frame = FrameBox()

    private var shadow: Color { Hue.hsl(Hue.searchStudioHue, 15, 18) }

    var body: some View {
        let size = SearchMetric.logoOnWall
        Button {
            let cell = frame.rect
            let rect = CGRect(x: cell.midX - size / 2, y: cell.minY + cell.height * SearchMetric.logoCenterY - size / 2,
                              width: size, height: size)
            model.remember(item.id)
            opener.open(item, from: .init(logo: rect, box: rect, radius: 0, shadow: shadow))
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    GeometryReader { cell in
                        PlaceMark(item: item, side: size, shadow: shadow)
                            .position(x: cell.size.width / 2, y: cell.size.height * SearchMetric.logoCenterY)
                    }
                }
                .opacity(opener.isAway(item) ? 0 : 1)
                .animation(nil, value: opener.isAway(item))
                .contentShape(Rectangle())
                .trackFrame(frame)
        }
        .buttonStyle(.press(.squish))
        .accessibilityLabel(item.name)
    }
}

struct PhotoCard: View {
    let item: SearchItem
    /// nil fills a grid column.
    var width: CGFloat? = SearchMetric.cardWidth
    /// New in St. Joseph's cards wear the mock's yellow New tag (five-tabs 04).
    var new = false
    @Environment(SearchModel.self) private var model
    @Environment(BusinessOpener.self) private var opener
    @State private var photoFrame = FrameBox()

    var body: some View {
        OpenButton(item: item, press: .squish, tap: tap) {
            VStack(alignment: .leading, spacing: 0) {
                SearchPhoto(item: item)
                    .frame(maxWidth: .infinity)
                    .frame(height: SearchMetric.cardPhoto)
                    .overlay(alignment: .topLeading) { if new { NewTag() } }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.photoCard, style: .continuous))
                    // Away on its business's page while that is open: there is only ever one.
                    .opacity(opener.isAway(item, from: photoFrame.rect) ? 0 : 1)
                    .animation(nil, value: opener.isAway(item))
                    .trackFrame(photoFrame)
                Text(item.name)
                    .font(.sansSemibold(15))
                    .foregroundStyle(Hue.ink)
                    .lineLimit(1)
                    .padding(.top, SearchMetric.cardTextTop)
                // Each minute, so an Event's "In 20 min" counts down and turns Now (BP app happening-now 07).
                TimelineView(.everyMinute) { context in
                    if let line = item.line(context.date) {
                        Text(line)
                            .font(.sans(14))
                            .foregroundStyle(Hue.inkSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: width)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        }
        // New in St. Joseph's say so first; the tag itself is hidden from VoiceOver.
        .accessibilityLabel([new ? "New" : nil, item.name, item.line(.now)].compactMap { $0 }.joined(separator: ", "))
    }

    /// A restaurant or coffee shop opens its page from the photo: the photo itself grows into the
    /// page's top photo (BP app place-photos 10).
    private func tap() {
        model.remember(item.id)
        guard item.opens else { return }
        opener.open(item, from: .tile(item, box: photoFrame.rect, radius: Radius.photoCard))
    }
}

/// Neighbours for the words typed, after the places, so the rows above stay put when they
/// arrive (BP app docs/plans/friends, ticket 02).
/// Never saved to Recent: a neighbour's name and photo stay off the phone.
/// Neighbours for the typed words, untitled after the one list (search-helpful 03).
private struct PeopleResults: View {
    let state: NeighborSearch.State

    var body: some View {
        switch state {
        case .found(let people):
            // Facebook's result with its button under the name, in Search's smaller sizes.
            ForEach(Neighbor.friendsFirst(people)) { person in
                ResultRow(person: person, face: SearchMetric.avatar, nameFont: .sansSemibold(14))
            }
        case .failed:
            // The Town feed's words for a read that failed, as on the Friends page.
            Text("Check your connection and try again.")
                .font(.sans(13))
                .foregroundStyle(Hue.inkSecondary)
                .padding(.horizontal, SearchMetric.side)
                .frame(height: SearchMetric.row)
        default:
            EmptyView()
        }
    }
}

private struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.display(16))
            .foregroundStyle(Hue.ink)
            .padding(.top, SearchMetric.sectionTop)
            .padding(.bottom, SearchMetric.sectionBottom)
            .padding(.horizontal, SearchMetric.side)
            .accessibilityAddTraits(.isHeader)
    }
}

/// What a card, row or tile does when tapped: a group's pushes its Group page, an Event's its Event
/// page and a school's or its activity's the school's page, each remembered as a recent; anything else
/// runs `tap`, which remembers it itself.
struct OpenButton<Label: View>: View {
    let item: SearchItem
    let press: Press
    let tap: () -> Void
    @ViewBuilder let label: () -> Label
    @Environment(SearchModel.self) private var model
    @Environment(\.openNews) private var openNews

    var body: some View {
        if let group = item.townGroup {
            NavigationLink(value: group, label: label)
                .buttonStyle(.press(press))
                .simultaneousGesture(TapGesture().onEnded { model.remember(item.id) })
        } else if let card = item.card {
            NavigationLink(value: card, label: label)
                .buttonStyle(.press(press))
                .simultaneousGesture(TapGesture().onEnded { model.remember(item.id) })
        } else if let team = item.team {
            NavigationLink(value: team, label: label)
                .buttonStyle(.press(press))
                .simultaneousGesture(TapGesture().onEnded { model.remember(item.id) })
        } else if let page = item.page {
            NavigationLink(value: page, label: label)
                .buttonStyle(.press(press))
                .simultaneousGesture(TapGesture().onEnded { model.remember(item.id) })
        } else if let board = item.board {
            NavigationLink(value: board, label: label)
                .buttonStyle(.press(press))
                .simultaneousGesture(TapGesture().onEnded { model.remember(item.id) })
        } else if let news = item.news {
            Button {
                model.remember(item.id)
                openNews?(news)
            } label: { label() }
                .buttonStyle(.press(press))
        } else {
            Button(action: tap, label: label)
                .buttonStyle(.press(press))
        }
    }
}

/// A result, a recent, or a neighbour: picture, name, and what it is. A school's activity has its
/// star before them and a › after (the mock, school-search 01).
struct ItemRow: View {
    let item: SearchItem
    var removable = false
    @Environment(SearchModel.self) private var model
    @Environment(BusinessOpener.self) private var opener
    @Environment(\.colorScheme) private var scheme
    @State private var avatarFrame = FrameBox()

    /// An activity's star, on a result: a recent has its X instead (the run's review).
    private var star: FollowTarget? { removable ? nil : item.activity }

    var body: some View {
        ZStack(alignment: .trailing) {
            OpenButton(item: item, press: .row, tap: tap) {
                HStack(spacing: SearchMetric.rowGap) {
                    // The star's room: it lies over the row, so a tap on it never opens the page.
                    if star != nil { Color.clear.frame(width: SearchMetric.star) }
                    avatar
                        .frame(width: SearchMetric.avatar, height: SearchMetric.avatar)
                        .trackFrame(avatarFrame)
                    // Each minute, so an Event's "In 20 min" counts down and turns Now (BP app happening-now 07).
                    TimelineView(.everyMinute) { context in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.name)
                                .font(.sansSemibold(14))
                                .foregroundStyle(Hue.ink)
                                .lineLimit(1)
                            if let line = item.rowLine(context.date) {
                                HStack(spacing: SearchMetric.rowFacesGap) {
                                    // Friends going lead the line with their faces, as the Town card's do.
                                    if let friends = item.card?.friendsGoing, !friends.isEmpty {
                                        FriendFaces(friends: friends, size: SearchMetric.rowFace,
                                                    tuck: SearchMetric.rowFaceTuck)
                                    }
                                    Text(Self.line(line, open: item.isOpen(context.date)))
                                        .font(.sans(13))
                                        .foregroundStyle(Hue.inkSecondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    Spacer(minLength: removable ? SearchMetric.removeSide : 0)
                    if star != nil {
                        Image(systemName: "chevron.right")
                            .font(.glyph(SearchMetric.chevronGlyph, weight: .semibold))
                            .foregroundStyle(Hue.searchClear)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, SearchMetric.side)
                .frame(height: SearchMetric.row)
                .contentShape(Rectangle())
            }
            if removable { RemoveButton(name: item.name) { forget() } }
        }
        .overlay(alignment: .leading) {
            if let star {
                ActivityStar(target: star, name: [item.name, item.line(.now)].compactMap { $0 }.joined(separator: ", "),
                             look: .bare(starred))
                    .padding(.leading, SearchMetric.side)
            }
        }
    }

    /// A followed star's colour: the school's, as on its page; on the Sports chip's dark page a school's dark colour
    /// would vanish, so ink there, as the school page's white star.
    private var starred: Color {
        scheme == .dark ? Hue.ink : ActivityStar.onPaper(item.team?.colors ?? []).map { Color(hex: $0) } ?? Hue.ink
    }

    /// The item as its row draws it: with `SearchItem.rowPhoto`.
    private var shown: SearchItem {
        var shown = item
        shown.photo = item.rowPhoto
        return shown
    }

    /// The line with a place's "Open" in green (Google Maps'); shut stays grey, never red (Jesse's yes to the mock).
    static func line(_ text: String, open: Bool) -> AttributedString {
        var line = AttributedString(text)
        if open, let word = line.range(of: "Open", options: .backwards) { line[word].foregroundColor = Hue.open }
        return line
    }

    /// A picture on every row (search-helpful 08): a person's face, a logo bare on the page, else its photo, credited
    /// ones too with the credit on the page it opens (Jesse's yes), else what kind of thing it is, bare: Search has
    /// no backdrops (taste, 2026-10-26).
    @ViewBuilder private var avatar: some View {
        if item.kind == .person {
            SearchPhoto(item: item).clipShape(Circle())
        } else if item.logo != nil {
            PlaceMark(item: item, side: SearchMetric.avatar)
                .opacity(opener.isAway(item) ? 0 : 1)
                .animation(nil, value: opener.isAway(item))
        } else if item.rowPhoto != nil {
            SearchPhoto(item: shown, credit: false)
                .clipShape(RoundedRectangle(cornerRadius: Radius.searchField, style: .continuous))
                .opacity(opener.isAway(item) ? 0 : 1)
                .animation(nil, value: opener.isAway(item))
        } else {
            Image(systemName: item.glyph)
                .font(.glyph(SearchMetric.rowGlyph))
                .foregroundStyle(Hue.inkSecondary)
        }
    }

    private func tap() {
        model.remember(item.id)
        guard item.opens else { return }
        let box = avatarFrame.rect, size = SearchMetric.avatar
        let rect = CGRect(x: box.midX - size / 2, y: box.midY - size / 2, width: size, height: size)
        if item.logo == nil {
            // Its photo grows into the page's (or its page fades in over the glyph), as a photo card's does.
            opener.open(item, from: .tile(shown, box: rect, radius: Radius.searchField))
        } else {
            opener.open(item, from: .init(logo: rect, box: rect, radius: 0, shadow: item.markShadow))
        }
    }

    private func forget() {
        withAnimation(.spring(response: 0.3, dampingFraction: 1)) { model.forget(item.id) }
    }
}

/// Words searched before: tapping one types them again.
private struct QueryRow: View {
    let words: String
    /// Recent's clock, or the typed words' magnifier (search-helpful 03).
    var glyph = "clock"
    var removable = true
    let onTap: () -> Void
    @Environment(SearchModel.self) private var model

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: onTap) {
                HStack(spacing: SearchMetric.rowGap) {
                    Image(systemName: glyph)
                        .font(.glyph(18, weight: .light))
                        .foregroundStyle(Hue.ink)
                        .frame(width: SearchMetric.avatar, height: SearchMetric.avatar)
                        .overlay(Circle().strokeBorder(Hue.edge, lineWidth: 1))
                    Text(words)
                        .font(.sansSemibold(14))
                        .foregroundStyle(Hue.ink)
                        .lineLimit(1)
                    Spacer(minLength: SearchMetric.removeSide)
                }
                .padding(.horizontal, SearchMetric.side)
                .frame(height: SearchMetric.row)
                .contentShape(Rectangle())
            }
            .buttonStyle(.press(.row))
            .accessibilityLabel(glyph == "magnifyingglass" ? "Search \(words)" : words)
            if removable {
                RemoveButton(name: words) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 1)) { model.forget(SearchModel.queryID(words)) }
                }
            }
        }
    }
}

/// Words to search, as outlined pills like the unpicked Search pills, wrapping: Try above Recent, and the
/// no-match page's nearest things (search-helpful 03, Nextdoor's Trending). A tap types the words.
private struct WordChips: View {
    let words: [String]
    let pick: (String) -> Void

    var body: some View {
        FlowLayout(spacing: SearchMetric.chipGap) {
            ForEach(words, id: \.self) { word in
                Button { pick(word) } label: {
                    Text(word)
                        .font(.sansSemibold(14))
                        .foregroundStyle(Hue.ink)
                        .padding(.horizontal, SearchMetric.chipPad)
                        .frame(height: SearchMetric.chipHeight)
                        .background(Capsule().strokeBorder(Hue.searchChipEdge, lineWidth: 1))
                        .contentShape(Rectangle().inset(by: (SearchMetric.chipHeight - PageMetric.tapMin) / 2))
                }
                .buttonStyle(.press(.squish))
            }
        }
        .padding(.horizontal, SearchMetric.side)
        .padding(.top, SearchMetric.wordChipsTop)
        .padding(.bottom, SearchMetric.wordChipsBottom)
    }
}

/// Nothing matched: one short line, then what Block Party does have, the nearest words and this week's Events,
/// so Search never ends on a blank page (search-helpful 03, the mock Jesse passed).
private struct NoMatch: View {
    let words: String
    let chips: [String]
    let week: [SearchItem]
    let pick: (String) -> Void

    var body: some View {
        Text("No match for \u{201C}\(words)\u{201D}")
            .font(.sansSemibold(15))
            .foregroundStyle(Hue.ink)
            .lineLimit(2)
            .padding(.horizontal, SearchMetric.side)
            .padding(.top, SearchMetric.noMatchTop)
            .padding(.bottom, SearchMetric.noMatchBottom)
        if !chips.isEmpty { WordChips(words: chips, pick: pick) }
        if !week.isEmpty {
            ShelfTitle(title: "This week", shelf: SearchShelf(kind: .event, title: "This week", items: week))
            Shelf(kind: .event, items: week)
        }
    }
}

private struct RemoveButton: View {
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.glyph(13, weight: .medium))
                .foregroundStyle(Hue.inkSecondary)
                .frame(width: SearchMetric.removeSide, height: SearchMetric.removeSide)
                .contentShape(Rectangle())
        }
        .buttonStyle(.press(.dim))
        .padding(.trailing, SearchMetric.removeTrail)
        .accessibilityLabel("Remove \(name)")
    }
}

/// Nothing matched: a large grey magnifier, no words.
struct NothingFound: View {
    var body: some View {
        Image(systemName: "magnifyingglass")
            .font(.glyph(34, weight: .light))
            .foregroundStyle(Hue.edge)
            .frame(maxWidth: .infinity)
            .padding(.top, SearchMetric.noneTop)
            .accessibilityLabel("Nothing found")
    }
}

/// A place, event or group's picture: bundled, or one Block Party saved of it, with its credit.
/// One with none shows its logo bare on the page, else what kind of thing it is.
struct SearchPhoto: View {
    let item: SearchItem
    /// A result row's 44 pt photo has no room for its credit: the page it opens shows it (search-helpful 08).
    var credit = true
    private var photo: SearchItem.Photo? { item.photo }

    var body: some View {
        Rectangle()
            .fill(photo == nil && item.logo != nil ? Color.clear : Hue.fill)
            .overlay {
                switch photo {
                case .bundled(let name):
                    if let url = Bundle.main.url(forResource: name, withExtension: "jpg") { FeedCardURLPhoto(url: url, loadingFill: .clear) }
                case .saved(let picture):
                    SavedPhoto(item: item, picture: picture, credit: credit)
                case .card(let source):
                    // Only a photo is an Event's `.card` (`SearchModel.events`): a logo is its `logo`. A flyer
                    // shows whole over its blur, so its words aren't cut (BP app event-photos 18).
                    if let url = source.url {
                        FeedCardURLPhoto(url: url, loadingFill: .clear, whole: item.card?.whole == true ? 0 : nil)
                        if credit, let credit = source.attribution {
                            PhotoCredit(names: [credit])
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        }
                    }
                case nil:
                    NoPhoto(item: item)
                }
            }
            .clipped()
    }
}

/// A photo Block Party saved of the place: shimmering until it is on screen, then credited (the
/// site it came from, or a free photo's author and licence). One that can't load leaves the
/// place looking like a place with no photo.
private struct SavedPhoto: View {
    let item: SearchItem
    let picture: PlacePicture
    var credit = true
    @State private var shown = false
    @State private var failed = false

    var body: some View {
        if failed {
            NoPhoto(item: item)
        } else {
            // A photo already decoded elsewhere draws at once: so does its credit.
            let ready = shown || FeedCardImageLoader.shared.largest(for: picture.url) != nil
            ZStack {
                if !ready { Rectangle().fill(Hue.fill).shimmering() }
                FeedCardURLPhoto(url: picture.url, onReady: { withAnimation(.easeOut(duration: 0.2)) { shown = true } },
                                 onFailure: { failed = true }, loadingFill: .clear)
                if ready, credit, let credit = picture.creditLine {
                    PhotoCredit(names: [credit])
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
        }
    }
}

/// No photo: the logo bare, a place with none yet its letter disc, else what kind of place it is.
private struct NoPhoto: View {
    let item: SearchItem

    var body: some View {
        ZStack {
            if let logo = item.logo {
                CastLogo(logo: logo, side: SearchMetric.logoOnTile)
            } else if item.opens {
                LetterDisc(initial: item.initial, side: SearchMetric.logoOnTile)
            } else {
                Image(systemName: item.glyph)
                    .font(.glyph(28, weight: .light))
                    .foregroundStyle(Hue.inkSecondary)
            }
        }
    }
}

// MARK: - A row's whole list

struct SearchShelfPage: View {
    let shelf: SearchShelf
    @State private var opener = BusinessOpener()
    @State private var tilt = PhoneTilt()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            Hue.paper.ignoresSafeArea()
            ScrollView {
                list
                    .padding(.top, PageMetric.bar)
                    .padding(.bottom, SearchMetric.tabBarClearance)
            }
            // Covered by an open business, the logos stop following the tilt.
            .environment(opener.isOpen ? nil : tilt)
            PageBar(title: shelf.title) { dismiss() }
            BusinessPage()
        }
        .environment(opener)
        .following(tilt)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { opener.reduceMotion = reduceMotion }
    }

    @ViewBuilder private var list: some View {
        switch shelf.kind {
        case .business:
            LogoWall(items: shelf.items)
        default:
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: SearchMetric.cardGap), count: 2),
                      spacing: SearchMetric.gridGapY) {
                ForEach(shelf.items) { PhotoCard(item: $0, width: nil) }
            }
            .padding(.horizontal, SearchMetric.side)
            .padding(.top, SearchMetric.gridTop)
        }
    }
}

/// Remembers where a view is on screen without redrawing it each time it moves, so a
/// logo knows where to fly from when it is tapped.
final class FrameBox {
    var rect = CGRect.zero
}

extension View {
    func trackFrame(_ box: FrameBox) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { box.rect = $0 }
    }
}

extension EnvironmentValues {
    /// Opens a News item as its Town card does (the shell's own, from the hello pill): a Search row's tap
    /// (search-helpful 07).
    @Entry var openNews: ((TownNews) -> Void)? = nil
}
