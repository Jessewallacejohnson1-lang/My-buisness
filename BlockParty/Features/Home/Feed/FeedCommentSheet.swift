//
//  FeedCommentSheet.swift
//  Block Party — backend-loaded flat comments with optimistic sending.
//

import SwiftUI

struct FeedCommentSheet: View {
    @Binding var commentState: FeedCommentState
    let onLoad: (() async throws -> [EventComment])?
    let onSend: ((String) async throws -> EventComment)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft = ""
    @State private var isLoading = false
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Hue.hairline).frame(height: 1)
            commentList
            Rectangle().fill(Hue.hairline).frame(height: 1)
            composer
        }
        .background(Hue.surface)
        .presentationDetents([.medium])
        .presentationCornerRadius(24)
        .presentationDragIndicator(.visible)
        .task { await loadComments() }
    }

    private var header: some View {
        HStack {
            Text("Comments")
                .font(.sansSemibold(17))
                .foregroundStyle(Hue.ink)

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Hue.ink)
                    .frame(width: 44, height: 44)
                    .background(Hue.fill, in: buttonShape)
                    .contentShape(buttonShape)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close comments")
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .frame(height: 56)
    }

    private var commentList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if isLoading && commentState.comments.isEmpty {
                        loadingState
                    } else if commentState.comments.isEmpty {
                        emptyState
                    } else {
                        ForEach(commentState.comments) { comment in
                            commentRow(comment)
                                .id(comment.id)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
            }
            .onChange(of: commentState.comments.count) { _, _ in
                guard let newest = commentState.comments.last else { return }
                if reduceMotion {
                    proxy.scrollTo(newest.id, anchor: .bottom)
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(newest.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var loadingState: some View {
        HStack(spacing: 10) {
            if reduceMotion {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Hue.ink)
                    .frame(width: 12, height: 12)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(Hue.ink)
            }
            Text("Loading comments")
                .font(.sans(15))
                .foregroundStyle(Hue.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }

    private var emptyState: some View {
        Text("No comments yet. Leave the first note.")
            .font(.sans(15))
            .foregroundStyle(Hue.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 24)
    }

    private func commentRow(_ comment: EventComment) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(comment.authorName)
                    .font(.sansSemibold(13))
                    .foregroundStyle(Hue.ink)

                Text(comment.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.mono(11))
                    .monospacedDigit()
                    .foregroundStyle(Hue.inkSecondary)
            }

            Text(comment.body)
                .font(.sans(15))
                .foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.sans(12))
                    .foregroundStyle(Hue.inkSecondary)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Add a comment", text: $draft, axis: .vertical)
                    .font(.sans(15))
                    .foregroundStyle(Hue.ink)
                    .lineLimit(1...3)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Hue.fill, in: buttonShape)
                    .disabled(isLoading || isSending)

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            canSend ? Hue.ink : Hue.ink.opacity(0.35),
                            in: buttonShape
                        )
                        .contentShape(buttonShape)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send comment")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Hue.surface)
    }

    private var canSend: Bool {
        !isLoading && !isSending
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var buttonShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
    }

    private func send() {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let local = commentState.appendLocal(body: body) else { return }
        draft = ""
        errorMessage = nil
        guard let onSend else { return }

        isSending = true
        Task { @MainActor in
            do {
                let posted = try await onSend(body)
                commentState.replace(local.id, with: posted)
            } catch {
                commentState.remove(local.id)
                draft = body
                errorMessage = "Couldn't post that comment. Try again."
                Log.network("FeedCommentSheet.send: \(error)")
            }
            isSending = false
        }
    }

    private func loadComments() async {
        guard let onLoad else { return }
        isLoading = true
        errorMessage = nil
        do {
            commentState.replaceAll(with: try await onLoad())
        } catch {
            errorMessage = "Couldn't load comments. Pull the sheet down and try again."
            Log.network("FeedCommentSheet.load: \(error)")
        }
        isLoading = false
    }
}
