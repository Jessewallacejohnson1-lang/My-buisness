//
//  ProfilePage.swift
//  Block Party — a profile's page, yours (Profile, behind your photo on You) and a neighbour's,
//  built from the Group page's parts (BP app references/profile-remake, mock round 4; taste/you.md
//  2026-10-25): the cover photo under the paper sheet, the round photo over the sheet's edge, the
//  name in the event title face, "St. Joseph · Neighbor since …", one counts line, About, Going as
//  the Group page's "Coming up" date tiles, and Groups. The text under the name is SF Pro
//  (`Font.apple`), the one screen off BP Body (Jesse: "use same font as group page").
//
//  Going is per Event, never a person's agenda (friends spec, 2026-10-13): your own next three,
//  a friend's only where you're both Going, a stranger's not at all.
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
    /// "Neighbor since October 2025", a neighbour's with the friends you share.
    var line: String?
    var friends: Int?
    var groups: [TownGroup] = []
    /// The Going rows, soonest first; nil leaves the section and its count out (a stranger).
    var going: [DailyEvent]?
    /// Your own plans in the three weeks, for the counts line; nil on a neighbour's page.
    var goingCount: Int?
    /// Your own page with no bio: "+ Add bio" where About would be.
    var addsBio = false

    /// The counts line's parts, "24 friends", "1 group", "9 going": a zero or an unknown is left
    /// out, never said.
    static func counts(friends: Int?, groups: Int, going: Int?) -> [(number: Int, word: String)] {
        var parts: [(number: Int, word: String)] = []
        if let friends, friends > 0 { parts.append((friends, friends == 1 ? "friend" : "friends")) }
        if groups > 0 { parts.append((groups, groups == 1 ? "group" : "groups")) }
        if let going, going > 0 { parts.append((going, "going")) }
        return parts
    }

    /// The next plans of a list in the Calendar's order (`YouCalendar.going`): those not over
    /// yet, three at most; and how many there are.
    static func nextPlans(_ events: [DailyEvent], now: Date) -> (rows: [DailyEvent], count: Int) {
        let ahead = events.filter { $0.ends > now }
        return (Array(ahead.prefix(3)), ahead.count)
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
        [bio == nil ? 0 : 1, addsBio ? 1 : 0, friends ?? -1, groups.count, going?.count ?? -1]
    }
}

/// The mock's sizes on a 402 pt phone (round 4). The cover, the sheet, the round buttons, the
/// sections and the date tiles are the Group page's (`GroupPage.Metric`, the Event page's).
enum ProfileMetric {
    /// The photo: 96 pt in a 4 pt paper ring, its middle on the sheet's edge, its left 20 pt in.
    static let photo: CGFloat = 96
    static let ring: CGFloat = 4
    /// The name starts 10 pt under the photo.
    static let nameTop: CGFloat = photo / 2 + 10
    static let rowText: CGFloat = 3
    /// "+ Add bio" sits where About's title would, in a 44 pt tap box around its 20 pt line.
    static let addBioLine: CGFloat = 20
}

struct ProfilePage<Buttons: View, Bar: View>: View {
    let face: ProfileFace
    /// The round buttons on the cover: your pencil and ☰, or a neighbour's back and •••.
    @ViewBuilder let buttons: () -> Buttons
    /// A neighbour's one pill at the bottom; nothing on your own page.
    @ViewBuilder let bar: () -> Bar
    var addBio: () -> Void = {}
    /// A row's tap: the page that holds this one pushes the Event or the Group page.
    var openEvent: (FeedCardItem) -> Void = { _ in }
    var openGroup: (TownGroup) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var zoom
    @State private var showingPhoto = false

    private typealias Event = FeedEventDetailDestination.Metric
    private typealias Sizes = GroupPage.Metric

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                cover
                sheet
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Hue.paper.ignoresSafeArea())
        // Outside the scroll, so the buttons stay put; read first by VoiceOver, as they sit.
        .overlay(alignment: .top) {
            buttons()
                .padding(.horizontal, Event.inset - (Event.tapBox - Event.button) / 2)
                .padding(.top, Event.buttonTop - (Event.tapBox - Event.button) / 2)
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
                        } else if let town = ProfileFace.town {
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
            Text(face.name)
                .font(.eventDisplay(28))
                .lineSpacing(Event.titleLineSpacing)
                .foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, ProfileMetric.nameTop)

            if let line = face.line {
                Text(line)
                    .font(.apple(15))
                    .foregroundStyle(Hue.inkSecondary)
                    .padding(.top, Sizes.kindTop)
            }

            let counts = ProfileFace.counts(friends: face.friends, groups: face.groups.count, going: face.goingCount)
            if !counts.isEmpty {
                countsLine(counts)
                    .padding(.top, Sizes.membersTop)
                    .transition(.opacity)
            }

            if let bio = face.bio {
                section("About")
                Text(bio)
                    .font(.apple(15))
                    .foregroundStyle(Hue.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Sizes.sectionBodyTop)
            } else if face.addsBio {
                // Nextdoor's "Add bio", under the counts where About will be.
                Button(action: addBio) {
                    Label("Add bio", systemImage: "plus")
                        .font(.apple(15, weight: .semibold))
                        .foregroundStyle(Hue.inkSecondary)
                        .frame(minHeight: SearchMetric.tapMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .padding(.top, Sizes.sectionTop - (SearchMetric.tapMin - ProfileMetric.addBioLine) / 2)
            }

            if let going = face.going, !going.isEmpty {
                section("Going")
                ForEach(going) { event in
                    Button { openEvent(event.item) } label: { goingRow(event) }
                        .buttonStyle(PressableStyle())
                        .padding(.top, Sizes.rowTop)
                }
            }

            if !face.groups.isEmpty {
                section("Groups")
                ForEach(face.groups) { group in
                    Button { openGroup(group) } label: { groupRow(group) }
                        .buttonStyle(PressableStyle())
                        .padding(.top, Sizes.rowTop)
                }
            }
        }
        .padding(.horizontal, Event.inset)
        .padding(.bottom, Event.contentBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.smooth, value: face.shape)
        .background(Hue.paper, in: UnevenRoundedRectangle(topLeadingRadius: Event.sheetCorner,
                                                         topTrailingRadius: Event.sheetCorner, style: .continuous))
        .overlay(alignment: .topLeading) { photo }
    }

    /// The round photo over the sheet's edge. A tap opens it whole; it drags down to close.
    private var photo: some View {
        Button {
            Haptics.light()
            showingPhoto = true
        } label: {
            NeighborFace(url: face.avatarUrl, size: ProfileMetric.photo)
                .padding(ProfileMetric.ring)
                .background(Hue.paper, in: Circle())
        }
        .buttonStyle(PressableStyle())
        .disabled(face.avatarUrl == nil)
        .matchedTransitionSource(id: "photo", in: zoom)
        .offset(x: Event.inset - ProfileMetric.ring, y: -(ProfileMetric.photo / 2 + ProfileMetric.ring))
        .accessibilityLabel("\(face.name)'s photo")
        .accessibilityHint(face.avatarUrl == nil ? "" : "Opens it larger")
    }

    /// "24 friends · 4 groups · 9 going": the numbers in ink, the words grey, the Group page's members line.
    private func countsLine(_ counts: [(number: Int, word: String)]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(counts.enumerated()), id: \.offset) { index, part in
                if index > 0 {
                    Text(" · ").foregroundStyle(Hue.inkSecondary)
                }
                Text("\(part.number)").font(.apple(15, weight: .semibold)).foregroundStyle(Hue.ink).monospacedDigit()
                Text(" \(part.word)").foregroundStyle(Hue.inkSecondary)
            }
        }
        .font(.apple(15))
        .accessibilityElement(children: .combine)
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.apple(17, weight: .semibold))
            .foregroundStyle(Hue.ink)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, Sizes.sectionTop)
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
                TimelineView(.everyMinute) { Text(ProfileFace.goingLine(event, now: $0.date)) }
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
                .font(.apple(15, weight: .semibold))
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
                FeedCardURLPhoto(url: url, loadingFill: Hue.ink)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("\(name)'s photo")
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.glyph(17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: SearchMetric.tapMin, height: SearchMetric.tapMin)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Close")
            .padding(.trailing, FeedEventDetailDestination.Metric.inset - (SearchMetric.tapMin - FeedEventDetailDestination.Metric.button) / 2)
        }
    }
}

/// A neighbour's one pill at the bottom, where the Group page's Join group sits: 24 pt in, 1 pt
/// over the home bar, the page fading to paper under it from 23 pt above.
struct ProfilePillBar<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, GroupPage.Metric.pillSide)
            .padding(.bottom, GroupPage.Metric.pillBottom)
            .background {
                LinearGradient(colors: [Hue.paper.opacity(0), Hue.paper], startPoint: .top, endPoint: .bottom)
                    .padding(.top, -GroupPage.Metric.fadeAbovePill)
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)
            }
    }
}
