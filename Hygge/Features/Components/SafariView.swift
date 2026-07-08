//
//  SafariView.swift
//  Hygge — shared in-app browser wrapper (SFSafariViewController).
//
//  Used by the Today card and the Board to open a board item's source_url
//  without leaving the app. No SPM dependency — SafariServices ships with iOS.
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
