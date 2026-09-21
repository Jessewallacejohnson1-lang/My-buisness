//
//  ReservedScreen.swift
//  Block Party — what a control that is BUILT but not yet WIRED opens.
//
//  The Today bar's search mark and bell landed on 2026-09-20 as chrome, ahead of the
//  screens behind them. The two honest options were a button that does nothing and a
//  named, empty room; this is the second one, and it is the same call `BlankTab`
//  already makes for the Daily and Business tabs — a reserved slot reads as reserved,
//  where a dead tap reads as broken.
//
//  Deliberately one small file and one small view. It is scaffolding with a
//  half-life: when a real search or notifications screen lands, its presentation
//  replaces the call here and this file's last caller goes with it.
//

import SwiftUI

/// A named, empty room: what the slot is for, in one line, on the app's own paper.
struct ReservedScreen: View {
    let title: String
    /// One line on what will live here. Present tense, no ship date — a promise with
    /// a date on it is a promise that expires.
    let promise: String
    let symbol: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Hue.paper.ignoresSafeArea()
            VStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.glyph(28, weight: .light))
                    .foregroundStyle(Hue.inkSecondary)
                    .padding(.bottom, 2)
                Text(title)
                    .font(.display(22))
                    .foregroundStyle(Hue.ink)
                Text(promise)
                    .font(.sans(14))
                    .foregroundStyle(Hue.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 44)
            }
            .accessibilityElement(children: .combine)
        }
        .overlay(alignment: .topTrailing) {
            Button("Close") { dismiss() }
                .font(.sansSemibold(15))
                .foregroundStyle(Hue.ink)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .presentationDragIndicator(.visible)
    }
}

extension ReservedScreen {
    /// The two the Today bar opens today.
    static var search: ReservedScreen {
        ReservedScreen(
            title: "Search",
            promise: "Find a place, a happening, or someone on the block.",
            symbol: "magnifyingglass"
        )
    }

    static var notifications: ReservedScreen {
        ReservedScreen(
            title: "Notifications",
            promise: "Replies, invites, and what changed while you were away.",
            symbol: "bell"
        )
    }
}

#Preview { ReservedScreen.search }
