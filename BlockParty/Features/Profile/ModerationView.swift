//
//  ModerationView.swift
//  Block Party — the admin review queue. Pending club_events and clubs wait here for
//  the admin's yes: neighbour posts the composer held back, and found events the
//  registry read from a town's own sources (ADR-021 in the registry's decision
//  records). RLS remains the real boundary (Admin.isAdmin is a product gate).
//
//  Rows follow a requests list (Reference: Yubo's friends list, references/review-queue/):
//  a date tile, the title, when and who announced it, a black Approve pill and an ×.
//  × on an event asks what was wrong, because the misread share of found events
//  decides when they may publish on their own. Decisions answer at once and a write
//  that fails puts the row back with a shake, like Join on the event page.
//

import SwiftUI
import Combine

/// Pure row formatting, kept apart so it can be tested without a view.
enum ReviewRow {
    /// "OCT" and "12" for the date tile, from a `yyyy-MM-dd` event date.
    static func tile(_ eventDate: String?) -> (month: String, day: String)? {
        let parts = (eventDate ?? "").split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        return (Calendar.current.shortMonthSymbols[parts[1] - 1].uppercased(), String(parts[2]))
    }

    /// "6 PM · City of St. Joseph": when, then who announced it (or where, for a post).
    static func subtitle(startTime: String?, allDay: Bool, sourceName: String?, location: String?) -> String {
        let when = allDay ? "All day" : startTime
        return [when, sourceName ?? location].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Only a web page opens in the in-app browser; anything else is no link at all.
    static func webURL(_ s: String?) -> URL? {
        guard let s, let url = URL(string: s), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host != nil else { return nil }
        return url
    }

    static func label(_ reason: DeclineReason) -> String {
        switch reason {
        case .notEvent: "Not an event"
        case .wrongWhen: "Wrong date or time"
        case .wrongPlace: "Wrong place"
        case .wrongTitle: "Wrong title"
        case .other: "Something else"
        }
    }
}

@MainActor
final class ModerationModel: ObservableObject {
    @Published var posts: [PendingPost] = []
    @Published var clubs: [ClubRow] = []
    @Published var loading = true
    @Published var failed = false
    /// Bumped when a decision fails and its row comes back, so that row shakes.
    @Published var rollbacks: [String: Int] = [:]
    private var acting: Set<String> = []   // in-flight guard so a double-tap can't double-patch
    private let preview: Bool

    init(preview: Bool = false) { self.preview = preview }

    func load(_ api: CommunityAPI) async {
        #if DEBUG
        if preview { posts = Self.fixtures; loading = false; return }
        #endif
        if posts.isEmpty && clubs.isEmpty { loading = true }
        do {
            async let p = api.getPendingPosts()
            async let c = api.getPendingClubs()
            posts = try await p
            clubs = try await c
            failed = false
        } catch {
            if posts.isEmpty && clubs.isEmpty { failed = true }
            Log.network("Moderation.load: \(error)")
        }
        loading = false
    }

    /// `reason` nil approves. The row leaves at once; a failed write brings it back.
    func decidePost(_ api: CommunityAPI, _ post: PendingPost, reason: DeclineReason?) async {
        guard !acting.contains(post.id), let i = posts.firstIndex(of: post) else { return }
        acting.insert(post.id); defer { acting.remove(post.id) }
        withAnimation(Self.leave) { _ = posts.remove(at: i) }
        do {
            try await write {
                if let reason { try await api.declinePost(post.id, reason: reason) }
                else { try await api.approvePost(post.id) }
            }
        } catch {
            withAnimation(Self.leave) { posts.insert(post, at: min(i, posts.count)) }
            rollback(post.id)
            Log.network("Moderation.decidePost: \(error)")
        }
    }

    func decideClub(_ api: CommunityAPI, _ club: ClubRow, approve: Bool) async {
        guard !acting.contains(club.id), let i = clubs.firstIndex(where: { $0.id == club.id }) else { return }
        acting.insert(club.id); defer { acting.remove(club.id) }
        withAnimation(Self.leave) { _ = clubs.remove(at: i) }
        do {
            try await write { try await api.setClubStatus(club.id, status: approve ? .approved : .rejected) }
        } catch {
            withAnimation(Self.leave) { clubs.insert(club, at: min(i, clubs.count)) }
            rollback(club.id)
            Log.network("Moderation.decideClub: \(error)")
        }
    }

    private func rollback(_ id: String) {
        Haptics.error()
        rollbacks[id, default: 0] += 1
    }

    private func write(_ op: () async throws -> Void) async throws {
        #if DEBUG
        if preview {
            try await Task.sleep(for: .milliseconds(400))
            if ProcessInfo.processInfo.arguments.contains("-review-queue-fail") {
                throw SupabaseError(message: "preview failure", status: 500)
            }
            return
        }
        #endif
        try await op()
    }

    /// Guessed: no Reference recording for a row leaving a requests list.
    static let leave = Animation.spring(response: 0.35, dampingFraction: 0.86)

    #if DEBUG
    /// The City's real found events from 2026-10-06 (`-review-queue-preview`).
    static let fixtures: [PendingPost] = [
        ("2026-10-06", "6 PM", false, "AED & Hands-Only CPR Training"),
        ("2026-10-10", "11 AM", false, "Empty Bowls: A Gathering of Hope"),
        ("2026-10-12", "6 PM", false, "Planning Commission"),
        ("2026-10-13", "7 PM", false, "Joint Planning Board (as needed)"),
        ("2026-10-19", "5 PM", false, "City Council Work Session"),
        ("2026-10-19", "6 PM", false, "City Council Meeting"),
        ("2026-10-20", "12 PM", false, "Economic Development Authority"),
        ("2026-10-26", "6:30 PM", false, "Park Board Meeting"),
        ("2026-11-09", nil, true, "Fare for All"),
    ].enumerated().map { i, row in
        PendingPost(trail: Trail(id: "fixture-\(i)", title: row.3, location: "St. Joseph MN 56374", length: nil,
                                 difficulty: nil, description: nil, imageUrl: nil, status: .pending, createdAt: ""),
                    kind: .event, eventDate: row.0, startTime: row.1, allDay: row.2,
                    sourceName: "City of St. Joseph",
                    sourceURL: URL(string: "https://www.stjosephmn.gov/Calendar.aspx?EID=\(2100 + i)"))
    }
    #endif
}

struct ModerationView: View {
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model: ModerationModel
    @Environment(\.dismiss) private var dismiss
    @State private var link: SafariLink?

    init(preview: Bool = false) {
        _model = StateObject(wrappedValue: ModerationModel(preview: preview))
    }

    private var api: CommunityAPI { CommunityAPI(auth: auth) }
    private var pendingCount: Int { model.posts.count + model.clubs.count }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if model.loading && pendingCount == 0 {
                        ModerationQueueSkeleton()
                    } else if model.failed {
                        emptyState(icon: "wifi.slash", title: "Couldn't load the queue",
                                   detail: "Check your connection, then pull to refresh.")
                    } else if pendingCount == 0 {
                        emptyState(icon: "checkmark.circle", title: "All caught up",
                                   detail: "Nothing is waiting for review.")
                    } else {
                        if !model.posts.isEmpty {
                            ModerationSectionLabel(text: "Events & trails")
                            ForEach(model.posts) { post in
                                ReviewQueueRow(
                                    tile: ReviewRow.tile(post.eventDate).map { .date($0.month, $0.day) }
                                        ?? .symbol(post.kind == .trail ? "figure.hiking" : "calendar"),
                                    title: post.trail.title,
                                    subtitle: ReviewRow.subtitle(startTime: post.startTime, allDay: post.allDay,
                                                                 sourceName: post.sourceName,
                                                                 location: post.trail.location),
                                    shakes: model.rollbacks[post.id, default: 0],
                                    onOpen: post.sourceURL.map { url in { link = SafariLink(url: url) } },
                                    onApprove: { Task { await model.decidePost(api, post, reason: nil) } },
                                    asksWhy: true,
                                    onDecline: { reason in Task { await model.decidePost(api, post, reason: reason) } })
                                .transition(Self.rowTransition)
                            }
                        }
                        if !model.clubs.isEmpty {
                            ModerationSectionLabel(text: "Clubs")
                            ForEach(model.clubs) { club in
                                ReviewQueueRow(
                                    tile: .symbol("person.3"),
                                    title: club.name,
                                    subtitle: [club.schedule, club.location].compactMap { $0 }
                                        .filter { !$0.isEmpty }.joined(separator: " · "),
                                    shakes: model.rollbacks[club.id, default: 0],
                                    onOpen: nil,
                                    onApprove: { Task { await model.decideClub(api, club, approve: true) } },
                                    asksWhy: false,
                                    onDecline: { _ in Task { await model.decideClub(api, club, approve: false) } })
                                .transition(Self.rowTransition)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .background(Hue.paper)
            .navigationTitle("Review queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Hue.inkSecondary)
                }
            }
            .sheet(item: $link) { SafariView(url: $0.url).ignoresSafeArea() }
            .task { await model.load(api) }
            .refreshable { await model.load(api) }
        }
    }

    private static let rowTransition = AnyTransition.asymmetric(
        insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity))

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.sansLight(30)).foregroundStyle(Hue.inkSecondary)
            Text(title).font(.sansSemibold(16)).foregroundStyle(Hue.ink)
            Text(detail).font(.sans(15)).foregroundStyle(Hue.inkSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 60).padding(.horizontal, 24)
    }
}

/// The mono section label, shared by the queue and its skeleton so they line up.
struct ModerationSectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.mono(11)).tracking(1.5).foregroundStyle(Hue.inkSecondary)
            .padding(.leading, 20).padding(.top, 14).padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One request: tile, two lines, Approve, ×. Sizes measured off Yubo's friends list
/// (row 80 pt, tile 60 pt, pill 36 pt tall; ±2 pt).
struct ReviewQueueRow: View {
    enum Tile { case date(String, String), symbol(String) }

    let tile: Tile
    let title: String
    let subtitle: String
    let shakes: Int
    let onOpen: (() -> Void)?
    let onApprove: () -> Void
    /// Events ask what was wrong (the reason is the measurement); clubs just go.
    let asksWhy: Bool
    let onDecline: (DeclineReason?) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var asking = false

    var body: some View {
        HStack(spacing: 12) {
            Button { onOpen?() } label: {
                HStack(spacing: 12) {
                    tileView
                    VStack(alignment: .leading, spacing: 2) {
                        // Two lines: the whole title is what a review checks ("Wrong title"). Picked;
                        // Yubo's names fit one line, the City's meeting names don't.
                        Text(title).font(.sansSemibold(17)).foregroundStyle(Hue.ink).lineLimit(2)
                        if !subtitle.isEmpty {
                            Text(subtitle).font(.sans(15)).foregroundStyle(Hue.inkSecondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.98))
            .disabled(onOpen == nil)
            .accessibilityElement(children: .combine)
            .accessibilityHint(onOpen == nil ? "" : "Opens where it was found")

            Button { Haptics.light(); onApprove() } label: {
                Text("Approve").font(.sansSemibold(15)).foregroundStyle(.white)
                    .padding(.horizontal, 16).frame(height: 36)
                    .background(Hue.ink, in: Capsule())
            }
            .buttonStyle(PressableStyle(scale: 0.94))

            Button { Haptics.light(); if asksWhy { asking = true } else { onDecline(nil) } } label: {
                Image(systemName: "xmark").font(.sans(15)).foregroundStyle(Hue.inkSecondary)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .accessibilityLabel("Decline")
            // On the × itself, so iOS 26 points the dialog at the row it is about.
            .confirmationDialog("What was wrong?", isPresented: $asking, titleVisibility: .visible) {
                ForEach(DeclineReason.allCases) { reason in
                    Button(ReviewRow.label(reason)) { onDecline(reason) }
                }
            }
        }
        .padding(.leading, 16).padding(.trailing, 6)
        .padding(.vertical, 10)
        .frame(minHeight: 80)
        .overlay(alignment: .top) {
            Rectangle().fill(Hue.hairline).frame(height: 1).padding(.leading, 88)
        }
        .keyframeAnimator(initialValue: CGFloat.zero, trigger: shakes) { [reduceMotion] row, x in
            row.offset(x: reduceMotion ? 0 : x)
        } keyframes: { _ in
            // Join's shake on the event page (guessed there too): out 6 pt, dying away, 0.32 s.
            KeyframeTrack {
                CubicKeyframe(6, duration: 0.06)
                CubicKeyframe(-5, duration: 0.08)
                CubicKeyframe(3, duration: 0.07)
                CubicKeyframe(-1.5, duration: 0.06)
                CubicKeyframe(0, duration: 0.05)
            }
        }
    }

    @ViewBuilder private var tileView: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Hue.fill)
            .frame(width: 60, height: 60)
            .overlay {
                switch tile {
                case let .date(month, day):
                    VStack(spacing: 0) {
                        Text(month).font(.sansSemibold(11)).tracking(0.6).foregroundStyle(Hue.inkSecondary)
                        Text(day).font(.sansBold(20)).foregroundStyle(Hue.ink).monospacedDigit()
                    }
                case let .symbol(name):
                    Image(systemName: name).font(.sans(20)).foregroundStyle(Hue.inkSecondary)
                }
            }
    }
}

/// Request rows under the real section label, at the rows' own sizes, so the queue
/// resolves without the list shifting. An emptier queue collapses to "All caught up"
/// the moment the fetch lands, which the skeleton cannot avoid and should not fake.
struct ModerationQueueSkeleton: View {
    var body: some View {
        FeedSkeletonSection(spacing: 0) {
            ModerationSectionLabel(text: "Events & trails")
        } content: {
            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { _ in row }
            }
        }
    }

    private var row: some View {
        HStack(spacing: 12) {
            SkeletonBlock(cornerRadius: 12).frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 8) {
                SkeletonLine(widthFraction: 0.8, height: 15)
                SkeletonLine(widthFraction: 0.55, height: 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SkeletonBlock(cornerRadius: 18).frame(width: 92, height: 36)
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.leading, 16).padding(.trailing, 6)
        .frame(minHeight: 80)
    }
}
