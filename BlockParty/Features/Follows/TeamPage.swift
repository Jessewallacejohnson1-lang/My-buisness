//
//  TeamPage.swift
//  Block Party — a local school's page (BP app hello-drop 03; school-activities 02). Opened from a game
//  card's host picture. Jesse, 2026-10-25: Apple Sports' "Follow Your Favourites" in the school's own
//  colours, "keep apples fading": its first colour at the top fading down into a deep shade of it. The
//  school has the word Follow; each of its activities a star that, filled in the school's second colour,
//  slides the row up into Following, and a search narrows both. Mock:
//  https://claude.ai/artifact/5aSHdsrmdRsf13TTsAZtUU (`references/school-activities/`).
//

import SwiftUI

struct TeamPage: View {
    let team: Game.Team

    @Environment(\.dismiss) private var dismiss
    @Environment(RealLifeActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var profile: TeamProfile?
    @State private var failed = false
    @State private var query = ""
    @State private var opened: TeamProfile.Activity?
    @Namespace private var rows

    // Measured off Apple Sports' list (references/school-activities/mobbin/5-Apple_Sports.jpg, 3x):
    // 48 pt rows, a 24 pt star 24 pt in, the icon at 79 pt, the name at 110 pt in 20 pt type.
    static let side: CGFloat = 20
    static let rowHeight: CGFloat = 48
    static let star: CGFloat = 24
    static let icon: CGFloat = 26
    static let logo: CGFloat = 56
    /// How far down the page the school's colour has faded into its deep shade (the mock's 560).
    static let fade: CGFloat = 560

    var body: some View {
        let colors = schoolColors
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                search
                    .padding(.top, 22)
                if let profile {
                    list(profile.activities)
                } else if failed {
                    Text("Check your connection and try again.")
                        .font(.sans(15))
                        .foregroundStyle(Hue.nameOnDark.opacity(0.6))
                        .padding(.top, 24)
                }
            }
            .padding(.horizontal, Self.side)
            .padding(.top, 70)
            .padding(.bottom, 40)
            .background(alignment: .top) {
                LinearGradient(colors: [colors.top, colors.deep], startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.fade)
                    .padding(.top, -400) // under the overscroll too
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(colors.deep.ignoresSafeArea())
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.glyph(20, weight: .semibold))
                    .foregroundStyle(Hue.nameOnDark)
                    .frame(width: SearchMetric.tapMin, height: SearchMetric.tapMin)
                    .background(Circle().fill(Hue.nameOnDark.opacity(0.12)))
                    .overlay(Circle().strokeBorder(Hue.nameOnDark.opacity(0.28), lineWidth: 1.5))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Back")
            .padding(.leading, Self.side)
        }
        .overlay(alignment: .topTrailing) {
            if let id = team.id ?? profile?.id {
                SchoolFollow(target: FollowTarget(type: .team, id: id), name: title)
                    .padding(.trailing, Self.side)
                    .padding(.top, 4)
            }
        }
        // Light words on the school's colour. The clock stays ink, as everywhere (taste.md, 2026-09-24).
        .environment(\.colorScheme, .dark)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $opened) { ActivityEvents(activity: $0, school: title) }
        .task { await load() }
    }

    private var title: String { profile?.name ?? team.name }

    private var header: some View {
        HStack(spacing: 14) {
            LogoDisc(logo: profile?.logo.flatMap(URL.init(string:)) ?? team.logo, initial: team.initial,
                     logoSide: Self.logo * 0.72, letter: .sansSemibold(20))
                .frame(width: Self.logo, height: Self.logo)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.sansBold(20))
                    .foregroundStyle(Hue.nameOnDark)
                    .fixedSize(horizontal: false, vertical: true)
                if let nickname = team.nickname {
                    Text(nickname)
                        .font(.sans(15))
                        .foregroundStyle(Hue.nameOnDark.opacity(0.6))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Apple's search field drawn in the body, since this page has no bar to put `.searchable` in.
    private var search: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.glyph(15, weight: .medium))
                .foregroundStyle(Hue.nameOnDark.opacity(0.55))
            TextField("", text: $query, prompt: Text("Search activities").foregroundStyle(Hue.nameOnDark.opacity(0.5)))
                .font(.sans(17))
                .foregroundStyle(Hue.nameOnDark)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Hue.nameOnDark.opacity(0.55))
                }
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(Hue.nameOnDark.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func list(_ all: [TeamProfile.Activity]) -> some View {
        let shown = query.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(query) }
        let mine = shown.filter { actions.follow(target($0)).isFollowing }
        let rest = shown.filter { !actions.follow(target($0)).isFollowing }
        if !mine.isEmpty {
            heading("Following")
            ForEach(mine) { row($0) }
        }
        if !rest.isEmpty {
            heading("Follow Activities")
            ForEach(rest) { row($0) }
        }
        if shown.isEmpty {
            Text(all.isEmpty ? "No activities yet" : "No activities match")
                .font(.sans(15))
                .foregroundStyle(Hue.nameOnDark.opacity(0.55))
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
        }
    }

    private func heading(_ words: String) -> some View {
        Text(words)
            .font(.sansBold(20))
            .foregroundStyle(Hue.nameOnDark)
            .padding(.top, 26)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ activity: TeamProfile.Activity) -> some View {
        HStack(spacing: 16) {
            ActivityStar(target: target(activity), name: activity.name, fill: schoolColors.star) {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.select) {
                    actions.toggleFollow(target(activity))
                }
            }
            Image(systemName: Self.symbol(activity))
                .font(.glyph(20, weight: .regular))
                .foregroundStyle(Hue.nameOnDark)
                .frame(width: Self.icon, height: Self.icon)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(activity.name)
                    .font(.sans(20))
                    .foregroundStyle(Hue.nameOnDark)
                    .lineLimit(1)
                Text(activity.next.map(Self.when) ?? "No events yet")
                    .font(.sans(13))
                    .foregroundStyle(Hue.nameOnDark.opacity(0.5))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if activity.next != nil {
                Image(systemName: "chevron.right")
                    .font(.glyph(15, weight: .semibold))
                    .foregroundStyle(Hue.nameOnDark.opacity(0.4))
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: Self.rowHeight)
        .contentShape(Rectangle())
        .onTapGesture { if activity.next != nil { opened = activity } }
        .accessibilityAction(named: "Coming up") { if activity.next != nil { opened = activity } }
        .matchedGeometryEffect(id: activity.id, in: rows)
    }

    private func target(_ activity: TeamProfile.Activity) -> FollowTarget {
        FollowTarget(type: .activity, id: activity.id)
    }

    /// The school's first colour bright at the top fading to a deep shade of it, and its second for a
    /// starred star; a school with no colours yet is ink.
    private var schoolColors: (top: Color, deep: Color, star: Color) {
        let hexes = profile?.colors?.compactMap(Game.Team.rgb(hex:)) ?? team.colors
        let first = hexes.first.map { Color(hex: $0) } ?? Hue.poster
        let star = hexes.dropFirst().first.map { Color(hex: $0) } ?? Hue.nameOnDark
        return (first, first.mix(with: Hue.nameShadow, by: 0.45), star)
    }

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

    /// "Tue, Oct 27 · 6 PM": its day and time, as the row says it.
    static func when(_ next: TeamProfile.Activity.Next) -> String {
        [day(next.date), next.time].compactMap { $0 }.joined(separator: " · ")
    }

    /// "2026-10-31" as "Sat, Oct 31".
    static func day(_ date: String) -> String? {
        let parse = DateFormatter()
        parse.locale = Locale(identifier: "en_US_POSIX")
        parse.timeZone = Town.timeZone
        parse.dateFormat = "yyyy-MM-dd"
        guard let day = parse.date(from: date) else { return nil }
        parse.dateFormat = "EEE, MMM d"
        return parse.string(from: day)
    }

    private func load() async {
        guard let id = team.id else { return }
        do {
            profile = try await CommunityAPI(auth: AuthStore.shared).teamPage(id)
            if let profile { actions.read(activities: profile.activities) }
            failed = profile == nil
        } catch {
            failed = profile == nil
        }
    }
}

/// The school's own Follow on its colour: white, then see-through "Following" (Jesse, 2026-10-25).
/// Follow's rules otherwise: one tap each way, a refused one turns back with the shake, and an
/// account that isn't signed up gets sign-up.
private struct SchoolFollow: View {
    let target: FollowTarget
    let name: String

    @Environment(RealLifeActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tappedAt = 0
    @State private var signingIn = false

    var body: some View {
        let following = actions.follow(target).isFollowing
        let failures = actions.followFailureCount(target)
        Button {
            guard !actions.needsSignUp else { signingIn = true; return }
            tappedAt = failures
            actions.toggleFollow(target)
        } label: {
            Text(following ? "Following" : "Follow")
                .font(.sansSemibold(15))
                .foregroundStyle(following ? Hue.nameOnDark : Hue.onBrandDisc)
                .padding(.horizontal, FollowMetric.pagePad)
                .frame(minWidth: FollowMetric.pageWidth, minHeight: FollowMetric.pageHeight)
                .background(following ? Hue.nameOnDark.opacity(0.18) : Hue.nameOnDark,
                            in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                .contentShape(Rectangle().inset(by: (FollowMetric.pageHeight - SearchMetric.tapMin) / 2))
        }
        .buttonStyle(PressableStyle())
        .turnBackShake(failures: failures, shakes: !reduceMotion && tappedAt != failures)
        .animation(.easeInOut(duration: reduceMotion ? 0.15 : RealLifeActions.flip), value: following)
        .accessibilityLabel("\(following ? "Following" : "Follow"), \(name)")
        .accessibilityAddTraits(following ? .isSelected : [])
        .onAppear { actions.followOpened(target) }
        .onDisappear { actions.followClosed(target) }
        .signInSheet(isPresented: $signingIn)
    }
}

/// An activity's star: Apple Sports' circle, filled in the school's second colour once you follow it.
private struct ActivityStar: View {
    let target: FollowTarget
    let name: String
    let fill: Color
    let toggle: () -> Void

    @Environment(RealLifeActions.self) private var actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tappedAt = 0
    @State private var signingIn = false

    var body: some View {
        let following = actions.follow(target).isFollowing
        let failures = actions.followFailureCount(target)
        Button {
            guard !actions.needsSignUp else { signingIn = true; return }
            tappedAt = failures
            toggle()
        } label: {
            Image(systemName: following ? "star.fill" : "star")
                .font(.glyph(13, weight: .semibold))
                .foregroundStyle(following ? Hue.onBrandDisc : Hue.nameOnDark)
                .frame(width: TeamPage.star, height: TeamPage.star)
                .background(Circle().fill(following ? fill : Hue.nameOnDark.opacity(0.16)))
                .frame(width: SearchMetric.tapMin, height: SearchMetric.tapMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .padding(.horizontal, -(SearchMetric.tapMin - TeamPage.star) / 2)
        .turnBackShake(failures: failures, shakes: !reduceMotion && tappedAt != failures)
        .accessibilityLabel("Follow \(name)")
        .accessibilityAddTraits(following ? .isSelected : [])
        .onAppear { actions.followOpened(target) }
        .onDisappear { actions.followClosed(target) }
        .signInSheet(isPresented: $signingIn)
    }
}

/// An activity's coming events, from its row's arrow: a plain list.
private struct ActivityEvents: View {
    let activity: TeamProfile.Activity
    let school: String

    @State private var events: [TeamProfile.ActivityEvent]?

    var body: some View {
        NavigationStack {
            List {
                if let events, events.isEmpty {
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
            .overlay { if events == nil { ProgressView() } }
        }
        .presentationDetents([.medium, .large])
        .task { events = (try? await CommunityAPI(auth: AuthStore.shared).activityEvents(activity.id)) ?? [] }
    }
}
