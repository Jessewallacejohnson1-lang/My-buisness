//
//  OnboardingFriends.swift
//  Block Party — "Find your friends" and "Friends on Block Party", onboarding's last two steps: the ask
//  before Apple's prompt, with Jesse's market drawing (BP app onboarding 51), then Luma's people
//  picker made simpler (onboarding 37, mock v8), over the Friends page's contact check (`ContactsMatch`). A tick waits on the
//  phone (`OnboardingStore.requests`) and goes up once onboarding is done and the name is saved, since
//  the server refuses a request from an account with no name.
//

import SwiftUI

/// Find your friends at 402 pt (BP app onboarding 51, mock v2), measured from the screen's top.
private enum AskMetric {
    /// Jesse's drawing runs full width from under the dashes down to the words (522 pt tall at 874), its
    /// foot fading out over 90 pt; 12 pt spare on each side for the drag.
    static let artTop: CGFloat = 92
    static let fade: CGFloat = 90
    static let spare: CGFloat = 12
    /// The words sit 150 pt up, 18 over the Next pill; the drawing stops 110 pt over them, its fade under their top.
    static let wordsBottom: CGFloat = 150
    static let wordsRoom: CGFloat = 110
    /// The logo at 210 pt wide.
    static let logo: CGFloat = 210 / BlockPartyWordmark.aspect
    /// A drag moves the drawing a third of the finger's way, held to 12 pt across, 10 up and 18 down.
    static let follow: CGFloat = 1 / 3
    static let reach = (across: CGFloat(12), up: CGFloat(10), down: CGFloat(18))
}

/// Step 6, in the Big art look on white (onboarding 51): Jesse's market drawing heads the step and
/// follows a drag a little; under it "Bring your friends to the" over the logo, and the line. The flow
/// lays Next and Not now under it; Apple's prompt carries the privacy words.
struct OnboardingFriendsAsk: View {
    @AccessibilityFocusState.Binding var focused: Bool

    @State private var shown = false
    @State private var pull: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // The drawing is decoration: at the accessibility text sizes it steps aside for the words.
                if !textSize.isAccessibilitySize {
                    drawing(width: geo.size.width,
                            height: geo.size.height - AskMetric.artTop - AskMetric.wordsBottom - AskMetric.wordsRoom)
                }
                words
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, FollowGridMetric.gutter)
                    .padding(.bottom, AskMetric.wordsBottom)
            }
        }
        .ignoresSafeArea(.container)
        .onAppear { shown = true }
    }

    /// Full width, top first; it rises in, follows a drag a third of the way and springs back, and its
    /// foot fades into the canvas.
    private func drawing(width: CGFloat, height: CGFloat) -> some View {
        Image(decorative: "FriendsMarket")
            .resizable()
            .scaledToFill()
            .frame(width: width + 2 * AskMetric.spare, height: max(0, height), alignment: .top)
            .offset(pull)
            .frame(width: width, height: max(0, height), alignment: .top)
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [Hue.bigArtCanvas.opacity(0), Hue.bigArtCanvas], startPoint: .top, endPoint: .bottom)
                    .frame(height: AskMetric.fade)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    // A short spring, not a jump: a grab mid spring-back carries on from where the drawing is.
                    withAnimation(reduceMotion ? nil : .interactiveSpring(response: 0.15)) { pull = CGSize(width: clamp(drag.translation.width * AskMetric.follow, -AskMetric.reach.across, AskMetric.reach.across),
                                  height: clamp(drag.translation.height * AskMetric.follow, -AskMetric.reach.up, AskMetric.reach.down)) }
                }
                .onEnded { _ in
                    withAnimation(reduceMotion ? nil : .spring(response: 0.52, dampingFraction: 0.6)) { pull = .zero }
                })
            .scaleEffect(shown || reduceMotion ? 1 : 0.97, anchor: .top)
            .offset(y: shown || reduceMotion ? 0 : 24)
            .opacity(shown ? 1 : 0)
            .animation(rise(delay: 0.06, duration: 0.62), value: shown)
            .padding(.top, AskMetric.artTop)
            .accessibilityHidden(true)
    }

    private var words: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("Bring your friends to the")
                    .appleFont(21, weight: .semibold)
                    .kerning(-0.3)
                BlockPartyWordmark(height: AskMetric.logo)
            }
            .foregroundStyle(Hue.ink)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Bring your friends to the Block Party")
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($focused)
            Text("Connect and share events with friends.")
                .font(.apple(15))
                .lineSpacing(3)
                .foregroundStyle(Hue.bigArtWords)
                .padding(.top, 10)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .offset(y: shown || reduceMotion ? 0 : 14)
        .opacity(shown ? 1 : 0)
        .animation(rise(delay: 0.24, duration: 0.46), value: shown)
    }

    private func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat { min(max(value, low), high) }

    private func rise(delay: Double, duration: Double) -> Animation {
        reduceMotion ? .easeOut(duration: 0.2) : Motion.outQuint(duration).delay(delay)
    }
}

/// Mock v8's people rows (`.crow`, `.get`).
private enum RowMetric {
    static let face: CGFloat = 40
    static let minHeight: CGFloat = 62
    static let corner: CGFloat = Radius.tile
    static let invite = CGSize(width: 72, height: 30)
}

/// Step 7, Luma's people picker made simpler: the question scrolls away with a search box and two white
/// cards. "On Block Party" (neighbours the check found you could still add): tap a row and its circle ticks;
/// the flow's one button sends every tick. "Invite to Block Party" (everyone else with a phone number):
/// iOS's small grey Invite on each row opens Messages with the invite written. Nobody here: only Invite.
struct OnboardingContactsList<Heading: View>: View {
    let model: ContactsMatch
    let requests: [String]
    let toggle: (String) -> Void
    @ViewBuilder let heading: Heading

    /// Contacts Messages opened for, this visit.
    @State private var invited: Set<String> = []
    @State private var query = ""
    /// The rows rise in once the check lands.
    @State private var shown = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            // The search pins at the scroll's top as the rest goes under it (mock v8 `.pin`, sticky), as
            // Follow 3's does.
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                heading
                // Mock v8's 16 pt and the `.pin`'s 12 over the box, outside the pin so it holds the box at the top.
                if searchable { Color.clear.frame(height: 28) }
                Section { rows } header: { if searchable { search } }
            }
            .padding(.horizontal, FollowGridMetric.gutter)
            .padding(.top, FollowGridMetric.headingTop - FollowGridMetric.scrollTop)
            .padding(.bottom, 200)
        }
        .scrollDismissesKeyboard(.immediately)
        // Once a visit of onboarding: back to Find your friends and on again shows the same list, no check spent.
        .task { await model.load() }
        .onAppear { if case .ready = model.state { shown = true } }
        .onChange(of: model.state) { _, state in if case .ready = state { shown = true } }
    }

    @ViewBuilder private var rows: some View {
        switch model.state {
        case .asking:
            OnboardingLoadingRows()
        case .off:
            line("Contacts are off.")
        case .failed:
            line("Check your connection and try again.")
            OnboardingLink(title: "Try again") { Task { await model.load(again: true) } }
                .padding(.leading, -12)
        case .limit:
            line("You've reached today's limit. Try again tomorrow.")
        case .ready(let onApp, let invite):
            // Only people you could still add: a friend, a request either way or a block isn't offered again.
            let people = onApp.filter { $0.relation == .stranger && matches($0.displayName) }
            let others = invite.filter { matches($0.name) }
            if !people.isEmpty {
                section("On Block Party")
                card(people) { index, person in personRow(person, index: index) }
            }
            if !others.isEmpty {
                section("Invite to Block Party")
                card(others) { index, contact in inviteRow(contact, index: people.count + index) }
            }
            if people.isEmpty, others.isEmpty {
                line(query.isEmpty ? "No contacts with a phone number or email." : "No contacts found")
            }
        }
    }

    /// The check found anyone, so there's someone to search for.
    private var searchable: Bool {
        guard case .ready(let onApp, let invite) = model.state else { return false }
        return !onApp.isEmpty || !invite.isEmpty
    }

    /// Mock v8's `.pin`: pinned, the box sits at the scroll's top on the canvas, 10 pt of it under the box.
    private var search: some View {
        OnboardingSearchField(prompt: "Search contacts", query: $query)
            .padding(.bottom, 10)
            .padding(.horizontal, FollowGridMetric.gutter)
            .background(Hue.onboardingCanvas)
            .padding(.horizontal, -FollowGridMetric.gutter)
    }

    private func matches(_ name: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty || name.localizedStandardContains(q)
    }

    /// A white card of rows on the canvas, a hairline between them.
    private func card<Item: Identifiable, Row: View>(_ items: [Item], @ViewBuilder row: @escaping (Int, Item) -> Row) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(index, item)
                    .overlay(alignment: .top) {
                        if index > 0 { Hue.hairline.frame(height: 1) }
                    }
            }
        }
        .background(Hue.surface)
        .clipShape(RoundedRectangle(cornerRadius: RowMetric.corner, style: .continuous))
    }

    /// Someone on Block Party: the whole row ticks them, its circle filling ink.
    private func personRow(_ person: Neighbor, index: Int) -> some View {
        let on = requests.contains(person.id)
        return Button { Haptics.light(); toggle(person.id) } label: {
            row(name: person.displayName, line: "In your contacts") {
                Avatar(avatarUrl: person.avatarUrl, size: RowMetric.face)
            } end: {
                InterestCheckCircle(on: on).padding(.leading, 4)
            }
        }
        .buttonStyle(.press(.row))
        .rise(shown, delay: 0.12 + 0.03 * Double(min(index, 11)), by: 8, duration: 0.32)
        .accessibilityLabel(person.displayName)
        .accessibilityValue(on ? "Picked" : "Not picked")
        .accessibilityHint("Sends a friend request when you tap the button below")
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("contact-row")
    }

    /// Someone to invite: iOS's small grey Invite at the end, grey "Invited" once Messages opened.
    private func inviteRow(_ contact: PhoneContact, index: Int) -> some View {
        let done = invited.contains(contact.id)
        return row(name: contact.name, line: contact.phone) {
            ContactFace(contact: contact, size: RowMetric.face)
        } end: {
            Button {
                invited.insert(contact.id)
                FriendsInvitePresenter.messages(to: contact.phone)
            } label: {
                Text(done ? "Invited" : "Invite")
                    .font(.apple(14, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(done ? Hue.inkSecondary : Hue.ink)
                    .padding(.horizontal, done ? 4 : 14)
                    .frame(minWidth: done ? 0 : RowMetric.invite.width, minHeight: RowMetric.invite.height)
                    .background(Capsule().fill(Hue.inviteGet).opacity(done ? 0 : 1))
                    // Drawn 30 pt, 44 pt to the finger.
                    .contentShape(Capsule().inset(by: (RowMetric.invite.height - PageMetric.tapMin) / 2))
            }
            .buttonStyle(.press(.squish))
            .accessibilityLabel("\(done ? "Invited" : "Invite") \(contact.name)")
        }
        .rise(shown, delay: 0.12 + 0.03 * Double(min(index, 11)), by: 8, duration: 0.32)
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.apple(13))
            .foregroundStyle(Hue.inkSecondary)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, 24)
            .padding(.leading, 4)
            .padding(.bottom, 8)
    }

    private func line(_ words: String) -> some View {
        Text(words)
            .font(.apple(15))
            .foregroundStyle(Hue.inkSecondary)
            .padding(.top, 24)
    }

    /// One row, the mock's: a 40 pt face, the name over a grey line, what's at the end.
    private func row<Face: View, End: View>(name: String, line: String?, @ViewBuilder face: () -> Face,
                                            @ViewBuilder end: () -> End) -> some View {
        HStack(spacing: 12) {
            face()
            VStack(alignment: .leading, spacing: 0) {
                // Wrapping, so large text grows the row rather than cutting the name.
                Text(name)
                    .font(.apple(15, weight: .semibold))
                    .foregroundStyle(Hue.ink)
                if let line {
                    Text(line)
                        .font(.apple(13))
                        .foregroundStyle(Hue.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            end()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: RowMetric.minHeight)
        .contentShape(Rectangle())
    }
}
