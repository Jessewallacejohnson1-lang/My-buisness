//
//  ShareCenter.swift
//  Block Party — the one entry point for every share in the app (BP app share-sheet 01).
//
//  Any share calls `ShareCenter.shared.present(...)`. It raises Apple's sheet in a window of its own, above the tab
//  bar and any sheet already up: the story card (`ShareCard`) in two looks to swipe between, the people to send it to
//  in a chat, and the apps (`ShareSheet`). Hypelist's share sheet is its Reference
//  (BP app `references/share-sheet/`).
//
//  To add a new share anywhere in the app, that's the whole integration:
//      ShareCenter.shared.present(SharePayload(story: ShareStory(title: "…", line: "…", photo: url),
//                                              shareText: "…"))
//

import SwiftUI
import UIKit
import Combine

/// What a share's card shows: its title and line over its picture (none: the Event page's yellow).
struct ShareStory: Equatable {
    var title: String
    var line: String
    var photo: URL?
}

/// One share: the card, the words that go with it, and for an Event, the Event a chat gets.
struct SharePayload: Identifiable {
    let id = UUID()
    var story: ShareStory
    let shareText: String
    /// An Event's share, the one that counts toward "Shared your first event!" (hello-drop 02).
    var isEvent = false
    /// The Event's id, so a share that went out counts in the weekly numbers (town-feed 26).
    var eventID: String?
    /// The Event itself: what a face in the people row sends (BP app five-tabs 05).
    var card: FeedCardItem?

    init(story: ShareStory, shareText: String) {
        self.story = story
        self.shareText = shareText
    }

    /// What Copy link copies: the words and the website, since an Event has no page of its own on it yet
    /// (Jesse, share-sheet round 2).
    var copied: String { shareText + " " + FriendsInvite.link.host()! }
}

@MainActor
final class ShareCenter: ObservableObject {
    static let shared = ShareCenter()
    private init() {}

    @Published private(set) var payload: SharePayload?
    /// The sheet is up; false lets it go down, and its going tears the window down.
    @Published var showing = false

    private var window: UIWindow?
    /// The sheet's height: Hypelist's, its top 88 pt down the screen.
    private(set) var sheetHeight: CGFloat = 0

    /// Who the people row lists and sends through; the shell sets them. Signed out, or without them, the row hides.
    weak var chats: ChatBook?
    weak var friends: FriendsBook?
    weak var you: YouModel?
    weak var actions: RealLifeActions?

    /// The card as the sheet shows it now, which is what Messages, Save image and More send.
    var shownLook = ShareLook.charcoal
    var shownPhoto: CGImage?

    func present(_ payload: SharePayload) {
        guard self.payload == nil else { return }   // one at a time
        self.payload = payload
        shownLook = .charcoal
        shownPhoto = nil
        guard showWindow() else {
            // No foreground window scene to present into: don't wedge the singleton for future shares.
            self.payload = nil
            return
        }
        Haptics.light()
        // The window is up with nothing in it; the sheet rises on the next turn, as Apple's does.
        DispatchQueue.main.async { self.showing = true }
    }

    /// The sheet has gone: so do its window and its share.
    func sheetGone() {
        window?.isHidden = true
        window = nil
        payload = nil
        shownPhoto = nil
    }

    private func showWindow() -> Bool {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return false }

        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1          // above the tab bar and any .sheet
        window.backgroundColor = .clear
        // A second window, so `RootView`'s `.preferredColorScheme` does not reach it. `.unspecified` is the
        // `.system` case. Read at creation rather than observed: the window exists only for one share.
        window.overrideUserInterfaceStyle = AppearanceStore.shared.choice.interfaceStyle
        sheetHeight = max(0, window.bounds.height - ShareMetric.sheetTop)
        let host = UIHostingController(rootView: ShareHost())
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false
        self.window = window
        return true
    }

    /// The topmost controller in the share window, the sheet itself once it's up: the presenter for Messages and
    /// Apple's share sheet.
    var presenter: UIViewController? {
        var top = window?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }

    /// The card as shown, drawn to a picture at 3x.
    func renderedImage() -> UIImage? {
        guard let payload else { return nil }
        let r = ImageRenderer(content: ShareCard(story: payload.story, look: shownLook, photo: shownPhoto))
        r.scale = 3
        return r.uiImage
    }

    private func activityItems() -> [Any] {
        guard let payload else { return [] }
        var items: [Any] = [payload.shareText]
        if let img = renderedImage() { items.insert(img, at: 0) }
        return items
    }

    /// "More": Apple's share sheet, over this one.
    func shareMore() {
        guard let presenter else { return }
        Haptics.light()
        let vc = UIActivityViewController(activityItems: activityItems(), applicationActivities: nil)
        let event = isEvent, id = payload?.eventID
        vc.completionWithItemsHandler = { _, completed, _, _ in
            if completed, event { Task { @MainActor in HelloMoments.shared.reach(.firstShare) } }
            if completed { Task { @MainActor in Self.recordShare(id) } }
        }
        vc.popoverPresentationController?.sourceView = presenter.view
        vc.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX,
                                                              y: presenter.view.bounds.maxY - 60,
                                                              width: 1, height: 1)
        presenter.present(vc, animated: true)
    }

    /// "Messages": Apple's composer with the card and the words.
    func sendMessages() {
        guard let presenter else { return }
        Haptics.light()
        let event = isEvent, id = payload?.eventID
        MessagesComposer.present(from: presenter,
                                 text: payload?.shareText ?? "",
                                 image: renderedImage(),
                                 sent: {
                                     if event { HelloMoments.shared.reach(.firstShare) }
                                     Self.recordShare(id)
                                 })
    }

    /// "Copy link": the words and the website.
    func copyLink() {
        guard let payload else { return }
        UIPasteboard.general.string = payload.copied
        Haptics.light()
    }

    /// "Save image": the card as shown, to Photos (add-only).
    func saveImage() {
        guard let img = renderedImage() else { return }
        Haptics.light()
        PhotoSaver.save(img)
    }

    /// WhatsApp and Messenger, each only where it's on the phone (`LSApplicationQueriesSchemes`).
    enum OtherApp {
        case whatsApp, messenger

        var scheme: URL { URL(string: self == .whatsApp ? "whatsapp://" : "fb-messenger://")! }

        /// WhatsApp takes the words; Messenger only a link.
        func url(for payload: SharePayload) -> URL? {
            var parts = URLComponents()
            switch self {
            case .whatsApp:
                parts.scheme = "whatsapp"; parts.host = "send"
                parts.queryItems = [URLQueryItem(name: "text", value: payload.copied)]
            case .messenger:
                parts.scheme = "fb-messenger"; parts.host = "share"
                parts.queryItems = [URLQueryItem(name: "link", value: FriendsInvite.link.absoluteString)]
            }
            return parts.url
        }
    }

    func onPhone(_ app: OtherApp) -> Bool { UIApplication.shared.canOpenURL(app.scheme) }

    func open(_ app: OtherApp) {
        guard let payload, let url = app.url(for: payload) else { return }
        Haptics.light()
        UIApplication.shared.open(url)
    }

    /// A share that went out, sent straight away; one that fails is dropped, as a lost view is.
    private static func recordShare(_ eventID: String?) {
        guard let eventID else { return }
        Task {
            do {
                try await CommunityAPI(auth: AuthStore.shared).recordFeedActions([FeedAction(itemID: eventID, kind: .share)])
            } catch {
                Log.network("ShareCenter: share not recorded: \(error)")
            }
        }
    }

    private var isEvent: Bool { payload?.isEvent ?? false }

    /// Messages only makes sense on a device that can send texts.
    var canSendMessages: Bool { MessagesComposer.canSend }
}

extension SharePayload {
    static func event(title: String, dateLabel: String, time: String?, location: String?) -> SharePayload {
        var text = "Come to \(title) with me. \(dateLabel)"
        if let time, !time.isEmpty { text += " at \(time)" }
        if let location, !location.isEmpty { text += ", \(location)" }
        text += ". Shared from Block Party."
        let line = [dateLabel, time].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
        var payload = SharePayload(story: ShareStory(title: title, line: line), shareText: text)
        payload.isEvent = true
        return payload
    }

    /// A feed card's Event: the card's share, and its Event page's. The card's line writes the day out
    /// ("Thu, Nov 19 · 6:30 PM"), never "Today": it's a picture that's kept.
    static func event(_ item: FeedCardItem) -> SharePayload {
        var payload = SharePayload.event(title: item.title, dateLabel: item.dateChip, time: item.shareTime,
                                         location: item.shareLocation)
        let when = FeedWhenLine(eventDate: item.eventDate, startTime: item.shareTime, fallbackDate: item.dateChip,
                                relative: false)
        payload.story = ShareStory(title: item.title, line: when?.text ?? "", photo: photo(item.image))
        payload.eventID = item.id
        payload.card = item
        return payload
    }

    /// A group, from its Group page: what it is, when and where it meets, and its own page.
    static func group(_ group: TownGroup) -> SharePayload {
        let detail = GroupPage.whenLine(group)
        var text = "Come to \(group.name) with me"
        if let detail { text += ": \(detail)" }
        if let page = group.pageUrl { text += ". \(page)" }
        text += ". Shared from Block Party."
        let line = detail ?? GroupPage.kindLine(group)
        return SharePayload(story: ShareStory(title: group.name, line: line,
                                              photo: group.photos.first { $0.kind == .photo }?.url),
                            shareText: text)
    }

    /// A place, from its page (BP app place-pages 11): its name and what it is over its cover. Copy link adds the
    /// website, as a place has no page of its own there yet.
    static func place(_ item: SearchItem) -> SharePayload {
        SharePayload(story: ShareStory(title: item.name, line: item.sub ?? "\(Town.everyday), \(Town.state)",
                                       photo: item.photos.first { $0.kind == .photo }?.url ?? item.cover),
                     shareText: "\(item.name) in \(Town.everyday). Shared from Block Party.")
    }

    static func appInvite() -> SharePayload {
        SharePayload(story: ShareStory(title: "Come see what's happening in town", line: "\(Town.everyday), \(Town.state)"),
                     shareText: "Come see what's happening in \(Town.everyday). Block Party has today's events, the town calendar, and a live map.")
    }

    /// A photo the card can show: an Event's own or its place's; a logo isn't one.
    static func photo(_ image: FeedCardImageSource) -> URL? {
        switch image {
        case .eventPhoto(let url), .placePhoto(let url, _, _, _): url
        case .placeLogo, .fallback: nil
        }
    }
}
