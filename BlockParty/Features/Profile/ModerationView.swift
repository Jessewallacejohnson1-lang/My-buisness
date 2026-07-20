//
//  ModerationView.swift
//  Block Party — the admin review queue. AddModel routes anything Claude doesn't clear
//  to status=pending, and CommunityAPI already exposes getPendingPosts/getPendingClubs
//  + approve/reject — but nothing consumed them, so queued submissions were invisible
//  until someone opened a SQL client. This is that missing screen: an admin-gated
//  list with approve / not-yet actions. RLS remains the real boundary (Admin.isAdmin
//  is a product gate); see supabase/pending/status_authorization.sql for the
//  server-side enforcement that should back this.
//

import SwiftUI
import Combine

@MainActor
final class ModerationModel: ObservableObject {
    @Published var posts: [PendingPost] = []
    @Published var clubs: [ClubRow] = []
    @Published var loading = true
    @Published var failed = false
    private var acting: Set<String> = []   // in-flight guard so a double-tap can't double-patch

    func load(_ api: CommunityAPI) async {
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

    func decidePost(_ api: CommunityAPI, _ post: PendingPost, approve: Bool) async {
        guard !acting.contains(post.id) else { return }
        acting.insert(post.id); defer { acting.remove(post.id) }
        do {
            if approve { try await api.approvePost(post.id) } else { try await api.rejectPost(post.id) }
            posts.removeAll { $0.id == post.id }
        } catch { Log.network("Moderation.decidePost: \(error)") }
    }

    func decideClub(_ api: CommunityAPI, _ club: ClubRow, approve: Bool) async {
        guard !acting.contains(club.id) else { return }
        acting.insert(club.id); defer { acting.remove(club.id) }
        do {
            try await api.setClubStatus(club.id, status: approve ? .approved : .rejected)
            clubs.removeAll { $0.id == club.id }
        } catch { Log.network("Moderation.decideClub: \(error)") }
    }
}

struct ModerationView: View {
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model = ModerationModel()
    @Environment(\.dismiss) private var dismiss

    private var api: CommunityAPI { CommunityAPI(auth: auth) }
    private var pendingCount: Int { model.posts.count + model.clubs.count }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if model.loading && pendingCount == 0 {
                        ProgressView().tint(Hue.inkSecondary).frame(maxWidth: .infinity).padding(.top, 60)
                    } else if model.failed {
                        emptyState(icon: "wifi.slash", title: "Couldn't load the queue",
                                   detail: "Check your connection, then pull to refresh.")
                    } else if pendingCount == 0 {
                        emptyState(icon: "checkmark.circle", title: "All caught up",
                                   detail: "Nothing is waiting for review.")
                    } else {
                        if !model.posts.isEmpty {
                            sectionLabel("EVENTS & TRAILS")
                            ForEach(model.posts) { post in
                                reviewCard(
                                    title: post.trail.title,
                                    subtitle: line(post.eventDate, post.startTime, post.trail.location),
                                    detail: post.trail.description,
                                    onApprove: { Task { await model.decidePost(api, post, approve: true) } },
                                    onReject: { Task { await model.decidePost(api, post, approve: false) } })
                            }
                        }
                        if !model.clubs.isEmpty {
                            sectionLabel("CLUBS")
                            ForEach(model.clubs) { club in
                                reviewCard(
                                    title: club.name,
                                    subtitle: line(club.host, club.schedule, club.location),
                                    detail: club.description,
                                    onApprove: { Task { await model.decideClub(api, club, approve: true) } },
                                    onReject: { Task { await model.decideClub(api, club, approve: false) } })
                            }
                        }
                    }
                }
                .padding(18)
            }
            .background(Hue.paper)
            .navigationTitle("Review queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Hue.inkSecondary)
                }
            }
            .task { await model.load(api) }
            .refreshable { await model.load(api) }
        }
    }

    private func line(_ parts: String?...) -> String {
        parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.mono(11)).tracking(1.5).foregroundStyle(Hue.inkSecondary)
            .padding(.leading, 4).padding(.top, 4)
    }

    private func reviewCard(title: String, subtitle: String, detail: String?,
                            onApprove: @escaping () -> Void, onReject: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.sansBold(16)).foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !subtitle.isEmpty {
                Text(subtitle).font(.sans(13)).foregroundStyle(Hue.inkSecondary)
            }
            if let detail, !detail.isEmpty {
                Text(detail).font(.sans(14)).foregroundStyle(Hue.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button { Haptics.light(); onApprove() } label: {
                    Text("Approve").font(.sansSemibold(14)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Hue.ink,
                                    in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                }
                .buttonStyle(PressableStyle(scale: 0.96))
                Button { Haptics.light(); onReject() } label: {
                    Text("Not yet").font(.sansSemibold(14)).foregroundStyle(Hue.inkSecondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                            .stroke(Hue.hairline, lineWidth: 1))
                }
                .buttonStyle(PressableStyle(scale: 0.96))
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .blockPartyCard(padding: 16)
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 30, weight: .light)).foregroundStyle(Hue.inkSecondary)
            Text(title).font(.sansSemibold(16)).foregroundStyle(Hue.ink)
            Text(detail).font(.sans(14)).foregroundStyle(Hue.inkSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 60).padding(.horizontal, 24)
    }
}
