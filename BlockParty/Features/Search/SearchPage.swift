//
//  SearchPage.swift
//  Block Party — the Search tab: a search field and filter pills over sideways rows of
//  the Town's people, businesses, food places and clubs. Tapping the field shows the
//  recent searches; typing shows results. A row's title ("Restaurants ›") opens the
//  whole list, and a logo opens its business (`BusinessPage`).
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
    static let logoTile: CGFloat = 78
    static let logoOnTile: CGFloat = 66
    static let logoGap: CGFloat = 8
    static let logoCenterY: CGFloat = 0.47
    /// Airbnb's photo cards.
    static let cardWidth: CGFloat = 167
    static let cardPhoto: CGFloat = 157
    static let cardGap: CGFloat = 12
    static let cardTextTop: CGFloat = 8
    /// Instagram's round faces, 105 apart.
    static let face: CGFloat = 79
    static let faceGap: CGFloat = 26
    static let faceLabel: CGFloat = 96
    static let faceLabelTop: CGFloat = 6
    static let faceRing: CGFloat = 0.5

    // The logo wall and the pushed pages.
    static let wallTop: CGFloat = 14
    static let wallGapX: CGFloat = 8
    static let wallGapY: CGFloat = 6
    static let logoOnWall: CGFloat = 96
    static let pageBar: CGFloat = 44
    static let gridTop: CGFloat = 12
    static let gridGapY: CGFloat = 20

    // List rows: results, recents, people.
    static let row: CGFloat = 60
    static let rowGap: CGFloat = 12
    static let avatar: CGFloat = 44
    static let avatarLogo: CGFloat = 36
    static let removeSide: CGFloat = 36
    static let removeTrail: CGFloat = 6
    static let sectionTop: CGFloat = 14
    static let sectionBottom: CGFloat = 6
    static let peopleTop: CGFloat = 6
    static let noneTop: CGFloat = 90

    /// Clears the floating tab bar: the same 96 the other tab scrollers reserve.
    static let tabBarClearance: CGFloat = 96

    // Touch and motion.
    static let pressScale: CGFloat = 0.95
    static let dimPressed: Double = 0.45
    static let rowPressed: Double = 0.05
    /// A new view of the results fades in, rising this far.
    static let enterRise: CGFloat = 10

    // The business page (`BusinessPage`).
    static let openResponse: CGFloat = 0.5
    static let openDamping: CGFloat = 0.84
    static let closeResponse: CGFloat = 0.4
    static let settleResponse: CGFloat = 0.45
    static let settleDamping: CGFloat = 0.9
    static let bizLogo: CGFloat = 76
    static let bizLogoRight: CGFloat = 10
    static let bizLogoCenter: CGFloat = 29
    static let bizBack: CGFloat = 44
    static let bizBackLeft: CGFloat = 16
    static let bizBackTop: CGFloat = 7
    static let bizBackFrom: CGFloat = 0.6
    static let bizGridTop: CGFloat = 69
    static let bizGridGap: CGFloat = 2
    /// Each row of photos starts this much later than the one above it.
    static let bizRowLag: Double = 0.07
    static let bizRiseScale: CGFloat = 0.94
    /// A finger drag this long closes the page from fully open.
    static let bizDrag: CGFloat = 520
    static let bizOverDrag: CGFloat = 1.04
    /// Let go faster than this downward (pt/s), or under this far open, and it closes.
    static let bizFlick: CGFloat = 500
    static let bizKeepOpen: CGFloat = 0.6
    static let liftStretch: CGFloat = 1.6
    static let liftFade: Double = 0.25
    static let bizLoadingTiles = 9
    static let bizBlankTiles = 15
    static let bizTileShade: Double = 0.06
    static let bizPhotoPixels = 400
}

/// A row's whole list, pushed from its title.
struct SearchShelf: Hashable {
    let kind: SearchItem.Kind
    let title: String
    let items: [SearchItem]
}

struct SearchPage: View {
    let model: SearchModel
    @State private var opener = BusinessOpener()
    @State private var chip = SearchChip.all
    @State private var words = SearchPage.debugWords
    /// From the field's first tap until Cancel: Cancel shows, and so do the recents.
    @State private var searching = SearchPage.debugSearching
    @FocusState private var fieldFocused: Bool
    @Namespace private var chipNS
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Mode: Hashable {
        case shelves, people, wall, groups(SearchItem.Kind), recents, results(SearchChip)
    }

    private var mode: Mode {
        if !words.trimmingCharacters(in: .whitespaces).isEmpty { return .results(chip) }
        if searching { return .recents }
        switch chip {
        case .all: return .shelves
        case .people: return .people
        case .businesses: return .wall
        default: return .groups(chip.kind ?? .park)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            content
            header
            BusinessPage()
        }
        .environment(model)
        .environment(opener)
        .navigationDestination(for: SearchShelf.self) { shelf in
            SearchShelfPage(shelf: shelf).environment(model)
        }
        .task { await model.load() }
        .onAppear {
            opener.reduceMotion = reduceMotion
            #if DEBUG
            if let debug = Self.debugChip { chip = debug }
            #endif
        }
        .onChange(of: fieldFocused) { _, focused in
            if focused { searching = true }
        }
        .onChange(of: opener.item?.id) { _, id in
            if id != nil { fieldFocused = false }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 0) {
            fieldRow
                .padding(.top, SearchMetric.fieldTop)
            chips
                .padding(.top, SearchMetric.chipsTop)
        }
        .padding(.bottom, SearchMetric.headBottom)
        .background(Hue.paper.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [Hue.paper.opacity(SearchMetric.softEdgeHaze), Hue.paper.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: SearchMetric.softEdge)
                .offset(y: SearchMetric.softEdge)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var fieldRow: some View {
        ZStack(alignment: .trailing) {
            field
                .padding(.trailing, searching ? SearchMetric.cancelReserve : 0)
            Button("Cancel") { cancel() }
                .font(.sans(16))
                .foregroundStyle(Hue.ink)
                .buttonStyle(DimStyle())
                .opacity(searching ? 1 : 0)
                .offset(x: searching ? 0 : SearchMetric.cancelSlide)
                .allowsHitTesting(searching)
                .accessibilityHidden(!searching)
        }
        .padding(.horizontal, SearchMetric.side)
        .frame(height: SearchMetric.fieldHeight)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 1), value: searching)
    }

    private var field: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.glyph(15, weight: .medium))
                .foregroundStyle(Hue.searchFaint)
                .frame(width: SearchMetric.fieldIcon, height: SearchMetric.fieldIcon)
                .padding(.leading, SearchMetric.fieldIconLead)
                .padding(.trailing, SearchMetric.fieldIconGap)
                .accessibilityHidden(true)
            TextField("Search", text: $words, prompt: Text("Search").foregroundStyle(Hue.searchFaint))
                .font(.sans(16))
                .foregroundStyle(Hue.ink)
                .focused($fieldFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit(submit)
            if !words.isEmpty {
                Button {
                    words = ""
                    fieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Hue.surface, Hue.searchClear)
                        .font(.glyph(17))
                        .frame(width: SearchMetric.clearSide, height: SearchMetric.clearSide)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .frame(height: SearchMetric.fieldHeight)
        .background(Hue.searchField, in: RoundedRectangle(cornerRadius: Radius.searchField, style: .continuous))
    }

    private var chips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SearchMetric.chipGap) {
                    ForEach(model.chips, id: \.self) { c in
                        chipButton(c).id(c)
                    }
                }
                .padding(.horizontal, SearchMetric.side)
                .frame(height: SearchMetric.chipsHeight)
            }
            .onChange(of: chip) { _, c in
                withAnimation(reduceMotion ? nil : .smooth) { proxy.scrollTo(c, anchor: .center) }
            }
        }
        .frame(height: SearchMetric.chipsHeight)
    }

    private func chipButton(_ c: SearchChip) -> some View {
        let on = c == chip
        return Button { pick(c) } label: {
            Text(c.title)
                .font(.sansSemibold(14))
                .foregroundStyle(on ? Hue.surface : Hue.ink)
                .padding(.horizontal, SearchMetric.chipPad)
                .frame(height: SearchMetric.chipHeight)
                .background {
                    if on {
                        Capsule().fill(Hue.ink).matchedGeometryEffect(id: "chip", in: chipNS)
                    } else {
                        Capsule().strokeBorder(Hue.searchChipEdge, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(SquishStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Content

    private var content: some View {
        ZStack {
            if mode == .wall {
                SearchBackdrop.studio.ignoresSafeArea()
            } else {
                Hue.paper.ignoresSafeArea()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    modeBody
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, SearchMetric.headHeight)
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
        case .shelves:
            shelf(.person, "People")
            shelf(.business, "Businesses")
            shelf(.restaurant, "Restaurants")
            shelf(.coffee, "Coffee")
            shelf(.club, "Clubs")
        case .people:
            Color.clear.frame(height: SearchMetric.peopleTop)
            ForEach(model.row(.person)) { ItemRow(item: $0) }
        case .wall:
            LogoWall(items: model.row(.business))
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
                    case .query(let words): QueryRow(words: words) { self.words = words }
                    }
                }
                .transition(.opacity)
            }
        case .results(let chip):
            let sections = model.results(for: words, in: chip)
            if sections.isEmpty {
                NothingFound()
            } else {
                ForEach(sections, id: \.kind) { section in
                    if chip.resultKinds.count > 1 { SectionTitle(text: SearchPage.sectionTitle(section.kind)) }
                    ForEach(section.items) { ItemRow(item: $0) }
                }
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
        case .business: "Businesses"
        case .restaurant: "Restaurants"
        case .coffee: "Coffee"
        case .event: "Events"
        case .club: "Clubs"
        case .park: "Parks"
        }
    }

    // MARK: Actions

    private func pick(_ c: SearchChip) {
        guard c != chip else { return }
        Haptics.selection()
        withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86)) { chip = c }
    }

    private func submit() {
        let q = words.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { model.remember(SearchModel.queryID(q)) }
        fieldFocused = false
    }

    private func cancel() {
        searching = false
        words = ""
        fieldFocused = false
    }

    // MARK: DEBUG launch flags (docs/debug-flags.md)

    #if DEBUG
    private static func debugArg(_ flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    /// `-search-words <text>`: opens with those words typed.
    private static var debugWords: String { debugArg("-search-words") ?? "" }
    /// `-search-focus`: opens on the recents, as after a tap on the field.
    private static var debugSearching: Bool {
        ProcessInfo.processInfo.arguments.contains("-search-focus") || !debugWords.isEmpty
    }
    /// `-search-chip <all|people|businesses|events|clubs|parks>`: opens on that filter.
    private static var debugChip: SearchChip? {
        debugArg("-search-chip").flatMap { name in SearchChip.allCases.first { $0.title.lowercased() == name } }
    }
    #else
    private static let debugWords = ""
    private static let debugSearching = false
    #endif
}

// MARK: - Rows

private struct ShelfTitle: View {
    let title: String
    let shelf: SearchShelf?

    var body: some View {
        if let shelf {
            NavigationLink(value: shelf) { label }
                .buttonStyle(DimStyle())
        } else {
            label
        }
    }

    private var label: some View {
        HStack(spacing: SearchMetric.titleGap) {
            Text(title)
                .font(.sansSemibold(18))
            Image(systemName: "chevron.right")
                .font(.glyph(12, weight: .bold))
                .accessibilityHidden(true)
        }
        .foregroundStyle(Hue.ink)
        .padding(.top, SearchMetric.titleTop)
        .padding(.bottom, SearchMetric.titleBottom)
        .padding(.horizontal, SearchMetric.side)
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isHeader)
    }
}

private struct Shelf: View {
    let kind: SearchItem.Kind
    let items: [SearchItem]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: Shelf.gap(kind)) {
                ForEach(items) { item in
                    switch kind {
                    case .person:
                        SearchFace(item: item)
                    case .business:
                        if let logo = item.logo { LogoTile(item: item, logo: logo) }
                    default:
                        PhotoCard(item: item)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, SearchMetric.side, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
    }

    static func gap(_ kind: SearchItem.Kind) -> CGFloat {
        switch kind {
        case .person: SearchMetric.faceGap
        case .business: SearchMetric.logoGap
        default: SearchMetric.cardGap
        }
    }
}

/// A row still waiting on the places: its tiles' shapes, in their places.
private struct ShelfSkeleton: View {
    let kind: SearchItem.Kind

    var body: some View {
        HStack(alignment: .top, spacing: Shelf.gap(kind)) {
            ForEach(0..<6, id: \.self) { _ in
                if kind == .business {
                    SkeletonBlock(cornerRadius: Radius.logoTile)
                        .frame(width: SearchMetric.logoTile, height: SearchMetric.logoTile)
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

private struct SearchFace: View {
    let item: SearchItem
    @Environment(SearchModel.self) private var model

    var body: some View {
        Button { model.remember(item.id) } label: {
            VStack(spacing: SearchMetric.faceLabelTop) {
                SearchPhoto(item: item)
                    .frame(width: SearchMetric.face, height: SearchMetric.face)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Hue.ink.opacity(0.16), lineWidth: SearchMetric.faceRing))
                Text(item.name.split(separator: " ").first.map(String.init) ?? item.name)
                    .font(.sans(12))
                    .foregroundStyle(Hue.ink)
                    .lineLimit(1)
                    .frame(width: SearchMetric.faceLabel)
            }
            .frame(width: SearchMetric.face)
        }
        .buttonStyle(SquishStyle())
        .accessibilityLabel(item.name)
    }
}

private struct LogoTile: View {
    let item: SearchItem
    let logo: SearchLogo
    @Environment(SearchModel.self) private var model
    @Environment(BusinessOpener.self) private var opener
    @State private var frame = FrameBox()

    var body: some View {
        let side = SearchMetric.logoTile, size = SearchMetric.logoOnTile
        Button {
            let box = frame.rect
            model.remember(item.id)
            opener.open(item, from: .init(
                logo: CGRect(x: box.midX - size / 2, y: box.minY + box.height * SearchMetric.logoCenterY - size / 2,
                             width: size, height: size),
                box: box, radius: Radius.logoTile, shadow: logo.shadow))
        } label: {
            ZStack(alignment: .top) {
                SearchBackdrop(colors: logo.backdrop)
                SearchFloor()
                CastLogo(logo: logo, side: size)
                    .padding(.top, side * SearchMetric.logoCenterY - size / 2)
                    .opacity(opener.isAway(item) ? 0 : 1)
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: Radius.logoTile, style: .continuous))
            .trackFrame(frame)
        }
        .buttonStyle(SquishStyle())
        .accessibilityLabel(item.name)
    }
}

/// Every business logo, cut out over one studio backdrop.
private struct LogoWall: View {
    let items: [SearchItem]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: SearchMetric.wallGapX), count: 3),
                  spacing: SearchMetric.wallGapY) {
            ForEach(items) { item in
                if let logo = item.logo { WallLogo(item: item, logo: logo) }
            }
        }
        .padding(.horizontal, SearchMetric.side)
        .padding(.top, SearchMetric.wallTop)
    }
}

private struct WallLogo: View {
    let item: SearchItem
    let logo: SearchLogo
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
                        CastLogo(logo: logo, side: size, shadow: shadow)
                            .position(x: cell.size.width / 2, y: cell.size.height * SearchMetric.logoCenterY)
                    }
                }
                .opacity(opener.isAway(item) ? 0 : 1)
                .contentShape(Rectangle())
                .trackFrame(frame)
        }
        .buttonStyle(SquishStyle())
        .accessibilityLabel(item.name)
    }
}

struct PhotoCard: View {
    let item: SearchItem
    /// nil fills a grid column.
    var width: CGFloat? = SearchMetric.cardWidth
    @Environment(SearchModel.self) private var model

    var body: some View {
        Button { model.remember(item.id) } label: {
            VStack(alignment: .leading, spacing: 0) {
                SearchPhoto(item: item)
                    .frame(maxWidth: .infinity)
                    .frame(height: SearchMetric.cardPhoto)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.photoCard, style: .continuous))
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
        .buttonStyle(SquishStyle())
    }
}

private struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.sansBold(16))
            .foregroundStyle(Hue.ink)
            .padding(.top, SearchMetric.sectionTop)
            .padding(.bottom, SearchMetric.sectionBottom)
            .padding(.horizontal, SearchMetric.side)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A result, a recent, or a neighbour: picture, name, and what it is.
struct ItemRow: View {
    let item: SearchItem
    var removable = false
    @Environment(SearchModel.self) private var model
    @Environment(BusinessOpener.self) private var opener
    @State private var avatarFrame = FrameBox()

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: tap) {
                HStack(spacing: SearchMetric.rowGap) {
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
                }
                .padding(.horizontal, SearchMetric.side)
                .frame(height: SearchMetric.row)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            if removable { RemoveButton(name: item.name) { forget() } }
        }
    }

    @ViewBuilder private var avatar: some View {
        if item.kind == .person {
            SearchPhoto(item: item).clipShape(Circle())
        } else if let logo = item.logo {
            ZStack {
                SearchBackdrop(colors: logo.backdrop)
                SearchFloor()
                CastLogo(logo: logo, side: SearchMetric.avatarLogo)
                    .opacity(opener.isAway(item) ? 0 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.searchField, style: .continuous))
        } else if item.photo == nil || item.photo == .google {
            // No logo, and a Google photo would need its photographer's credit on it,
            // with no room for one at this size: what kind of place it is instead.
            RoundedRectangle(cornerRadius: Radius.searchField, style: .continuous)
                .fill(Hue.fill)
                .overlay {
                    Image(systemName: item.kind == .park ? "tree" : item.kind == .business ? "storefront" : "fork.knife")
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
        guard item.opens, let logo = item.logo else { return }
        let box = avatarFrame.rect, size = SearchMetric.avatarLogo
        let rect = CGRect(x: box.midX - size / 2, y: box.midY - size / 2, width: size, height: size)
        opener.open(item, from: .init(logo: rect, box: rect, radius: 0, shadow: logo.shadow))
    }

    private func forget() {
        withAnimation(.spring(response: 0.3, dampingFraction: 1)) { model.forget(item.id) }
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
            .buttonStyle(RowPressStyle())
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
        .buttonStyle(DimStyle())
        .padding(.trailing, SearchMetric.removeTrail)
        .accessibilityLabel("Remove \(name)")
    }
}

private struct NothingFound: View {
    var body: some View {
        Image(systemName: "magnifyingglass")
            .font(.glyph(34, weight: .light))
            .foregroundStyle(Hue.edge)
            .frame(maxWidth: .infinity)
            .padding(.top, SearchMetric.noneTop)
            .accessibilityLabel("Nothing found")
    }
}

/// A place, event or club's picture: bundled, from the asset catalog, or Google's with
/// its photographer's credit. Waits as a shimmering block, and falls back to the logo
/// on its backdrop when Google has nothing.
struct SearchPhoto: View {
    let item: SearchItem

    var body: some View {
        Rectangle()
            .fill(Hue.fill)
            .overlay {
                switch item.photo {
                case .bundled(let name):
                    if let url = Bundle.main.url(forResource: name, withExtension: "jpg") { FeedCardURLPhoto(url: url) }
                case .asset(let name):
                    Image(name).resizable().scaledToFill()
                case .google:
                    GooglePhoto(item: item)
                case nil:
                    EmptyView()
                }
            }
            .clipped()
    }
}

private struct GooglePhoto: View {
    let item: SearchItem
    @State private var photo: ConfidentPhoto?
    @State private var asked = false
    @State private var shown = false

    var body: some View {
        ZStack {
            if let photo {
                FeedCardURLPhoto(url: GooglePlacesService.shared.photoURL(name: photo.photoName, maxWidth: 600),
                                 onReady: { shown = true }, onFailure: { self.photo = nil })
                if shown {
                    PhotoCredit(names: photo.attributions)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            } else if asked {
                if let logo = item.logo {
                    SearchBackdrop(colors: logo.backdrop)
                    CastLogo(logo: logo, side: SearchMetric.logoOnTile)
                }
            } else {
                Rectangle().fill(Hue.fill).shimmering()
            }
        }
        .task(id: item.id) {
            photo = await Self.lookup(item)
            asked = true
        }
    }

    /// A real Google id is asked directly; anything else has to clear Locked Rule A.
    static func lookup(_ item: SearchItem) async -> ConfidentPhoto? {
        let places = GooglePlacesService.shared
        if let id = item.googleId {
            return await places.details(placeId: id)?.photo.map { ConfidentPhoto(photoName: $0.name, attributions: $0.attributions) }
        }
        guard let coordinate = item.coordinate else { return nil }
        return await places.confidentPhoto(name: item.fullName ?? item.name, coordinate: coordinate)
    }
}

// MARK: - A row's whole list

struct SearchShelfPage: View {
    let shelf: SearchShelf
    @State private var opener = BusinessOpener()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var studio: Bool { shelf.kind == .business }

    var body: some View {
        ZStack(alignment: .top) {
            if studio {
                SearchBackdrop.studio.ignoresSafeArea()
            } else {
                Hue.paper.ignoresSafeArea()
            }
            ScrollView {
                list
                    .padding(.top, SearchMetric.pageBar)
                    .padding(.bottom, SearchMetric.tabBarClearance)
            }
            bar
            BusinessPage()
        }
        .environment(opener)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { opener.reduceMotion = reduceMotion }
    }

    @ViewBuilder private var list: some View {
        switch shelf.kind {
        case .person:
            LazyVStack(spacing: 0) { ForEach(shelf.items) { ItemRow(item: $0) } }
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

    private var bar: some View {
        ZStack {
            Text(shelf.title)
                .font(.sansSemibold(17))
                .foregroundStyle(Hue.ink)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.glyph(20, weight: .semibold))
                        .foregroundStyle(Hue.ink)
                        .frame(width: SearchMetric.pageBar, height: SearchMetric.pageBar)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DimStyle())
                .accessibilityLabel("Back")
                Spacer()
            }
            .padding(.leading, SearchMetric.removeTrail)
        }
        .frame(height: SearchMetric.pageBar)
        .frame(maxWidth: .infinity)
        .background((studio ? SearchBackdrop.studioTop : Hue.paper).ignoresSafeArea(edges: .top))
    }
}

// MARK: - Touch

/// Squishes while the finger is down, sprung like the mockup's (0.95; response 0.28,
/// damping 0.68), and springs back the way it went.
struct SquishStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? SearchMetric.pressScale : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.68), value: configuration.isPressed)
    }
}

/// Fades while pressed: a row's title, Cancel, back.
struct DimStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? SearchMetric.dimPressed : 1)
    }
}

/// A list row darkens a touch under the finger.
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(Hue.ink.opacity(configuration.isPressed ? SearchMetric.rowPressed : 0))
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
