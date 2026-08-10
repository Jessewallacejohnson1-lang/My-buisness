// TODO: This screen will become the full feed-discovery destination for browsing
// recent events, clubs, and town happenings, but it is intentionally not built yet.
// Features/Board/BoardView.swift already implements almost exactly this screen:
// three sections (Today / This week / Around town) over
// CommunityAPI.getBoardSections(), with SafariView link handling and empty states.
// BoardView is orphaned: `BoardView(` is never constructed anywhere in the app.
// Before building this destination, decide whether to revive or wrap BoardView
// instead of writing a second implementation of the same concept.

import SwiftUI

struct FeedDiscoveryDestination: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("See what’s happening")
                    .font(.displaySemi(28))
                    .foregroundStyle(Hue.ink)

                Text("This screen isn’t built yet. It will bring together everything recently posted across Block Party—events, clubs, and town happenings—so you can find something to do and join in.")
                    .font(.sans(16))
                    .foregroundStyle(Hue.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Hue.paper.ignoresSafeArea())
            .navigationTitle("Around town")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Hue.ink)
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    FeedDiscoveryDestination()
}
#endif
