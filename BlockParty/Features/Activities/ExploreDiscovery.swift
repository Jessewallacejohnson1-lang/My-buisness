//
//  ExploreDiscovery.swift
//  Block Party — the "Explore" discovery surface, ported ~99% from a Wolt Discovery
//  reference layout and re-skinned to Block Party's coral-on-white brand:
//    town header → category tiles → featured carousel → "happening this week"
//    shelf → compose banner → the "Around St. Joe" directory.
//
//  Wolt's structure & polish, Block Party's palette + REAL St. Joseph content. Every
//  surface is built from the shared tokens (Hue / Radius / CardShadow) and the
//  ExploreKit primitives (PressableStyle, SaveBookmarkButton, photo slots), so
//  nothing here hardcodes a hex or a placeholder the design system already owns.
//

import SwiftUI
import CoreLocation

// MARK: - Shared helpers

/// The coral-led overline on an event card: "Sat, Jul 18 · 9 AM" (time only when
/// the event carries one). Mirrors the metadata idiom used on the vertical cards.
func exploreEventDateline(_ event: UpcomingEvent) -> String {
    DateHelpers.prettyDate(event.eventDate) + (event.startTime.map { " · \($0)" } ?? "")
}

// MARK: - Town header (Wolt's "Berlin ▾", re-skinned + a search entry point)

/// The top row. At rest: a coral place-pin, "Saint Joseph", a chevron, and a
/// trailing search circle that opens the frosted search overlay (`onOpen`). Once
/// a search has been committed (`searching`) the row becomes a slim crisp search
/// bar holding the query — tap it to reopen the overlay, or Cancel to exit. The
/// actual typing UI (glass + suggestions) lives in `ExploreSearchOverlay`.
struct ExploreTownHeader: View {
    var town: String = "Saint Joseph"
    var searching: Bool
    var query: String
    var onOpen: () -> Void
    var onCancel: () -> Void

    var body: some View {
        Group {
            if searching { committedBar } else { restingRow }
        }
        .frame(height: 44)
        .padding(.horizontal, 18)
    }

    private var restingRow: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(Hue.fill)
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Hue.ink)
            }
            .frame(width: 40, height: 40)

            HStack(spacing: 5) {
                Text(town)
                    .font(.sansBold(22))
                    .foregroundStyle(Hue.ink)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Hue.inkSecondary)
            }

            Spacer(minLength: 8)

            Button { onOpen() } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Hue.ink)
                    .frame(width: 42, height: 42)
                    .background(Hue.paper)
                    .clipShape(Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.92))
            .accessibilityLabel("Search")
        }
    }

    /// The persistent slim bar shown after a search is committed — crisp white
    /// rounded control + shadow, matching the overlay's bar so reopening feels continuous.
    private var committedBar: some View {
        HStack(spacing: 12) {
            Button { onOpen() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Hue.inkSecondary)
                    Text(query.isEmpty ? "Search St. Joe" : query)
                        .font(.sans(16))
                        .foregroundStyle(query.isEmpty ? Hue.inkSecondary : Hue.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Hue.surface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 4)
                .contentShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit search")

            Button("Cancel") { onCancel() }
                .font(.sansSemibold(15))
                .foregroundStyle(Hue.ink)
                .buttonStyle(.plain)
        }
    }
}

// MARK: - Category tiles (Wolt's icon squares)

/// One rounded-square category tile: a big glyph in a soft square + a label
/// beneath, coral-filled when it is the active filter. Tapping toggles the
/// filter (active tile → back to the discovery "All" view).
struct ExploreCategoryTile: View {
    let title: String
    let icon: String
    let selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .fill(Hue.fill)
                    Image(systemName: icon)
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(selected ? Hue.ink : Hue.ink)
                }
                .frame(width: 74, height: 74)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .stroke(selected ? Hue.ink : Color.clear, lineWidth: 2)
                )
                Text(title)
                    .font(.sansMedium(12.5))
                    .foregroundStyle(selected ? Hue.ink : Hue.inkSecondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

// MARK: - Section header + "See all" button

/// A bold section title with an optional trailing control — the Wolt "Happy
/// Women's Day  ·  See all" row.
struct ExploreSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.sansBold(21))
                .foregroundStyle(Hue.ink)
            Spacer(minLength: 8)
            trailing()
        }
    }
}

/// The light "See all" button.
struct SeeAllPill: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("See all")
                .font(.sansSemibold(13))
                .foregroundStyle(Hue.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Hue.fill)
                .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.95))
    }
}

// MARK: - Featured carousel (Wolt's promo carousel → this week's happenings)

/// A full-width, swipeable hero carousel of the soonest upcoming events, with
/// Wolt-style page dots beneath. Calm by design — no autoplay.
struct FeaturedCarousel: View {
    let events: [UpcomingEvent]
    var onInvite: (UpcomingEvent) -> Void
    @State private var index = 0

    var body: some View {
        VStack(spacing: 12) {
            TabView(selection: $index) {
                ForEach(Array(events.enumerated()), id: \.element.id) { i, e in
                    FeaturedEventCard(event: e) { onInvite(e) }
                        .padding(.horizontal, 18)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 210)

            if events.count > 1 {
                CarouselDots(count: events.count, index: index)
            }
        }
    }
}

/// The hero card. A bundled photo (dark-scrimmed for legible white type) when
/// one exists, otherwise the shared neutral no-photo mark.
struct FeaturedEventCard: View {
    let event: UpcomingEvent
    var onInvite: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            background
            LinearGradient(colors: [.clear, .black.opacity(0.12), .black.opacity(0.62)],
                           startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                Text(exploreEventDateline(event).uppercased())
                    .font(.monoMedium(12)).monospacedDigit()
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.92))
                Text(event.title)
                    .font(.sansBold(25))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let loc = event.location, !loc.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "mappin").font(.system(size: 11, weight: .semibold))
                        Text(loc).font(.sans(14)).lineLimit(1)
                    }
                    .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Hue.hairline, lineWidth: 1)
        )
        .modifier(CardShadow())
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 10) {
                Button(action: onInvite) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Hue.ink)
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .accessibilityLabel("Invite a neighbor")
                SaveBookmarkButton(id: event.id)
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var background: some View {
        if let url = event.imageUrl.flatMap(URL.init) {
            // Organizer's own photo — a scrim + white type already sit on top.
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: ExploreBlankPhoto()
                }
            }
        } else if let name = KnownLocalPhoto.name(forTitle: event.title) {
            PhotoView(name: name).scaledToFill()
        } else {
            VenuePhoto(venueName: event.location ?? event.title,
                       hint: event.location != nil ? event.title : nil, maxWidth: 1200) { ExploreBlankPhoto() }
        }
    }
}

/// Wolt-style page dots — an elongated coral capsule marks the active page.
struct CarouselDots: View {
    let count: Int
    let index: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Hue.ink : Hue.fill)
                    .frame(width: i == index ? 20 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: index)
    }
}

// MARK: - "Happening this week" shelf (Wolt's Treats/Flowers row)

/// A compact photo card for the horizontal weekly shelf. Text sits *below* the
/// image, so the standard photo slot (real photo or neutral blank) is safe.
struct EventShelfCard: View {
    let event: UpcomingEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                photo
                    .frame(width: 232, height: 132)
                    .clipped()
                SaveBookmarkButton(id: event.id).padding(9)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(exploreEventDateline(event))
                    .font(.monoMedium(12)).monospacedDigit()
                    .foregroundStyle(Hue.ink)
                    .lineLimit(1)
                Text(event.title)
                    .font(.sansBold(16))
                    .foregroundStyle(Hue.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let loc = event.location, !loc.isEmpty {
                    Text(loc)
                        .font(.sans(13))
                        .foregroundStyle(Hue.inkSecondary)
                        .lineLimit(1)
                }
                if event.goingCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill").font(.system(size: 10, weight: .semibold))
                        Text("\(event.goingCount) going").font(.monoMedium(12)).monospacedDigit()
                    }
                    .foregroundStyle(Hue.inkSecondary)
                }
            }
            .padding(.horizontal, 13)
            .padding(.top, 11)
            .padding(.bottom, 13)
            .frame(width: 232, alignment: .leading)
        }
        .background(Hue.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Hue.hairline, lineWidth: 1)
        )
        .modifier(CardShadow())
    }

    @ViewBuilder
    private var photo: some View {
        if let url = event.imageUrl.flatMap(URL.init) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: ExploreBlankPhoto()
                }
            }
        } else if let name = KnownLocalPhoto.name(forTitle: event.title) {
            PhotoView(name: name).scaledToFill()
        } else {
            VenuePhoto(venueName: event.location ?? event.title,
                       hint: event.location != nil ? event.title : nil, maxWidth: 700) { ExploreBlankPhoto() }
        }
    }
}

// MARK: - Place card (Wolt's collection cards → St. Joe parks)

/// A large photo collection card for the horizontal "Parks & green space" shelf
/// — a bundled/venue photo (or the shared neutral blank), the park name
/// bottom-left, tap → detail.
struct ExplorePlaceCard: View {
    let park: Park
    @State private var showDetail = false

    var body: some View {
        Button {
            Haptics.light()
            showDetail = true
        } label: {
            ZStack(alignment: .bottomLeading) {
                photo
                    .frame(width: 212, height: 150)
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.1), .black.opacity(0.58)],
                               startPoint: .center, endPoint: .bottom)
                Text(park.title)
                    .font(.sansBold(17))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
            }
            .frame(width: 212, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(Hue.hairline, lineWidth: 1)
            )
            .modifier(CardShadow())
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .sheet(isPresented: $showDetail) { ParkDetailView(park: park) }
        .accessibilityLabel(park.title)
    }

    @ViewBuilder
    private var photo: some View {
        if let name = KnownLocalPhoto.name(forTitle: park.title) {
            PhotoView(name: name).scaledToFill()
        } else {
            VenuePhoto(venueName: park.title, hint: park.address,
                       coordinate: park.coordinate, maxWidth: 700) { ExploreBlankPhoto() }
        }
    }
}

// MARK: - Compose banner (Wolt+ upsell → a neighborly "add yours")

/// The wide contribution card that replaces Wolt's paid-tier banner —
/// on-brand: an invitation to contribute, not an upsell. Opens the composer.
struct ExploreComposeBanner: View {
    var action: (() -> Void)?

    var body: some View {
        Button { action?() } label: {
            HStack(spacing: 14) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Hue.surface)
                    .frame(width: 46, height: 46)
                    .background(Hue.ink,
                                in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                    .shadow(color: Hue.ink.opacity(0.3), radius: 6, x: 0, y: 3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose what to add")
                        .font(.sansBold(16))
                        .foregroundStyle(Hue.ink)
                    Text("Event, club, or trail")
                        .font(.sans(13))
                        .foregroundStyle(Hue.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Hue.ink)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Hue.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .stroke(Hue.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }
}
