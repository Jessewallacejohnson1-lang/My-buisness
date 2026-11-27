//
//  ProfilePage.swift
//  Block Party — a profile's page, yours (the You tab, five-tabs 03) and a neighbour's, laid out
//  as Luma's (BP app references/profile-left, agreed 2026-11-25): no cover, on the light grey, the
//  picture at the top left with your Edit profile and map beside it, the name, the bio and the
//  counts on one line under it on the left, then Going as the Group page's "Coming up" date tiles
//  and Groups, each list in a white card on the grey. The top buttons are flat white circles. The
//  text under the name is SF Pro (`Font.apple`).
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
    var bio: String?
    var friends: Int?
    /// How many they follow (`get_profile`); nil until read, or from a server without the count.
    var following: Int?
    /// How many follow them (`get_profile`); nil until read, or from a server without the count.
    var followers: Int?
    /// The counts' read is out (a real account, no answer yet): their place holds a skeleton.
    var countsLoading = false
    var groups: [TownGroup] = []
    /// The Going rows, soonest first; nil leaves the section out (a stranger, and your own page).
    var going: [DailyEvent]?
    /// Your own page with no bio: "+ Add bio" where the bio would be.
    var addsBio = false
    /// The time the Going rows' "Now" and start times are read at.
    var now = Date()

    /// The counts' parts, "24 friends", "9 following", "3 followers": three numbers at most, the
    /// same on every Profile (Jesse, 2026-11-17, BP app references/followers-count). A zero or an
    /// unknown is left out, never said.
    static func counts(friends: Int?, following: Int?, followers: Int?) -> [(number: Int, word: String)] {
        var parts: [(number: Int, word: String)] = []
        if let friends, friends > 0 { parts.append((friends, friends == 1 ? "friend" : "friends")) }
        if let following, following > 0 { parts.append((following, "following")) }
        if let followers, followers > 0 { parts.append((followers, followers == 1 ? "follower" : "followers")) }
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

    /// Changes when a section comes or goes, so it fades rather than pops.
    fileprivate var shape: [Int] {
        [bio == nil ? 0 : 1, addsBio ? 1 : 0, friends ?? -1, following ?? -1, countsLoading ? 1 : 0, groups.count,
         going?.count ?? -1]
    }
}

/// The agreed mock's sizes on a 402 pt phone (BP app references/profile-left, `SPEC.md` and
/// `make_mock.py`'s CSS): the picture on the left, the buttons beside it, no cover.
enum ProfileMetric {
    /// A picture on the left, a person's or (profile-left 03) a Place's logo: 80 pt, 20 pt from the
    /// side, Luma's, measured on both References.
    static let picture: CGFloat = 80
    static let pictureSide: CGFloat = 20
    /// A person's picture starts 56 pt under the safe area's top (Luma's 118 under a 62 pt safe area).
    static let pictureTop: CGFloat = 56
    /// The buttons beside the picture, at the right, 20 pt in (`pictureSide`): 36 pt drawn and 44 to
    /// the finger (the agent's pick; Luma's are 32), 10 pt apart. A capsule's words 16 pt in, its icon
    /// 7 pt after them and 15 pt tall; the round one's glyph 16 pt.
    static let side: CGFloat = 36
    static let sideGap: CGFloat = 10
    static let sidePad: CGFloat = 16
    /// At least 6 pt above and below its words, so it grows with large text (picked).
    static let sideTextPad: CGFloat = 6
    static let sideIconGap: CGFloat = 7
    static let sideIcon: CGFloat = 15
    static let sideGlyph: CGFloat = 16
    /// The round one's lift, the mock's: black at 8%, 4 pt down with a 16 pt blur (SwiftUI's radius is half).
    static let sideShadow: Double = 0.08
    static let sideBlur: CGFloat = 8
    static let sideDrop: CGFloat = 4
    /// At the largest text sizes, where they no longer fit beside it, they drop 12 pt under the picture
    /// (picked).
    static let sideUnder: CGFloat = 12
    /// The side buttons' middle, down the page: 27 pt under a cover's foot when the picture sits over one
    /// (a Place), else 13 pt above the picture's foot.
    static func sideMiddle(pictureTop: CGFloat, coverFoot: CGFloat?) -> CGFloat {
        coverFoot.map { $0 + 27 } ?? pictureTop + picture - 13
    }

    /// The name 16 pt under the picture, Inter Tight SemiBold 26 a touch tight, the mock's -0.2.
    static let nameUnder: CGFloat = 16
    static let nameTracking: CGFloat = -0.2
    /// The bio 6 pt under the name, Apple 16 on 22: SF's own line at 16 is about 19, so 3 between lines.
    static let bioTop: CGFloat = 6
    static let bioLineSpacing: CGFloat = 3
    /// "+ Add bio": its 44 pt tap box 4 pt under the name.
    static let addBioTop: CGFloat = 4
    /// The counts on one line 12 pt under the bio, 16 pt apart, the mock's. Too long for the line (the
    /// largest text), each takes its own line, 4 pt apart (picked).
    static let countsTop: CGFloat = 12
    static let countGap: CGFloat = 16
    static let countLines: CGFloat = 4
    /// Their skeleton while the read is out (picked): three blocks 12 pt tall, each as wide as
    /// "24 following", on the line they stand in for.
    static let countSkeletons = 3
    static let countSkeletonHeight: CGFloat = 12

    /// The Place page's centred head (place-pages 08), until profile-left 03 moves its logo to the left:
    /// the 96 pt disc in a 4 pt ring, the name 10 pt under the ring, and its two black buttons, 16 pt under,
    /// 40 pt tall to the eye and 44 to the finger, 10 pt apart, the icon 8 pt from its word.
    static let photo: CGFloat = 96
    static let ring: CGFloat = 4
    static let nameTop: CGFloat = photo / 2 + ring + 10
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
    /// The top circles, Hypelist's measured: 42 pt in a 44 pt tap box, 16 pt from the side, 8 pt
    /// apart, their tops at the safe area's top.
    static let glass: CGFloat = 42
    static let glassSide: CGFloat = 16
    static let glassGap: CGFloat = 8
    /// Between two tap boxes, so the circles sit `glassGap` apart.
    static let glassBoxGap: CGFloat = glassGap - (PageMetric.tapMin - glass)
    /// The glass over a Place's cover, the mock's CSS: white at 74% with a white rim at 70%, or black at
    /// 60% with a white rim at 16%, over the thin material, a 1 pt rim; each lifted by black at 12%, 2 pt
    /// down with a 10 pt blur (SwiftUI's radius is half of it).
    static let whiteGlass: Double = 0.74
    static let whiteRim: Double = 0.7
    static let darkGlass: Double = 0.6
    static let darkRim: Double = 0.16
    static let glassRim: CGFloat = 1
    static let glassShadow: Double = 0.12
    static let glassBlur: CGFloat = 5
    static let glassDrop: CGFloat = 2
}

struct ProfilePage<Buttons: View, Side: View>: View {
    let face: ProfileFace
    /// Your own page: your full Calendar and Agenda under "Going", where a neighbour's page has
    /// its Going rows (five-tabs 03). Nil on a neighbour's.
    var calendar: YouPage?
    /// The flat white circles at the top (`ProfileGlassButton`): your share and gear, or a
    /// neighbour's Back, Message and •••.
    @ViewBuilder let buttons: () -> Buttons
    /// A neighbour's one button beside the picture, in your Edit profile's spot (`RelationButtons`,
    /// profile-left 02); unused on your own page.
    @ViewBuilder let side: () -> Side
    /// Your own page: Edit profile, from "+ Add bio" and the button beside your picture; nil on a
    /// neighbour's, which has neither.
    var edit: (() -> Void)? = nil
    /// Your own page's round map button: the town map, as the Town bar's yellow disc opens it.
    var openMap: () -> Void = {}
    /// A row's tap: the page that holds this one pushes the Event or the Group page.
    var openEvent: (FeedCardItem) -> Void = { _ in }
    var openGroup: (TownGroup) -> Void = { _ in }
    /// Your own page: a tap on a count opens that list; nil leaves it plain.
    var openFriends: (() -> Void)? = nil
    var openFollowing: (() -> Void)? = nil
    var openFollowers: (() -> Void)? = nil
    /// Your own page: Start a group, the last row of Groups (BP app start-a-group 02); nil on a neighbour's.
    var startGroup: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var zoom
    @State private var showingPhoto = false

    private typealias Event = EventPage.Metric
    private typealias Sizes = GroupPage.Metric

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                head

                if let calendar {
                    section("Going")
                    // Edge to edge: the Calendar keeps Lapse's 18.5 pt sides, and the Agenda swipes
                    // across the whole width.
                    calendar.padding(.horizontal, -ProfileMetric.pictureSide)
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

                if !face.groups.isEmpty || startGroup != nil {
                    section("Groups")
                    card {
                        ForEach(face.groups) { group in
                            Button { openGroup(group) } label: { groupRow(group) }
                                .buttonStyle(.press(.squish))
                                .padding(.top, Sizes.rowTop)
                        }
                        if let startGroup {
                            StartGroupRow(tile: Sizes.tile, corner: Sizes.tileCorner, font: .apple(16, weight: .semibold),
                                          action: startGroup)
                                .padding(.top, Sizes.rowTop)
                        }
                    }
                }
            }
            .padding(.horizontal, ProfileMetric.pictureSide)
            .padding(.top, ProfileMetric.pictureTop)
            .padding(.bottom, Event.contentBottom)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.smooth, value: face.shape)
        }
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
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showingPhoto) {
            ProfilePhotoView(url: face.avatarUrl.flatMap(URL.init(string:)), name: face.name)
                .navigationTransition(.zoom(sourceID: "photo", in: zoom))
        }
    }

    // MARK: The head

    /// The picture at the left with your buttons beside it, then the name, the bio or "+ Add bio" and
    /// the counts under it, all on the left (Luma's).
    private var head: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Beside the picture, or under it once they no longer fit (the largest text sizes).
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    photo
                    Spacer(minLength: ProfileMetric.sideGap)
                    sideButtons
                        .padding(.top, ProfileMetric.sideMiddle(pictureTop: 0, coverFoot: nil) - ProfileMetric.side / 2)
                        .frame(height: ProfileMetric.picture, alignment: .top)
                }
                VStack(alignment: .leading, spacing: ProfileMetric.sideUnder) {
                    photo
                    sideButtons
                }
            }

            Text(face.name)
                .font(.displaySemi(26))
                .tracking(ProfileMetric.nameTracking)
                .foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, ProfileMetric.nameUnder)

            if let bio = face.bio {
                Text(bio)
                    .font(.apple(16))
                    .lineSpacing(ProfileMetric.bioLineSpacing)
                    .foregroundStyle(Hue.ink)
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

            let counts = ProfileFace.counts(friends: face.friends, following: face.following,
                                            followers: face.followers)
            // The counts, or their skeleton while the read is out, in one place, cross-fading, so the
            // lists under them never move when the counts land (docs/rules/design.md, "Loading"). No
            // counts, a failed read or the quiet account: no row and no gap.
            if !counts.isEmpty || face.countsLoading {
                ZStack(alignment: .leading) {
                    if counts.isEmpty {
                        countsSkeleton.transition(.opacity)
                    } else {
                        countsRow(counts).transition(.opacity)
                    }
                }
                .padding(.top, ProfileMetric.countsTop)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The squircle at the left. A tap opens it whole; it drags down to close.
    private var photo: some View {
        Button {
            Haptics.light()
            showingPhoto = true
        } label: {
            Avatar(avatarUrl: face.avatarUrl, size: ProfileMetric.picture, outlined: true)
        }
        .buttonStyle(.press(.squish))
        .disabled(face.avatarUrl == nil)
        // No photo to open: the blank picture says nothing, so VoiceOver skips it, never "dimmed".
        .accessibilityHidden(face.avatarUrl == nil)
        .matchedTransitionSource(id: "photo", in: zoom)
        .accessibilityLabel("\(face.name)'s photo")
        .accessibilityHint(face.avatarUrl == nil ? "" : "Opens it larger")
    }

    /// The buttons beside the picture: on your own page Edit profile with Jesse's palette, then the round
    /// map; on a neighbour's their one button.
    @ViewBuilder
    private var sideButtons: some View {
        if let edit {
            HStack(spacing: ProfileMetric.sideGap) {
                Button(action: edit) {
                    SideCapsule {
                        Text("Edit profile")
                        Image(decorative: "Palette")
                            .resizable()
                            .scaledToFit()
                            .frame(height: ProfileMetric.sideIcon)
                    }
                }
                .buttonStyle(.press(.squish))
                // The squish without a haptic, as the Town bar's disc: opening the map is not a commit.
                Button(action: openMap) {
                    SideCircle { Image(systemName: "map") }
                }
                .buttonStyle(.press(.squish))
                .accessibilityLabel("Map")
            }
        } else {
            side()
        }
    }

    /// The counts on one line, "24 friends  9 following  3 followers", the numbers in ink, the words grey,
    /// or one under another when the line won't hold them. VoiceOver reads them as one line, or, on your own
    /// page where each opens its list (Instagram's counts), one button each. Each is known by its word, so
    /// a count that arrives slides the others over, never cross-fading one into its neighbour's place.
    private func countsRow(_ counts: [(number: Int, word: String)]) -> some View {
        let tappable = counts.contains { opens($0.word) != nil }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: ProfileMetric.countGap) { countParts(counts) }
            VStack(alignment: .leading, spacing: ProfileMetric.countLines) { countParts(counts) }
        }
        .accessibilityElement(children: tappable ? .contain : .ignore)
        .accessibilityLabel(tappable ? "" : counts.map { "\($0.number) \($0.word)" }.joined(separator: ", "))
    }

    @ViewBuilder
    private func countParts(_ counts: [(number: Int, word: String)]) -> some View {
        ForEach(counts, id: \.word) { part in
            let words = Text("\(Text("\(part.number)").fontWeight(.semibold).foregroundStyle(Hue.ink)) \(part.word)")
                .font(.apple(16))
                .monospacedDigit()
                .foregroundStyle(Hue.inkSecondary)
                .lineLimit(1)
                .fixedSize()
            if let open = opens(part.word) {
                Button(action: open) { words.contentShape(TapArea()) }
                    .buttonStyle(.press(.squish))
                    .accessibilityLabel("\(part.number) \(part.word)")
            } else {
                words
            }
        }
    }

    /// The list a count opens: your friends, your follows and your followers, on your own page only.
    private func opens(_ word: String) -> (() -> Void)? {
        switch word {
        case "friend", "friends": openFriends
        case "following": openFollowing
        case "follower", "followers": openFollowers
        default: nil
        }
    }

    /// The counts' place while their read is out: three short blocks on the line, each as wide as a count
    /// and the line as tall as the text it stands in for (the text is there, hidden), so the row that lands
    /// takes exactly this height.
    private var countsSkeleton: some View {
        HStack(spacing: ProfileMetric.countGap) {
            ForEach(0..<ProfileMetric.countSkeletons, id: \.self) { _ in
                Text(verbatim: "24 following")
                    .font(.apple(16))
                    .lineLimit(1)
                    .fixedSize()
                    .hidden()
                    .overlay {
                        SkeletonBlock(cornerRadius: ProfileMetric.countSkeletonHeight / 2, color: Hue.onboardingField)
                            .frame(height: ProfileMetric.countSkeletonHeight)
                    }
            }
        }
        .shimmering()
        .accessibilityHidden(true)
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
                // Asks to join waiting on a Group you run (start-a-group 03): the quiet yellow dot.
                .overlay(alignment: .topTrailing) {
                    if (group.requests ?? 0) > 0 { UnreadDot(ring: Hue.surface, inkRight: 4, inkTop: 4) }
                }
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
                            .frame(width: ProfileMetric.picture, height: ProfileMetric.picture)
                            .scaleEffect(side / ProfileMetric.picture)
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

/// A button beside the picture (profile-left), drawn 36 pt tall (taller only with large text) and 44 to
/// the finger, with round ends, as wide as its words, 16 pt in: white words on ink (your Edit profile, a
/// neighbour's Add friend and Confirm), or `light`, ink words on white with a hairline round it (Cancel
/// request, Delete and Friends), the mock's `.bk` and `.wt`.
struct SideCapsule<Content: View>: View {
    var light = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: ProfileMetric.sideIconGap) { content() }
            .font(.displaySemi(15))
            .foregroundStyle(light ? Hue.ink : Hue.surface)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, ProfileMetric.sidePad)
            // Taller with the text at the largest sizes, never cut.
            .padding(.vertical, ProfileMetric.sideTextPad)
            .frame(minHeight: ProfileMetric.side)
            .background {
                Capsule()
                    .fill(light ? Hue.surface : Hue.ink)
                    .overlay { if light { Capsule().strokeBorder(Hue.hairline, lineWidth: ProfileMetric.glassRim) } }
            }
            .contentShape(TapArea())
    }
}

/// The round button beside the picture: an ink glyph on a white disc with a hairline and a soft lift,
/// 36 pt drawn and 44 to the finger. Your map.
struct SideCircle<Glyph: View>: View {
    @ViewBuilder let glyph: () -> Glyph

    var body: some View {
        glyph()
            .font(.glyph(ProfileMetric.sideGlyph, weight: .semibold))
            .foregroundStyle(Hue.ink)
            .frame(width: ProfileMetric.side, height: ProfileMetric.side)
            .background {
                Circle()
                    .fill(Hue.surface)
                    .overlay { Circle().strokeBorder(Hue.hairline, lineWidth: ProfileMetric.glassRim) }
                    .shadow(color: .black.opacity(ProfileMetric.sideShadow), radius: ProfileMetric.sideBlur,
                            y: ProfileMetric.sideDrop)
            }
            .contentShape(TapArea())
    }
}

/// One of a Place's black buttons with round ends: white words on ink, half the row, 40 pt to the eye
/// and 44 to the finger. A Place's Follow and Map (place-pages 08), until profile-left 03.
struct ProfileBlackButton<Content: View>: View {
    var fill = Hue.ink
    var ink = Hue.surface
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: ProfileMetric.buttonIconGap) { content() }
            .font(.displaySemi(15))
            .foregroundStyle(ink)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: ProfileMetric.button)
            .background(fill, in: Capsule())
            .contentShape(Rectangle().inset(by: (ProfileMetric.button - PageMetric.tapMin) / 2))
    }
}

/// A round button at the top of a page, Hypelist's (BP app references/profile-middle): a 42 pt circle in
/// a 44 pt tap box. On a Profile (profile-left 01) and a Place with no photo it is `flat`: solid white with
/// a hairline. Over a Place's cover it is glass: white glass carries an ink glyph, dark glass (•••) a white one. A tint over the thin material, as the Event page's `EventGlassButton`, not
/// Liquid Glass: neither may change with the photo under it (taste.md, "Chrome over content"; Liquid
/// Glass went dark over a dark photo, `EventPage.circleButton`). Both pin the material's light scheme,
/// whatever the phone's mode: the dark one's black tint over the dark material came out nearly solid
/// black, where the mock's black at 60% lets the photo through.
struct ProfileGlassButton<Glyph: View>: View {
    let glyph: Glyph
    let label: String
    var dark = false
    var flat = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ProfileGlassCircle(glyph: glyph, dark: dark, flat: flat)
        }
        .buttonStyle(.press(.squish))
        .accessibilityLabel(label)
    }
}

/// The glass circle in its 44 pt tap box, alone, so a menu's label draws it too (a place's •••, place-pages
/// 11). `flat`: on a page with no photo under it, solid white with a hairline round it, the mock's.
struct ProfileGlassCircle<Glyph: View>: View {
    let glyph: Glyph
    var dark = false
    var flat = false

    var body: some View {
        glyph
            .font(.glyph(17, weight: .semibold))
            .foregroundStyle(dark ? Color.white : Hue.ink)
            .frame(width: ProfileMetric.glass, height: ProfileMetric.glass)
            .background {
                if flat {
                    Circle()
                        .fill(Hue.surface)
                        .overlay { Circle().strokeBorder(Hue.hairline, lineWidth: ProfileMetric.glassRim) }
                        .shadow(color: .black.opacity(ProfileMetric.glassShadow), radius: ProfileMetric.glassBlur,
                                y: ProfileMetric.glassDrop)
                } else {
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
            }
            .environment(\.colorScheme, .light)
            .frame(width: PageMetric.tapMin, height: PageMetric.tapMin)
            .contentShape(Rectangle())
    }
}
