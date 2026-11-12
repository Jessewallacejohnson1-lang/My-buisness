//
//  SearchPage.swift
//  Block Party — the Search tab: a search field and filter pills (All, Businesses, Events, Parks)
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

    // The field, Cancel and the pills.
    static let fieldTop: CGFloat = 3
    static let fieldHeight: CGFloat = 36
    static let fieldIcon: CGFloat = 17
    static let fieldIconLead: CGFloat = 10
    static let fieldIconGap: CGFloat = 6
    static let clearSide: CGFloat = 36
    /// While searching, the field's right edge moves in this far for Cancel, which
    /// slides in from `cancelSlide` to the right.
    static let cancelReserve: CGFloat = 68
    static let cancelSlide: CGFloat = 14
    static let chipsTop: CGFloat = 8
    static let chipsHeight: CGFloat = 40
    static let chipHeight: CGFloat = 34
    static let chipPad: CGFloat = 15
    static let chipGap: CGFloat = 8
    static let headBottom: CGFloat = 6
    /// Everything above the content, from the safe area's top.
    static let headHeight: CGFloat = fieldTop + fieldHeight + chipsTop + chipsHeight + headBottom
    /// The rows fade out under the pills over this much (Instagram's top edge).
    static let softEdge: CGFloat = 22
    static let softEdgeHaze: Double = 0.92

    // Sideways rows. 28 over a title and 14 under it: Airbnb's, measured.
    static let titleTop: CGFloat = 28
    static let titleBottom: CGFloat = 14
    static let titleGap: CGFloat = 6
    /// Photoroom's logo squares; the logo fills 66 of 78, its centre 47% down.
    static let logoOnTile: CGFloat = 66
    /// The Businesses row's logos, bare on the page with no tile (Jesse, 2026-10-24).
    static let logoOnRow: CGFloat = 80
    static let logoGap: CGFloat = 10
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
    /// A typed activity's star before its school's crest, and its › (school-search 01): the mock's 26 pt box,
    /// its 19 pt star and its 6 by 10 pt ›, measured.
    static let star: CGFloat = 26
    static let starGlyph: CGFloat = 18
    static let chevronGlyph: CGFloat = 11

    // The Sports chip (school-search 04): "BlockParty. Sports" where Apple Sports has its logo and "Sports", on the
    // app's dark colours. The mock Jesse picked (`references/school-search/sports-bp-mock-2.html`, version 8),
    // measured at 3x beside Apple Sports (`mobbin/1.jpg`), from a 59 pt safe area: the wordmark 35 pt tall and
    // "Sports" 34 pt, 9 pt apart on one baseline 26 pt down; the field 54-97, the chips 109-143, the first disc 167.
    static let sportsWordmark: CGFloat = 35.2
    static let sportsWord: CGFloat = 34
    static let sportsWordGap: CGFloat = 9
    /// The title's room above the field, and how far its words sit up off that room's foot (tuned on the build so
    /// the baseline lands 26 pt down).
    static let sportsTitle: CGFloat = 37
    static let sportsTitleLift: CGFloat = 2.3
    static let sportsFieldTop: CGFloat = 17
    static let sportsFieldHeight: CGFloat = 43
    static let sportsFieldIconLead: CGFloat = 14
    static let sportsFieldIconGap: CGFloat = 8
    /// Apple's field and chips sit 8 pt in; the words over them keep the page's 16.
    static let sportsSide: CGFloat = 8
    static let sportsChipsTop: CGFloat = 9
    /// Every chip's glass is ink at 5%, the field's at 7%.
    static let sportsChipGlass: Double = 0.05
    static let sportsFieldGlass: Double = 0.07
    /// The warm-grey fade from the top, to paper by 440 pt, through its middle shade at 240 pt.
    static let sportsFade: CGFloat = 440
    static let sportsFadeMid: CGFloat = 240
    /// Apple's discs (`mobbin/1.jpg`): 80 pt, three to a row 154 pt apart (a 132 pt cell and 22 under it), the logo
    /// in a 45 pt box, the name 8 pt under the disc. The first sits 24 pt under the chips.
    static let discTop: CGFloat = 24
    static let disc: CGFloat = 80
    static let discLogo: CGFloat = 45
    static let discCell: CGFloat = 132
    static let discRowGap: CGFloat = 22
    static let discNameGap: CGFloat = 8
    static let discSkeletonName: CGFloat = 12
    /// Everything above the Sports chip's content, from the safe area's top.
    static let sportsHeadHeight: CGFloat = sportsTitle + sportsFieldTop + sportsFieldHeight + sportsChipsTop
        + chipsHeight + headBottom

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
    /// Around town's shuffle: a new one each visit, since the shell builds the tab again on every
    /// switch, and the same one back from an Event page, so the grid never moves under the thumb.
    @State private var seed = UInt64.random(in: 0 ... .max)
    @State private var opener = BusinessOpener()
    /// Each page follows the tilt on its own: a pushed row's page has its own.
    @State private var tilt = PhoneTilt()
    @FocusState private var fieldFocused: Bool
    @Namespace private var chipNS
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var auth: AuthStore
    @Environment(FriendsBook.self) private var book

    private enum Mode: Hashable {
        case rest, wall, sports, groups(SearchItem.Kind), recents, results(SearchChip)
    }

    private var mode: Mode {
        if !model.words.trimmingCharacters(in: .whitespaces).isEmpty { return .results(model.chip) }
        if model.searching { return .recents }
        switch model.chip {
        case .all: return .rest
        case .businesses: return .wall
        case .sports: return .sports
        default: return .groups(model.chip.kind ?? .park)
        }
    }

    /// The Sports chip turns the page to the app's dark colours, searching and typed results included
    /// (school-search 04): the mock Jesse picked.
    private var sports: Bool { model.chip == .sports }

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                // Covered by an open business, the logos stop following the tilt.
                content.environment(opener.isOpen ? nil : tilt)
                header
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
        // People rows carry the friend button; a failed tap shakes only while Search is open.
        .onAppear { book.screenOpened() }
        .onDisappear { book.screenClosed() }
    }

    // MARK: Header

    private var header: some View {
        // The field's and chips' glass blend only with each other, never across the 8 pt between chips.
        GlassEffectContainer(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if sports { SportsTitle() }
                fieldRow
                    .padding(.top, sports ? SearchMetric.sportsFieldTop : SearchMetric.fieldTop)
                chips
                    .padding(.top, sports ? SearchMetric.sportsChipsTop : SearchMetric.chipsTop)
            }
        }
        .padding(.bottom, SearchMetric.headBottom)
        // The page's own ground behind it, opaque down to its foot and fading over the rows under it
        // (Instagram's top edge): drawn from the screen's top, so on Sports it is the same slice of the fade.
        .background(alignment: .top) {
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

    /// The page's ground: paper, or on Sports the warm-grey fade from the top of the screen (the mock's).
    @ViewBuilder private var ground: some View {
        if sports {
            SportsFade()
        } else {
            Hue.paper
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
        .padding(.horizontal, sports ? SearchMetric.sportsSide : SearchMetric.side)
        .frame(height: sports ? SearchMetric.sportsFieldHeight : SearchMetric.fieldHeight)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 1), value: model.searching)
    }

    private var field: some View {
        // On Sports: Apple Sports' field, a capsule of glass, its prompt and magnifier in the dark ramp's grey.
        let faint = sports ? Hue.inkSecondary : Hue.searchFaint
        let prompt = sports ? "Schools and teams" : "Search"
        let shape = RoundedRectangle(cornerRadius: sports ? SearchMetric.sportsFieldHeight / 2 : Radius.searchField,
                                     style: .continuous)
        return HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.glyph(sports ? 17 : 15, weight: .medium))
                .foregroundStyle(faint)
                .frame(width: SearchMetric.fieldIcon, height: SearchMetric.fieldIcon)
                .padding(.leading, sports ? SearchMetric.sportsFieldIconLead : SearchMetric.fieldIconLead)
                .padding(.trailing, sports ? SearchMetric.sportsFieldIconGap : SearchMetric.fieldIconGap)
                .accessibilityHidden(true)
            TextField(prompt, text: $model.words, prompt: Text(prompt).foregroundStyle(faint))
                .font(.sans(sports ? 17 : 16))
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
        .frame(height: sports ? SearchMetric.sportsFieldHeight : SearchMetric.fieldHeight)
        .background(sports ? Color.clear : Hue.searchField, in: shape)
        .glassEffect(sports ? Glass.regular.tint(Hue.ink.opacity(SearchMetric.sportsFieldGlass)) : .identity, in: shape)
    }

    private var chips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SearchMetric.chipGap) {
                    ForEach(model.chips, id: \.self) { c in
                        chipButton(c).id(c)
                    }
                }
                .padding(.horizontal, sports ? SearchMetric.sportsSide : SearchMetric.side)
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
                .foregroundStyle(on ? (sports ? Hue.paper : Hue.surface) : Hue.ink)
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
                .glassEffect(sports ? Glass.regular.tint(Hue.ink.opacity(SearchMetric.sportsChipGlass)) : .identity,
                             in: Capsule())
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
                .padding(.top, sports ? SearchMetric.sportsHeadHeight : SearchMetric.headHeight)
                .padding(.bottom, SearchMetric.tabBarClearance)
            }
            .scrollDismissesKeyboard(.immediately)
            .id(mode)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: SearchMetric.enterRise)),
                                    removal: .identity))
        }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1), value: mode)
    }

    @ViewBuilder private var modeBody: some View {
        switch mode {
        case .rest:
            SearchAtRest(seed: seed)
        case .wall:
            LogoWall(items: model.row(.business))
        case .sports:
            SportsGrid()
        case .groups(let kind):
            let items = model.row(kind)
            let title = SearchPage.sectionTitle(kind)
            let groups = items.reduce(into: [String]()) { if !$0.contains($1.group ?? title) { $0.append($1.group ?? title) } }
            ForEach(groups, id: \.self) { group in
                shelf(kind, group, items.filter { ($0.group ?? title) == group })
            }
        case .recents:
            let recents = model.recents
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
            let sections = model.results(for: model.words, in: chip)
            // Less anyone you just blocked (ticket 04).
            let people = book.visible(chip == .all ? model.people.state : .idle)
            if sections.isEmpty && !people.hasRows {
                // Nothing here yet: wait for the neighbours' answer before saying so.
                if people != .loading { NothingFound() }
            } else {
                ForEach(sections, id: \.kind) { section in
                    if chip.resultKinds.count > 1 { SectionTitle(text: SearchPage.sectionTitle(section.kind)) }
                    ForEach(section.items) { ItemRow(item: $0) }
                }
                PeopleResults(state: people, titled: chip.resultKinds.count > 1)
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
        case .club: "Groups"
        case .park: "Parks"
        }
    }

    // MARK: Actions

    /// A pill's tap, and "Schools ›" on the Schools row, which opens the Sports chip (school-search 04).
    /// Into or out of Sports the page turns at once, as Instagram's dark Reels tab does: the whole page changes
    /// colour, glass draws where it lands rather than where it travels (swift-traps), and the ticket asks for no
    /// wait the reader can see. Between the other pills the selection slides as before.
    static func pick(_ c: SearchChip, in model: SearchModel, reduceMotion: Bool) {
        guard c != model.chip else { return }
        Haptics.selection()
        if c == .sports || model.chip == .sports {
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
    /// Search has read it, its logo flying in from mid-screen as from a photo card, so a
    /// place-photos check needn't find it on the wall (BP app backlog 03).
    private func openDebugBusiness() {
        guard !Self.debugBusinessOpened, let id = LaunchFlags.value(.openBusiness),
              let item = model.items.first(where: { $0.id == id || $0.id == "p:\(id)" }), item.opens else { return }
        Self.debugBusinessOpened = true
        let size = SearchMetric.logoOnTile, rect = CGRect(x: 160, y: 400, width: size, height: size)
        opener.open(item, from: .init(logo: rect, box: rect, radius: 0, shadow: item.markShadow, fades: true))
    }
    /// `-search-focus`: opens on the recents, as after a tap on the field.
    private static var debugSearching: Bool {
        LaunchFlags.has(.searchFocus) || debugWords != nil
    }
    /// `-search-chip <all|businesses|sports|events|parks>`: opens on that filter.
    private static var debugChip: SearchChip? {
        LaunchFlags.value(.searchChip).flatMap { name in SearchChip.allCases.first { $0.title.lowercased() == name } }
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
                        RowCrest(item: item)
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
        .scrollClipDisabled(Self.logos(kind))
    }

    /// A row of bare logos, the Businesses row's size and gap, rather than photo cards: a school's crests too.
    static func logos(_ kind: SearchItem.Kind) -> Bool { kind == .business || kind == .school }

    static func gap(_ kind: SearchItem.Kind) -> CGFloat {
        logos(kind) ? SearchMetric.logoGap : SearchMetric.cardGap
    }
}

/// A row still waiting on the places: its tiles' shapes, in their places.
struct ShelfSkeleton: View {
    let kind: SearchItem.Kind

    var body: some View {
        HStack(alignment: .top, spacing: Shelf.gap(kind)) {
            ForEach(0..<6, id: \.self) { _ in
                if Shelf.logos(kind) {
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

/// "BlockParty. Sports" where Apple Sports has its logo and "Sports" (school-search 04): the app's wordmark and the
/// word in Inter Tight on one baseline, both in ink. No yellow on the screen.
private struct SportsTitle: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SearchMetric.sportsWordGap) {
            BlockPartyWordmark(height: SearchMetric.sportsWordmark)
                // The artwork's baseline, measured on `Wordmark.png`: the B's foot, 171 of its 216 rows down.
                .alignmentGuide(.firstTextBaseline) { $0.height * 171 / 216 }
            Text("Sports")
                .font(.display(SearchMetric.sportsWord))
        }
        .foregroundStyle(Hue.ink)
        .padding(.horizontal, SearchMetric.side)
        .padding(.bottom, SearchMetric.sportsTitleLift)
        .frame(height: SearchMetric.sportsTitle, alignment: .bottomLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Block Party Sports")
        .accessibilityAddTraits(.isHeader)
    }
}

/// The Sports chip's ground: a warm grey at the top of the screen fading to the dark paper by 440 pt, the mock's
/// "darker fade" (Jesse, 2026-11-11), drawn from the screen's top wherever it shows.
private struct SportsFade: View {
    var body: some View {
        LinearGradient(stops: [.init(color: Hue.sportsFadeTop, location: 0),
                               .init(color: Hue.sportsFadeMid, location: SearchMetric.sportsFadeMid / SearchMetric.sportsFade),
                               .init(color: Hue.paper, location: 1)],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: SearchMetric.sportsFade)
            // No smaller than offered, and no taller: a header's slice of it stays the header's height.
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
            .background(Hue.paper)
            .clipped()
    }
}

/// The Sports chip (school-search 04): every school's logo in Apple Sports' disc, three to a row, its short name
/// under it, colleges first; a disc opens the school's page. Shimmering discs while the schools are read.
private struct SportsGrid: View {
    @Environment(SearchModel.self) private var model

    var body: some View {
        Group {
            if model.isLoading(.school) {
                grid {
                    ForEach(0..<9, id: \.self) { _ in
                        VStack(spacing: SearchMetric.discNameGap) {
                            SkeletonCircle(diameter: SearchMetric.disc)
                            SkeletonLine(height: SearchMetric.discSkeletonName)
                                .frame(width: SearchMetric.disc * 0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: SearchMetric.discCell, alignment: .top)
                    }
                }
                .shimmering()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Loading")
            } else {
                grid { ForEach(model.sports) { SchoolDisc(item: $0) } }
            }
        }
        // 24 pt from the chips' foot to the first disc.
        .padding(.top, SearchMetric.discTop - (SearchMetric.chipsHeight - SearchMetric.chipHeight) / 2
                 - SearchMetric.headBottom)
    }

    private func grid(@ViewBuilder _ cells: () -> some View) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 3), spacing: SearchMetric.discRowGap) {
            cells()
        }
        .padding(.horizontal, SearchMetric.sportsSide)
    }
}

/// One school on the Sports chip: its logo fitted in Apple's 45 pt box on an 80 pt disc of the fill, its short
/// name under it in the secondary ink.
private struct SchoolDisc: View {
    let item: SearchItem

    var body: some View {
        OpenButton(item: item, press: .squish, tap: {}) {
            VStack(spacing: SearchMetric.discNameGap) {
                LogoDisc(logo: item.logo?.url, initial: item.initial, logoSide: SearchMetric.discLogo,
                         letter: .sansSemibold(20), disc: false)
                    .frame(width: SearchMetric.discLogo, height: SearchMetric.discLogo)
                    .frame(width: SearchMetric.disc, height: SearchMetric.disc)
                    .background(Hue.fill, in: Circle())
                Text(item.team?.short ?? item.name)
                    .font(.sansSemibold(13))
                    .foregroundStyle(Hue.inkSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: SearchMetric.discCell, alignment: .top)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(item.name)
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
                    .trackFrame(photoFrame)
                Text(item.name)
                    .font(.sansSemibold(15))
                    .foregroundStyle(Hue.ink)
                    .lineLimit(1)
                    .padding(.top, SearchMetric.cardTextTop)
                if let sub = item.sub {
                    Text(sub)
                        .font(.sans(14))
                        .foregroundStyle(Hue.inkSecondary)
                        .lineLimit(1)
                }
            }
            .frame(width: width)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        }
        // New in St. Joseph's say so first; the tag itself is hidden from VoiceOver.
        .accessibilityLabel([new ? "New" : nil, item.name, item.sub].compactMap { $0 }.joined(separator: ", "))
    }

    /// A restaurant or coffee shop opens its page from the photo: the logo, or its letter disc, flies
    /// out of the photo's middle.
    private func tap() {
        model.remember(item.id)
        guard item.opens else { return }
        let box = photoFrame.rect, size = SearchMetric.logoOnTile
        opener.open(item, from: .init(
            logo: CGRect(x: box.midX - size / 2, y: box.midY - size / 2, width: size, height: size),
            box: box, radius: Radius.photoCard, shadow: item.markShadow, fades: true))
    }
}

/// Neighbours for the words typed, after the places, so the rows above stay put when they
/// arrive (BP app docs/plans/friends, ticket 02).
/// Never saved to Recent: a neighbour's name and photo stay off the phone.
private struct PeopleResults: View {
    let state: NeighborSearch.State
    let titled: Bool

    var body: some View {
        if state.hasRows, titled { SectionTitle(text: SearchPage.sectionTitle(.person)) }
        switch state {
        case .found(let people):
            // Facebook's result with its button under the name, in Search's smaller sizes.
            ForEach(people) { person in
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
    @State private var avatarFrame = FrameBox()

    var body: some View {
        ZStack(alignment: .trailing) {
            OpenButton(item: item, press: .row, tap: tap) {
                HStack(spacing: SearchMetric.rowGap) {
                    // The star's room: it lies over the row, so a tap on it never opens the page.
                    if item.activity != nil { Color.clear.frame(width: SearchMetric.star) }
                    avatar
                        .frame(width: SearchMetric.avatar, height: SearchMetric.avatar)
                        .trackFrame(avatarFrame)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.name)
                            .font(.sansSemibold(14))
                            .foregroundStyle(Hue.ink)
                            .lineLimit(1)
                        if let sub = item.sub {
                            Text(sub)
                                .font(.sans(13))
                                .foregroundStyle(Hue.inkSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: removable ? SearchMetric.removeSide : 0)
                    if item.activity != nil && !removable {
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
            if let target = item.activity {
                ResultStar(target: target, name: [item.name, item.sub].compactMap { $0 }.joined(separator: ", "),
                           colors: item.team?.colors ?? [])
                    .padding(.leading, SearchMetric.side)
            }
        }
    }

    @ViewBuilder private var avatar: some View {
        if item.kind == .person {
            SearchPhoto(item: item).clipShape(Circle())
        } else if item.logo != nil || item.opens {
            PlaceMark(item: item, side: SearchMetric.avatar)
                .opacity(opener.isAway(item) ? 0 : 1)
                .animation(nil, value: opener.isAway(item))
        } else if item.photo?.credited ?? true {
            // No logo, and a saved photo carries its credit, with no room for one at this
            // size: what kind of place it is instead.
            RoundedRectangle(cornerRadius: Radius.searchField, style: .continuous)
                .fill(Hue.fill)
                .overlay {
                    Image(systemName: item.glyph)
                        .font(.glyph(17))
                        .foregroundStyle(Hue.inkSecondary)
                }
        } else {
            SearchPhoto(item: item)
                .clipShape(RoundedRectangle(cornerRadius: Radius.searchField, style: .continuous))
        }
    }

    private func tap() {
        model.remember(item.id)
        guard item.opens else { return }
        let box = avatarFrame.rect, size = SearchMetric.avatar
        let rect = CGRect(x: box.midX - size / 2, y: box.midY - size / 2, width: size, height: size)
        opener.open(item, from: .init(logo: rect, box: rect, radius: 0, shadow: item.markShadow))
    }

    private func forget() {
        withAnimation(.spring(response: 0.3, dampingFraction: 1)) { model.forget(item.id) }
    }
}

/// A typed activity's star (school-search 01): the school page's star (`TeamPage`) bare on Search's paper, as
/// the mock drew it. One tap follows or unfollows the activity, a refused one turns back with the shake, and
/// with no account it does nothing.
struct ResultStar: View {
    let target: FollowTarget
    let name: String
    /// Its school's colours, as 0xRRGGBB.
    let colors: [UInt32]

    @Environment(RealLifeActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var tappedAt = 0

    var body: some View {
        let following = actions.follow(target).isFollowing
        let failures = actions.followFailureCount(target)
        // On the Sports chip's dark page a school's dark colour would vanish: ink, as the school page's white star.
        let on = scheme == .dark ? Hue.ink : Self.fill(colors).map { Color(hex: $0) } ?? Hue.ink
        Button {
            tappedAt = failures
            actions.toggleFollow(target)
        } label: {
            Image(systemName: following ? "star.fill" : "star")
                .font(.glyph(SearchMetric.starGlyph, weight: .regular))
                .foregroundStyle(following ? on : Hue.searchFaint)
                // Swapped at once: an animated swap cross-fades through a grey blob (swift-traps).
                .transaction { $0.animation = nil }
                .frame(width: PageMetric.tapMin, height: SearchMetric.row)
                .contentShape(Rectangle())
        }
        .buttonStyle(.press(.squish))
        .padding(.horizontal, -(PageMetric.tapMin - SearchMetric.star) / 2)
        .turnBackShake(failures: failures, shakes: !reduceMotion && tappedAt != failures)
        .accessibilityLabel("Follow \(name)")
        .accessibilityAddTraits(following ? .isSelected : [])
        .onAppear { actions.followOpened(target) }
        .onDisappear { actions.followClosed(target) }
    }

    /// The school page's star colour (its second, or its first when its first is too light for white words),
    /// unless that is too light for Search's paper too: then its leading dark colour. nil with none: ink.
    static func fill(_ colors: [UInt32]) -> UInt32? {
        var hexes = colors
        if let first = hexes.first, TeamPage.light(first),
           let darkest = hexes.min(by: { TeamPage.luma($0) < TeamPage.luma($1) }), !TeamPage.light(darkest) {
            hexes = [darkest, first]
        }
        return [hexes.dropFirst().first, hexes.first].compactMap { $0 }.first { !TeamPage.light($0) }
    }
}

/// Words searched before: tapping one types them again.
private struct QueryRow: View {
    let words: String
    let onTap: () -> Void
    @Environment(SearchModel.self) private var model

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: onTap) {
                HStack(spacing: SearchMetric.rowGap) {
                    Image(systemName: "clock")
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
            RemoveButton(name: words) {
                withAnimation(.spring(response: 0.3, dampingFraction: 1)) { model.forget(SearchModel.queryID(words)) }
            }
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

    var body: some View {
        Rectangle()
            .fill(item.photo == nil && item.logo != nil ? Color.clear : Hue.fill)
            .overlay {
                switch item.photo {
                case .bundled(let name):
                    if let url = Bundle.main.url(forResource: name, withExtension: "jpg") { FeedCardURLPhoto(url: url, loadingFill: .clear) }
                case .saved(let picture):
                    SavedPhoto(item: item, picture: picture)
                case .card(let source):
                    // Only a photo is an Event's `.card` (`SearchModel.events`): a logo is its `logo`.
                    if let url = source.url {
                        FeedCardURLPhoto(url: url, loadingFill: .clear)
                        if let credit = source.attribution {
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
                if ready, let credit = picture.creditLine {
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
