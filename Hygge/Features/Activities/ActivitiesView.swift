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
    @State private var trailsShowingMap = false

    private var api: CommunityAPI { CommunityAPI(auth: auth) }

    enum Filter: String, CaseIterable { case all = "All", events = "Events", clubs = "Clubs", trails = "Trails" }

    var body: some View {
        Group {
            if filter == .trails {
                if trailsShowingMap {
                    TrailsMapView(trails: trails, onBack: { trailsShowingMap = false })
                } else {
                    trailsExplore
                }
            } else {
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
            }
        }
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

    // MARK: - Trails "Explore" screen (AllTrails-style)

    private var trailsExplore: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                trailsExploreHeader
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 18)

                WobegonExploreCard(onOpenMap: { trailsShowingMap = true })
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)

                ForEach(trails) { trail in
                    TrailExploreCard(trail: trail, onOpenMap: { trailsShowingMap = true })
                        .padding(.horizontal, 18)
                        .padding(.bottom, 14)
                }

                if trails.isEmpty {
                    Text("Community-posted trails will appear here once neighbors add them.")
                        .font(.sans(14))
                        .foregroundStyle(Hue.ink3)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                }

                Color.clear.frame(height: 100)
            }
        }
        .background(Color.white)
    }

    private var trailsExploreHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { filter = .all } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Activities")
                            .font(.sansMedium(13))
                    }
                    .foregroundStyle(Hue.sky700)
                }
                .buttonStyle(.plain)

                Spacer()

                Button { trailsShowingMap = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 12, weight: .medium))
                        Text("View map")
                            .font(.sansSemibold(13))
                    }
                    .foregroundStyle(Hue.coral700)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Hue.coral.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Hue.coral.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Explore")
                    .font(.display(30))
                    .foregroundStyle(Hue.ink)
                Text("Trails near St. Joseph")
                    .font(.sans(13))
                    .foregroundStyle(Hue.ink2)
            }
        }
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

// MARK: - Explore cards (photo-forward, tap anywhere → in-app trails map)

/// Featured trail. Uses the real bundled photo; tapping opens the map.
private struct WobegonExploreCard: View {
    var onOpenMap: () -> Void

    var body: some View {
        Button(action: onOpenMap) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    PhotoView(name: "wobegon-trail")
                        .scaledToFill()
                        .frame(height: 190)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    viewMapPill().padding(12)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Lake Wobegon Trail")
                        .font(.sansBold(17))
                        .foregroundStyle(Hue.ink)
                    Text("St. Joseph, Minnesota")
                        .font(.sans(13))
                        .foregroundStyle(Hue.ink2)
                    HStack(spacing: 6) {
                        Label("Easy", systemImage: "figure.hiking")
                            .font(.mono(11))
                            .foregroundStyle(Hue.coral700)
                        exploreDot
                        Text("Paved rail-trail").font(.mono(11)).foregroundStyle(Hue.sky600)
                        exploreDot
                        Text("Bike · Run · Walk").font(.mono(11)).foregroundStyle(Hue.sky600)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Hue.paper)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Color.black.opacity(0.10), lineWidth: 1))
            .modifier(CardShadow())
        }
        .buttonStyle(.plain)
    }
}

/// Community trail. Shows a real photo only when one exists — otherwise a clean
/// blank slot (no auto-fetched stock photo, no gradient). Tapping opens the map.
private struct TrailExploreCard: View {
    let trail: Trail
    var onOpenMap: () -> Void

    // Metadata row: the lead stat (difficulty) in coral, the rest muted —
    // matching WobegonExploreCard's convention.
    @ViewBuilder
    private var metaRow: some View {
        let diff = trail.difficulty.flatMap { $0.isEmpty ? nil : $0 }
        let len = trail.length.flatMap { $0.isEmpty ? nil : $0 }
        if diff != nil || len != nil {
            HStack(spacing: 6) {
                if let diff { Text(diff).font(.mono(11)).foregroundStyle(Hue.coral700) }
                if diff != nil, len != nil { exploreDot }
                if let len { Text(len).font(.mono(11)).foregroundStyle(Hue.sky600) }
            }
        }
    }

    var body: some View {
        Button(action: onOpenMap) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    photoSlot
                        .frame(height: 160)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    viewMapPill().padding(12)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(trail.title).font(.sansBold(16)).foregroundStyle(Hue.ink)
                    if let loc = trail.location, !loc.isEmpty {
                        Text(loc).font(.sans(13)).foregroundStyle(Hue.ink2)
                    }
                    metaRow
                    if let desc = trail.description, !desc.isEmpty {
                        Text(desc).font(.sans(13)).foregroundStyle(Hue.ink2).lineLimit(2)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Hue.paper)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Color.black.opacity(0.10), lineWidth: 1))
            .modifier(CardShadow())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var photoSlot: some View {
        if let url = trail.imageUrl.flatMap(URL.init) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: blankSlot
                }
            }
        } else {
            blankSlot
        }
    }

    // Blank "add a photo here" slot — faint coral glyph on a light coral panel.
    // No auto-fetched stock photo, no gradient.
    private var blankSlot: some View {
        ZStack {
            Hue.coral.opacity(0.08)
            Image(systemName: "photo")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Hue.coral.opacity(0.4))
        }
    }
}

// MARK: - Explore card helpers

/// Decorative pill over the card photo. The whole card is the tap target,
/// so this is a label, not a button.
private func viewMapPill() -> some View {
    HStack(spacing: 5) {
        Image(systemName: "map.fill").font(.system(size: 11, weight: .semibold))
        Text("View map").font(.sansSemibold(13))
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    .background(Hue.coral700)
    .clipShape(Capsule())
    .shadow(color: Hue.coral700.opacity(0.35), radius: 5, x: 0, y: 2)
}

private var exploreDot: some View {
    Text("·").font(.mono(11)).foregroundStyle(Hue.ink3)
}
