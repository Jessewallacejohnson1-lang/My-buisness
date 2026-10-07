//
//  FriendChatPage.swift
//  Block Party — one chat, pushed from the friends inbox. Option C of Jesse's Figma
//  (2026-10-06), Instagram's layout: the face and name in the bar, a big face at the top
//  of the history, grey bubbles for them and black ones for you (never yellow: taste.md
//  2026-10-06), and a message pill at the bottom. Text only for now: no camera, photo or
//  plus buttons until photos can be sent, and no "View profile" until other people's
//  profiles exist (Jesse, Check-in 1).
//

import SwiftUI

struct FriendChatPage: View {
    let id: String
    @Environment(FriendsModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @FocusState private var typing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            Hue.paper.ignoresSafeArea()
            if let chat = model.chat(id) {
                history(chat)
                bar(chat)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { model.markRead(id) }
    }

    // MARK: Bar

    private func bar(_ chat: FriendChat) -> some View {
        HStack(spacing: 0) {
            FriendsBackButton { dismiss() }
            FriendFace(photo: chat.photo, size: FriendsMetric.barFace)
                .padding(.trailing, FriendsMetric.barFaceGap)
            Text(chat.name)
                .font(.sansSemibold(16))
                .foregroundStyle(Hue.ink)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .padding(.leading, SearchMetric.pageBackLead)
        .frame(height: FriendsMetric.chatBar)
        .frame(maxWidth: .infinity)
        .background(Hue.paper.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Hue.hairline).frame(height: FriendsMetric.hairline)
        }
    }

    // MARK: History

    private func history(_ chat: FriendChat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    hero(chat)
                    if let first = chat.messages.first {
                        Text(FriendsModel.stamp(first.at))
                            .font(.sansMedium(12))
                            .foregroundStyle(Hue.inkSecondary)
                            .padding(.top, FriendsMetric.stampTop)
                            .padding(.bottom, FriendsMetric.stampBottom)
                    }
                    ForEach(Array(chat.messages.enumerated()), id: \.element.id) { i, message in
                        let prev = i > 0 ? chat.messages[i - 1] : nil
                        let next = i + 1 < chat.messages.count ? chat.messages[i + 1] : nil
                        Bubble(message: message, photo: chat.photo,
                               showsFace: !message.fromMe && next?.fromMe != false)
                            .padding(.top, prev == nil ? 0 : (prev?.fromMe == message.fromMe ? FriendsMetric.sameGap : FriendsMetric.turnGap))
                            .id(message.id)
                    }
                }
                .padding(.top, FriendsMetric.chatBar)
                .padding(.bottom, FriendsMetric.historyBottom)
            }
            // Opens on the newest message and stays there as messages arrive; a short chat
            // still starts at the top under the bar, as Instagram's does.
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) { composer(proxy: proxy, chat: chat) }
            .onChange(of: typing) { _, now in
                guard now, let last = chat.last?.id else { return }
                withAnimation(reduceMotion ? nil : .smooth) { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
    }

    private func hero(_ chat: FriendChat) -> some View {
        VStack(spacing: FriendsMetric.heroNameTop) {
            FriendFace(photo: chat.photo, size: FriendsMetric.hero)
            Text(chat.name)
                .font(.sansBold(20))
                .foregroundStyle(Hue.ink)
        }
        .padding(.top, FriendsMetric.heroTop)
        .frame(maxWidth: .infinity)
    }

    // MARK: Composer

    private func composer(proxy: ScrollViewProxy, chat: FriendChat) -> some View {
        let canSend = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(alignment: .bottom, spacing: 8) {
            TextField("Message", text: $draft, prompt: Text("Message…").foregroundStyle(Hue.searchFaint), axis: .vertical)
                .font(.sans(16))
                .foregroundStyle(Hue.ink)
                .lineLimit(1...5)
                .focused($typing)
                .padding(.vertical, FriendsMetric.composerTextV)
                .padding(.leading, FriendsMetric.composerTextLead)
            if canSend {
                Button { send(proxy: proxy) } label: {
                    Image(systemName: "arrow.up")
                        .font(.glyph(16, weight: .bold))
                        .foregroundStyle(Hue.paper)
                        .frame(width: FriendsMetric.send, height: FriendsMetric.send)
                        .background(Hue.ink, in: Circle())
                        .frame(width: SearchMetric.tapMin, height: SearchMetric.tapMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SquishStyle())
                .padding(.trailing, FriendsMetric.sendInset - (SearchMetric.tapMin - FriendsMetric.send) / 2)
                .accessibilityLabel("Send")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(minHeight: FriendsMetric.composer)
        .background(Hue.fill, in: RoundedRectangle(cornerRadius: FriendsMetric.composer / 2, style: .continuous))
        .padding(.horizontal, FriendsMetric.composerSide)
        .padding(.bottom, FriendsMetric.composerSide)
        .background(Hue.paper.ignoresSafeArea(edges: .bottom))
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.75), value: canSend)
    }

    private func send(proxy: ScrollViewProxy) {
        guard model.send(draft, to: id) else { return }
        draft = ""
        Haptics.light()
        if let last = model.chat(id)?.last?.id {
            withAnimation(reduceMotion ? nil : .smooth) { proxy.scrollTo(last, anchor: .bottom) }
        }
    }
}

/// One message. Theirs sit left, in grey, with their face by the last of a run; yours sit
/// right, in black with paper text.
private struct Bubble: View {
    let message: FriendMessage
    let photo: String
    let showsFace: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: FriendsMetric.bubbleFaceGap) {
            if message.fromMe {
                Spacer(minLength: 0)
            } else if showsFace {
                FriendFace(photo: photo, size: FriendsMetric.bubbleFace)
            } else {
                Color.clear.frame(width: FriendsMetric.bubbleFace, height: 1)
            }
            Text(message.text)
                .font(.sans(16))
                .foregroundStyle(message.fromMe ? Hue.paper : Hue.ink)
                .padding(.horizontal, FriendsMetric.bubbleH)
                .padding(.vertical, FriendsMetric.bubbleV)
                .background(message.fromMe ? Hue.ink : Hue.fill, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .frame(maxWidth: FriendsMetric.bubbleMax, alignment: message.fromMe ? .trailing : .leading)
            if !message.fromMe { Spacer(minLength: 0) }
        }
        .padding(.horizontal, FriendsMetric.side)
    }
}
