//
//  FeedEventDetailDestination.swift
//  Block Party — the single event behind a Your Day card.
//
//  "Tapping any upcoming item opens that item's detail" was in the spec with no
//  screen to open, so Today's plans were inert. This is that screen, and it is
//  deliberately small: an event the neighbour already said yes to needs the facts
//  and one control, not a second feed.
//
//  Reuses the feed's existing pieces rather than inventing a card language —
//  `FeedCardURLPhoto` / `VenuePhoto` for the image, `FeedEventCardJoinButton` for
//  the RSVP morph, `CommunityAPI` for the write.
//
//  PRODUCT RULE: never render a zero count or a placeholder. Every row below is
//  optional and simply absent when the data is. `YourDayLogic.*Text` return nil
//  rather than "Location TBD"/"0 going" so this screen cannot invent a fact.
//

import Combine
import SwiftUI

struct FeedEventDetailDestination: View {
    let event: UpcomingEvent

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model: FeedEventDetailModel

    init(event: UpcomingEvent, auth: AuthStore? = nil) {
        self.event = event
        _model = StateObject(wrappedValue: FeedEventDetailModel(event: event, auth: auth))
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    facts
                }
            }
            .background(Hue.paper.ignoresSafeArea())
            .navigationTitle("Your day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Hue.ink)
                }
            }
        }
    }

    // MARK: Image — organizer's own photo first, then the venue's, then nothing.

    @ViewBuilder
    private var hero: some View {
        if let url = model.organizerImageURL {
            FeedCardURLPhoto(url: url)
                .frame(height: 220)
                .clipped()
                .accessibilityHidden(true)
        } else if let venue = YourDayLogic.placeText(for: event) {
            VenuePhoto(venueName: venue, hint: event.title, maxWidth: 1200) {
                // No confident match: draw nothing at all. A grey box would be a
                // placeholder standing in for a photograph that does not exist.
                EmptyView()
            }
            .frame(height: 220)
            .clipped()
            .accessibilityHidden(true)
        }
    }

    // MARK: Facts

    private var facts: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(event.title)
                .font(.displaySemi(28))
                .foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let schedule = scheduleText {
                Text(schedule)
                    .font(.sansSemibold(15))
                    .foregroundStyle(Hue.ink)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let place = YourDayLogic.placeText(for: event) {
                Text(place)
                    .font(.sans(15))
                    .foregroundStyle(Hue.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let going = YourDayLogic.goingLabel(for: model.goingCount) {
                Text(going)
                    .font(.sansMedium(14))
                    .foregroundStyle(Hue.inkSecondary)
                    .monospacedDigit()
            }

            rsvpRow
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    private var scheduleText: String? {
        let day = YourDayLogic.dayText(for: event, now: Date())
        let time = YourDayLogic.startTimeText(for: event)
        return YourDayLogic.joined(day: day, time: time)
    }

    private var rsvpRow: some View {
        HStack(spacing: 14) {
            FeedEventCardJoinButton(
                isJoined: model.isGoing,
                isFallback: true,
                reduceMotion: reduceMotion,
                autoplayPressed: false,
                onToggle: { model.toggleGoing() }
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(model.isGoing ? "You’re going" : "You’re not going")
                    .font(.sansSemibold(15))
                    .foregroundStyle(Hue.ink)

                Text(model.isGoing ? "Tap to drop out" : "Tap to join")
                    .font(.sans(13))
                    .foregroundStyle(Hue.inkSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .blockPartyCard(padding: nil)
    }
}

/// Optimistic RSVP with rollback, matching how `BriefingModel` treats a vote: the
/// control answers instantly and only reverts if the write actually fails.
@MainActor
final class FeedEventDetailModel: ObservableObject {
    @Published private(set) var isGoing: Bool
    @Published private(set) var goingCount: Int

    let organizerImageURL: URL?

    private let eventID: String
    private let auth: AuthStore
    private var inFlight: Task<Void, Never>?

    init(event: UpcomingEvent, auth: AuthStore? = nil) {
        self.eventID = event.id
        self.auth = auth ?? .shared
        self.isGoing = event.rsvpd
        self.goingCount = event.goingCount
        self.organizerImageURL = event.imageUrl.flatMap(URL.init(string:))
    }

    func toggleGoing() {
        let wasGoing = isGoing
        let previousCount = goingCount

        isGoing = !wasGoing
        goingCount = max(0, previousCount + (wasGoing ? -1 : 1))
        Haptics.light()

        inFlight?.cancel()
        inFlight = Task { [eventID, auth] in
            do {
                let api = CommunityAPI(auth: auth)
                if wasGoing {
                    try await api.unRsvpEvent(eventID)
                } else {
                    try await api.rsvpEvent(eventID)
                }
            } catch {
                guard !Task.isCancelled else { return }
                Log.network("event rsvp toggle failed: \(error.localizedDescription)")
                isGoing = wasGoing
                goingCount = previousCount
            }
        }
    }
}
