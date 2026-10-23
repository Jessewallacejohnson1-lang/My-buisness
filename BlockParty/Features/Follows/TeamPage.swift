//
//  TeamPage.swift
//  Block Party — a local team's page (BP app hello-drop 03; Jesse, 2026-10-23: "tap profile picture
//  and able to follow from there", "only have profiles for local teams"). Opened from a game card's
//  host picture. A band in the colours read from its logo, the logo, its name, Follow, and its next
//  games. The Reference is Roku's game page (`references/team-follow/`).
//

import SwiftUI

struct TeamPage: View {
    let team: Game.Team

    @Environment(\.dismiss) private var dismiss
    @State private var profile: TeamProfile?
    @State private var failed = false

    static let band: CGFloat = 170
    static let logo: CGFloat = 96
    static let side: CGFloat = 20

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                bandView
                LogoDisc(logo: team.logo, initial: team.initial, logoSide: Self.logo * 0.72, letter: .sansSemibold(20))
                    .frame(width: Self.logo, height: Self.logo)
                    .overlay(Circle().strokeBorder(Hue.paper, lineWidth: 4))
                    .shadow(color: .black.opacity(0.15), radius: 9, y: 6)
                    .padding(.top, -Self.logo / 2)
                Text(team.name)
                    .font(.sansBold(20))
                    .foregroundStyle(Hue.ink)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                if let id = team.id {
                    FollowButton(target: FollowTarget(type: .team, id: id), name: team.short)
                        .padding(.top, 16)
                }
                games
                    .padding(.top, 26)
            }
            .padding(.bottom, 40)
        }
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .topLeading) {
            // On a white disc, so it reads over any team's colours (the mock's).
            FriendsBackButton { dismiss() }
                .background(Circle().fill(.white.opacity(0.92)).frame(width: 40, height: 40))
                .padding(.leading, SearchMetric.pageBackLead)
        }
        .background(Hue.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
    }

    /// The logo's colours: the first across, the second cut in on a slant, as the mock draws them.
    private var bandView: some View {
        let colors = (profile?.colors?.compactMap(Game.Team.rgb(hex:)) ?? team.colors).map { Color(hex: $0) }
        let first = colors.first ?? Hue.ink
        let second = colors.dropFirst().first ?? first
        return LinearGradient(stops: [.init(color: first, location: 0), .init(color: first, location: 0.62),
                                      .init(color: second, location: 0.62), .init(color: second, location: 1)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
            .frame(height: Self.band)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var games: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let profile, !profile.games.isEmpty {
                Text("Next games")
                    .font(.sansSemibold(13))
                    .foregroundStyle(Hue.inkSecondary)
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ForEach(profile.games) { game in
                        row(game)
                        if game != profile.games.last { Divider().overlay(Hue.hairline) }
                    }
                }
                .background(Hue.surface, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous).strokeBorder(Hue.hairline, lineWidth: 1))
            } else if failed {
                Text("Check your connection and try again.")
                    .font(.sans(15))
                    .foregroundStyle(Hue.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Self.side)
    }

    private func row(_ game: TeamProfile.Game) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text([Self.day(game.date), game.time].compactMap { $0 }.joined(separator: " · "))
                .font(.sansSemibold(15))
                .foregroundStyle(Hue.ink)
            Text([[game.sport, "vs \(game.other)"].compactMap { $0 }.joined(separator: " "), game.location]
                    .compactMap { $0 }.joined(separator: " · "))
                .font(.sans(15))
                .foregroundStyle(Hue.inkSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    /// "2026-10-31" as "Sat, Oct 31".
    private static func day(_ date: String) -> String? {
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
            failed = false
        } catch {
            failed = profile == nil
        }
    }
}
