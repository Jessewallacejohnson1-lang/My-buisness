//
//  ForYouSection.swift
//  Block Party — monochrome cards and actions for the For You module.
//

import SwiftUI

struct ForYouSection: View {
    let state: ForYouContentState
    let postings: [ForYouPosting]
    let onSetInterests: () -> Void
    let onJoin: (String) -> Void
    let onSave: (String) -> Void
    let onDismiss: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("For you")
                .font(.displaySemi(24))
                .foregroundStyle(Hue.ink)
                .accessibilityAddTraits(.isHeader)

            if state == .needsInterests {
                needsInterests
            } else {
                postingStrip
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var needsInterests: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose a few interests to make these picks yours.")
                .font(.sans(15))
                .foregroundStyle(Hue.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Haptics.light()
                onSetInterests()
            } label: {
                Text("Set interests")
                    .font(.sansSemibold(15))
                    .foregroundStyle(Hue.surface)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(
                        Hue.ink,
                        in: RoundedRectangle(
                            cornerRadius: Radius.button,
                            style: .continuous
                        )
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .blockPartyCard(padding: nil)
    }

    private var postingStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(postings) { posting in
                    ForYouPostingCard(
                        posting: posting,
                        onJoin: { onJoin(posting.id) },
                        onSave: { onSave(posting.id) },
                        onDismiss: { onDismiss(posting.id) }
                    )
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 2)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
    }
}

private struct ForYouPostingCard: View {
    let posting: ForYouPosting
    let onJoin: () -> Void
    let onSave: () -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var joining = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(posting.reason)
                .font(.sansMedium(12))
                .foregroundStyle(Hue.inkSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(posting.title)
                .font(.displaySemi(20))
                .foregroundStyle(Hue.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            Text(scheduleLine)
                .font(.sansSemibold(13))
                .foregroundStyle(Hue.ink)
                .lineLimit(1)
                .monospacedDigit()
                .padding(.top, 14)

            if let location = cleanLocation {
                Text(location)
                    .font(.sans(13))
                    .foregroundStyle(Hue.inkSecondary)
                    .lineLimit(1)
                    .padding(.top, 4)
            }

            Spacer(minLength: 14)

            HStack(spacing: 10) {
                FeedEventCardJoinButton(
                    isJoined: joining,
                    isFallback: false,
                    reduceMotion: reduceMotion,
                    autoplayPressed: false,
                    onToggle: beginJoin
                )

                Spacer(minLength: 0)

                actionButton(
                    symbol: "bookmark",
                    label: "Save event",
                    action: onSave
                )
                actionButton(
                    symbol: "xmark",
                    label: "Dismiss recommendation",
                    action: onDismiss
                )
            }
        }
        .padding(16)
        .frame(width: 300, height: 230, alignment: .leading)
        .background(
            Hue.surface,
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Hue.hairline, lineWidth: 1)
        }
    }

    private var scheduleLine: String {
        let date = DateHelpers.prettyDate(posting.eventDate)
        guard let time = posting.startTime?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !time.isEmpty else { return date }
        return "\(date) · \(time)"
    }

    private var cleanLocation: String? {
        guard let location = posting.location?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !location.isEmpty else { return nil }
        return location
    }

    private func actionButton(
        symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Hue.ink)
                .frame(width: 44, height: 44)
                .background(
                    Hue.fill,
                    in: RoundedRectangle(
                        cornerRadius: Radius.button,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: Radius.button,
                        style: .continuous
                    )
                    .strokeBorder(Hue.hairline, lineWidth: 1)
                }
        }
        .buttonStyle(ForYouActionPressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel(label)
    }

    private func beginJoin() {
        guard !joining else { return }
        Haptics.selection()
        joining = true

        Task { @MainActor in
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(380))
            }
            onJoin()
        }
    }
}

private struct ForYouActionPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.88 : 1))
            .animation(
                reduceMotion
                    ? nil
                    : .spring(response: 0.25, dampingFraction: 0.6),
                value: configuration.isPressed
            )
    }
}

struct ForYouSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                .fill(Hue.fill)
                .frame(width: 94, height: 24)

            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Hue.fill)
                .frame(width: 300, height: 230)
        }
        .accessibilityHidden(true)
    }
}

struct ForYouUnavailableCard: View {
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("For you couldn't load.")
                .font(.displaySemi(20))
                .foregroundStyle(Hue.ink)

            Button("Try again", action: retry)
                .font(.sansSemibold(15))
                .foregroundStyle(Hue.ink)
                .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .blockPartyCard(padding: nil)
    }
}
