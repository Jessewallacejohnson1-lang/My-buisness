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
        showWindow()
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

    private func showWindow() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }

        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1          // above the tab bar and any .sheet
        window.backgroundColor = .clear
        let host = UIHostingController(rootView: ShareRevealView())
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false
        self.window = window
    }

    /// The topmost VC in the overlay window — the presenter for Messages / the
    /// iOS share sheet (used by ShareTargets in a later task).
    var overlayPresenter: UIViewController? { window?.rootViewController }
}
