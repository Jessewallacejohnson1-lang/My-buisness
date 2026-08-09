//
//  YourDayModule.swift
//  Block Party — the signed-in user's next RSVP plans, fetched independently.
//

import Combine
import SwiftUI

@MainActor
final class YourDayModule: @MainActor FeedModule {
    let id: FeedModuleID = .yourDay
    let order = 2
    let ownsFetch = true

    @Published private var events: [UpcomingEvent] = []
    @Published private var loadState: LoadState = .loading

    private enum LoadState {
        case loading
        case ready
        case failed
    }

    init(briefing _: BriefingModel) {}

    var phase: FeedPhase {
        switch loadState {
        case .loading: .loading
        case .ready: .ready
        case .failed: .failed
        }
    }

    func isVisible(_ ctx: FeedModuleContext) -> Bool { true }

    func load(_ ctx: FeedModuleContext) async {
        loadState = .loading

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-yourday-sample") {
            events = YourDayLogic.debugEvents(now: Date())
            loadState = .ready
            return
        }
        #endif

        guard ctx.auth.userId != nil else {
            events = []
            loadState = .ready
            return
        }

        do {
            events = try await CommunityAPI(auth: ctx.auth).getMyUpcomingRsvps()
            loadState = .ready
        } catch {
            loadState = .failed
        }
    }

    func makeView(_ ctx: FeedModuleContext) -> AnyView {
        switch phase {
        case .loading:
            return AnyView(
                YourDaySkeleton()
                    .padding(.horizontal, 18)
                    .padding(.top, 22)
            )

        case .failed:
            return AnyView(
                YourDayUnavailableCard { Task { await self.load(ctx) } }
                .padding(.horizontal, 18)
                .padding(.top, 22)
            )

        case .ready:
            return AnyView(
                YourDaySection(
                    events: events,
                    onFindSomething: { ctx.navigate(.feedDiscovery) }
                )
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .springReveal(
                    1,
                    revealed: ctx.contentRevealed,
                    animated: ctx.revealAnimated
                )
            )

        case .empty:
            // Your Day is the deliberate exception: an empty RSVP list is an
            // onboarding opportunity, so this module never enters `.empty`.
            return AnyView(EmptyView())
        }
    }
}

private struct YourDaySection: View {
    let events: [UpcomingEvent]
    let onFindSomething: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your day")
                .font(.displaySemi(24))
                .foregroundStyle(Hue.ink)
                .accessibilityAddTraits(.isHeader)

            if events.isEmpty {
                emptyState
            } else {
                eventStrip
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nothing on your calendar yet.")
                .font(.displaySemi(22))
                .foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)

            Button("See what's happening →") {
                Haptics.light()
                onFindSomething()
            }
            .font(.sansSemibold(15))
            .foregroundStyle(Hue.surface)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(
                Hue.ink,
                in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
            )
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .blockPartyCard(padding: nil)
    }

    private var eventStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(YourDayLogic.stripItems(from: events)) { item in
                    switch item {
                    case .event(let event):
                        YourDayEventCard(event: event)
                    case .findSomething:
                        YourDayFindSomethingCard(action: onFindSomething)
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 2)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
    }
}

private struct YourDayEventCard: View {
    let event: UpcomingEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(event.title)
                .font(.displaySemi(20))
                .foregroundStyle(Hue.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                let presentation = YourDayLogic.schedulePresentation(
                    for: event,
                    now: timeline.date
                )

                Group {
                    if let countdown = presentation.countdown {
                        ViewThatFits(in: .horizontal) {
                            Text(presentation.label)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(presentation.dateAndTime)
                                Text("— \(countdown)")
                            }
                            .lineLimit(1)
                        }
                    } else {
                        Text(presentation.label)
                            .lineLimit(2)
                    }
                }
                .font(.sansSemibold(13))
                .foregroundStyle(Hue.ink)
                .monospacedDigit()
            }
            .padding(.top, 16)

            Text(placeLabel)
                .font(.sans(13))
                .foregroundStyle(Hue.inkSecondary)
                .lineLimit(1)
                .padding(.top, 5)

            if let going = YourDayLogic.goingLabel(for: event.goingCount) {
                Text(going)
                    .font(.sansMedium(12))
                    .foregroundStyle(Hue.inkSecondary)
                    .monospacedDigit()
                    .padding(.top, 10)
            }
        }
        .padding(16)
        .frame(width: 218, height: 208, alignment: .leading)
        .background(
            Hue.surface,
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Hue.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var placeLabel: String {
        guard let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines),
              !location.isEmpty
        else { return "Location TBD" }
        return location
    }
}

private struct YourDayFindSomethingCard: View {
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .fill(Hue.ink)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Hue.surface)
                    }

                Spacer(minLength: 0)

                Text("Find something.")
                    .font(.displaySemi(20))
                    .foregroundStyle(Hue.ink)
                    .multilineTextAlignment(.leading)
            }
            .padding(16)
            .frame(width: 170, height: 208, alignment: .topLeading)
            .background(
                Hue.fill,
                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Hue.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(YourDayFindPressStyle(reduceMotion: reduceMotion))
        .accessibilityLabel("Find something")
    }
}

/// Matches `FeedEventCardJoinButton`'s established 0.88 press and compact spring.
private struct YourDayFindPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.88 : 1))
            .animation(
                reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.6),
                value: configuration.isPressed
            )
    }
}

private struct YourDaySkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                .fill(Hue.fill)
                .frame(width: 104, height: 24)

            HStack(spacing: 12) {
                skeletonCard
                skeletonCard
            }
        }
        .accessibilityHidden(true)
    }

    private var skeletonCard: some View {
        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .fill(Hue.fill)
            .frame(width: 218, height: 208)
    }
}

private struct YourDayUnavailableCard: View {
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your day couldn't load.")
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
