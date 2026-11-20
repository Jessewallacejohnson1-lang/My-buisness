//
//  ShareSheet.swift
//  Block Party — the share sheet (BP app share-sheet 01): Hypelist's, on Apple's own sheet.
//
//  Measured off Hypelist's (BP app `references/share-sheet/SPEC.md`): the sheet's top 88 pt down the screen, "Share",
//  the story card in two looks you swipe between, the second at 85% off to the side; then the people an Event goes to,
//  a line, and the apps. Jesse picked each at Check-in 1 (mock https://claude.ai/artifact/C367X4f1gs9PMKJ5SniSLW).
//

import SwiftUI
import UIKit

/// The share window's root: nothing of its own, only Apple's sheet over the app.
struct ShareHost: View {
    @ObservedObject private var center = ShareCenter.shared

    var body: some View {
        Color.clear
            .ignoresSafeArea()
            .sheet(isPresented: $center.showing, onDismiss: center.sheetGone) {
                if let payload = center.payload {
                    ShareSheet(payload: payload, height: center.sheetHeight)
                        .environment(center.you)
                }
            }
    }
}

struct ShareSheet: View {
    let payload: SharePayload
    let height: CGFloat

    @ObservedObject private var center = ShareCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var photo: CGImage?
    @State private var colour: UInt32?
    @State private var look: Int? = 0
    @State private var list: ChatSendList?
    @State private var detent: PresentationDetent
    @State private var copied = false
    @State private var saved = false

    @State private var searchOpen = false

    init(payload: SharePayload, height: CGFloat) {
        self.payload = payload
        self.height = height
        _detent = State(initialValue: .height(height))
    }

    private var looks: [ShareLook] { [.colour(colour), .pale(colour)] }

    var body: some View {
        Group {
            if searchOpen, let list {
                ChatPicker(list: list) { closeSearch() }
            } else {
                sheet
            }
        }
        .presentationDetents([.height(height), .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackground(Hue.surface)
        .onChange(of: detent) { _, now in
            if now != .large, searchOpen { searchOpen = false }
        }
        .task { await loadPhoto() }
        .task { await loadPeople() }
        .onChange(of: look) { _, _ in center.shownLook = looks[look ?? 0] }
        .onChange(of: colour) { _, _ in center.shownLook = looks[look ?? 0] }
    }

    private func closeSearch() {
        withAnimation(reduceMotion ? nil : Motion.sheet) {
            searchOpen = false
            detent = .height(height)
        }
    }

    /// On a phone too short for Hypelist's layout (an iPhone SE, a mini), how far the rows move up: first out of
    /// the space under the card, then out of the card's own size, so the apps still fit.
    private var short: CGFloat {
        max(0, (list != nil ? ShareMetric.appsTop : ShareMetric.peopleTop) + ShareMetric.rowFoot - height)
    }

    private var cardScale: CGFloat {
        (ShareMetric.cardHeight - max(0, short - ShareMetric.gapGive)) / ShareMetric.cardHeight
    }

    private var sheet: some View {
        ZStack(alignment: .top) {
            Text("Share")
                .font(.displaySemi(17))
                .foregroundStyle(Hue.ink)
                .padding(.top, ShareMetric.titleTop)
                .accessibilityAddTraits(.isHeader)
            cards
                .scaleEffect(cardScale, anchor: .top)
                .padding(.top, ShareMetric.cardsTop)
            if list != nil {
                people
                    .padding(.top, ShareMetric.peopleTop - short)
                Hue.hairline
                    .frame(height: 1 / 3)
                    .padding(.top, ShareMetric.ruleTop - short)
            }
            apps
                .padding(.top, (list != nil ? ShareMetric.appsTop : ShareMetric.peopleTop) - short)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: The card, in two looks

    private var cards: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: ShareMetric.cardGap) {
                    ForEach(looks.indices, id: \.self) { index in
                        ShareCard(story: payload.story, look: looks[index], photo: photo)
                            .scrollTransition(.interactive, axis: .horizontal) { card, phase in
                                card.scaleEffect(1 - (1 - ShareMetric.sideScale) * min(1, abs(phase.value)))
                            }
                            .id(index)
                            .accessibilityLabel("\(payload.story.title), \(index == 0 ? "colour" : "light") card")
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, (proxy.size.width - ShareMetric.cardWidth) / 2, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $look)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        .frame(height: ShareMetric.cardHeight)
        .animation(reduceMotion ? nil : Motion.smooth, value: colour)
    }

    private func loadPhoto() async {
        guard let url = payload.story.photo, let image = await ShareCard.picture(url) else { return }
        photo = image
        center.shownPhoto = image
        let pixels = EventLook.pixels(of: image)
        colour = payload.card?.cancelled == true ? EventLook.grey : EventLook.dominant(pixels: pixels)
    }

    // MARK: The people an Event goes to

    private func loadPeople() async {
        guard let card = payload.card, let chats = center.chats, let book = center.friends,
              AuthStore.shared.isSignedIn, !AuthStore.shared.isAnonymous else { return }
        let list = ChatSendList(card: card, chats: chats, book: book)
        self.list = list
        await list.load(you: center.you, actions: center.actions)
    }

    private var people: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: ShareMetric.circleGap) {
                ShareRound(word: "Search", fill: Hue.fill) {
                    Image(systemName: "magnifyingglass").font(.glyph(ShareMetric.glyph, weight: .medium)).foregroundStyle(Hue.ink)
                } action: {
                    withAnimation(reduceMotion ? nil : Motion.sheet) {
                        searchOpen = true
                        detent = .large
                    }
                }
                if let list, let targets = list.targets {
                    ForEach(targets) { target in
                        let done = list.sent.contains(target.id)
                        ShareRound(word: done ? "Sent" : target.name, dim: done, done: done) {
                            ChatTargetFace(target: target, size: ShareMetric.circle)
                        } action: {
                            Task { await list.deliver(target) }
                        }
                        .accessibilityLabel(done ? "Sent to \(target.name)" : "Send to \(target.name)")
                    }
                } else {
                    HStack(spacing: ShareMetric.circleGap) {
                        ForEach(0..<4, id: \.self) { _ in
                            SkeletonCircle(diameter: ShareMetric.circle)
                        }
                    }
                    .shimmering()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Loading")
                }
            }
        }
        .contentMargins(.horizontal, ShareMetric.rowSide, for: .scrollContent)
        .scrollIndicators(.hidden)
    }

    // MARK: The apps

    private var apps: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: ShareMetric.circleGap) {
                ShareRound(word: copied ? "Copied" : "Copy link", dim: copied, fill: Hue.fill) {
                    Image(systemName: copied ? "checkmark" : "link")
                        .font(.glyph(ShareMetric.glyph - 2, weight: .semibold))
                        .foregroundStyle(Hue.ink)
                        .contentTransition(.symbolEffect(.replace))
                } action: {
                    center.copyLink()
                    copied = true
                }
                if center.canSendMessages {
                    ShareRound(word: "Messages") {
                        ZStack {
                            LinearGradient(colors: [Hue.messagesTop, Hue.messagesFoot], startPoint: .top, endPoint: .bottom)
                            Image(systemName: "message.fill").font(.glyph(ShareMetric.glyph, weight: .regular)).foregroundStyle(.white)
                        }
                    } action: { center.sendMessages() }
                }
                if center.onPhone(.whatsApp) {
                    ShareRound(word: "WhatsApp", fill: Hue.whatsApp) {
                        Image("WhatsApp").resizable().scaledToFit().frame(width: ShareMetric.glyph + 4).foregroundStyle(.white)
                    } action: { center.open(.whatsApp) }
                }
                if center.onPhone(.messenger) {
                    ShareRound(word: "Messenger") {
                        ZStack {
                            LinearGradient(colors: [Hue.messengerBlue, Hue.messengerPurple, Hue.messengerPink],
                                           startPoint: .bottomLeading, endPoint: .topTrailing)
                            Image("Messenger").resizable().scaledToFit().frame(width: ShareMetric.glyph + 4).foregroundStyle(.white)
                        }
                    } action: { center.open(.messenger) }
                }
                ShareRound(word: saved ? "Saved" : "Save image", dim: saved, fill: Hue.fill) {
                    Image(systemName: saved ? "checkmark" : "arrow.down.to.line")
                        .font(.glyph(ShareMetric.glyph - 2, weight: .semibold))
                        .foregroundStyle(Hue.ink)
                        .contentTransition(.symbolEffect(.replace))
                } action: {
                    center.saveImage()
                    saved = true
                }
                ShareRound(word: "More", fill: Hue.fill) {
                    Image(systemName: "ellipsis").font(.glyph(ShareMetric.glyph, weight: .semibold)).foregroundStyle(Hue.ink)
                } action: { center.shareMore() }
            }
        }
        .contentMargins(.horizontal, ShareMetric.rowSide, for: .scrollContent)
        .scrollIndicators(.hidden)
        .animation(.easeInOut(duration: 0.18), value: copied)
        .animation(.easeInOut(duration: 0.18), value: saved)
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: ShareMetric.copiedHold)
            copied = false
        }
        .task(id: saved) {
            guard saved else { return }
            try? await Task.sleep(for: ShareMetric.copiedHold)
            saved = false
        }
    }
}

/// One round button: its picture in a 58.5 pt circle, its word 9 pt under it; a send's tick on its corner once done.
private struct ShareRound<Face: View>: View {
    let word: String
    var dim = false
    var done = false
    var fill: Color? = nil
    @ViewBuilder let face: () -> Face
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: ShareMetric.wordTop) {
                face()
                    .frame(width: ShareMetric.circle, height: ShareMetric.circle)
                    .background { if let fill { Circle().fill(fill) } }
                    .clipShape(Circle())
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "checkmark")
                            .font(.glyph(ShareMetric.badgeGlyph, weight: .bold))
                            .foregroundStyle(Hue.surface)
                            .frame(width: ShareMetric.badge, height: ShareMetric.badge)
                            .background(Circle().fill(Hue.ink))
                            .overlay(Circle().stroke(Hue.surface, lineWidth: ShareMetric.badgeRing))
                            .scaleEffect(done ? 1 : 0.01)
                            .opacity(done ? 1 : 0)
                            .animation(Motion.snappy, value: done)
                    }
                Text(word)
                    .font(.sans(12))
                    .foregroundStyle(dim ? Hue.inkSecondary : Hue.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: ShareMetric.wordWidth)
            }
            .frame(width: ShareMetric.circle)
            .contentShape(Rectangle())
        }
        .buttonStyle(.press(.squish))
    }
}
