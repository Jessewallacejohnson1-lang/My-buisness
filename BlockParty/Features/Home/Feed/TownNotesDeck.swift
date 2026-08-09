//
//  TownNotesDeck.swift
//  Block Party — the horizontal, hard-stop Town Notes card deck.
//

import SwiftUI

struct TownNotesDeck: View {
    private static let caughtUpID = "townnotes-caught-up"

    let stories: [NewsStory]
    let sweepLine: String?

    @State private var expandedStoryID: String?
    @State private var scrollID: String?
    @State private var link: SafariLink?

    init(
        stories: [NewsStory],
        sweepLine: String?,
        initialExpandedStoryID: String? = nil,
        startsAtCaughtUp: Bool = false
    ) {
        self.stories = stories
        self.sweepLine = sweepLine
        _expandedStoryID = State(initialValue: initialExpandedStoryID)
        _scrollID = State(
            initialValue: startsAtCaughtUp ? Self.caughtUpID : stories.first?.id
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TOWN NOTES")
                .font(.sansSemibold(11))
                .tracking(1)
                .foregroundStyle(Hue.inkSecondary)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(stories) { story in
                        TownNotesStoryCard(
                            story: story,
                            isExpanded: expandedStoryID == story.id,
                            onToggle: { toggle(story) },
                            onRead: { url in link = SafariLink(url: url) }
                        )
                        .frame(width: 300)
                        .id(story.id)
                    }

                    TownNotesCaughtUpCard(sweepLine: sweepLine)
                        .frame(width: 300)
                        .id(Self.caughtUpID)
                }
                .scrollTargetLayout()
                .padding(.vertical, 8)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrollID, anchor: .leading)
            .scrollClipDisabled()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $link) { link in
            SafariView(url: link.url).ignoresSafeArea()
        }
    }

    private func toggle(_ story: NewsStory) {
        Haptics.light()
        expandedStoryID = expandedStoryID == story.id ? nil : story.id
    }
}

struct TownNotesStoryCard: View {
    let story: NewsStory
    let isExpanded: Bool
    let onToggle: () -> Void
    let onRead: (URL) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                collapsedContent
            }
            .buttonStyle(TownNotesCardPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(story.categoryLabel). \(story.headline). \(story.sourceTimeLine)"
            )
            .accessibilityHint(isExpanded ? "Collapses the summary" : "Expands the summary")

            if isExpanded {
                expandedContent
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .move(edge: .top))
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .blockPartyCard(padding: 0)
    }

    private func toggle() {
        withAnimation(
            reduceMotion
                ? .easeOut(duration: 0.18)
                : Motion.bentoExpand
        ) {
            onToggle()
        }
    }

    @ViewBuilder
    private var collapsedContent: some View {
        if let imageURL = story.imageURL {
            photoContent(imageURL)
        } else {
            textContent
        }
    }

    private func photoContent(_ imageURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                FeedCardURLPhoto(url: imageURL)
                    .frame(width: 300, height: 225)
                    .clipped()

                LinearGradient(
                    colors: [Hue.ink.opacity(0), Hue.ink.opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 6) {
                    eyebrow(foreground: Hue.surface.opacity(0.84))

                    Text(story.headline)
                        .font(.displaySemi(26))
                        .foregroundStyle(Hue.surface)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
            }
            .accessibilityHidden(true)

            metadata
                .frame(minHeight: 55)
                .padding(.horizontal, 18)
        }
        .frame(height: 280, alignment: .top)
        .contentShape(Rectangle())
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            eyebrow(foreground: Hue.inkSecondary)

            Text(story.headline)
                .font(.displaySemi(28))
                .foregroundStyle(Hue.ink)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            metadata
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .frame(height: 280, alignment: .leading)
        .background(Hue.surface)
        .contentShape(Rectangle())
    }

    private func eyebrow(foreground: Color) -> some View {
        Text(story.categoryLabel.uppercased())
            .font(.sansSemibold(10))
            .tracking(1)
            .foregroundStyle(foreground)
    }

    private var metadata: some View {
        Text(story.sourceTimeLine)
            .font(.sansMedium(12))
            .foregroundStyle(Hue.inkSecondary)
            .monospacedDigit()
            .lineLimit(1)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider().overlay(Hue.hairline)

            Text(story.summary)
                .font(.sans(15))
                .foregroundStyle(Hue.ink)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            Text(story.sourceTimeLine)
                .font(.sans(12))
                .foregroundStyle(Hue.inkSecondary)
                .monospacedDigit()

            if let sourceURL = story.sourceURL,
               let actionTitle = story.readActionTitle {
                Button {
                    onRead(sourceURL)
                } label: {
                    Text(actionTitle)
                        .font(.sansSemibold(14))
                        .foregroundStyle(Hue.ink)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, 14)
                        .background(Hue.fill)
                        .clipShape(
                            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        )
                        .blockPartyHairline(radius: Radius.button)
                }
                .buttonStyle(TownNotesSecondaryPressStyle())
                .accessibilityHint("Opens the original story in the in-app browser")
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }
}

struct TownNotesCaughtUpCard: View {
    let sweepLine: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You’re all caught up.")
                .font(.displaySemi(28))
                .foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let sweepLine {
                Text(sweepLine)
                    .font(.sans(12))
                    .foregroundStyle(Hue.inkSecondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .frame(height: 280, alignment: .topLeading)
        .background(Hue.fill)
        .blockPartyCard(padding: 0)
        .accessibilityElement(children: .combine)
    }
}

struct TownNotesSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonLine(widthFraction: 0.28, height: 9)
            SkeletonBlock(cornerRadius: Radius.card)
                .frame(width: 300, height: 280)
        }
        .shimmering()
        .accessibilityLabel("Loading town notes")
    }
}

struct TownNotesUnavailableCard: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Town notes didn’t load")
                .font(.displaySemi(20))
                .foregroundStyle(Hue.ink)

            Text("Check your connection and try once more.")
                .font(.sans(15))
                .foregroundStyle(Hue.inkSecondary)

            Button("Try again", action: onRetry)
                .font(.sansSemibold(14))
                .foregroundStyle(Hue.surface)
                .frame(minHeight: 44)
                .padding(.horizontal, 20)
                .background(Hue.ink)
                .clipShape(
                    RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                )
                .buttonStyle(TownNotesSecondaryPressStyle())
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Hue.fill)
        .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
    }
}

private struct TownNotesCardPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.985 : 1))
            .opacity(reduceMotion && configuration.isPressed ? 0.78 : 1)
            .animation(
                reduceMotion ? .easeOut(duration: 0.1) : Motion.tilePress,
                value: configuration.isPressed
            )
    }
}

private struct TownNotesSecondaryPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.97 : 1))
            .opacity(configuration.isPressed ? 0.76 : 1)
            .animation(
                reduceMotion ? .easeOut(duration: 0.1) : Motion.tilePress,
                value: configuration.isPressed
            )
    }
}
