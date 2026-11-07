//
//  FeedCardMenu.swift
//  Block Party — a Town feed card's ••• sheet: why the card is there and a way to change
//  that (BP app docs/plans/town-feed, ticket 18). The points behind its place stay on the
//  server (Jesse, 2026-11-04).
//
//  Instagram's ••• sheet is the Reference (BP app references/recipe-why-score/),
//  measured off its frames: grey groups 16pt in from each side with 16pt corners, 51pt
//  rows, a 22pt icon 20pt in and the label 22pt after it, 17pt text. The reason sits
//  right at the top, not behind its own row (Jesse, 2026-10-10). Not interested, Mute
//  and Report join as a group below it (tickets 21 and 22). A card showing a photo Block
//  Party saved of its place starts that group with a red Report photo (BP app place-photos
//  06), which opens the neighbour's mail app on an email to Block Party.
//
//  Apple's sheet carries it, so it drags down under the finger and can be stopped
//  halfway; a solid surface keeps iOS 26 and 27 alike.
//
//  Not interested and Mute (ticket 21, mock https://claude.ai/artifact/HAJWN4Zj2Xh4wAeJA5UNcg)
//  sit in their own group under Edit your interests, Instagram's crossed-out eye beside the
//  first. Either closes the sheet; the card goes once it has closed (`FeedCardMenuSheet`).
//
//  Report (ticket 22, mock https://claude.ai/artifact/JrbAPcf2yQaf8bfH1CKppP) ends that group in
//  red, as Instagram's does (BP app references/report/). It slides the same sheet to the reasons,
//  then to a thank-you once the report has gone; one that doesn't go shakes the list and stays.
//  Where Report shows, Report photo is its Wrong photo reason.
//
//  On a Town card the ••• went (inside-cards 24, Jesse 2026-11-07): holding the card opens Apple's
//  context menu (`TownCardHold`) with Share, Not interested, Mute and Report, and Report opens this
//  sheet at its reasons. A neighbour's post keeps its •••.
//

import SwiftUI

struct FeedCardMenu: View {
    let why: String
    var report: PhotoReport? = nil
    /// The host Mute names; nil, no Mute (a neighbour's own posting names none).
    var hostName: String? = nil
    /// Not interested (false) or Mute (true); nil, neither row (signed out, or off the Town feed).
    var onHide: ((Bool) -> Void)? = nil
    /// The reasons Report offers, and where a picked one goes; nil, no Report row.
    var reasons: [ReportReason] = []
    var onReport: ((ReportReason) async throws -> Void)? = nil
    /// Report from a held Town card: the sheet opens at the reasons, its close the way out.
    var opensOnReasons = false

    private enum Pane { case menu, reasons, thanks }

    @State private var height: CGFloat = 220
    @State private var editingInterests = false
    /// nil until a row moves it: the menu, or the reasons when it opens on them.
    @State private var pane: Pane?
    @State private var sending: ReportReason?
    @State private var failures = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    private enum Metric {
        static let rowHeight: CGFloat = 51
        static let rowLeading: CGFloat = 20
        static let iconGap: CGFloat = 22
        static let iconWidth: CGFloat = 22
        /// Below the system grabber, to the title's top.
        static let titleTop: CGFloat = 32
    }

    var body: some View {
        Group {
            switch pane ?? (opensOnReasons ? .reasons : .menu) {
            case .menu: menu
            case .reasons: reasonList.transition(slide)
            case .thanks: thanks.transition(slide)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Hue.surface)
        .sheet(isPresented: $editingInterests) { FeedInterestEditorDestination() }
    }

    private var slide: AnyTransition {
        reduceMotion ? .opacity : .push(from: .trailing)
    }

    private func go(_ next: Pane) {
        withAnimation(.spring(response: 0.42, dampingFraction: 1)) { pane = next }
    }

    private var menu: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Why you're seeing this")
                    .font(.displaySemi(17))
                    .foregroundStyle(Hue.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(why)
                    .font(.sans(15))
                    .foregroundStyle(Hue.inkSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.top, Metric.titleTop)
            .padding(.bottom, 20)

            group {
                Button { editingInterests = true } label: {
                    HStack(spacing: Metric.iconGap) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.sans(20))
                            .frame(width: Metric.iconWidth)
                        Text("Edit your interests")
                            .font(.sans(17))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.sansSemibold(13))
                            .foregroundStyle(Hue.inkSecondary)
                    }
                    .foregroundStyle(Hue.ink)
                    .padding(.leading, Metric.rowLeading)
                    .padding(.trailing, 16)
                    .frame(minHeight: Metric.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.press(.row))
            }

            if let onHide {
                group {
                    VStack(spacing: 0) {
                        // `menu-not-interested`
                        hideRow("eye.slash", "Not interested") { onHide(false) }
                        if let hostName {
                            // `menu-mute`
                            hideRow("speaker.slash", "Mute \(hostName)") { onHide(true) }
                        }
                        if onReport != nil {
                            // `menu-report`
                            Button { go(.reasons) } label: {
                                HStack(spacing: Metric.iconGap) {
                                    Image(systemName: "exclamationmark.bubble")
                                        .font(.sans(20))
                                        .frame(width: Metric.iconWidth)
                                    Text("Report")
                                        .font(.sans(17))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .foregroundStyle(Hue.report)
                                .padding(.leading, Metric.rowLeading)
                                .padding(.trailing, 16)
                                .frame(minHeight: Metric.rowHeight)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.press(.row))
                        }
                    }
                }
                .padding(.top, 12)
            }

            if let report, onReport == nil {
                group {
                    Button {
                        dismiss()
                        openURL(report.mail)
                    } label: {
                        HStack(spacing: Metric.iconGap) {
                            Image(systemName: "exclamationmark.bubble")
                                .font(.sans(20))
                                .frame(width: Metric.iconWidth)
                            Text("Report photo")
                                .font(.sans(17))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .foregroundStyle(Hue.report)
                        .padding(.leading, Metric.rowLeading)
                        .padding(.trailing, 16)
                        .frame(minHeight: Metric.rowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.press(.row))
                }
                .padding(.top, 12)
            }
        }
    }

    // MARK: Report (ticket 22)

    /// Instagram's report page: its title and a close, the question, one row per reason.
    private var reasonList: some View {
        VStack(spacing: 0) {
            reportBar
            VStack(spacing: 8) {
                Text("Why are you reporting this?")
                    .font(.display(22))
                    .foregroundStyle(Hue.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Your report is anonymous.")
                    .font(.sans(15))
                    .foregroundStyle(Hue.inkSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 18)
            VStack(spacing: 0) {
                ForEach(reasons) { reason in
                    Rectangle().fill(Hue.hairline).frame(height: 1)
                    Button { send(reason) } label: {
                        HStack {
                            Text(reason.label)
                                .font(.sans(17))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right")
                                .font(.sansSemibold(13))
                                .foregroundStyle(Hue.inkSecondary)
                        }
                        .foregroundStyle(Hue.ink)
                        // While a report is on its way, the other reasons fade back.
                        .opacity(sending == nil || sending == reason ? 1 : 0.35)
                        .animation(.easeOut(duration: 0.2), value: sending)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 61)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.press(.row))
                }
                Rectangle().fill(Hue.hairline).frame(height: 1)
            }
            .padding(.horizontal, -16)
            .disabled(sending != nil)
            .turnBackShake(failures: failures, shakes: !reduceMotion)
        }
    }

    /// The thanks once the report has gone: a check, one line, Done. It keeps the list's height,
    /// so the sheet doesn't jump.
    private var thanks: some View {
        VStack(spacing: 0) {
            reportBar
            VStack(spacing: 20) {
                Image(systemName: "checkmark")
                    .font(.sansSemibold(28))
                    .foregroundStyle(Hue.ink)
                    .frame(width: 75, height: 75)
                    .background(Hue.fill, in: Circle())
                    .accessibilityHidden(true)
                Text("Thanks for reporting")
                    .font(.display(22))
                    .foregroundStyle(Hue.ink)
            }
            .padding(.top, 48)
            Spacer(minLength: 32)
            Button { dismiss() } label: {
                Text("Done")
                    .font(.displaySemi(17))
                    .foregroundStyle(Hue.paper)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Hue.ink, in: Capsule())
            }
            .buttonStyle(.press(.squish))
        }
        .frame(height: max(height - 16, 0), alignment: .top)
    }

    private var reportBar: some View {
        ZStack {
            Text("Report")
                .font(.displaySemi(17))
                .foregroundStyle(Hue.ink)
                .accessibilityAddTraits(.isHeader)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.sansSemibold(17))
                    .foregroundStyle(Hue.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.press(.squish))
            .accessibilityLabel("Close")
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: 56)
        .padding(.top, 8)
    }

    private func send(_ reason: ReportReason) {
        guard let onReport, sending == nil else { return }
        sending = reason
        Task {
            do {
                try await onReport(reason)
                sending = nil
                Haptics.success()
                go(.thanks)
            } catch {
                Log.network("FeedCardMenu: report not sent: \(error)")
                sending = nil
                failures += 1
                Haptics.error()
                AccessibilityNotification.Announcement("Couldn't send. Try again.").post()
            }
        }
    }

    private func hideRow(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            HStack(spacing: Metric.iconGap) {
                Image(systemName: icon)
                    .font(.sans(20))
                    .frame(width: Metric.iconWidth)
                Text(title)
                    .font(.sans(17))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Hue.ink)
            .padding(.leading, Metric.rowLeading)
            .padding(.trailing, 16)
            .frame(minHeight: Metric.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.press(.row))
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .background(Hue.fill)
            .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
    }

    /// The line under the title, from `get_town_feed`'s reason code and the one name it
    /// needs. Working words from the recipe playground; Jesse writes the final ones.
    /// nil for a code this app has no words for, which leaves the card without its •••.
    static func line(reason: String, name: String?) -> String? {
        switch reason {
        case "new": return "New"
        case "friend": return name.map { "\($0) is going" }
        case "follow": return name.map { "You follow \($0)" }
        // Instagram's "Your algorithm" says "Lately you've been into ..." (town-feed 30).
        case "tapped": return name.map { "You've been into \($0) lately" }
        case "interest":
            let label = Interests.all.first { $0.id == name }?.label ?? name
            return label.map { "Matches \($0)" }
        case "popular": return "Popular in town"
        case "size": return "Big in town"
        case "today": return "Happening today"
        case "tomorrow": return "Happening tomorrow"
        case "soon": return "Coming up soon"
        case "final": return "Final score"
        default: return nil
        }
    }
}

/// A Town card's ••• sheet with Not interested and Mute (ticket 21): the choice waits until the
/// sheet has closed, so the card it hangs on isn't taken away under it. Off the Town feed (no
/// `TownFeed` around) or signed out, the sheet has neither row. A News post's sheet (news-menu)
/// has the same two rows and no Report.
struct FeedCardMenuSheet: ViewModifier {
    @Binding var isPresented: Bool
    /// What it hides, by its id and its host's name.
    let id: String
    let hostName: String
    let why: String?
    let report: PhotoReport?
    /// The Event's card, which Report sends; nil for News and posts.
    let card: FeedCardItem?
    /// A neighbour's post (town-feed 29): Not interested and Report, by its id alone.
    var post: TownPost? = nil
    /// A Town card's sheet opens only for Report, from its hold menu, so at the reasons.
    var reasonsFirst = false

    init(isPresented: Binding<Bool>, item: FeedCardItem, report: PhotoReport?) {
        _isPresented = isPresented
        reasonsFirst = true
        id = item.id
        hostName = item.hostName
        why = item.why
        self.report = report
        card = item
    }

    /// Someone else's post (town-feed 29): Not interested and Report, by its id, and no Mute; your own
    /// post's ••• is Delete instead (`FeedPostCard`).
    init(isPresented: Binding<Bool>, post: TownPost) {
        _isPresented = isPresented
        id = post.id
        hostName = ""
        why = "Posted in \(Town.everyday)"
        report = nil
        card = nil
        self.post = post
    }

    @Environment(TownFeed.self) private var feed: TownFeed?
    @Environment(RealLifeActions.self) private var actions
    @State private var chosen: Bool?
    /// A report that went and hides the card (ticket 22): the card folds once the sheet has closed.
    @State private var reported = false

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: hide) { menu }
    }

    // Its own property and methods: GitHub's older Swift couldn't type-check the menu with its
    // closures written inline in the sheet.
    @ViewBuilder private var menu: some View {
        if let why {
            FeedCardMenu(why: why, report: report,
                         hostName: hostName.isEmpty ? nil : hostName,
                         onHide: onHide,
                         reasons: card.map { ReportReason.offered(photo: report != nil, found: $0.found) }
                            ?? (post == nil ? [] : ReportReason.offered(photo: false, found: false)),
                         onReport: onReport, opensOnReasons: reasonsFirst)
        }
    }

    private var canAct: Bool { feed != nil && actions.canAct }
    /// Once per card: a second report from the same phone would only add to its count.
    private var canReport: Bool { canAct && (card != nil || post != nil) && feed?.reportedIDs.contains(id) == false }

    private var onHide: ((Bool) -> Void)? {
        guard canAct else { return nil }
        return { mute in chosen = mute }
    }

    private var onReport: ((ReportReason) async throws -> Void)? {
        guard canReport else { return nil }
        return { reason in try await send(reason) }
    }

    private func send(_ reason: ReportReason) async throws {
        try await feed?.report(id: id, reason)
        guard reason.hides else { return }
        // The sheet was dragged away while it sent: fold now, not at the next close.
        if isPresented { reported = true } else { feed?.hideReported(id: id, host: hostName) }
    }

    private func hide() {
        guard let feed else { return }
        if reported {
            reported = false
            Haptics.light()
            feed.hideReported(id: id, host: hostName)
            return
        }
        guard let mute = chosen else { return }
        chosen = nil
        Haptics.light()
        Task { await feed.hide(id: id, host: hostName, mute: mute) }
    }
}

extension TownNews {
    /// The interest it shares with you, else only that it's News (Jesse at news-menu's Check-in 1:
    /// "just do news").
    var why: String { interest.flatMap { FeedCardMenu.line(reason: "interest", name: $0) } ?? "News" }
}

/// A Town card held (inside-cards 24; Jesse, 2026-11-07: "if you hold down the card, it lets you share
/// it"): Apple's context menu, the card lifted as itself over the blurred feed, as the App Store's cards
/// do (`references/town-card-buttons/hold/`). It took the send and the ••• off the card: Share and View
/// on Map first (Jesse: "also add view in Map to share dropdown"), then the sheet's Not interested and
/// Mute, then Report, which opens the sheet at its reasons. Its grey title is the sheet's top line, why
/// the card is there. Signed out, or off the Town feed, Share and View on Map alone.
struct TownCardHold: ViewModifier {
    let id: String
    let hostName: String
    let why: String?
    let share: (() -> Void)?
    /// Report's sheet, opened at its reasons; nil, no Report (News).
    var report: Binding<Bool>? = nil
    /// The Event View on Map shows; nil for News.
    var event: FeedCardItem? = nil

    @Environment(TownFeed.self) private var feed: TownFeed?
    @Environment(RealLifeActions.self) private var actions
    @Environment(\.viewOnMap) private var viewOnMap

    /// Apple's lift of the whole card, its heart, Attend and host's mark included, which keep their own
    /// taps. No `contentShape(.contextMenuPreview, …)`: with one, no button on a held card took a tap
    /// (`EventCardPhotoTapTests`).
    func body(content: Content) -> some View {
        content.contextMenu { items }
    }

    @ViewBuilder private var items: some View {
        if let why {
            Section(why) { shareButton }
        } else {
            shareButton
        }
        if let feed, actions.canAct {
            Section {
                Button("Not interested", systemImage: "eye.slash") { hide(feed, mute: false) }
                if !hostName.isEmpty {
                    Button("Mute \(hostName)", systemImage: "speaker.slash") { hide(feed, mute: true) }
                }
            }
            // Once per card, as the sheet: a second report from the same phone would only add to its count.
            if let report, !feed.reportedIDs.contains(id) {
                Section {
                    Button("Report", systemImage: "exclamationmark.bubble", role: .destructive) {
                        report.wrappedValue = true
                    }
                }
            }
        }
    }

    @ViewBuilder private var shareButton: some View {
        if let share {
            Button("Share", systemImage: "square.and.arrow.up", action: share)
        }
        if let event, let viewOnMap, EventMapRoute.route(event, now: TodayBubbleClock.now(), spot: true) != nil {
            Button("View on Map", systemImage: "map") { viewOnMap.open(event) }
        }
    }

    /// The card folds into "Hidden · Undo" as it does from the sheet.
    private func hide(_ feed: TownFeed, mute: Bool) {
        Haptics.light()
        Task { await feed.hide(id: id, host: hostName, mute: mute) }
    }
}

/// View on Map from a held Town card: the shell's (`MainTabsView`), which can open the map. A class
/// made once, as `HostOpener` is, so the cards that read it don't redraw each time the shell does.
final class EventMapOpener {
    let open: (FeedCardItem) -> Void
    init(_ open: @escaping (FeedCardItem) -> Void) { self.open = open }
}

extension EnvironmentValues {
    @Entry var viewOnMap: EventMapOpener? = nil
}

/// Where View on Map takes an Event (inside-cards 24): Block Party's map, on its bubble and card, when
/// it's there today; else Apple Maps at its place, as the Event page's place does until our map shows
/// every day and every Event has a spot (inside-cards 06, 19 and 20).
enum EventMapRoute: Equatable {
    case ourMap
    case appleMaps(URL)

    /// Today's and not over: the map shows it once its spot is read.
    static func today(_ event: FeedCardItem, now: Date) -> Bool {
        event.eventDate == Town.day(now) && TodayBubbleRules.phase(event, now: now) != .ended
    }

    /// `spot`: the map has a spot for it. Nil, nowhere to show it, so the menu leaves the row out.
    static func route(_ event: FeedCardItem, now: Date, spot: Bool) -> EventMapRoute? {
        if spot && today(event, now: now) { return .ourMap }
        return Directions.url(forPlace: event.whereLine).map { .appleMaps($0) }
    }
}
