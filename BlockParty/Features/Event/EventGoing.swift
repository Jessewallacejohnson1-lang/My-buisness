//
//  EventGoing.swift
//  Block Party — who's going, as Luma shows it (BP app docs/plans/inside-cards, ticket 36; Jesse, 2026-11-23: "copy a glass
//  bar that pops up for events very similar to this shows who else is going to the event and add a pfp and going bar where
//  theirs is"). Under the host on an Event page: the count, up to four faces and the names. A tap raises Apple's small sheet,
//  which iOS draws as glass: Attend until you're Going ("as luma and attend"), then the list. Who may be named is the
//  server's (`get_event_going`): never someone under 18 who isn't your friend. Measured off Luma in BP app
//  `references/whos-going/SPEC.md`.
//

import SwiftUI

/// Who the section names and what it says (`EventGoingTests`).
nonisolated struct GoingWords: Equatable {
    struct Face: Equatable, Identifiable {
        let id: String
        let name: String
        let photo: URL?
        /// Your own, at the front once you're Going.
        var you = false
    }

    /// Luma's four.
    static let most = 4

    /// Everyone Going, never fewer than it names.
    let total: Int
    /// The faces drawn. With nobody to name, that many blank ones.
    let faces: [Face]
    /// "Sam, Marlene, Alex, Ava, and 2 more"; nil with nobody to name.
    let names: String?

    /// How many the faces leave out: the +2.
    var more: Int { total - faces.count }

    static func make(count: Int, you: Face?, others: [Face]) -> GoingWords? {
        let known = (you.map { [$0] } ?? []) + others
        let total = max(count, known.count)
        guard total > 0 else { return nil }
        let shown = Array(known.prefix(most))
        guard !shown.isEmpty else {
            let blank = (0..<min(most, total)).map { Face(id: "blank\($0)", name: "", photo: nil) }
            return GoingWords(total: total, faces: blank, names: nil)
        }
        return GoingWords(total: total, faces: shown, names: line(shown.map(\.name), more: total - shown.count))
    }

    /// A face is known by its name, so the card's own friends stay put when the server's answer names them too.
    static func faces(_ people: [(name: String, photo: URL?)]) -> [Face] {
        var seen: [String: Int] = [:]
        return people.map { person in
            seen[person.name, default: 0] += 1
            return Face(id: "\(person.name)\(seen[person.name, default: 0])", name: person.name, photo: person.photo)
        }
    }

    /// Luma's words: a comma before "and" from three on.
    static func line(_ names: [String], more: Int) -> String {
        let parts = names + (more > 0 ? ["\(more) more"] : [])
        guard parts.count > 2, let last = parts.last else { return parts.joined(separator: " and ") }
        return parts.dropLast().joined(separator: ", ") + ", and " + last
    }

    /// The section is there for an Event still to come: not called off, a game's final not in, not ended.
    static func shows(cancelled: Bool, final: Bool, end: Date?, now: Date) -> Bool {
        !cancelled && !final && end.map { $0 > now } != false
    }
}

/// Luma's "6 Going" under the host: the count, a hairline, the faces and the names. Opens the card.
struct EventGoingSection: View {
    let item: FeedCardItem
    var sun = false

    @Environment(RealLifeActions.self) private var actions
    /// Your photo for your face; nil (a preview) or none is Instagram's blank.
    @Environment(ProfileModel.self) private var profile: ProfileModel?
    @Environment(\.eventPageShown) private var shown
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The server's answer, friends first; nil until it lands, when the card's own friends stand in.
    @State private var people: [Neighbor]?
    /// Whether you were Going at the last read that came back or failed; nil before the first.
    @State private var readFor: Bool?
    @State private var open = false
    /// The row tapped in the list: its page opens once the card is down.
    @State private var tapped: Neighbor?
    /// Pushes their page over this one; nil on the map's own stack, where a row opens nothing.
    @Environment(\.hostOpener) private var opener

    /// What the read depends on: again once you're Going or not, and each time the card comes up.
    private struct Ask: Equatable {
        let id: String
        let going: Bool
        let open: Bool
    }

    private var ink: Color { sun ? Hue.onBrandDisc : .white }
    private var dim: Color { ink.opacity(sun ? EventLook.sunDim : EventLook.dim) }
    private var going: RealLifeActions.Going { actions.going(item) }

    private var yourPhoto: URL? { profile?.avatarUrl.flatMap(URL.init(string:)) }

    private var you: GoingWords.Face? {
        going.isGoing ? .init(id: "you", name: "You", photo: yourPhoto, you: true) : nil
    }

    private var others: [GoingWords.Face] {
        if let people {
            return GoingWords.faces(people.map { ($0.firstName, $0.avatarUrl.flatMap(URL.init(string:))) })
        }
        return GoingWords.faces(item.friendsGoing.map { ($0.name, $0.photo) })
    }

    private var words: GoingWords? {
        guard GoingWords.shows(cancelled: item.cancelled, final: item.game?.final != nil, end: item.when?.end, now: .now) else { return nil }
        return .make(count: going.count, you: you, others: others)
    }

    var body: some View {
        // Always something on screen, so the read starts before anyone is known to be Going.
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 0)
            if let words {
                if actions.hasAccount {
                    Button { open = true } label: { label(words) }
                        .buttonStyle(.press(.squish))
                        .accessibilityLabel([GoingMetric.count(words.total), words.names].compactMap { $0 }.joined(separator: ", "))
                        .accessibilityHint("Shows who's going")
                        .padding(.top, GoingMetric.top)
                        .transition(.opacity)
                } else {
                    count(words)
                        .padding(.top, GoingMetric.top)
                        .transition(.opacity)
                }
            }
        }
        .animation(reduceMotion ? nil : Motion.smooth, value: words)
        .task(id: shown ? Ask(id: item.id, going: going.isGoing, open: open) : nil) {
            guard shown, actions.hasAccount else { return }
            // Attend shows before its write lands; the list is the server's to give only after.
            let wanted = going.isGoing
            await actions.goingLanded(item.id)
            guard !Task.isCancelled else { return }
            let read = try? await Self.read(item, going: wanted)
            guard !Task.isCancelled else { return }
            if let read { people = read }
            readFor = wanted
        }
        .sheet(isPresented: $open, onDismiss: {
            if let tapped { opener?.push(tapped) }
            tapped = nil
        }) {
            EventGoingCard(item: item, yourPhoto: yourPhoto, people: people ?? [], readFor: readFor, sun: sun, onPerson: opener == nil ? nil : { person in
                tapped = person
                open = false
            })
        }
    }

    private func count(_ words: GoingWords) -> some View {
        Text(GoingMetric.count(words.total))
            .font(.displaySemi(GoingMetric.word))
            .foregroundStyle(dim)
            .monospacedDigit()
            .contentTransition(.numericText())
    }

    private func label(_ words: GoingWords) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            count(words)
            ink.opacity(EventLook.hairline)
                .frame(height: EventPage.Metric.hairline)
                .padding(.top, GoingMetric.lineTop)
            faces(words)
                .padding(.top, GoingMetric.facesTop)
            // Their line is held while the first read is out, so the page doesn't move under it.
            if words.names != nil || readFor == nil {
                Text(words.names ?? " ")
                    .font(.sansSemibold(GoingMetric.word))
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, GoingMetric.namesTop)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// Each face cuts its own gap out of the one before, as Luma's do, so the page's colour shows between them.
    private func faces(_ words: GoingWords) -> some View {
        HStack(spacing: -GoingMetric.tuck) {
            ForEach(words.faces) { face in
                Avatar(face.photo, size: GoingMetric.face)
                    .background { gap }
                    .transition(reduceMotion || !face.you ? .opacity : .scale(scale: 0.3).combined(with: .opacity))
            }
            if words.more > 0 {
                Text("+\(words.more)")
                    .font(.sansSemibold(GoingMetric.plus))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(dim)
                    .frame(width: GoingMetric.face, height: GoingMetric.face)
                    .background(ink.opacity(EventLook.fill), in: FaceShape())
                    .background { gap }
            }
        }
        .compositingGroup()
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.62), value: words.faces)
    }

    private var gap: some View {
        FaceShape().inset(by: -GoingMetric.gap).fill(.black).blendMode(.destinationOut)
    }

    /// `get_event_going`; under DEBUG `-town-samples` the sample friends on the card, then sample neighbours.
    private static func read(_ item: FeedCardItem, going: Bool) async throws -> [Neighbor] {
        switch LaunchFlags.backend {
        case .live:
            // A sample's id isn't a real one.
            guard UUID(uuidString: item.id) != nil else { return [] }
            return try await CommunityAPI(auth: AuthStore.shared).eventGoing(item.id)
        case .offline: throw URLError(.notConnectedToInternet)
        case .samples:
            let names = Set(item.friendsGoing.map(\.name))
            let friends = Neighbor.samples.filter { $0.relation == .friends && names.contains($0.firstName) }
            let neighbors = Neighbor.samples.filter { $0.relation == .stranger } + Neighbor.sampleSuggestions.suffix(2)
            return Array((friends + neighbors).prefix(going ? 500 : GoingWords.most))
        }
    }
}

/// Luma's glass card: Attend until you're Going, then the list, growing in place. iOS draws the glass: Apple's sheet at a
/// small height with no background of its own.
private struct EventGoingCard: View {
    let item: FeedCardItem
    let yourPhoto: URL?
    let people: [Neighbor]
    let readFor: Bool?
    let sun: Bool
    let onPerson: ((Neighbor) -> Void)?

    @Environment(RealLifeActions.self) private var actions
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// `actions.failureCount` at the last tap: a tap mid-shake stills it.
    @State private var tappedAt = 0
    @State private var gateHeight = GoingMetric.gate
    /// The home indicator's room, which Apple adds under a sheet's own height; none on an iPhone SE.
    @State private var safeBottom = GoingMetric.foot

    private var isGoing: Bool { actions.going(item).isGoing }
    private var ink: Color { sun ? Hue.onBrandDisc : .white }
    /// You and everyone named.
    private var known: Int { people.count + (isGoing ? 1 : 0) }
    private var total: Int { max(actions.going(item).count, known) }
    private var left: Int { total - known }
    /// The list isn't in yet: a row's shape in place of "and 37 more".
    private var loading: Bool { readFor != isGoing }

    private var foot: CGFloat { max(0, GoingMetric.foot - safeBottom) }

    private var height: CGFloat {
        guard isGoing else { return gateHeight + foot }
        let rows = known + (left > 0 || loading ? 1 : 0)
        return min(GoingMetric.listMost, GoingMetric.listTop + CGFloat(rows) * GoingMetric.row + foot)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // One is nearly gone before the other comes, so their words don't cross.
            if isGoing { list.transition(Self.swap) } else { gate.transition(Self.swap) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topTrailing) { close }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { safeBottom = $0 }
        .animation(reduceMotion ? nil : Motion.smooth, value: height)
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(sun ? .light : .dark)
    }

    private static let swap = AnyTransition.asymmetric(
        insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.06)),
        removal: .opacity.animation(.easeOut(duration: 0.1)))

    private var gate: some View {
        let failures = actions.failureCount(item.id)
        return VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "person.2")
                .font(.glyph(GoingMetric.discGlyph, weight: .medium))
                .overlay(alignment: .bottomTrailing) { lock }
                .compositingGroup()
                .foregroundStyle(ink)
                .frame(width: GoingMetric.disc, height: GoingMetric.disc)
                .background(ink.opacity(GoingMetric.discFill), in: Circle())
                .accessibilityHidden(true)
            Text("Attend to see who's going")
                .font(.display(GoingMetric.title))
                .foregroundStyle(ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, GoingMetric.titleTop)
            Text("Only neighbors going can see the list.")
                .font(.sansSemibold(GoingMetric.word))
                .foregroundStyle(ink.opacity(GoingMetric.wordsDim))
                .padding(.top, GoingMetric.wordsTop)
            Button {
                tappedAt = failures
                actions.toggleGoing(item)
            } label: {
                HStack(spacing: RSVPArea.glyphGap) {
                    Image(systemName: "calendar")
                        .font(.glyph(RSVPArea.Size.page.calendar, weight: .semibold))
                        .accessibilityHidden(true)
                    Text("Attend")
                }
                .font(.displaySemi(RSVPArea.Size.page.top))
                .frame(maxWidth: .infinity)
            }
            // As the page's bar: white, a game's in our team's color.
            .buttonStyle(MeetupPillStyle(height: GoingMetric.button, minWidth: 0, grey: item.game == nil, yellow: item.game != nil,
                                         tint: item.game.flatMap { GameMatchup.attend($0) }))
            .environment(\.colorScheme, .light)
            .turnBackShake(failures: failures, shakes: !reduceMotion && tappedAt != failures)
            .padding(.top, GoingMetric.buttonTop)
        }
        .padding(.horizontal, GoingMetric.inset)
        .padding(.top, GoingMetric.inset)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { gateHeight = $0 }
    }

    /// Luma's people with a lock, cut out of them; SF Symbols has no such pair.
    private var lock: some View {
        Image(systemName: "lock")
            .font(.glyph(GoingMetric.lockGlyph, weight: .semibold))
            .padding(GoingMetric.gap)
            .background { Capsule().fill(.black).blendMode(.destinationOut) }
            .offset(x: GoingMetric.lockOut, y: GoingMetric.lockOut)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(GoingMetric.count(total))
                .font(.display(GoingMetric.title))
                .foregroundStyle(ink)
                .monospacedDigit()
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, GoingMetric.inset)
                .frame(height: GoingMetric.listTop)
                // Level with the X.
                .offset(y: GoingMetric.closeInset + GoingMetric.close / 2 - GoingMetric.listTop / 2)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    row(yourPhoto, "You")
                    ForEach(people) { person in
                        let photo = person.avatarUrl.flatMap(URL.init(string:))
                        if let onPerson {
                            Button { onPerson(person) } label: { row(photo, person.firstName) }
                                .buttonStyle(.press(.dim))
                                .accessibilityHint("Opens their page")
                        } else {
                            row(photo, person.firstName)
                        }
                    }
                    if loading {
                        loadingRow
                    } else if left > 0 {
                        Text("and \(left) more")
                            .contentTransition(.numericText())
                            .font(.sans(GoingMetric.word))
                            .foregroundStyle(ink.opacity(sun ? EventLook.sunDim : EventLook.dim))
                            .padding(.horizontal, GoingMetric.inset)
                            .frame(height: GoingMetric.row)
                    }
                }
                .padding(.bottom, foot)
                .animation(reduceMotion ? nil : Motion.smooth, value: people)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var loadingRow: some View {
        HStack(spacing: GoingMetric.rowGap) {
            SkeletonBlock(cornerRadius: GoingMetric.rowFace * Radius.faceShare, color: ink.opacity(GoingMetric.closeFill))
                .frame(width: GoingMetric.rowFace, height: GoingMetric.rowFace)
            SkeletonBlock(cornerRadius: FriendsMetric.loadingLine / 2, color: ink.opacity(GoingMetric.closeFill))
                .frame(width: FriendsMetric.loadingName, height: FriendsMetric.loadingLine)
        }
        .padding(.horizontal, GoingMetric.inset)
        .frame(height: GoingMetric.row)
        .shimmering()
        .accessibilityHidden(true)
    }

    private func row(_ photo: URL?, _ name: String) -> some View {
        HStack(spacing: GoingMetric.rowGap) {
            Avatar(photo, size: GoingMetric.rowFace)
            Text(name)
                .font(.sansSemibold(GoingMetric.rowName))
                .foregroundStyle(ink)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, GoingMetric.inset)
        .frame(height: GoingMetric.row)
        .contentShape(Rectangle())
    }

    private var close: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.glyph(GoingMetric.closeGlyph, weight: .semibold))
                .foregroundStyle(ink)
                .frame(width: GoingMetric.close, height: GoingMetric.close)
                .contentShape(Circle())
        }
        .buttonStyle(.press(.squish))
        // Glass on the sheet's glass all but disappears, so Luma's disc and rim are drawn.
        .background(ink.opacity(GoingMetric.closeFill), in: Circle())
        .overlay { Circle().strokeBorder(ink.opacity(GoingMetric.closeRim), lineWidth: GoingMetric.closeRimWidth).allowsHitTesting(false) }
        .padding(GoingMetric.closeInset)
        .accessibilityLabel("Close")
        .accessibilitySortPriority(1)
    }
}

/// Luma's sizes (BP app `references/whos-going/SPEC.md`), and the list's, off the approved mock.
enum GoingMetric {
    static func count(_ total: Int) -> String { "\(total) going" }
    /// The section: the count, 9 to the hairline, 16 to the faces, 11 to the names.
    static let top: CGFloat = 14
    static let word: CGFloat = 16
    static let lineTop: CGFloat = 9
    static let facesTop: CGFloat = 16
    static let namesTop: CGFloat = 11
    /// 36 pt faces on a 24 pt pitch, a 2 pt gap between them.
    static let face: CGFloat = 36
    static let tuck: CGFloat = 12
    static let gap: CGFloat = 2
    static let plus: CGFloat = 13
    /// The card. iOS 26 draws a small sheet at 96%, Luma's too, so these are the sizes drawn divided by it: a 54 pt disc, a
    /// 48 pt button, 19 in. 34 under the button, the home indicator's room.
    static let inset: CGFloat = 20
    static let gate: CGFloat = 210
    static let foot: CGFloat = 20
    static let disc: CGFloat = 56
    static let discGlyph: CGFloat = 24
    static let discFill: Double = 0.08
    static let lockGlyph: CGFloat = 16
    static let lockOut: CGFloat = 5
    static let title: CGFloat = 21
    static let titleTop: CGFloat = 11
    static let wordsTop: CGFloat = 4
    static let wordsDim: Double = 0.84
    static let button: CGFloat = 50
    static let buttonTop: CGFloat = 24
    static let close: CGFloat = 46
    static let closeFill: Double = 0.1
    static let closeRim: Double = 0.22
    static let closeRimWidth: CGFloat = 0.7
    static let closeInset: CGFloat = 16
    static let closeGlyph: CGFloat = 17
    /// The list: 56 pt rows with 44 pt faces, about 540 tall at most, then it scrolls.
    static let listTop: CGFloat = 68
    static let listMost: CGFloat = 526
    static let row: CGFloat = 58
    static let rowFace: CGFloat = 46
    static let rowGap: CGFloat = 12
    static let rowName: CGFloat = 17
}
