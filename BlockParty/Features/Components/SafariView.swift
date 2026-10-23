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

/// Identifiable URL wrapper so a link can drive `.sheet(item:)`.
struct SafariLink: Identifiable {
    let id = UUID()
    let url: URL
}
