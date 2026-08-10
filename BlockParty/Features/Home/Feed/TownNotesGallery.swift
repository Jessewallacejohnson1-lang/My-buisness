//
//  TownNotesGallery.swift
//  Block Party — DEBUG-only visual coverage for every Town Notes card state.
//

import SwiftUI

#if DEBUG
struct TownNotesGallery: View {
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                Color.clear
                    .frame(height: 0)
                    .id(Self.topID)

                VStack(alignment: .leading, spacing: 30) {
                    galleryState(1, "TEXT-ONLY · COLLAPSED") {
                        TownNotesStoryCard(
                            story: textStory,
                            isExpanded: false,
                            onToggle: {},
                            onRead: { _ in }
                        )
                    }

                    galleryState(2, "IMAGE-BACKED · COLLAPSED") {
                        TownNotesStoryCard(
                            story: imageStory,
                            isExpanded: false,
                            onToggle: {},
                            onRead: { _ in }
                        )
                    }

                    galleryState(3, "EXPANDED · READ ACTION") {
                        TownNotesStoryCard(
                            story: linkedStory,
                            isExpanded: true,
                            onToggle: {},
                            onRead: { _ in }
                        )
                    }

                    galleryState(4, "EXPANDED · NO SOURCE URL") {
                        TownNotesStoryCard(
                            story: unlinkedStory,
                            isExpanded: true,
                            onToggle: {},
                            onRead: { _ in }
                        )
                    }

                    galleryState(5, "CAUGHT UP · NO SWEEP") {
                        TownNotesCaughtUpCard(sweepLine: nil)
                    }

                    galleryState(6, "CAUGHT UP · WITH SWEEP") {
                        TownNotesCaughtUpCard(
                            sweepLine: "4 sources checked · Last sweep at 6:12 AM"
                        )
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Hue.paper)
            .task(id: page) {
                await Task.yield()
                proxy.scrollTo(Self.topID, anchor: .top)
            }
        }
    }

    private static let topID = "townnotes-gallery-top"

    /// The full gallery stays stacked and scrollable without a page argument.
    /// `-townnotes-gallery-page 1...6` renders one state at the top because this
    /// simulator setup cannot scroll or gesture headlessly.
    private var page: Int? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-townnotes-gallery-page"),
              index + 1 < args.count,
              let value = Int(args[index + 1]),
              (1...6).contains(value)
        else { return nil }
        return value
    }

    @ViewBuilder
    private func galleryState<Content: View>(
        _ statePage: Int,
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if let page, page != statePage {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(label)
                    .font(.monoMedium(10))
                    .tracking(1)
                    .monospacedDigit()
                    .foregroundStyle(Hue.inkSecondary)

                content()
                    .frame(width: 300, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var textStory: NewsStory {
        story(
            id: "gallery-text",
            headline: "School board shares its welcome plan",
            summary: "Families will see a calmer arrival route and a short welcome window before classes begin.",
            sourceName: "District 742",
            sourceURL: URL(string: "https://example.com/town-notes-school")
        )
    }

    private var imageStory: NewsStory {
        story(
            id: "gallery-image",
            headline: "Saint Ben’s opens a new student gathering room",
            summary: "The room gives student groups a shared place for meetings, study breaks, and small campus events.",
            sourceName: "College of Saint Benedict",
            sourceURL: URL(string: "https://example.com/town-notes-campus"),
            imageURL: Bundle.main.url(forResource: "saint-bens", withExtension: "jpg")
        )
    }

    private var linkedStory: NewsStory {
        story(
            id: "gallery-linked",
            headline: "A new lunch counter is taking shape downtown",
            summary: "The owners plan a small weekday menu with sandwiches, soup, and coffee. Opening hours will be shared later this month.",
            sourceName: "St. Cloud Live",
            sourceURL: URL(string: "https://example.com/town-notes-business")
        )
    }

    private var unlinkedStory: NewsStory {
        story(
            id: "gallery-unlinked",
            headline: "Community garden plots open for fall planting",
            summary: "A few plots remain available for neighbors who want to plant late greens or prepare a bed for spring.",
            sourceName: "City of St. Joseph",
            sourceURL: nil
        )
    }

    private func story(
        id: String,
        headline: String,
        summary: String,
        sourceName: String,
        sourceURL: URL?,
        imageURL: URL? = nil
    ) -> NewsStory {
        let now = Date()
        return NewsStory(
            id: id,
            headline: headline,
            summary: summary,
            sourceName: sourceName,
            sourceURL: sourceURL,
            publishedAt: now.addingTimeInterval(-38 * 60),
            category: "community",
            imageURL: imageURL,
            fetchedAt: now
        )
    }
}
#endif
