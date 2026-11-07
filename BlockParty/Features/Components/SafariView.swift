//
//  SafariView.swift
//  Block Party — shared in-app browser wrapper (SFSafariViewController).
//
//  Opens a town news post (when its own app isn't on the phone) or a found event's page
//  without leaving the app.
//  No SPM dependency — SafariServices ships with iOS.
//

import SwiftUI
import SafariServices

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

/// The in-app browser over whatever is on top, so a link opens the same from a page under the map's
/// cover or a sheet as from the shell: a sheet hung on the shell can't rise over those.
enum InAppBrowser {
    @MainActor static func open(_ url: URL) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let next = top?.presentedViewController { top = next }
        top?.present(SFSafariViewController(url: url), animated: true)
    }
}

/// Identifiable URL wrapper so a link can drive `.sheet(item:)`.
struct SafariLink: Identifiable {
    let id = UUID()
    let url: URL
}
