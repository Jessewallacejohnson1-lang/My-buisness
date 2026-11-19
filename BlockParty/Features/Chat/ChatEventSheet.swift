//
//  ChatEventSheet.swift
//  Block Party — the + in a chat (BP app messages 02): "Send an Event". Apple's sheet, white, as tall as its rows up
//  to five; it follows a drag down. It lists the Events you're Going to and the ones you hearted, soonest first, and
//  with none the Town's next ten (`ChatLook.eventsToSend`). A tap sends that Event's card. Its sizes are guessed: no
//  Instagram still shows one.
//

import SwiftUI

struct ChatEventSheet: View {
    let send: (FeedCardItem) -> Void
    @Environment(ChatBook.self) private var chats
    @Environment(\.dismiss) private var dismiss
    /// nil until the read lands; three rows' shapes stand in.
    @State private var events: [FeedCardItem]?

    private static let rowHeight = ChatMetric.sheetPhoto + 2 * ChatMetric.rowPad
    private static let titleHeight = ChatMetric.sheetTitleTop + ChatMetric.titleLine + ChatMetric.rowPad

    private var height: CGFloat {
        let rows = CGFloat(min(max(events?.count ?? 3, 1), 5))
        return Self.titleHeight + rows * Self.rowHeight + ChatMetric.side
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let events {
                    if events.isEmpty {
                        Text("No Events coming up.")
                            .appleFont(14)
                            .foregroundStyle(Hue.chatGrey)
                            .frame(maxWidth: .infinity, minHeight: Self.rowHeight)
                    }
                    ForEach(events) { card in
                        Button {
                            dismiss()
                            send(card)
                        } label: { row(card) }
                            .buttonStyle(.press(.dim))
                    }
                } else {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: ChatMetric.rowGap) {
                            SkeletonBlock(cornerRadius: ChatMetric.sheetPhotoCorner)
                                .frame(width: ChatMetric.sheetPhoto, height: ChatMetric.sheetPhoto)
                            SkeletonBlock(cornerRadius: ChatMetric.loadingLine / 2)
                                .frame(width: ChatMetric.loadingName, height: ChatMetric.loadingLine)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, ChatMetric.rowPad)
                        .shimmering()
                        .accessibilityHidden(true)
                    }
                }
            }
            .padding(.horizontal, ChatMetric.side)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Text("Send an Event")
                .appleFont(16, weight: .semibold)
                .foregroundStyle(Hue.ink)
                .frame(maxWidth: .infinity)
                .frame(height: ChatMetric.titleLine)
                .padding(.top, ChatMetric.sheetTitleTop)
                .padding(.bottom, ChatMetric.rowPad)
                .background(Hue.surface)
                .accessibilityAddTraits(.isHeader)
        }
        .task { events = await chats.eventsToSend?() ?? [] }
        .presentationDetents([.height(height), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(ChatMetric.sheetCorner)
        .presentationBackground(Hue.surface)
    }

    private func row(_ card: FeedCardItem) -> some View {
        HStack(spacing: ChatMetric.rowGap) {
            Hue.chatFill
                .frame(width: ChatMetric.sheetPhoto, height: ChatMetric.sheetPhoto)
                .overlay {
                    if let url = card.image.url {
                        FeedCardURLPhoto(url: url, loadingFill: Hue.chatFill)
                    } else if let logo = card.image.logo {
                        CastLogo(logo: logo, side: ChatMetric.sheetPhoto)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: ChatMetric.sheetPhotoCorner, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(card.title)
                    .appleFont(15, weight: .semibold)
                    .foregroundStyle(Hue.ink)
                    .lineLimit(1)
                Text([card.whenLine?.text, card.whereLine].compactMap { $0 }.joined(separator: " · "))
                    .appleFont(13)
                    .foregroundStyle(Hue.chatGrey)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, ChatMetric.rowPad)
        .contentShape(Rectangle())
    }
}
