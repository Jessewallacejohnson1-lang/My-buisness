//
//  BoardView.swift
//  Block Party — the full town Board.
//
//  Three sections over the shared board fetch (CommunityAPI.getBoardSections —
//  the same "hook" the Today card uses): Today (events starting today), This week
//  (the next 7 days), and Around town (announcements from the last 7 days). Empty
//  sections collapse. Every row shows title, blurb, and a "via {source}"
//  attribution that opens the item's source_url in-app. Pull to refresh.
//

import SwiftUI
import Combine

@MainActor
final class BoardModel: ObservableObject {
    @Published var sections: BoardSections?
    @Published var loaded = false

    func load(_ api: CommunityAPI) async {
        do { sections = try await api.getBoardSections() }
        catch { /* keep whatever we have; the UI shows calm empty states */ }
        loaded = true
    }
}

struct BoardView: View {
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model = BoardModel()
    @Environment(\.dismiss) private var dismiss

    @State private var link: SafariLink?

    private var api: CommunityAPI { CommunityAPI(auth: auth) }

    private var isEmpty: Bool {
        guard let s = model.sections else { return false }
        return s.today.isEmpty && s.week.isEmpty && s.around.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    if let s = model.sections {
                        section("Today", s.today)
                        section("This week", s.week)
                        section("Around town", s.around)
                        if isEmpty { emptyState }
                    } else if model.loaded {
                        emptyState
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Hue.canvas)
            .navigationTitle("The Board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Hue.accent)
                }
            }
            .refreshable { await model.load(api) }
            .task { await model.load(api) }
            .sheet(item: $link) { l in SafariView(url: l.url).ignoresSafeArea() }
        }
    }

    /// A section renders only when it has rows — empty sections collapse.
    @ViewBuilder
    private func section(_ title: String, _ rows: [BoardRow]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.displaySemi(20))
                    .foregroundStyle(Hue.ink)
                ForEach(rows) { row($0) }
            }
        }
    }

    private func row(_ item: BoardRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.title)
                    .font(.sansSemibold(16))
                    .foregroundStyle(Hue.ink)
                Spacer(minLength: 8)
                if let t = item.timeLabel {
                    Text(t)
                        .font(.mono(12))
                        .monospacedDigit()
                        .foregroundStyle(Hue.ink3)
                }
            }

            if let blurb = item.blurb, !blurb.isEmpty {
                Text(blurb)
                    .font(.sans(14))
                    .foregroundStyle(Hue.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            attribution(item)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .blockPartyCard(padding: 14)
    }

    /// "via {source}" — tappable when there's a source_url, plain text otherwise.
    @ViewBuilder
    private func attribution(_ item: BoardRow) -> some View {
        if let url = item.url {
            Button { link = SafariLink(url: url) } label: {
                HStack(spacing: 3) {
                    Text("via \(item.sourceName)")
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                }
                .font(.sansMedium(12))
                .foregroundStyle(Hue.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        } else {
            Text("via \(item.sourceName)")
                .font(.sansMedium(12))
                .foregroundStyle(Hue.ink3)
                .padding(.top, 2)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quiet on the board")
                .font(.displaySemi(20))
                .foregroundStyle(Hue.ink)
            Text("Nothing posted right now. Check back soon — new happenings show up here as neighbors and the town add them.")
                .font(.sans(15))
                .foregroundStyle(Hue.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .blockPartyCard(padding: 18)
    }
}
