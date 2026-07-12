//
//  ShareCenter.swift
//  Hygge — the one entry point for the app-wide "share reveal".
//
//  Any share in the app calls `ShareCenter.shared.present(...)`. The reveal is a
//  preview card of exactly what's being shared (the same view is rendered to the
//  shared image), springing up over a dimmed backdrop with a Duolingo-style
//  target row. Ported from a reference recording — see
//  docs/superpowers/specs/2026-07-11-share-reveal-animation-design.md.
//
//  To add a NEW share anywhere in the app, that's the whole integration:
//      ShareCenter.shared.present(SharePayload(title: "SHARE THIS THING",
//                                              shareText: "…",
//                                              includesImage: true) { MyCard(…) })
//

import SwiftUI
import UIKit
import Combine

/// Describes one share: the card to preview + render, the sheet title, the text,
/// and whether a rendered image is part of the share (drives "Save image").
struct SharePayload: Identifiable {
    let id = UUID()
    let preview: AnyView
    let title: String
    let shareText: String
    let includesImage: Bool

    init<V: View>(title: String,
                  shareText: String,
                  includesImage: Bool,
                  @ViewBuilder preview: () -> V) {
        self.title = title
        self.shareText = shareText
        self.includesImage = includesImage
        self.preview = AnyView(preview())
    }
}

@MainActor
final class ShareCenter: ObservableObject {
    static let shared = ShareCenter()
    private init() {}

    @Published private(set) var payload: SharePayload?
    /// The off→on state the reveal animates against. false = card small/hidden.
    @Published var revealed: Bool = false

    private var window: UIWindow?

    func present(_ payload: SharePayload) {
        guard self.payload == nil else { return }   // one at a time
        self.payload = payload
        self.revealed = false
        guard showWindow() else {
            // No foreground window scene to present into — don't wedge the
            // singleton for future shares.
            self.payload = nil
            self.revealed = false
            return
        }
        Haptics.light()
        // Let the reveal render in its off-state, then spring it in next runloop.
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.74)) {
                self.revealed = true
            }
        }
    }

    func dismiss() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            self.revealed = false
        }
        // Tear down after the dismiss spring settles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) { [weak self] in
            guard let self, self.revealed == false else { return }
            self.window?.isHidden = true
            self.window = nil
            self.payload = nil
        }
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
        let host = UIHostingController(rootView: ShareRevealView())
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false
        self.window = window
        return true
    }

    /// The topmost VC in the overlay window — the presenter for Messages / the
    /// iOS share sheet (used by ShareTargets in a later task).
    var overlayPresenter: UIViewController? { window?.rootViewController }

    /// Render the current payload's preview card to a shareable image (scale 3).
    func renderedImage() -> UIImage? {
        guard let payload else { return nil }
        let r = ImageRenderer(content: payload.preview)
        r.scale = 3
        return r.uiImage
    }

    private func activityItems() -> [Any] {
        guard let payload else { return [] }
        var items: [Any] = [payload.shareText]
        if payload.includesImage, let img = renderedImage() { items.insert(img, at: 0) }
        return items
    }

    /// "More" → the OS share sheet, presented above the reveal.
    func shareMore() {
        guard let presenter = overlayPresenter else { return }
        Haptics.light()
        let vc = UIActivityViewController(activityItems: activityItems(), applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = presenter.view
        vc.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX,
                                                              y: presenter.view.bounds.maxY - 60,
                                                              width: 1, height: 1)
        presenter.present(vc, animated: true)
    }

    /// "Messages" → the SMS/iMessage composer seeded with image + text.
    func sendMessages() {
        guard let presenter = overlayPresenter else { return }
        Haptics.light()
        MessagesComposer.present(from: presenter,
                                 text: payload?.shareText ?? "",
                                 image: (payload?.includesImage ?? false) ? renderedImage() : nil)
    }

    /// "Save image" → write the rendered card to Photos (add-only auth).
    func saveImage() {
        guard let img = renderedImage() else { return }
        Haptics.light()
        PhotoSaver.save(img)
    }

    /// Messages target only makes sense on a device that can send texts.
    var canSendMessages: Bool { MessagesComposer.canSend }
}
