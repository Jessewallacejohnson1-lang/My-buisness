//
//  TeamPage.swift
//  Block Party — a local school's page (BP app hello-drop 03; school-activities 02; school-search 05).
//  Opened from a game card's host picture, a school Event's host, Profile's Following list or a
//  Notification. Jesse, 2026-10-25: Apple Sports' "Follow Your Favourites" in the school's own colours,
//  "keep apples fading". Jesse, 2026-11-11: closer to Apple Sports' league page, "compressing the top and
//  using glass", with the school's events back: glass back and Follow, a small logo and name that fold into
//  the bar as you scroll, the events card, then search and the activities in dark cards; each activity's
//  star slides its row up into Following. Mock (version 2): https://claude.ai/artifact/LeS4sSai7DLT7qTqGgTYx5
//  (`references/school-search/`).
//

import SwiftUI

/// A school's page's sizes: the picked mock's, which it read off Apple Sports' league page
/// (references/school-search/mobbin/page/p5.jpg, 3x), from the safe area's top: the bar's 44 pt glass circles 16 pt
/// in, a 28 pt logo centred 73 pt down, the name's middle 108 pt down, the first card 128 pt down, 11 pt in from the
/// screen's sides; 52 pt rows 16 pt in, 12 pt between cards. (Re-measured, Apple's own card sits 10 pt in and its
/// name is 15 pt; the mock's numbers stand until Jesse says otherwise.)
nonisolated enum SchoolMetric {
    static let side: CGFloat = 11
    static let bar: CGFloat = 44
    static let barSide: CGFloat = 16
    /// Four times the mock's 28 pt (Jesse, 2026-11-13: "make the logo larger maybe 400 percent larger").
    static let logo: CGFloat = 112
    /// The bar's foot to the logo's top.
    static let logoTop: CGFloat = 15
    /// The bar's foot to the first card: the mock's 84 pt, plus what the logo grew.
    static let top: CGFloat = 84 + 112 - 28
    static let gap: CGFloat = 12
    static let rowHeight: CGFloat = 52
    static let rowPad: CGFloat = 16
    static let star: CGFloat = 24
    static let icon: CGFloat = 24
    /// The bar's folded title stays clear of Back and of Following (16 + 111 pt).
    static let titleInset: CGFloat = 128
    /// A card's top and foot inside its corners, and the segments' inset from its sides.
    static let cardPad: CGFloat = 6
    static let segmentInset: CGFloat = 9
    static let hairline: CGFloat = 0.5
}

struct TeamPage: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RealLifeActions.self) private var actions
    @State private var model: TeamPageModel
    @State private var query = ""
    @State private var opened: TeamProfile.Activity?
    @State private var fold = SchoolFoldBox()
    @Namespace private var rows

    init(team: Game.Team) {
        _model = State(initialValue: TeamPageModel(team: team))
    }

    private var team: Game.Team { model.team }
    private var profile: TeamProfile? { model.profile }

    var body: some View {
        let colors = schoolColors
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                SchoolTop(fold: fold, logo: profile?.logo.flatMap(URL.init(string:)) ?? team.logo,
                          initial: team.initial, name: title)
                if model.failed {
                    // The page couldn't be read: one message, where the events would be.
                    Text(SchoolEvents.tryAgain)
                        .font(.sans(15))
                        .foregroundStyle(Hue.nameOnDark.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, SchoolMetric.rowPad)
                        .padding(.vertical, 24)
                        .schoolCard()
                        .transition(.opacity)
                } else {
                    SchoolEventsCard(events: model.events)
                    search
                        .padding(.top, SchoolMetric.gap)
                    if let profile {
                        lists(profile.activities)
                            .transition(.opacity)
                    } else {
                        skeleton
                            .transition(.opacity)
                    }
                }
            }
            // Each read's skeleton cross-fades into what came (design.md, Loading).
            .animation(Motion.smooth, value: profile == nil)
            .animation(Motion.smooth, value: model.failed)
            .padding(.horizontal, SchoolMetric.side)
            .padding(.top, SchoolMetric.bar)
            .padding(.bottom, 40)
            .background(alignment: .top) { fade(colors) }
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            SchoolFold.progress(geometry.contentOffset.y + geometry.contentInsets.top)
        } action: { _, progress in
            fold.progress = progress
        }
        .scrollDismissesKeyboard(.interactively)
        // Its own task: SwiftUI cancelled the refresh's task as the page it refreshed changed under it
        // (measured: every read ended "cancelled" 0.4 s in).
        .refreshable { await Task { await model.load(actions) }.value }
        .background(colors.deep.ignoresSafeArea())
        .overlay(alignment: .top) { bar(colors) }
        // Light words on the school's colour.
        .environment(\.colorScheme, .dark)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $opened) { ActivityEvents(activity: $0, api: model.api) }
        .task { await model.load(actions) }
        // The clock goes white over the school's colour, as iOS inks it over any dark page (Jesse,
        // 2026-10-25: this page only). The Town feed's hold on a black clock (`holdsClock`) is let go
        // here; the feed takes it back when it shows again.
        .onAppear { AppearanceStore.shared.holdsClock = false }
    }

    /// Rows in the list's own shape while it loads, as Apple Sports' list draws them.
    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: 12) {
                    SkeletonCircle(diameter: SchoolMetric.star)
                    SkeletonCircle(diameter: SchoolMetric.icon)
                    SkeletonLine(widthFraction: 0.6, height: 16)
                }
                .frame(height: SchoolMetric.rowHeight)
            }
        }
        .padding(.horizontal, SchoolMetric.rowPad)
        .opacity(0.25)
        .shimmering()
        .accessibilityHidden(true)
        .schoolCard()
        .padding(.top, SchoolMetric.gap)
    }

    private var title: String { profile?.name ?? team.name }

    /// The school's colour lit at the top of the screen, its own colour 160 pt down and its deep shade
    /// 560 pt down (the mock's 0, 220 and 620 from the screen's top), the light colour carrying on up
    /// under a pull.
    private func fade(_ colors: SchoolColors) -> some View {
        LinearGradient(stops: [.init(color: colors.lit, location: 340 / 960),
                               .init(color: colors.top, location: 560 / 960),
                               .init(color: colors.deep, location: 1)],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: 960)
            .padding(.top, -400)
    }

    /// Back, the folded title and Follow, in the school's tinted glass; the bar fills in behind them as the
    /// top folds away (the mock's 55% of the deep shade over a blur).
    private func bar(_ colors: SchoolColors) -> some View {
        ZStack {
            SchoolBarTitle(fold: fold, title: profile?.short ?? team.short)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.glyph(20, weight: .semibold))
                        .foregroundStyle(Hue.nameOnDark)
                        .frame(width: SchoolMetric.bar, height: SchoolMetric.bar)
                        .glassEffect(.regular.tint(colors.glass).interactive(), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Spacer()
                if let id = team.id ?? profile?.id {
                    SchoolFollow(target: FollowTarget(type: .team, id: id), name: title, tint: colors.glass)
                }
            }
            .padding(.horizontal, SchoolMetric.barSide)
        }
        .frame(height: SchoolMetric.bar)
        .background { SchoolBarGround(fold: fold, color: colors.deep).ignoresSafeArea(edges: .top) }
    }

    /// Apple's search field drawn in the body, since this page has no bar to put `.searchable` in: the
    /// mock's glass capsule.
    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.glyph(15, weight: .medium))
                .foregroundStyle(Hue.nameOnDark.opacity(0.6))
            TextField("", text: $query, prompt: Text("Search activities").foregroundStyle(Hue.nameOnDark.opacity(0.55)))
                .font(.sans(17))
                .foregroundStyle(Hue.nameOnDark)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Hue.nameOnDark.opacity(0.55))
                        .frame(width: PageMetric.tapMin, height: PageMetric.tapMin)
                        .contentShape(Rectangle())
                }
                .padding(.trailing, -10)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: SchoolMetric.bar)
        .glassEffect(.regular, in: Capsule())
    }

    @ViewBuilder
    private func lists(_ all: [TeamProfile.Activity]) -> some View {
        let shown = query.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(query) }
        let mine = shown.filter { actions.follow(target($0)).isFollowing }
        let rest = shown.filter { !actions.follow(target($0)).isFollowing }
        VStack(spacing: 0) {
            card("Following", mine)
            card("Activities", rest)
            if shown.isEmpty {
                Text(all.isEmpty ? "No activities yet" : "No activities match")
                    .font(.sans(15))
                    .foregroundStyle(Hue.nameOnDark.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .schoolCard()
                    .padding(.top, SchoolMetric.gap)
            }
        }
    }

    /// A card of rows under its heading. Both cards stay on the page, an empty one folded to nothing, so a starred
    /// row slides from one to the other as it slid under the headings before there were cards (origin/main): the
    /// row stays whole as it travels, each heading fades in or out where it sits and moves with its own rows, and
    /// a card's ground grows or folds with them.
    private func card(_ heading: String, _ activities: [TeamProfile.Activity]) -> some View {
        let empty = activities.isEmpty
        return VStack(spacing: 0) {
            if !empty {
                Text(heading)
                    .font(.displaySemi(15))
                    .foregroundStyle(Hue.nameOnDark.opacity(0.7))
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                    .accessibilityAddTraits(.isHeader)
                    .transition(.opacity)
            }
            ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                row(activity, first: index == 0)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, empty ? 0 : SchoolMetric.cardPad)
        .schoolCard(shown: !empty)
        .padding(.top, empty ? 0 : SchoolMetric.gap)
    }

    private func row(_ activity: TeamProfile.Activity, first: Bool) -> some View {
        HStack(spacing: 12) {
            ActivityStar(target: target(activity), name: activity.name, look: .disc(schoolColors.star), slides: true)
            Button { opened = activity } label: {
                HStack(spacing: 12) {
                    Image(systemName: Self.symbol(activity))
                        .font(.glyph(17, weight: .regular))
                        .foregroundStyle(Hue.nameOnDark)
                        .frame(width: SchoolMetric.icon, height: SchoolMetric.icon)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(activity.name)
                            .font(.sans(17))
                            .foregroundStyle(Hue.nameOnDark)
                            .lineLimit(1)
                        Text(Self.line(activity))
                            .font(.sans(13))
                            .foregroundStyle(Hue.nameOnDark.opacity(0.5))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if activity.next != nil {
                        Image(systemName: "chevron.right")
                            .font(.glyph(15, weight: .semibold))
                            .foregroundStyle(Hue.nameOnDark.opacity(0.35))
                            .accessibilityHidden(true)
                    }
                }
                .frame(minHeight: SchoolMetric.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.press(.squish))
            .disabled(activity.next == nil)
            .accessibilityElement(children: .combine)
            .accessibilityHint(activity.next == nil ? "" : "Shows what's coming up")
        }
        .padding(.horizontal, SchoolMetric.rowPad)
        .overlay(alignment: .top) {
            if !first { SchoolRule() }
        }
        .matchedGeometryEffect(id: activity.id, in: rows)
    }

    private func target(_ activity: TeamProfile.Activity) -> FollowTarget {
        FollowTarget(type: .activity, id: activity.id)
    }

    struct SchoolColors {
        /// The top of the screen, its colour lit a little (the mock's #2A3C7A over Kennedy's #1B2859).
        let lit: Color
        let top: Color
        let deep: Color
        let star: Color
        /// The bar's glass buttons (the mock's).
        let glass: Color
    }

    /// The school's first colour fading to a deep shade of it, and its second for a starred star; a school
    /// with no colours yet is ink.
    private var schoolColors: SchoolColors {
        let hexes = Self.darkFirst(profile?.colors?.compactMap(Game.Team.rgb(hex:)) ?? team.colors)
        let top = hexes.first.map { Color(hex: $0) } ?? Hue.poster
        let star = hexes.dropFirst().first.map { Color(hex: $0) } ?? Hue.nameOnDark
        // The mock's top (#2A3C7A) and glass tint (#465FB4) are Kennedy's #1B2859 brightened about 1.45 and
        // 2 times; the tint at 60% shows through Liquid Glass about as the mock's 45% did through its blur.
        let lit = hexes.first.map { Color(hex: Self.brighter($0, by: 1.45)) } ?? top
        let glass = hexes.first.map { Color(hex: Self.brighter($0, by: 2)) } ?? Hue.nameOnDark
        return SchoolColors(lit: lit, top: top, deep: top.mix(with: Hue.nameShadow, by: 0.62), star: star,
                            glass: glass.opacity(0.6))
    }

    /// A school's colours with a dark one leading: a light first colour (Cathedral's gold) fades to olive, so its
    /// darkest colour leads instead and the light one comes second, filling the star (Jesse, 2026-10-25).
    static func darkFirst(_ hexes: [UInt32]) -> [UInt32] {
        guard let first = hexes.first, light(first), let darkest = hexes.min(by: { luma($0) < luma($1) }),
              !light(darkest) else { return hexes }
        return [darkest, first]
    }

    /// A 0xRRGGBB colour with each channel multiplied by `factor`, up to full.
    static func brighter(_ rgb: UInt32, by factor: Double) -> UInt32 {
        [16, 8, 0].reduce(0) { sum, shift in
            sum | UInt32(min(255, (Double(rgb >> shift & 0xFF) * factor).rounded())) << shift
        }
    }

    /// How light a 0xRRGGBB colour reads, 0 to 1 (Rec. 601 weights).
    static func luma(_ rgb: UInt32) -> Double {
        (0.299 * Double(rgb >> 16 & 0xFF) + 0.587 * Double(rgb >> 8 & 0xFF) + 0.114 * Double(rgb & 0xFF)) / 255
    }

    /// Too light for white words to sit on.
    static func light(_ rgb: UInt32) -> Bool { luma(rgb) > 0.6 }

    /// An SF Symbol for what it is, from its name; a sport with none gets the generic one.
    static func symbol(_ activity: TeamProfile.Activity) -> String {
        let name = activity.name.lowercased()
        let byWord: [(String, String)] = [
            ("basketball", "basketball"), ("volleyball", "volleyball"), ("soccer", "soccerball"),
            ("football", "football"), ("baseball", "baseball"), ("softball", "baseball"), ("hockey", "hockey.puck"),
            ("tennis", "tennisball"), ("golf", "figure.golf"), ("swim", "figure.pool.swim"),
            ("cross country", "figure.run"), ("track", "figure.run"), ("ski", "figure.skiing.crosscountry"),
            ("wrestl", "figure.wrestling"), ("gymnast", "figure.gymnastics"), ("lacrosse", "figure.lacrosse"),
            ("dance", "figure.dance"), ("bowling", "figure.bowling"), ("trap", "scope"), ("clay", "scope"),
            ("band", "music.note"), ("orchestra", "music.note"), ("choir", "music.mic"), ("music", "music.note"),
            ("theat", "theatermasks"), ("drama", "theatermasks"), ("play", "theatermasks"), ("musical", "theatermasks"),
            ("robot", "gearshape.2"), ("math", "function"), ("knowledge", "brain.head.profile"),
            ("speech", "text.bubble"), ("debate", "text.bubble"), ("art", "paintpalette"), ("chess", "checkerboard.rectangle"),
        ]
        if let hit = byWord.first(where: { name.contains($0.0) }) { return hit.1 }
        switch activity.kind {
        case "sport": return "sportscourt"
        case "arts": return "paintpalette"
        default: return "person.3"
        }
    }

    /// A row's grey line: its next Event's day and time; else when it meets, "Fridays · 8 AM" (nothing-scheduled 03,
    /// Apple Sports' "Off Season" line); else "No events yet". Only an Event opens the row.
    static func line(_ activity: TeamProfile.Activity) -> String {
        activity.next.map(when) ?? activity.meets?.lazy.compactMap(\.words).first ?? "No events yet"
    }

    /// "Tue, Oct 27 · 6 PM": its day and time, as the row says it.
    static func when(_ next: TeamProfile.Activity.Next) -> String {
        [day(next.date), next.time].compactMap { $0 }.joined(separator: " · ")
    }

    /// "2026-10-31" as "Sat, Oct 31".
    static func day(_ date: String) -> String? {
        guard let townDay = DateHelpers.townDay(date) else { return nil }
        return day(townDay)
    }

    /// A Town day as "Sat, Oct 31".
    static func day(_ date: Date) -> String { dayFormatter.string(from: date) }

    /// Display only (text on screen), built once: "Sat, Oct 31" on the Town's clock.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = Town.timeZone
        f.dateFormat = "EEE, MMM d"
        return f
    }()
}

/// The school's small logo over its name, folding toward its foot and fading as the page scrolls under the
/// bar (Apple Sports' league page). Its own view, so only it and the bar's title redraw as the scroll moves.
private struct SchoolTop: View {
    let fold: SchoolFoldBox
    let logo: URL?
    let initial: String
    let name: String

    var body: some View {
        let progress = fold.progress
        VStack(spacing: 9) {
            LogoDisc(logo: logo, initial: initial, logoSide: SchoolMetric.logo, letter: .sansSemibold(60), fits: true, disc: false)
                .frame(width: SchoolMetric.logo, height: SchoolMetric.logo)
            Text(name)
                .font(.displaySemi(17))
                .foregroundStyle(Hue.nameOnDark)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.top, SchoolMetric.logoTop)
        .frame(maxWidth: .infinity)
        .frame(height: SchoolMetric.top, alignment: .top)
        .scaleEffect(SchoolFold.topScale(progress), anchor: .bottom)
        .opacity(1 - progress)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The school's short name in the bar once the top has folded into it.
private struct SchoolBarTitle: View {
    let fold: SchoolFoldBox
    let title: String

    var body: some View {
        let shown = SchoolFold.titleOpacity(fold.progress)
        Text(title)
            .font(.displaySemi(17))
            .foregroundStyle(Hue.nameOnDark)
            .lineLimit(1)
            .padding(.horizontal, SchoolMetric.titleInset)
            .opacity(shown)
            .offset(y: 8 * (1 - shown))
            .accessibilityHidden(true)
    }
}

/// Behind the bar: nothing at rest, the deep shade over a blur once the top has folded.
private struct SchoolBarGround: View {
    let fold: SchoolFoldBox
    let color: Color

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(color.opacity(0.55))
            .opacity(fold.progress)
    }
}

/// The school's own Follow in the bar: the word in the school's tinted glass, white once you follow
/// (the mock, Jesse 2026-11-11). Follow's rules otherwise: one tap each way, a refused one turns back
/// with the shake, and an account that isn't signed up gets sign-up.
private struct SchoolFollow: View {
    let target: FollowTarget
    let name: String
    let tint: Color

    @Environment(RealLifeActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tappedAt = 0

    var body: some View {
        let following = actions.follow(target).isFollowing
        let failures = actions.followFailureCount(target)
        Button {
            tappedAt = failures
            actions.toggleFollow(target)
        } label: {
            Text(following ? "Following" : "Follow")
                .font(.displaySemi(16))
                .foregroundStyle(following ? Hue.onBrandDisc : Hue.nameOnDark)
                .padding(.horizontal, FollowMetric.glassPad)
                .frame(height: SchoolMetric.bar)
                .glassEffect((following ? Glass.regular.tint(Hue.nameOnDark) : .regular.tint(tint)).interactive(),
                             in: Capsule())
        }
        .buttonStyle(.plain)
        .turnBackShake(failures: failures, shakes: !reduceMotion && tappedAt != failures)
        .animation(.easeInOut(duration: reduceMotion ? 0.15 : RealLifeActions.flip), value: following)
        .accessibilityLabel("\(following ? "Following" : "Follow"), \(name)")
        .accessibilityAddTraits(following ? .isSelected : [])
        .onAppear { actions.followOpened(target) }
        .onDisappear { actions.followClosed(target) }
    }
}

/// An activity's star, on its school's page and in Search's typed results (school-search 01): one tap follows or
/// unfollows the activity, a refused one turns back with the shake, and with no account it does nothing.
struct ActivityStar: View {
    enum Look {
        /// Apple Sports' circle on the school's page, filled in this colour once you follow it.
        case disc(Color)
        /// Bare on Search's page as the mock drew it, this colour once you follow it.
        case bare(Color)
    }

    let target: FollowTarget
    let name: String
    let look: Look
    /// On the school's page the tap slides the row into Following.
    var slides = false

    @Environment(RealLifeActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tappedAt = 0

    var body: some View {
        let following = actions.follow(target).isFollowing
        let failures = actions.followFailureCount(target)
        Button {
            tappedAt = failures
            withAnimation(slides ? (reduceMotion ? .easeInOut(duration: 0.15) : Motion.select) : nil) {
                actions.toggleFollow(target)
            }
        } label: {
            glyph(following)
                .frame(width: PageMetric.tapMin, height: box.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.press(.squish))
        .padding(.horizontal, -(PageMetric.tapMin - box.width) / 2)
        .turnBackShake(failures: failures, shakes: !reduceMotion && tappedAt != failures)
        .accessibilityLabel("Follow \(name)")
        .accessibilityAddTraits(following ? .isSelected : [])
        .onAppear { actions.followOpened(target) }
        .onDisappear { actions.followClosed(target) }
    }

    /// The star's room in its row, and the tap's height.
    private var box: CGSize {
        switch look {
        case .disc: CGSize(width: SchoolMetric.star, height: PageMetric.tapMin)
        case .bare: CGSize(width: SearchMetric.star, height: SearchMetric.row)
        }
    }

    @ViewBuilder
    private func glyph(_ following: Bool) -> some View {
        let symbol = following ? "star.fill" : "star"
        switch look {
        case .disc(let fill):
            Image(systemName: symbol)
                .font(.glyph(13, weight: .semibold))
                .foregroundStyle(following ? Hue.onBrandDisc : Hue.nameOnDark)
                .frame(width: SchoolMetric.star, height: SchoolMetric.star)
                .background(Circle().fill(following ? fill : Hue.nameOnDark.opacity(0.16)))
        case .bare(let fill):
            Image(systemName: symbol)
                .font(.glyph(SearchMetric.starGlyph, weight: .regular))
                .foregroundStyle(following ? fill : Hue.searchFaint)
                // Swapped at once: an animated swap cross-fades through a grey blob (swift-traps).
                .transaction { $0.animation = nil }
        }
    }

    /// The bare star's colour on Search's paper: the school page's star colour (`TeamPage.darkFirst`'s second),
    /// unless that is too light for paper too, then its leading dark colour; nil with none, for ink.
    static func onPaper(_ colors: [UInt32]) -> UInt32? {
        let hexes = TeamPage.darkFirst(colors)
        return [hexes.dropFirst().first, hexes.first].compactMap { $0 }.first { !TeamPage.light($0) }
    }
}

/// An activity's coming events, from its row's arrow: a plain list.
private struct ActivityEvents: View {
    let activity: TeamProfile.Activity
    let api: CommunityAPI

    @State private var events: [TeamProfile.ActivityEvent]?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            List {
                if failed {
                    Text("Check your connection and try again.").foregroundStyle(Hue.inkSecondary)
                } else if let events, events.isEmpty {
                    Text("No events yet").foregroundStyle(Hue.inkSecondary)
                }
                ForEach(events ?? []) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text([TeamPage.day(event.date), event.time].compactMap { $0 }.joined(separator: " · "))
                            .font(.sansSemibold(15))
                        Text([event.title, event.location].compactMap { $0 }.joined(separator: " · "))
                            .font(.sans(15))
                            .foregroundStyle(Hue.inkSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .navigationTitle(activity.name)
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if events == nil && !failed {
                    VStack(spacing: 16) { ForEach(0..<3, id: \.self) { _ in SkeletonLine(height: 16) } }
                        .padding(24)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .shimmering()
                        .accessibilityHidden(true)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            do { events = try await api.activityEvents(activity.id) } catch { failed = true }
        }
    }
}
