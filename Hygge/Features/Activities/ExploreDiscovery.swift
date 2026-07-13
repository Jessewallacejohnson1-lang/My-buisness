//
//  ExploreDiscovery.swift
//  Hygge — the "Explore" discovery surface, ported ~99% from a Wolt Discovery
//  reference layout and re-skinned to Hygge's coral-on-white brand:
//    town header → category tiles → featured carousel → "happening this week"
//    shelf → compose banner → the "Around St. Joe" directory.
//
//  Wolt's structure & polish, Hygge's palette + REAL St. Joseph content. Every
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

// MARK: - Town header (Wolt's "Berlin ▾", re-skinned + an expandable search)

/// The top row: a coral place-pin, "Saint Joseph", and a chevron — with a
/// trailing search circle that expands the row into a search field in place.
/// Faithful to Wolt (no persistent search bar) while keeping search reachable.
struct ExploreTownHeader: View {
    var town: String = "Saint Joseph"
    @Binding var searching: Bool
    @Binding var query: String
    var searchField: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 11) {
            if searching {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Hue.gray)
                TextField("Search St. Joe", text: $query)
                    .font(.sans(16))
                    .foregroundStyle(Hue.mapInk)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused(searchField)
                    .submitLabel(.search)
                if !query.isEmpty {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { query = "" }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Hue.grayLight)
                    }
                    .buttonStyle(PressableStyle(scale: 0.9))
                }
                Button("Cancel") { close() }
                    .font(.sansSemibold(15))
                    .foregroundStyle(Hue.accent)
                    .buttonStyle(.plain)
            } else {
                ZStack {
                    Circle().fill(Hue.accentSoft)
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Hue.accent)
                }
                .frame(width: 40, height: 40)

                HStack(spacing: 5) {
                    Text(town)
                        .font(.sansBold(22))
                        .foregroundStyle(Hue.ink)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Hue.ink3)
                }

                Spacer(minLength: 8)

                Button { open() } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Hue.mapInk)
                        .frame(width: 42, height: 42)
                        .background(Hue.bgSubtle)
                        .clipShape(Circle())
                }
                .buttonStyle(PressableStyle(scale: 0.92))
                .accessibilityLabel("Search")
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 18)
    }

    private func open() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { searching = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { searchField.wrappedValue = true }
    }
    private func close() {
        searchField.wrappedValue = false
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            searching = false
            query = ""
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
                    RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .fill(selected ? Hue.accentSoft : Hue.bgSubtle)
                    Image(systemName: icon)
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(selected ? Hue.accent : Hue.ink)
                }
                .frame(width: 74, height: 74)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                        .stroke(selected ? Hue.accent : Color.clear, lineWidth: 2)
                )
                Text(title)
                    .font(.sansMedium(12.5))
                    .foregroundStyle(selected ? Hue.accent : Hue.ink2)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

// MARK: - Section header + "See all" pill

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

/// The light-coral "See all" pill (Wolt's tinted pill, in Hygge coral).
struct SeeAllPill: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("See all")
                .font(.sansSemibold(13))
                .foregroundStyle(Hue.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Hue.accentSoft)
                .clipShape(Capsule())
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
/// one exists, otherwise a typographic coral panel — never a fake photo, and
/// never white text on a light blank slot.
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
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .stroke(Hue.hairline, lineWidth: 1)
        )
        .modifier(CardShadow())
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 10) {
                Button(action: onInvite) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Hue.mapInk)
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
                default: coralPanel
                }
            }
        } else if let name = KnownLocalPhoto.name(forTitle: event.title) {
            PhotoView(name: name).scaledToFill()
        } else {
            VenuePhoto(venueName: event.location ?? event.title,
                       hint: event.location != nil ? event.title : nil, maxWidth: 1200) { coralPanel }
        }
    }

    /// The typographic coral panel shown when there's no photo — a faint calendar
    /// motif, so the white overline/title/location always read.
    private var coralPanel: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [Hue.accent, Hue.accentPressed],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "calendar")
                .font(.system(size: 118, weight: .light))
                .foregroundStyle(.white.opacity(0.12))
                .rotationEffect(.degrees(-8))
                .offset(x: 26, y: -18)
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
                    .fill(i == index ? Hue.accent : Hue.paper300)
                    .frame(width: i == index ? 20 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: index)
    }
}

// MARK: - "Happening this week" shelf (Wolt's Treats/Flowers row)

/// A compact photo card for the horizontal weekly shelf. Text sits *below* the
/// image, so the standard photo slot (real photo or coral-glyph blank) is safe.
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
                    .foregroundStyle(Hue.accent)
                    .lineLimit(1)
                Text(event.title)
                    .font(.sansBold(16))
                    .foregroundStyle(Hue.mapInk)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let loc = event.location, !loc.isEmpty {
                    Text(loc)
                        .font(.sans(13))
                        .foregroundStyle(Hue.gray)
                        .lineLimit(1)
                }
                if event.goingCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill").font(.system(size: 10, weight: .semibold))
                        Text("\(event.goingCount) going").font(.monoMedium(12)).monospacedDigit()
                    }
                    .foregroundStyle(Hue.gray)
                }
            }
            .padding(.horizontal, 13)
            .padding(.top, 11)
            .padding(.bottom, 13)
            .frame(width: 232, alignment: .leading)
        }
        .background(Hue.paper)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
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
/// — a bundled/venue photo (or a typographic coral panel when none exists, so
/// white type is always legible), the park name bottom-left, tap → detail.
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
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
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
                       coordinate: park.coordinate, maxWidth: 700) { placeFallback }
        }
    }

    /// The typographic coral panel shown while a photo resolves or when there is
    /// none — a faint leaf motif, so white type over it always reads.
    private var placeFallback: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [Hue.moss400, Hue.accent],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "leaf.fill")
                .font(.system(size: 74, weight: .regular))
                .foregroundStyle(.white.opacity(0.16))
                .rotationEffect(.degrees(-12))
                .offset(x: 14, y: -10)
        }
    }
}

// MARK: - Compose banner (Wolt+ upsell → a neighborly "add yours")

/// The wide, soft-coral call-to-action that replaces Wolt's paid-tier banner —
/// on-brand: an invitation to contribute, not an upsell. Opens the composer.
struct ExploreComposeBanner: View {
    var action: (() -> Void)?

    var body: some View {
        Button { action?() } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Hue.accent)
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 46, height: 46)
                .shadow(color: Hue.accent.opacity(0.3), radius: 6, x: 0, y: 3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add your own happening")
                        .font(.sansBold(16))
                        .foregroundStyle(Hue.ink)
                    Text("Post an event, club, or trail for neighbors")
                        .font(.sans(13))
                        .foregroundStyle(Hue.ink2)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Hue.accent)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Hue.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }
}
