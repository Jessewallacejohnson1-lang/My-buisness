//
//  ProfilePage.swift
//  Block Party — a profile's page, yours (the You tab, five-tabs 03) and a neighbour's,
//  built from the Group page's parts (BP app references/profile-remake; taste/you.md 2026-10-25)
//  and centred as Places' (BP app references/profile-middle, mock version 8): the cover photo
//  under a light grey sheet, the round photo in the middle of the sheet's edge, the name, the bio,
//  the counts as numbers over words, your two black buttons, then Going as the Group page's
//  "Coming up" date tiles and Groups, each list in a white card on the grey. The cover's round
//  buttons are glass that never changes with the photo. The text under the name is SF Pro
//  (`Font.apple`), the one screen off BP Body (Jesse: "use same font as group page").
//
//  Going is per Event, never a person's agenda (friends spec, 2026-10-13): your own is your full
//  Calendar and Agenda, which only you see; a friend's only the Events you're both Going to, a
//  stranger's not at all.
//
//  PRODUCT RULE, as the Group page's: never a zero count or a placeholder. Every row is absent
//  when its data is.
//

import SwiftUI

/// What one profile shows.
struct ProfileFace {
    var name: String
    var avatarUrl: String?
    var coverUrl: String?
    var bio: String?
    var friends: Int?
    /// How many they follow (`get_profile`); nil until read, or from a server without the count.
    var following: Int?
    /// The counts' read is out (a real account, no answer yet): their place holds a skeleton.
    var countsLoading = false
    var groups: [TownGroup] = []
    /// The Going rows, soonest first; nil leaves the section out (a stranger, and your own page).
    var going: [DailyEvent]?
    /// Your own page with no bio: "+ Add bio" where the bio would be.
    var addsBio = false
    /// A neighbour's friends you share: "2 mutual" in the counts.
    var mutual = 0
    /// False until the read that says whether they picked a cover has come back: the plain fill
    /// until then, never the town photo first and theirs after.
    var coverKnown = true
    /// The time the Going rows' "Now" and start times are read at.
    var now = Date()

    /// The counts' parts, "24 friends", "1 group", "9 following": a zero or an unknown is left
    /// out, never said.
    static func counts(friends: Int?, mutual: Int = 0, groups: Int, following: Int?) -> [(number: Int, word: String)] {
        var parts: [(number: Int, word: String)] = []
        if let friends, friends > 0 { parts.append((friends, friends == 1 ? "friend" : "friends")) }
        if mutual > 0 { parts.append((mutual, "mutual")) }
        if groups > 0 { parts.append((groups, groups == 1 ? "group" : "groups")) }
        if let following, following > 0 { parts.append((following, "following")) }
        return parts
    }

    /// The next plans of a list in the Calendar's order (`YouCalendar.going`): those not over
    /// yet, three at most.
    static func nextPlans(_ events: [DailyEvent], now: Date) -> [DailyEvent] {
        Array(events.filter { $0.ends > now }.prefix(3))
    }

    /// A row's line: "Sat, Oct 31 · 9 AM", the Group page's words with the card's time.
    static func goingLine(_ event: DailyEvent, now: Date) -> String {
        [GroupPage.meetingLine(TownGroup.Meeting(what: "", day: Town.day(event.starts))), event.startTime(now: now)]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// The cover until they pick one: the bundled downtown photo, read once.
    @MainActor static let town: UIImage? = Bundle.main.url(forResource: "downtown", withExtension: "jpg")
        .flatMap { UIImage(contentsOfFile: $0.path) }

    /// Changes when a section comes or goes, so it fades rather than pops.
    fileprivate var shape: [Int] {
        [bio == nil ? 0 : 1, addsBio ? 1 : 0, friends ?? -1, following ?? -1, countsLoading ? 1 : 0, groups.count,
         going?.count ?? -1]
    }
}

/// The agreed mock's sizes on a 402 pt phone (BP app references/profile-middle, `SPEC.md` "Agreed
/// for the build", mock version 8's CSS). The cover, the sheet and the date tiles are the Group
/// page's (`GroupPage.Metric`, the Event page's).
enum ProfileMetric {
    /// The photo: 96 pt in a 4 pt ring of the page's grey, its middle on the sheet's edge and on the
    /// screen's (Places', measured).
    static let photo: CGFloat = 96
    static let ring: CGFloat = 4
    /// The name starts 10 pt under the ring: 62 pt down the sheet, the mock's.
    static let nameTop: CGFloat = photo / 2 + ring + 10
    /// The name's Inter Tight SemiBold 26 a touch tight, the mock's -0.2.
    static let nameTracking: CGFloat = -0.2
    /// The bio 8 pt under the name (picked, Places' 13 between inks), Apple 16 on 22: SF's own line
    /// at 16 is about 19, so 3 between lines.
    static let bioTop: CGFloat = 8
    static let bioLineSpacing: CGFloat = 3
    /// "+ Add bio": its 44 pt tap box 4 pt under the name, the mock's.
    static let addBioTop: CGFloat = 4
    /// The counts 16 pt under the bio (picked), each number over its word in an 81 pt column:
    /// Hypelist's measured pitch, no card (Jesse, 2026-11-14).
    static let countsTop: CGFloat = 16
    static let countColumn: CGFloat = 81
    /// Their skeleton while the read is out (picked): three columns, a 24 x 14 pt block for the
    /// number over a 44 x 10 pt one for the word, each centred on the line it stands in for.
    static let countSkeletons = 3
    static let countSkeletonNumber = CGSize(width: 24, height: 14)
    static let countSkeletonWord = CGSize(width: 44, height: 10)
    /// Your two buttons, Places' measured: 16 pt under the counts (picked), 40 pt tall to the eye and
    /// 44 to the finger (`PageMetric.tapMin`), 10 pt apart, each half the row; the icon 8 pt from its
    /// word, the mock's. Jesse's palette is drawn 17 pt tall (its image set's own size).
    static let buttonsTop: CGFloat = 16
    static let button: CGFloat = 40
    static let buttonGap: CGFloat = 10
    static let buttonIconGap: CGFloat = 8
    /// A list's title 28 pt under what's above it (picked); its white card 12 pt under the title,
    /// the rows 12 pt in from its sides and foot, the Agenda card's 0.5 pt hairline round it.
    static let sectionTop: CGFloat = 28
    static let cardTop: CGFloat = 12
    static let cardInset: CGFloat = 12
    static let cardLine: CGFloat = 0.5
    static let rowText: CGFloat = 3
    /// The cover's glass circles, Hypelist's measured: 42 pt in a 44 pt tap box, 16 pt from the
    /// side, 8 pt apart, their tops at the safe area's top.
    static let glass: CGFloat = 42
    static let glassSide: CGFloat = 16
    static let glassGap: CGFloat = 8
    /// Between two tap boxes, so the circles sit `glassGap` apart.
    static let glassBoxGap: CGFloat = glassGap - (PageMetric.tapMin - glass)
    /// The glass, the mock's CSS: white at 74% with a white rim at 70%, or black at 60% with a white
    /// rim at 16%, over the thin material, a 1 pt rim; each lifted by black at 12%, 2 pt down with a
    /// 10 pt blur (SwiftUI's radius is half of it).
    static let whiteGlass: Double = 0.74
    static let whiteRim: Double = 0.7
    static let darkGlass: Double = 0.6
    static let darkRim: Double = 0.16
    static let glassRim: CGFloat = 1
    static let glassShadow: Double = 0.12
    static let glassBlur: CGFloat = 5
    static let glassDrop: CGFloat = 2
}

struct ProfilePage<Buttons: View, Bar: View>: View {
    let face: ProfileFace
    /// Your own page: your full Calendar and Agenda under "Going", where a neighbour's page has
    /// its Going rows (five-tabs 03). Nil on a neighbour's.
    var calendar: YouPage?
    /// The glass circles on the cover (`ProfileGlassButton`): your share and gear, or a neighbour's
    /// Back, Message and •••.
    @ViewBuilder let buttons: () -> Buttons
    /// A neighbour's one pill at the bottom; nothing on your own page.
    @ViewBuilder let bar: () -> Bar
    /// Your own page: Edit profile, from "+ Add bio" and the first black button; nil on a
    /// neighbour's, which has neither button.
    var edit: (() -> Void)? = nil
    /// Your own page's Map button: the town map, as the Town bar's yellow disc opens it.
    var openMap: () -> Void = {}
    /// A row's tap: the page that holds this one pushes the Event or the Group page.
    var openEvent: (FeedCardItem) -> Void = { _ in }
    var openGroup: (TownGroup) -> Void = { _ in }
    /// Your own page: a tap on the friends or following count opens that list; nil leaves it plain.
    var openFriends: (() -> Void)? = nil
    var openFollowing: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var zoom
    @State private var showingPhoto = false

    private typealias Event = EventPage.Metric
    private typealias Sizes = GroupPage.Metric

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                cover
                sheet
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Hue.onboardingCanvas.ignoresSafeArea())
        // Outside the scroll, so the buttons stay put; read first by VoiceOver, as they sit. The
        // circles' tops at the safe area's, 16 pt from the sides; their tap boxes reach 1 pt past.
        .overlay(alignment: .top) {
            buttons()
                .padding(.horizontal, ProfileMetric.glassSide - (PageMetric.tapMin - ProfileMetric.glass) / 2)
                .padding(.top, -(PageMetric.tapMin - ProfileMetric.glass) / 2)
                .accessibilityElement(children: .contain)
                .accessibilitySortPriority(1)
        }
        .accessibilityElement(children: .contain)
        .safeAreaInset(edge: .bottom, spacing: 0) { bar() }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showingPhoto) {
            ProfilePhotoView(url: face.avatarUrl.flatMap(URL.init(string:)), name: face.name)
                .navigationTransition(.zoom(sourceID: "photo", in: zoom))
        }
    }

    // MARK: The cover

    /// Their cover, else a St. Joseph photo; pulling past the top stretches it, as the Group page's.
    private var cover: some View {
        Color.clear
            .aspectRatio(Sizes.heroAspect, contentMode: .fit)
            .overlay(alignment: .top) {
                GeometryReader { proxy in
                    Group {
                        if let url = face.coverUrl.flatMap(URL.init(string:)) {
                            FeedCardURLPhoto(url: url, loadingFill: Hue.fill)
                        } else if face.coverKnown, let town = ProfileFace.town {
                            Image(uiImage: town).resizable().scaledToFill()
                        } else {
                            Hue.fill
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height + Event.heroUnderlap)
                    .clipped()
                }
            }
            .visualEffect { content, proxy in
                let pull = max(0, proxy.frame(in: .scrollView(axis: .vertical)).minY)
                return content.scaleEffect(1 + pull / max(proxy.size.height, 1), anchor: .bottom)
            }
            .accessibilityHidden(true)
    }

    // MARK: The sheet

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            head

            if let calendar {
                section("Going")
                // Edge to edge: the Calendar keeps Lapse's 18.5 pt sides, and the Agenda swipes
                // across the whole width.
                calendar.padding(.horizontal, -Event.inset)
            }

            if let going = face.going, !going.isEmpty {
                section("Going")
                card {
                    ForEach(going) { event in
                        Button { openEvent(event.item) } label: { goingRow(event) }
                            .buttonStyle(.press(.squish))
                            .padding(.top, Sizes.rowTop)
                    }
                }
            }

            if !face.groups.isEmpty {
                section("Groups")
                card {
                    ForEach(face.groups) { group in
                        Button { openGroup(group) } label: { groupRow(group) }
                            .buttonStyle(.press(.squish))
                            .padding(.top, Sizes.rowTop)
                    }
                }
            }
        }
        .padding(.horizontal, Event.inset)
        .padding(.bottom, Event.contentBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.smooth, value: face.shape)
        .background(Hue.onboardingCanvas, in: UnevenRoundedRectangle(topLeadingRadius: Event.sheetCorner,
                                                                    topTrailingRadius: Event.sheetCorner,
                                                                    style: .continuous))
        .overlay(alignment: .top) { photo }
    }

    /// Under the photo, in the middle as Places' head: the name, the bio or "+ Add bio", the counts,
    /// and on your own page your two buttons.
    private var head: some View {
        VStack(spacing: 0) {
            Text(face.name)
                .font(.displaySemi(26))
                .tracking(ProfileMetric.nameTracking)
                .foregroundStyle(Hue.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, ProfileMetric.nameTop)

            if let bio = face.bio {
                Text(bio)
                    .font(.apple(16))
                    .lineSpacing(ProfileMetric.bioLineSpacing)
                    .foregroundStyle(Hue.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, ProfileMetric.bioTop)
            } else if face.addsBio, let edit {
                // Nextdoor's "Add bio", where the bio will be.
                Button(action: edit) {
                    Label("Add bio", systemImage: "plus")
                        .font(.apple(15, weight: .semibold))
                        .foregroundStyle(Hue.inkSecondary)
                        .frame(minHeight: PageMetric.tapMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.press(.squish))
                .padding(.top, ProfileMetric.addBioTop)
            }

            let counts = ProfileFace.counts(friends: face.friends, mutual: face.mutual, groups: face.groups.count,
                                            following: face.following)
            // The counts, or their skeleton while the read is out, in one place, cross-fading, so the
            // buttons and lists under them never move when the counts land (docs/rules/design.md,
            // "Loading"). No counts, a failed read or the quiet account: no row and no gap.
            if !counts.isEmpty || face.countsLoading {
                ZStack {
                    if counts.isEmpty {
                        countsSkeleton.transition(.opacity)
                    } else {
                        countsRow(counts).transition(.opacity)
                    }
                }
                .padding(.top, ProfileMetric.countsTop)
                .transition(.opacity)
            }

            if let edit {
                yourButtons(edit: edit)
                    .padding(.top, ProfileMetric.buttonsTop)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The round photo in the middle of the sheet's edge. A tap opens it whole; it drags down to close.
    private var photo: some View {
        Button {
            Haptics.light()
            showingPhoto = true
        } label: {
            Avatar(avatarUrl: face.avatarUrl, size: ProfileMetric.photo, outlined: true)
                .padding(ProfileMetric.ring)
                .background(Hue.onboardingCanvas, in: Circle())
        }
        .buttonStyle(.press(.squish))
        .disabled(face.avatarUrl == nil)
        // No photo to open: the blank picture says nothing, so VoiceOver skips it, never "dimmed".
        .accessibilityHidden(face.avatarUrl == nil)
        .matchedTransitionSource(id: "photo", in: zoom)
        .offset(y: -(ProfileMetric.photo / 2 + ProfileMetric.ring))
        .accessibilityLabel("\(face.name)'s photo")
        .accessibilityHint(face.avatarUrl == nil ? "" : "Opens it larger")
    }

    /// Each number over its word in an 81 pt column, the numbers in ink, the words grey, no card.
    /// VoiceOver reads them as one line: "24 friends, 2 groups, 9 following", or, on your own page
    /// where friends and following open their lists (Instagram's counts), one button each. Each
    /// column is known by its word, so a count that arrives and moves the others over slides them,
    /// never cross-fading one number into its neighbour's place.
    private func countsRow(_ counts: [(number: Int, word: String)]) -> some View {
        let tappable = counts.contains { opens($0.word) != nil }
        return HStack(spacing: 0) {
            ForEach(counts, id: \.word) { part in
                let column = VStack(spacing: 0) {
                    Text("\(part.number)")
                        .font(.apple(17, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Hue.ink)
                    Text(part.word)
                        .font(.apple(13))
                        .foregroundStyle(Hue.inkSecondary)
                }
                .lineLimit(1)
                .frame(width: ProfileMetric.countColumn)
                if let open = opens(part.word) {
                    Button(action: open) { column.contentShape(Rectangle().inset(by: -4)) }
                        .buttonStyle(.press(.squish))
                        .accessibilityLabel("\(part.number) \(part.word)")
                } else {
                    column.accessibilityElement(children: .combine)
                }
            }
        }
        .accessibilityElement(children: tappable ? .contain : .ignore)
        .accessibilityLabel(tappable ? "" : counts.map { "\($0.number) \($0.word)" }.joined(separator: ", "))
    }

    /// The list a count opens: your friends and your follows, on your own page only.
    private func opens(_ word: String) -> (() -> Void)? {
        switch word {
        case "friend", "friends": openFriends
        case "following": openFollowing
        default: nil
        }
    }

    /// The counts' place while their read is out: short blocks over shorter ones in the counts'
    /// columns, each line as tall as the text it stands in for (the text is there, hidden), so the
    /// row that lands takes exactly this height.
    private var countsSkeleton: some View {
        HStack(spacing: 0) {
            ForEach(0..<ProfileMetric.countSkeletons, id: \.self) { _ in
                VStack(spacing: 0) {
                    Text(verbatim: "0")
                        .font(.apple(17, weight: .semibold))
                        .hidden()
                        .overlay { countSkeletonBlock(ProfileMetric.countSkeletonNumber) }
                    Text(verbatim: "following")
                        .font(.apple(13))
                        .hidden()
                        .overlay { countSkeletonBlock(ProfileMetric.countSkeletonWord) }
                }
                .frame(width: ProfileMetric.countColumn)
            }
        }
        .shimmering()
        .accessibilityHidden(true)
    }

    private func countSkeletonBlock(_ size: CGSize) -> some View {
        SkeletonBlock(cornerRadius: size.height / 2, color: Hue.onboardingField)
            .frame(width: size.width, height: size.height)
    }

    /// Your two black buttons with round ends, Places' (Jesse, 2026-11-14): "Edit profile" then
    /// Jesse's own palette, and a globe then "Map", each half the row.
    private func yourButtons(edit: @escaping () -> Void) -> some View {
        HStack(spacing: ProfileMetric.buttonGap) {
            Button(action: edit) {
                blackButton {
                    Text("Edit profile")
                    Image(decorative: "Palette")
                }
            }
            .buttonStyle(.press(.squish))
            // The squish without a haptic, as the Town bar's disc: opening the map is not a commit.
            Button(action: openMap) {
                blackButton {
                    Image(systemName: "globe")
                        .font(.glyph(15, weight: .semibold))
                        .accessibilityHidden(true)
                    Text("Map")
                }
            }
            .buttonStyle(.press(.squish))
        }
    }

    /// White words on ink, 40 pt to the eye and 44 to the finger.
    private func blackButton<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: ProfileMetric.buttonIconGap) { content() }
            .font(.displaySemi(15))
            .foregroundStyle(Hue.surface)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: ProfileMetric.button)
            .background(Hue.ink, in: Capsule())
            .contentShape(Rectangle().inset(by: (ProfileMetric.button - PageMetric.tapMin) / 2))
    }

    /// A list's title, the Event page's About: Inter Tight Bold 20.
    private func section(_ title: String) -> some View {
        Text(title)
            .font(.display(20))
            .foregroundStyle(Hue.ink)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, ProfileMetric.sectionTop)
    }

    /// A list's rows in a white card on the grey, the Agenda card's: its corners, shadow and hairline.
    private func card<Rows: View>(@ViewBuilder _ rows: () -> Rows) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) { rows() }
            .padding(.horizontal, ProfileMetric.cardInset)
            .padding(.bottom, ProfileMetric.cardInset)
            .background {
                shape.fill(Hue.surface)
                    .modifier(CardShadow())
                    .overlay { shape.strokeBorder(Hue.hairline, lineWidth: ProfileMetric.cardLine) }
            }
            .padding(.top, ProfileMetric.cardTop)
    }

    /// The Group page's date tile ("OCT" over "31"), then the Event and when.
    private func goingRow(_ event: DailyEvent) -> some View {
        let tile = GroupPage.tile(Town.day(event.starts))
        return HStack(spacing: Sizes.rowGap) {
            VStack(spacing: 0) {
                Text(tile.month)
                    .font(.apple(11, weight: .semibold))
                    .foregroundStyle(Hue.inkSecondary)
                Text(tile.day)
                    .font(.apple(20, weight: .semibold))
                    .foregroundStyle(Hue.ink)
                    .monospacedDigit()
            }
            .frame(width: Sizes.tile, height: Sizes.tile)
            .background(Hue.fill, in: RoundedRectangle(cornerRadius: Sizes.tileCorner, style: .continuous))
            .accessibilityHidden(true)
            rowWords(event.item.title) {
                Text(ProfileFace.goingLine(event, now: face.now))
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The group's logo on its backdrop, or Search's group icon, in the date tile's square.
    private func groupRow(_ group: TownGroup) -> some View {
        HStack(spacing: Sizes.rowGap) {
            Hue.fill
                .overlay { YouGroupPicture(group: group) }
                .frame(width: Sizes.tile, height: Sizes.tile)
                .clipShape(RoundedRectangle(cornerRadius: Sizes.tileCorner, style: .continuous))
                .accessibilityHidden(true)
            rowWords(group.name) {
                if let members = GroupPage.membersText(group.memberCount) { Text(members) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func rowWords<Line: View>(_ title: String, @ViewBuilder line: () -> Line) -> some View {
        VStack(alignment: .leading, spacing: ProfileMetric.rowText) {
            Text(title)
                .font(.apple(16, weight: .semibold))
                .foregroundStyle(Hue.ink)
                .multilineTextAlignment(.leading)
            line()
                .font(.apple(13))
                .foregroundStyle(Hue.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// The photo whole, on black, from a tap on the round one; it drags down to close (Apple's zoom).
private struct ProfilePhotoView: View {
    let url: URL?
    let name: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let url {
                GeometryReader { proxy in
                    let side = min(proxy.size.width, proxy.size.height)
                    ZStack {
                        // The round photo's bitmap, already decoded at its size, stands in
                        // until the whole one lands, so the zoom never opens on black.
                        FeedCardURLPhoto(url: url, loadingFill: Hue.ink)
                            .frame(width: ProfileMetric.photo, height: ProfileMetric.photo)
                            .scaleEffect(side / ProfileMetric.photo)
                        FeedCardURLPhoto(url: url, loadingFill: .clear)
                            .frame(width: side, height: side)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .accessibilityElement()
                .accessibilityLabel("\(name)'s photo")
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.glyph(17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: PageMetric.tapMin, height: PageMetric.tapMin)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.press(.squish))
            .accessibilityLabel("Close")
            .padding(.trailing, EventPage.Metric.inset - (PageMetric.tapMin - EventPage.Metric.button) / 2)
        }
    }
}

/// A neighbour's one pill at the bottom, where the Group page's Join group sits: 24 pt in, 1 pt
/// over the home bar, the page fading to its grey under it from 23 pt above.
struct ProfilePillBar<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, GroupPage.Metric.pillSide)
            .padding(.bottom, GroupPage.Metric.pillBottom)
            .background {
                LinearGradient(colors: [Hue.onboardingCanvas.opacity(0), Hue.onboardingCanvas],
                               startPoint: .top, endPoint: .bottom)
                    .padding(.top, -GroupPage.Metric.fadeAbovePill)
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)
            }
    }
}

/// A round glass button on a profile's cover, Hypelist's (BP app references/profile-middle): a 42 pt
/// circle in a 44 pt tap box. White glass (share, Back, Message) carries an ink glyph, dark glass (the
/// gear, •••) a white one. A tint over the thin material, as the Event page's `EventGlassButton`, not
/// Liquid Glass: neither may change with the photo under it (taste.md, "Chrome over content"; Liquid
/// Glass went dark over a dark photo, `EventPage.circleButton`). Both pin the material's light scheme,
/// whatever the phone's mode: the dark one's black tint over the dark material came out nearly solid
/// black, where the mock's black at 60% lets the photo through.
struct ProfileGlassButton<Glyph: View>: View {
    let glyph: Glyph
    let label: String
    var dark = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            glyph
                .font(.glyph(17, weight: .semibold))
                .foregroundStyle(dark ? Color.white : Hue.ink)
                .frame(width: ProfileMetric.glass, height: ProfileMetric.glass)
                .background {
                    Circle()
                        .fill(dark ? Color.black.opacity(ProfileMetric.darkGlass) : Color.white.opacity(ProfileMetric.whiteGlass))
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay {
                            Circle().strokeBorder(.white.opacity(dark ? ProfileMetric.darkRim : ProfileMetric.whiteRim),
                                                  lineWidth: ProfileMetric.glassRim)
                        }
                        .shadow(color: .black.opacity(ProfileMetric.glassShadow), radius: ProfileMetric.glassBlur,
                                y: ProfileMetric.glassDrop)
                }
                .environment(\.colorScheme, .light)
                .frame(width: PageMetric.tapMin, height: PageMetric.tapMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.press(.squish))
        .accessibilityLabel(label)
    }
}
