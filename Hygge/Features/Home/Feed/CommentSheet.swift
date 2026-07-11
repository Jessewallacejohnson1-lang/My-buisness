//
//  CommentSheet.swift
//  Hygge — flat comments ("notes") on a feed posting (club_events row). One
//  level only, no threading (spec §3 — "No threaded/nested comments"). A clean
//  opaque sheet (glass is reserved for the community Profile — see ProfileView's
//  header comment); this one reads calmer on paper, matching EditProfileView /
//  AddFormView's input styling.
//
//  Backed by SocialAPI.comments / addComment / deleteComment (SocialAPI.swift).
//  `addComment` already routes through the Moderation edge function server-side,
//  so a rejected note surfaces its real reason here rather than a fake success.
//
//  Note: the `event_comments` migration (docs/superpowers/plans/
//  2026-07-11-today-tab-remake.md Task 0) hasn't been merged to prod yet, so a
//  live run of this sheet will fail its network calls — that's expected until
//  Task 0/10 land; this file targets a clean, correct build against the already
//  landed `SocialAPI` + `EventComment` shapes.
//

import SwiftUI

struct CommentSheet: View {
    let eventId: String
    let eventTitle: String

    @EnvironmentObject var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var comments: [EventComment] = []
    @State private var loading = false
    @State private var loadError: String?

    @State private var draft = ""
    @State private var sending = false
    @State private var sendError: String?

    @FocusState private var composerFocused: Bool

    init(eventId: String, eventTitle: String) {
        self.eventId = eventId
        self.eventTitle = eventTitle
    }

    private var api: SocialAPI { SocialAPI(auth: auth) }

    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var draftTooLong: Bool { trimmedDraft.count > 500 }
    private var canSend: Bool { !trimmedDraft.isEmpty && !draftTooLong && !sending }

    var body: some View {
        VStack(spacing: 0) {
            header
            commentList
            composer
        }
        .background(Hue.canvas.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await load() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Comments").font(.sansSemibold(13)).foregroundStyle(Hue.ink3)
                Text(eventTitle).font(.display(18)).foregroundStyle(Hue.ink).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { Haptics.light(); dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Hue.ink)
                    .frame(width: 32, height: 32)
                    .background(Hue.paper200, in: Circle())
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    // MARK: - List

    @ViewBuilder
    private var commentList: some View {
        if loading && comments.isEmpty {
            Spacer(minLength: 0)
            ProgressView().tint(Hue.accent)
            Spacer(minLength: 0)
        } else if let loadError, comments.isEmpty {
            Spacer(minLength: 0)
            errorState(loadError)
            Spacer(minLength: 0)
        } else if comments.isEmpty {
            Spacer(minLength: 0)
            emptyState
            Spacer(minLength: 0)
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(comments.enumerated()), id: \.element.id) { index, comment in
                        commentRow(comment)
                        if index < comments.count - 1 {
                            Rectangle().fill(Hue.hairline).frame(height: 1)
                                .padding(.leading, 57)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Hue.ink3.opacity(0.5))
            Text("Be the first to leave a note")
                .font(.sansMedium(15))
                .foregroundStyle(Hue.ink2)
            Text("A tip, a question, or just \"see you there\" — neighbors will see it here.")
                .font(.sans(13))
                .foregroundStyle(Hue.ink3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Hue.clay700)
            Text(message)
                .font(.sans(14))
                .foregroundStyle(Hue.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Haptics.light()
                Task { await load() }
            } label: {
                Text("Try again").font(.sansSemibold(14)).foregroundStyle(Hue.accent)
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }

    private func commentRow(_ comment: EventComment) -> some View {
        HStack(alignment: .top, spacing: 11) {
            avatar(for: comment)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(comment.authorName).font(.sansSemibold(14)).foregroundStyle(Hue.ink).lineLimit(1)
                    Text(relativeTime(comment.createdAt))
                        .font(.mono(12)).foregroundStyle(Hue.ink3)
                    Spacer(minLength: 6)
                    if comment.authorId == auth.userId {
                        Button {
                            Haptics.light()
                            Task { await delete(comment) }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Hue.ink3)
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                Text(comment.body)
                    .font(.sans(15))
                    .foregroundStyle(Hue.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 13)
    }

    private func avatar(for comment: EventComment) -> some View {
        Group {
            if let urlString = comment.authorAvatar, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: initialsAvatar(comment.authorName)
                    }
                }
            } else {
                initialsAvatar(comment.authorName)
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(Circle())
        .overlay(Circle().stroke(Hue.hairline, lineWidth: 1))
    }

    private func initialsAvatar(_ name: String) -> some View {
        ZStack {
            Hue.accentSoft
            Text(initials(for: name))
                .font(.sansSemibold(13))
                .foregroundStyle(Hue.accent)
        }
    }

    private func initials(for name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(Hue.hairline).frame(height: 1)

            if let sendError {
                Text(sendError)
                    .font(.sans(13))
                    .foregroundStyle(Hue.clay700)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .transition(.opacity)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Leave a note…", text: $draft, axis: .vertical)
                    .font(.sans(15))
                    .foregroundStyle(Hue.ink)
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Hue.paper)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                    .hyggeHairline(radius: Radius.lg)

                sendButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            HStack {
                Spacer()
                Text("\(trimmedDraft.count)/500")
                    .font(.mono(11)).monospacedDigit()
                    .foregroundStyle(draftTooLong ? Hue.clay700 : Hue.ink3)
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 10)
        .background(Hue.canvas)
    }

    private var sendButton: some View {
        Button {
            Haptics.light()
            Task { await send() }
        } label: {
            Group {
                if sending {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 40, height: 40)
            .background(canSend ? Hue.accent : Hue.ink3.opacity(0.35), in: Circle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!canSend)
    }

    // MARK: - Actions

    private func load() async {
        guard !loading else { return }
        loading = true
        loadError = nil
        do {
            comments = try await api.comments(eventId: eventId)
        } catch {
            loadError = (error as? SupabaseError)?.message ?? error.localizedDescription
        }
        loading = false
    }

    private func send() async {
        let body = trimmedDraft
        guard !body.isEmpty, body.count <= 500, !sending else { return }
        sending = true
        withAnimation(.easeOut(duration: 0.15)) { sendError = nil }
        do {
            let comment = try await api.addComment(eventId: eventId, body: body)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                comments.append(comment)
            }
            draft = ""
            composerFocused = false
            Haptics.success()
        } catch {
            let message = (error as? SupabaseError)?.message ?? error.localizedDescription
            withAnimation(.easeOut(duration: 0.15)) { sendError = message }
            Haptics.error()
        }
        sending = false
    }

    private func delete(_ comment: EventComment) async {
        let previous = comments
        withAnimation(.easeOut(duration: 0.2)) { comments.removeAll { $0.id == comment.id } }
        do {
            try await api.deleteComment(comment.id)
        } catch {
            // Roll back — the delete failed server-side; don't fake success.
            let message = (error as? SupabaseError)?.message ?? error.localizedDescription
            withAnimation { comments = previous }
            sendError = message
            Haptics.error()
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
