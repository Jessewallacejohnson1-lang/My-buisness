//
//  ChatRoomRow.swift
//  Block Party — a room's row on its own page (BP app five-tabs 06 and 07): the Going chat's under an Event's place, the
//  Group chat's under a Group's members. Once you're in, the chat's newest word. With no birthday yet it asks once;
//  under 18, it stays away.
//

import SwiftUI

struct ChatRoomRow: View {
    let title: String
    /// Going, or in the Group: the app's own to know, so the read can't race the tap that got you in.
    let isIn: Bool
    /// Finds it on your list. There, you're in: known before the read, so the page doesn't jump on every open.
    let listed: (ChatBook) -> Chat?
    /// The second line with nothing said yet.
    var quiet: String? = nil
    /// Under the place's row, a line between them; a Group's has none above it.
    var ruled = true
    let access: (ChatAPI) async throws -> ChatAccess
    /// Where it opens: whether you're the host is what the read and the list know.
    let route: (_ isHost: Bool) -> ChatRoute

    @Environment(ChatBook.self) private var chats: ChatBook?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var read: ChatAccess?
    @State private var asking = false
    /// Under 13 on the wheel saves nothing (onboarding's rule), so this phone remembers not to ask again.
    @AppStorage("goingChat.tooYoung") private var tooYoung = false

    private var chat: Chat? { chats.flatMap(listed) }

    private var shows: Bool {
        if let chat { return read?.state != .hidden && (chat.isHost == true || isIn) }
        guard let read, read.state != .hidden, !(read.state == .ask && tooYoung) else { return false }
        return read.isHost || isIn
    }

    private var lines: EventPage.FactLines {
        .init(first: title, second: chat.map { ChatWords.preview($0) } ?? quiet)
    }

    private var opens: ChatRoute { route(read?.isHost ?? chat?.isHost == true) }

    var body: some View {
        let m = EventPage.Metric.self
        // A stack, not a Group: a Group with nothing in it runs no `.task`, and the read is what brings the row.
        VStack(spacing: 0) {
            if shows {
                VStack(spacing: 0) {
                    if ruled {
                        Hue.hairline
                            .frame(height: m.hairline)
                            .padding(.leading, m.rowGlyph + m.rowGap)
                    }
                    FactRow(glyph: "bubble.left.and.bubble.right", glyphSize: m.chatGlyph, lines: lines, end: .opens,
                            hint: "Opens the chat", link: read?.state == .ask ? nil : opens) { asking = true }
                }
                // Fades in while the page makes room: sliding, it passed over the words above.
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : Motion.smooth, value: shows)
        // Again once you're in: a read that failed, or found the chat closed to you, gets another try.
        .task(id: isIn) {
            guard let chats else { return }
            for wait in ChatThread.joinRetries {
                if let new = try? await access(chats.api) { read = new; return }
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: wait)
            }
            if let new = try? await access(chats.api) { read = new }
        }
        .sheet(isPresented: $asking) {
            if let chats {
                ChatBirthday(chats: chats) { saved in
                    guard saved else { tooYoung = true; return }
                    Task {
                        if let new = try? await access(chats.api) { read = new }
                        if read?.state == .open { chats.push?(opens) }
                    }
                }
            }
        }
    }
}

/// "When's your birthday?", once, for an account with none: onboarding's field and wheel in a sheet.
private struct ChatBirthday: View {
    let chats: ChatBook
    /// Saved, or under 13, for whom nothing is saved.
    let done: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var date = Date.now
    @State private var turned = false
    @State private var saving = false
    @State private var failures = 0

    /// Its height: the words, field and button over the wheel (picked); the button as Onboarding's.
    private static let height: CGFloat = OnboardingBirthdayWheel.height + 280
    private static let button: CGFloat = 50

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("When's your birthday?")
                .font(.display(28))
                .foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, EventPage.Metric.inset)
            // Never says why: naming the age would tell someone under 18 which answer gets them in (Jesse, 2026-11-04).
            Text("Only you see your birthday.")
                .font(.sans(15))
                .foregroundStyle(Hue.inkSecondary)
                .padding(.top, ChatMetric.chipGap)
            OnboardingBirthdayField(date: date, now: .now)
                .padding(.top, ChatMetric.side)
            Button(action: save) {
                Text("Continue")
                    .font(.displaySemi(17))
                    .foregroundStyle(Hue.surface)
                    .frame(maxWidth: .infinity, minHeight: Self.button)
                    .background(Hue.ink.opacity(turned ? 1 : 0.3), in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.press(.squish))
            .disabled(!turned || saving)
            .turnBackShake(failures: failures, shakes: !reduceMotion)
            .padding(.top, ChatMetric.side)
            Spacer(minLength: ChatMetric.side)
        }
        .padding(.horizontal, EventPage.Metric.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OnboardingBirthdayWheel(date: $date, now: .now)
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .onChange(of: date) { turned = true }
        .presentationDetents([.height(Self.height)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Hue.surface)
    }

    private func save() {
        guard OnboardingAge.years(from: date, to: .now) >= 13 else {
            dismiss()
            done(false)
            return
        }
        saving = true
        Task {
            do {
                try await ProfileAPI(chats.api.db).setBirthday(date)
                dismiss()
                done(true)
            } catch {
                Log.network("ChatBirthday: \(error)")
                failures += 1
                Haptics.error()
            }
            saving = false
        }
    }
}
