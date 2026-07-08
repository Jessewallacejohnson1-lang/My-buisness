//
//  TodayInStJoe.swift
//  Hygge — the "Today in St. Joe" hero: the curated town board (board_items),
//  read over the shared weather background.
//
//  Data (see CommunityAPI.getTodayInStJoe): published board_items — today's
//  events first (by start time), then null-start announcements published in the
//  last 48h — first 3 shown as calm single lines. If nothing qualifies, one
//  random active evergreen_pool line. This is a distinct data source from the
//  club_events timeline in the "Today" section below it.
//
//  Interactions: tapping an item with a source_url opens it in an in-app
//  SFSafariViewController; items without a URL aren't tappable. Tapping the card
//  background (anywhere but an item link) opens the full Board screen (stubbed).
//

import SwiftUI

// MARK: - Content model

/// One line on the card. `timeLabel` is present for dated events; `url` makes
/// the row tappable (opens in-app Safari).
struct BoardItem: Identifiable, Hashable {
    let id: String
    let title: String
    let timeLabel: String?
    let url: URL?
}

/// What the card shows. Owned by HomeModel and refetched on focus / pull-to-refresh.
enum TodayInStJoeContent {
    case loading
    case items([BoardItem])
    case evergreen(String)
    case empty
}

// MARK: - Card

struct TodayInStJoeCard: View {
    let content: TodayInStJoeContent

    /// One enum-driven sheet so the two routes never fight over presentation.
    private enum Route: Identifiable {
        case board
        case link(URL)
        var id: String {
            switch self {
            case .board:          return "board"
            case .link(let url):  return url.absoluteString
            }
        }
    }

    @State private var weather: Weather?
    @State private var route: Route?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            WeatherBackground(state: weather?.state)

            // Scrim so white text stays legible over any sky.
            LinearGradient(colors: [.black.opacity(0.12), .black.opacity(0.58)],
                           startPoint: .top, endPoint: .bottom)

            cardContent
                .padding(16)
                .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Hue.hairline, lineWidth: 1))
        .shadow(color: Color(hex: 0x2a241c, alpha: 0.10), radius: 11, x: 0, y: 6)   // matches hyggeCard's one lift
        .contentShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .onTapGesture { route = .board }
        .task { weather = await WeatherService.current() }
        .sheet(item: $route) { r in
            switch r {
            case .board:         BoardView()
            case .link(let url): SafariView(url: url).ignoresSafeArea()
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Weather readout (place · conditions · temp) — the "existing weather background".
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("St. Joseph, Minnesota")
                        .font(.sansSemibold(14))
                        .foregroundStyle(.white)
                    Text(weather?.label ?? "—")
                        .font(.sans(12))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                if let w = weather {
                    Text("\(w.tempF)°")
                        .font(.monoMedium(26))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            }

            Rectangle().fill(.white.opacity(0.18)).frame(height: 1)

            Text("TODAY IN ST. JOE")
                .font(.mono(11))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.9))

            board
        }
    }

    @ViewBuilder
    private var board: some View {
        switch content {
        case .loading:
            Text("Checking what's on today…")
                .font(.sans(14))
                .foregroundStyle(.white.opacity(0.85))
        case .empty:
            Text("Nothing on the board today — tap to see what's around town.")
                .font(.sans(14))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        case .evergreen(let line):
            Text(line)
                .font(.sans(15))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        case .items(let items):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(items) { item in row(item) }
            }
        }
    }

    @ViewBuilder
    private func row(_ item: BoardItem) -> some View {
        let line = HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.title)
                .font(.sans(15))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let t = item.timeLabel {
                Text(t)
                    .font(.mono(12))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85))
            }
            if item.url != nil {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .contentShape(Rectangle())

        // A URL row is a Button (consumes the tap, so the card's background tap
        // doesn't also fire). A URL-less row has no gesture, so a tap falls
        // through to the card background → opens the Board.
        if let url = item.url {
            Button { route = .link(url) } label: { line }
                .buttonStyle(.plain)
        } else {
            line
        }
    }
}
