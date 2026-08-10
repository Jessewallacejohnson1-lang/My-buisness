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

    func isVisible(_ ctx: FeedModuleContext) -> Bool {
        #if DEBUG
        if FeedDebugFocus.isHidden(id) { return false }
        #endif
        return true
    }

    func load(_ ctx: FeedModuleContext) async {
        loadState = .loading

        #if DEBUG
        if applyDebugStateIfRequested() { return }
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
                FeedUnavailableCard(title: FeedStateCopy.yourDayUnavailable) {
                    Task { await self.load(ctx) }
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)
            )

        case .ready:
            return AnyView(
                YourDaySection(
                    events: events,
                    onOpenEvent: { ctx.navigate(.event($0)) },
                    onFindSomething: { ctx.navigate(.feedDiscovery) }
                )
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .springReveal(
                    1,
                    revealed: ctx.contentRevealed,
                    animated: ctx.revealAnimated
                )
                .modifier(YourDayDebugDetailOpener(events: events, navigate: ctx.navigate))
            )

        case .empty:
            // Your Day is the deliberate exception: an empty RSVP list is an
            // onboarding opportunity, so this module never enters `.empty` — it
            // renders its designed empty state from the `.ready` branch instead.
            return AnyView(EmptyView())
        }
    }
}

#if DEBUG
private extension YourDayModule {
    /// `-yourday-sample|-yourday-loading|-yourday-error|-yourday-empty` bypass auth
    /// and the network so each state can be screenshotted. Production loaders are
    /// untouched; the fixtures are the same clearly-marked debug events.
    func applyDebugStateIfRequested() -> Bool {
        let args = ProcessInfo.processInfo.arguments

        if args.contains("-yourday-loading") {
            events = []
            loadState = .loading
            return true
        }
        if args.contains("-yourday-error") {
            events = []
            loadState = .failed
            return true
        }
        if args.contains("-yourday-empty") {
            events = []
            loadState = .ready
            return true
        }
        if args.contains("-yourday-sample") {
            events = YourDayLogic.debugEvents(now: Date())
            loadState = .ready
            return true
        }
        return false
    }
}
#endif

/// `-yourday-open-detail` opens the first upcoming event's detail on appear.
/// There is no tap automation in this simulator setup, so a screen only reachable
/// by tapping a card is otherwise unverifiable. No-op without the flag, and the
/// whole modifier compiles to a pass-through in Release.
private struct YourDayDebugDetailOpener: ViewModifier {
    let events: [UpcomingEvent]
    let navigate: (FeedRoute) -> Void

    func body(content: Content) -> some View {
        #if DEBUG
        content.task {
            let args = ProcessInfo.processInfo.arguments
            guard let flag = args.firstIndex(of: "-yourday-open-detail") else { return }
            let offset = (flag + 1 < args.count ? Int(args[flag + 1]) : nil) ?? 0
            guard events.indices.contains(offset) else { return }
            try? await Task.sleep(for: .milliseconds(400))
            navigate(.event(events[offset]))
        }
        #else
        content
        #endif
    }
}

/// The section's heading. Shared with the skeleton so the two are the same object
/// and the title cannot move when content swaps in.
private struct YourDayHeading: View {
    var body: some View {
        Text("Your day")
            .font(.displaySemi(24))
            .foregroundStyle(Hue.ink)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct YourDaySection: View {
    let events: [UpcomingEvent]
    let onOpenEvent: (UpcomingEvent) -> Void
    let onFindSomething: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            YourDayHeading()

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

            // Styling lives inside the label so the press style scales the whole
            // control rather than the text inside a stationary background.
            Button {
                Haptics.light()
                onFindSomething()
            } label: {
                Text("See what’s happening →")
                    .font(.sansSemibold(15))
                    .foregroundStyle(Hue.surface)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(
                        Hue.ink,
                        in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    )
            }
            .buttonStyle(FeedCardPressStyle())
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
                        YourDayEventCard(event: event) { onOpenEvent(event) }
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
    let onOpen: () -> Void

    var body: some View {
        // A Button, not a `.gesture` — a whole-card gesture claims the touch on
        // press-down and out-competes the enclosing ScrollView's pan.
        Button(action: onOpen) {
            cardBody
        }
        .buttonStyle(FeedCardPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this event")
    }

    private var cardBody: some View {
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

            if let place = YourDayLogic.placeText(for: event) {
                Text(place)
                    .font(.sans(13))
                    .foregroundStyle(Hue.inkSecondary)
                    .lineLimit(1)
                    .padding(.top, 5)
            }

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
    }
}

private struct YourDayFindSomethingCard: View {
    let action: () -> Void

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
        // This is a whole card inside a scroll view, so it gets the feed's quiet
        // press — the emphatic 0.88 spring belongs to the "+" button alone.
        .buttonStyle(FeedCardPressStyle())
        .accessibilityLabel("Find something")
    }
}

/// The heading is real; only the cards are placeholders. Their widths, heights,
/// radius and gap are the strip's own (218 × 208, 12pt, `Radius.card`), and the
/// trailing 170pt block is the Find-something tile, so nothing shifts on swap-in.
private struct YourDaySkeleton: View {
    var body: some View {
        FeedSkeletonSection(spacing: 12) {
            YourDayHeading()
        } content: {
            FeedSkeletonStrip(widths: [218, 218, 170], height: 208)
        }
    }
}

// The bespoke "Your day couldn't load." card was replaced by the shared
// `FeedUnavailableCard`, so the three self-fetching modules fail the same way.
