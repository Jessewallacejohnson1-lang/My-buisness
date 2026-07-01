//
//  ActivitiesView.swift
//  Hygge — browse real clubs, events, and trails. Search + filter, join/leave.
//

import SwiftUI

struct ActivitiesView: View {
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model = ActivitiesModel()

    @State private var filter: Filter = .all
    @State private var query = ""

    private var api: CommunityAPI { CommunityAPI(auth: auth) }

    enum Filter: String, CaseIterable { case all = "All", events = "Events", clubs = "Clubs", trails = "Trails" }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Activities")
                    .font(.display(30))
                    .foregroundStyle(Hue.ink)
                    .padding(.top, 8)

                searchField
                filterPills

                if model.loading && !model.loaded {
                    ProgressView().tint(Hue.ink3).frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    suggestedSection
                    content
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 18)
        }
        .background(Hue.canvas)
        .refreshable { await model.load(api) }
        .task { await model.load(api) }
    }

    // MARK: - Filtered data

    private var showEvents: Bool { filter == .all || filter == .events }
    private var showClubs: Bool { filter == .all || filter == .clubs }
    private var showTrails: Bool { filter == .all || filter == .trails }

    private func matches(_ haystack: String...) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return true }
        return haystack.contains { $0.lowercased().contains(q) }
    }

    private var events: [UpcomingEvent] {
        showEvents ? model.events.filter { matches($0.title, $0.location ?? "") } : []
    }
    private var clubs: [ClubView] {
        showClubs ? model.clubs.filter { matches($0.name, $0.host ?? "", $0.vibe ?? "", $0.schedule ?? "", $0.location ?? "") } : []
    }
    private var trails: [Trail] {
        showTrails ? model.trails.filter { matches($0.title, $0.location ?? "", $0.description ?? "") } : []
    }

    // MARK: - Suggested for you (interest-matched)

    private var interestIds: [String] { Interests.get() }

    private var suggestedClubs: [ClubView] {
        guard !interestIds.isEmpty else { return [] }
        return model.clubs.filter { Interests.matches("\($0.name) \($0.vibe ?? "") \($0.schedule ?? "") \($0.host ?? "")", interestIds) }
    }
    private var suggestedTrails: [Trail] {
        guard !interestIds.isEmpty else { return [] }
        return model.trails.filter { Interests.matches("\($0.title) \($0.description ?? "") \($0.location ?? "")", interestIds, isTrail: true) }
    }

    @ViewBuilder
    private var suggestedSection: some View {
        let show = filter == .all
            && query.trimmingCharacters(in: .whitespaces).isEmpty
            && (!suggestedClubs.isEmpty || !suggestedTrails.isEmpty)
        if show {
            VStack(alignment: .leading, spacing: 12) {
                Text("Suggested for you")
                    .font(.displaySemi(20))
                    .foregroundStyle(Hue.ink)
                ForEach(suggestedClubs) { club in
                    ClubCard(club: club) { Task { await model.toggleJoin(api, club) } }
                }
                ForEach(suggestedTrails) { TrailCard(trail: $0) }
                Rectangle().fill(Hue.hairline).frame(height: 1).padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let isEmpty = events.isEmpty && clubs.isEmpty && trails.isEmpty
        if isEmpty {
            emptyState
        } else {
            VStack(spacing: 12) {
                ForEach(events) { EventBrowseCard(event: $0) }
                ForEach(clubs) { club in
                    ClubCard(club: club) { Task { await model.toggleJoin(api, club) } }
                }
                ForEach(trails) { TrailCard(trail: $0) }
            }
        }
    }

    // MARK: - Pieces

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Hue.ink3)
            TextField("Search clubs, events, trails", text: $query)
                .font(.sans(14))
                .foregroundStyle(Hue.ink)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Hue.ink3)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Hue.paper)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .hyggeHairline()
    }

    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Filter.allCases, id: \.self) { f in
                    let on = f == filter
                    Button { filter = f } label: {
                        Text(f.rawValue)
                            .font(.sansSemibold(13))
                            .foregroundStyle(on ? Hue.paper : Hue.ink)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(on ? Hue.ink : Hue.paper)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Hue.hairline, lineWidth: on ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Hue.ink3)
            Text(query.isEmpty ? "Nothing here yet" : "No matches")
                .font(.sansSemibold(15))
                .foregroundStyle(Hue.ink)
            Text(query.isEmpty
                 ? "Real clubs, events, and trails show up here once neighbors post them."
                 : "Try a different search.")
                .font(.sans(13))
                .foregroundStyle(Hue.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36).padding(.horizontal, 20)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(Hue.hairline)
        )
        .padding(.top, 12)
    }
}

// MARK: - Cards

private struct EventBrowseCard: View {
    let event: UpcomingEvent
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(DateHelpers.prettyDate(event.eventDate))\(event.startTime.map { " · \($0)" } ?? "")")
                .font(.mono(12)).monospacedDigit()
                .foregroundStyle(Hue.sky600)
            Text(event.title).font(.sansBold(16)).foregroundStyle(Hue.ink)
            if let loc = event.location, !loc.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse").font(.system(size: 11))
                    Text(loc).font(.sans(13))
                }.foregroundStyle(Hue.ink2)
            }
            HStack {
                if event.goingCount > 0 {
                    Text("\(event.goingCount) going").font(.mono(11)).monospacedDigit().foregroundStyle(Hue.ink3)
                }
                Spacer()
                InviteButton(title: event.title,
                             dateLabel: DateHelpers.prettyDate(event.eventDate),
                             time: event.startTime, location: event.location)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hyggeCard(padding: 16)
    }
}

private struct ClubCard: View {
    let club: ClubView
    var onToggleJoin: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(club.name).font(.sansBold(16)).foregroundStyle(Hue.ink)
                if let host = club.host, !host.isEmpty {
                    Text("with \(host)").font(.sans(13)).foregroundStyle(Hue.ink2)
                }
                if let schedule = club.schedule, !schedule.isEmpty {
                    Text(schedule).font(.mono(12)).foregroundStyle(Hue.sky600)
                }
                if let vibe = club.vibe, !vibe.isEmpty {
                    Text(vibe).font(.sans(13)).foregroundStyle(Hue.ink2).italic()
                }
                if club.memberCount > 0 {
                    Text("\(club.memberCount) member\(club.memberCount == 1 ? "" : "s")")
                        .font(.mono(11)).monospacedDigit().foregroundStyle(Hue.ink3)
                }
            }
            Spacer(minLength: 8)
            Button(action: onToggleJoin) {
                Text(club.joined ? "Joined" : "Join")
                    .font(.sansSemibold(13))
                    .foregroundStyle(club.joined ? Hue.paper : Hue.moss700)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(club.joined ? Hue.moss700 : Hue.paper)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(club.joined ? Color.clear : Hue.moss700.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hyggeCard(padding: 16)
    }
}

private struct TrailCard: View {
    let trail: Trail
    private var meta: String {
        [trail.location, trail.length, trail.difficulty].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(trail.title).font(.sansBold(16)).foregroundStyle(Hue.ink)
            if !meta.isEmpty {
                Text(meta).font(.mono(12)).foregroundStyle(Hue.sky600)
            }
            if let desc = trail.description, !desc.isEmpty {
                Text(desc).font(.sans(13)).foregroundStyle(Hue.ink2).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hyggeCard(padding: 16)
    }
}
