//
//  GroupPage.swift
//  Block Party — a group's own page (BP app docs/plans/rsvp-and-groups, ticket 05), pushed from
//  Search's Groups shelf onto the shell's stack like the Event page. Drawn to the Figma frame
//  "Group page" (page "Meetup depth", approved by Jesse on 2026-10-17) with the changes he took
//  at Check-in 1 on 2026-10-18: the group's own photos (else its logo) at the top under the
//  Event page's round back and share buttons; a sheet over their bottom edge with the name, what
//  kind of group and the town, when and where it meets, its members (from one up), About, its
//  next get-togethers and its own website; and Meetup's charcoal Join group pill floating at the
//  bottom, which joins in one tap (ticket 06, `RealLifeActions`).
//
//  PRODUCT RULE: never a zero count or a placeholder. Every row is absent when its data is.
//

import SwiftUI

struct GroupPage: View {
    let group: TownGroup

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Being in the group, shared with every screen that shows it (`RealLifeActions`).
    @Environment(RealLifeActions.self) private var actions
    /// `actions.memberFailureCount` at the last tap: a tap mid-shake stills it (as `RSVPArea`'s).
    @State private var tappedAt = 0
    @State private var photoPage: Int? = 0
    /// Photos whose bitmaps are on screen: until then a photo shimmers, and its credit waits.
    @State private var shownPhotos: Set<URL> = []
    /// Photos that could not be loaded leave the pager, so a failure never holds a skeleton.
    @State private var failedPhotos: Set<URL> = []

    /// The Figma frame's sizes, on a 420 pt phone. The round buttons, the sheet's corner, its
    /// side inset and the title's rhythm are the Event page's (`FeedEventDetailDestination.Metric`).
    enum Metric {
        /// The sheet's edge 256 pt down a 420 pt phone; other widths keep the ratio.
        static let heroAspect: CGFloat = 420.0 / 256.0
        static let kindTop: CGFloat = 6
        static let whenTop: CGFloat = 2
        static let membersTop: CGFloat = 16
        static let sectionTop: CGFloat = 24
        static let sectionBodyTop: CGFloat = 6
        /// Coming up: a 64 pt date tile with 12 pt corners, the words 12 pt beside it, rows 12 pt apart.
        static let tile: CGFloat = 64
        static let tileCorner: CGFloat = 12
        static let rowGap: CGFloat = 12
        static let rowTop: CGFloat = 12
        static let linkTop: CGFloat = 24
        /// Join group, as Meetup's measures off its iOS screen at 3x: 54 pt tall, 24 pt in from each
        /// side, its bottom 35 pt above the screen's (1 pt over the 34 pt home-bar inset; Jesse took
        /// Meetup's own spot over the Figma page's 74 pt, 2026-10-18). The page fades to paper under
        /// it from 23 pt above its top, as under the Event page's bar.
        static let pillHeight: CGFloat = 54
        static let pillSide: CGFloat = 24
        static let pillBottom: CGFloat = 1
        static let fadeAbovePill: CGFloat = 23
    }

    private typealias Event = FeedEventDetailDestination.Metric

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                hero
                sheet
            }
        }
        // The photo runs up under the status bar; with none the page starts below it.
        .ignoresSafeArea(edges: hasHero ? .top : [])
        .background(Hue.paper.ignoresSafeArea())
        // Outside the scroll, so the buttons stay put; read first by VoiceOver, as they sit.
        .overlay(alignment: .top) {
            topButtons
                .accessibilityElement(children: .contain)
                .accessibilitySortPriority(1)
        }
        .accessibilityElement(children: .contain)
        // An inset, so the page scrolls under the pill and its last line stops clear of it. Only
        // for someone who may act, as the Event page's RSVP bar: it comes up when the quiet
        // account arrives.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if actions.canAct {
                joinBar
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom))
            }
        }
        .animation(Motion.smooth, value: actions.canAct)
        // Hidden, never `navigationBarBackButtonHidden`: `SwipeBack` (RootView) keeps the swipe.
        .toolbar(.hidden, for: .navigationBar)
        // A failed join shakes and buzzes only while the page is open.
        .onAppear { actions.pageOpened(group.id) }
        .onDisappear { actions.pageClosed(group.id) }
    }

    // MARK: Pictures

    private var photos: [PlacePicture] { group.photos.filter { !failedPhotos.contains($0.url) } }

    /// No photo: its logo on its Search backdrop, as an Event page draws a place it has no photo of.
    private var heroLogo: SearchLogo? {
        photos.isEmpty ? group.logo.flatMap { FeedCardImageSource($0).logo } : nil
    }

    private var hasHero: Bool { !photos.isEmpty || heroLogo != nil }

    @ViewBuilder
    private var hero: some View {
        if hasHero {
            Color.clear
                .aspectRatio(Metric.heroAspect, contentMode: .fit)
                .overlay(alignment: .top) {
                    GeometryReader { proxy in
                        Group {
                            if let logo = heroLogo {
                                FeedCardPlaceLogo(logo: logo, topShare: 0.29, sideShare: 0.43)
                            } else {
                                PhotoPager(urls: photos.map(\.url), page: $photoPage, shown: $shownPhotos,
                                           value: photoValue, onFailure: drop)
                            }
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height + Event.heroUnderlap)
                    }
                }
                // Pulling the page down past its top stretches the picture from its bottom edge.
                .visualEffect { content, proxy in
                    let pull = max(0, proxy.frame(in: .scrollView(axis: .vertical)).minY)
                    return content.scaleEffect(1 + pull / max(proxy.size.height, 1), anchor: .bottom)
                }
                .overlay(alignment: .bottomLeading) { credit }
                .overlay(alignment: .bottomTrailing) { counter }
        }
    }

    /// The photo on screen's credit, once it is drawn: the group's own site. A tap on it reports
    /// the photo (BP app place-photos 06).
    @ViewBuilder private var credit: some View {
        let index = photoPage ?? 0
        if photos.indices.contains(index), PhotoPager.isShown(photos[index].url, in: shownPhotos),
           let credit = photos[index].creditLine {
            PhotoCredit(names: [credit], report: PhotoReport(place: group.name, photo: photos[index].url),
                        spoken: photos.count < 2)
                .padding(.leading, Event.inset - PhotoCredit.edgeInset)
                .padding(.bottom, Event.counterBottom - PhotoCredit.edgeInset)
        }
    }

    @ViewBuilder private var counter: some View {
        if let text = FeedEventDetailDestination.counterText(page: photoPage ?? 0, count: photos.count) {
            PhotoCounter(text: text)
                .padding(.trailing, Event.inset)
                .padding(.bottom, Event.counterBottom)
        }
    }

    private var photoValue: String {
        let index = photoPage ?? 0
        let credit = photos.indices.contains(index) ? photos[index].creditLine : nil
        return "Photo \(index + 1) of \(photos.count)" + (credit.map { ", by \($0)" } ?? "")
    }

    private func drop(_ url: URL) {
        failedPhotos.insert(url)
        photoPage = min(photoPage ?? 0, max(photos.count - 1, 0))
    }

    // MARK: Buttons

    private var topButtons: some View {
        HStack(spacing: 0) {
            FeedEventDetailDestination.circleButton(glyph: Image(systemName: "arrow.left"), label: "Back",
                                                    reduceMotion: reduceMotion) { dismiss() }
            Spacer(minLength: 0)
            FeedEventDetailDestination.circleButton(
                glyph: Image(systemName: "square.and.arrow.up").font(.sansSemibold(15)), label: "Share",
                reduceMotion: reduceMotion
            ) {
                ShareCenter.shared.present(.group(group))
            }
        }
        .padding(.horizontal, Event.inset - (Event.tapBox - Event.button) / 2)
        .padding(.top, Event.buttonTop - (Event.tapBox - Event.button) / 2)
    }

    // MARK: The sheet

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(group.name)
                .font(.eventDisplay(28))
                .lineSpacing(Event.titleLineSpacing)
                .foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, Event.titleTop)

            Text(Self.kindLine(group))
                .font(.sans(15))
                .foregroundStyle(Hue.inkSecondary)
                .padding(.top, Metric.kindTop)

            if let when = Self.whenLine(group) {
                Text(when)
                    .font(.sans(15))
                    .foregroundStyle(Hue.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Metric.whenTop)
            }

            // Counts you the instant you join: the line fades in and the number rolls.
            if let members = Self.membersText(actions.member(group).count) {
                Text(members)
                    .font(.sansSemibold(15))
                    .foregroundStyle(Hue.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .padding(.top, Metric.membersTop)
                    .transition(.opacity)
            }

            if let about = Self.nonempty(group.about) {
                section("About")
                Text(about)
                    .font(.sans(15))
                    .foregroundStyle(Hue.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Metric.sectionBodyTop)
            }

            let meetings = Self.upcoming(group.meetings)
            if !meetings.isEmpty {
                section("Coming up")
                ForEach(Array(meetings.enumerated()), id: \.offset) { _, meeting in
                    meetingRow(meeting)
                        .padding(.top, Metric.rowTop)
                }
            }

            if let page = group.pageUrl, let row = BusinessPage.rows([PlaceLink(kind: "website", url: page)]).first {
                InfoPill(glyph: row.glyph, text: row.text, url: row.url, hint: "Opens outside Block Party",
                         glyphBox: SearchMetric.bizGlyphBox)
                    .padding(.top, Metric.linkTop)
            }
        }
        .padding(.horizontal, Event.inset)
        .padding(.bottom, Event.contentBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.smooth, value: actions.member(group).count)
        .background(Hue.paper, in: UnevenRoundedRectangle(topLeadingRadius: Event.sheetCorner,
                                                         topTrailingRadius: Event.sheetCorner, style: .continuous))
        .padding(.top, hasHero ? 0 : Event.buttonTop + Event.button + Event.noPhotoGap)
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.sansSemibold(17))
            .foregroundStyle(Hue.ink)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, Metric.sectionTop)
    }

    /// A date tile ("OCT" over "20"), then what it is and when.
    private func meetingRow(_ meeting: TownGroup.Meeting) -> some View {
        let tile = Self.tile(meeting.day)
        return HStack(spacing: Metric.rowGap) {
            VStack(spacing: 0) {
                Text(tile.month)
                    .font(.sansSemibold(11))
                    .foregroundStyle(Hue.inkSecondary)
                Text(tile.day)
                    .font(.sansSemibold(20))
                    .foregroundStyle(Hue.ink)
                    .monospacedDigit()
            }
            .frame(width: Metric.tile, height: Metric.tile)
            .background(Hue.fill, in: RoundedRectangle(cornerRadius: Metric.tileCorner, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(meeting.what)
                    .font(.sansSemibold(15))
                    .foregroundStyle(Hue.ink)
                Text(Self.meetingLine(meeting))
                    .font(.sans(13))
                    .foregroundStyle(Hue.inkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Join group

    /// Meetup's charcoal pill over a fade to the page. One tap joins: "You're in!" at once, the pill
    /// shrinks into Invite at the right and the Event page's glass bar comes up around it, with
    /// "Leave group?" under the words (Jesse, 2026-10-18: inside the group you can leave), over the
    /// RSVP pill's 0.18 s, both ways. It stays one button, so VoiceOver keeps its place. A join
    /// the server refuses holds, turns back, then shakes.
    private var joinBar: some View {
        let isMember = actions.member(group).isMember
        let failures = actions.memberFailureCount(group.id)
        let size = RSVPArea.Size.page
        return HStack(spacing: 0) {
            if isMember {
                VStack(alignment: .leading, spacing: 1) {
                    Text("You're in!")
                        .font(.sansBold(size.top))
                        .foregroundStyle(Hue.ink)
                    RSVPArea.leave("Leave group?", size: size, hint: "Takes you out of the group",
                                   reduceMotion: reduceMotion, action: toggle)
                }
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .layoutPriority(1)
                .transition(.opacity)
                Spacer(minLength: 12)
            }
            Button {
                if isMember { ShareCenter.shared.present(.group(group)) } else { toggle() }
            } label: {
                // Both faces stay inside the pill and cross-fade as it shrinks; a face swapped
                // out stayed where the wide pill had been, outside the small one.
                ZStack {
                    Text("Join group")
                        .opacity(isMember ? 0 : 1)
                    HStack(spacing: RSVPArea.glyphGap) { RSVPArea.invite(size) }
                        .opacity(isMember ? 1 : 0)
                }
                .font(.sansSemibold(size.top))
                .frame(maxWidth: isMember ? nil : .infinity)
            }
            .buttonStyle(MeetupPillStyle(height: isMember ? size.pillHeight : Metric.pillHeight,
                                         minWidth: size.pillMinWidth))
            .turnBackShake(failures: failures, shakes: !reduceMotion && tappedAt != failures)
            .accessibilityLabel(isMember ? "Invite" : "Join group")
            .accessibilityValue(isMember ? "Joined" : "")
        }
        // In the group: the Event page's capsule (`FeedEventDetailDestination.rsvpBar`), the words 24 pt
        // in, the pill 5.5 pt from its end, 57 pt tall, a little glass over a white layer.
        .padding(.leading, isMember ? Event.barWordsInset : 0)
        .padding(.trailing, isMember ? Event.barPillInset : 0)
        .padding(.vertical, isMember ? Event.barPillInset : 0)
        .frame(minHeight: isMember ? Event.barHeight : nil)
        // The whole capsule takes a touch: a tap between the words and the pill once opened the
        // group's website, under the bar.
        .contentShape(Capsule())
        .glassEffect(isMember ? .regular : .identity, in: Capsule())
        .background {
            Capsule()
                .fill(Hue.surface.opacity(isMember ? Event.barWhite : 0))
                .allowsHitTesting(false)
        }
        .padding(.horizontal, isMember ? Event.inset : Metric.pillSide)
        // Reduce Motion: shorter, as the RSVP pill (`RSVPArea`); swapping the bar for a cross-fade
        // would rebuild the button and lose VoiceOver's place.
        .animation(.easeInOut(duration: reduceMotion ? 0.15 : RealLifeActions.flip), value: isMember)
        .padding(.bottom, Metric.pillBottom)
        .background {
            LinearGradient(colors: [Hue.paper.opacity(0), Hue.paper], startPoint: .top, endPoint: .bottom)
                .padding(.top, -Metric.fadeAbovePill)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }

    /// Join group and "Leave group?" both flip being in it; a write the server refuses turns back
    /// and shakes the pill.
    private func toggle() {
        tappedAt = actions.memberFailureCount(group.id)
        actions.toggleMember(group)
    }

    // MARK: Words (SearchModelTests)

    /// "Book club · St. Joseph": the town alone when the group doesn't say what kind it is.
    static func kindLine(_ group: TownGroup) -> String {
        let town = Town.display.components(separatedBy: ",").first ?? Town.display
        return [nonempty(group.kind), town].compactMap { $0 }.joined(separator: " · ")
    }

    /// "1st Tuesdays at 9:30 AM · Fireside Room, Resurrection Lutheran"; nil with neither.
    static func whenLine(_ group: TownGroup) -> String? {
        let parts = [nonempty(group.schedule), nonempty(group.location)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The get-togethers from today on: the groups are read once a launch, so one can pass while the app stays open.
    static func upcoming(_ meetings: [TownGroup.Meeting], today: Date = Date()) -> [TownGroup.Meeting] {
        let day = Town.day(today)
        return meetings.filter { $0.day >= day }
    }

    /// Never "0 members".
    static func membersText(_ count: Int) -> String? {
        switch count {
        case ..<1: nil
        case 1: "1 member"
        default: "\(count) members"
        }
    }

    /// "Tue, Oct 20 · 6 PM", with its place when it isn't the group's usual one.
    static func meetingLine(_ meeting: TownGroup.Meeting) -> String {
        var parts: [String] = []
        if let day = YourDayLogic.townDay(meeting.day) { parts.append(format("EEE, MMM d").string(from: day)) }
        if let minutes = YourDayLogic.minutes(from: meeting.time) {
            let hour = (minutes / 60) % 12 == 0 ? 12 : (minutes / 60) % 12, minute = minutes % 60
            parts.append((minute == 0 ? "\(hour)" : String(format: "%d:%02d", hour, minute)) + (minutes < 720 ? " AM" : " PM"))
        }
        if let place = nonempty(meeting.place) { parts.append(place) }
        return parts.joined(separator: " · ")
    }

    /// The date tile's words: "OCT" and "20".
    static func tile(_ day: String) -> (month: String, day: String) {
        guard let date = YourDayLogic.townDay(day) else { return ("", "") }
        return (format("MMM").string(from: date).uppercased(), format("d").string(from: date))
    }

    private static func format(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Town.calendar
        f.locale = Locale(identifier: "en_US")
        f.timeZone = Town.timeZone
        f.dateFormat = pattern
        return f
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
