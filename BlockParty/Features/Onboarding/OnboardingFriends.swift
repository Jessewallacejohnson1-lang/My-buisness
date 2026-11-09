//
//  OnboardingFriends.swift
//  Block Party — "Find your friends" and "Friends on Block Party", onboarding's last two steps, in Luma's
//  look (BP app onboarding 37, mock v8): Luma's contacts ask before Apple's prompt, then Luma's people
//  picker made simpler, over the Friends page's contact check (`ContactsMatch`). A tick waits on the
//  phone (`OnboardingStore.requests`) and goes up once onboarding is done and the name is saved, since
//  the server refuses a request from an account with no name.
//

import SwiftUI

/// Mock v8's Find your friends at 402 pt, measured from the screen's top.
private enum AskMetric {
    static let face: CGFloat = 114
    /// The faces' rows start under the back chevron and progress line, 22 pt apart, 56 pt in from each side.
    static let facesTop: CGFloat = 104
    static let faceGap: CGFloat = 22
    static let faceSide: CGFloat = 56
    /// The privacy note, then the white sheet.
    static let noteTop: CGFloat = 396
    static let sheetTop: CGFloat = 462
    static let side: CGFloat = 36
    static let sheetPad: CGFloat = 30
    /// What the sheet's words keep clear at the bottom: the Next pill's 84 pt, its 48 and 16 more.
    static let clear: CGFloat = 84 + OnboardingNextBar.height + 16
}

/// Step 6, Luma's contacts ask: three big glowing faces on the grey canvas, a short note on privacy, then
/// a white sheet with the question. The flow lays its white Next pill and Not now over the sheet.
struct OnboardingFriendsAsk: View {
    @AccessibilityFocusState.Binding var focused: Bool

    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // The faces are decoration: at the accessibility text sizes they step aside, so the
                    // question isn't pushed under the Next pill.
                    if textSize.isAccessibilitySize {
                        Color.clear.frame(height: AskMetric.facesTop)
                    } else {
                        faces
                            .frame(maxWidth: .infinity, minHeight: AskMetric.noteTop, alignment: .top)
                    }
                    note
                        .frame(maxWidth: .infinity, minHeight: AskMetric.sheetTop - AskMetric.noteTop, alignment: .topLeading)
                        // The canvas over the white that sits behind for a bounce, as large text pushes the sheet down.
                        .background(Hue.onboardingCanvas)
                    sheet
                        .frame(maxWidth: .infinity, minHeight: geo.size.height - AskMetric.sheetTop, alignment: .topLeading)
                        .background(Hue.surface)
                        .offset(y: shown || reduceMotion ? 0 : 40)
                        .opacity(shown ? 1 : 0)
                        .animation(rise(delay: 0.2, duration: 0.46), value: shown)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            // White under the sheet when it bounces, as Luma's sheet runs off the bottom.
            .background(alignment: .bottom) {
                Hue.surface.frame(height: max(0, geo.size.height - AskMetric.sheetTop))
            }
        }
        .ignoresSafeArea(.container)
        .onAppear { shown = true }
    }

    /// Two faces across, one under the left: graphite, then periwinkle.
    private var faces: some View {
        VStack(spacing: AskMetric.faceGap) {
            HStack {
                face(0, graphite: true)
                Spacer(minLength: 0)
                face(1, graphite: false)
            }
            HStack {
                face(2, graphite: false)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, AskMetric.faceSide)
        .padding(.top, AskMetric.facesTop)
        .accessibilityHidden(true)
    }

    /// A face lit from the top with a soft glow under it, popping in .6 to 104% and settling, 90 ms after the
    /// one before. Nobody's contacts are read before Apple's prompt, so each holds a person, not letters.
    private func face(_ index: Int, graphite: Bool) -> some View {
        let top = graphite ? Hue.friendsFaceGraphiteTop : Hue.friendsFaceLilacTop
        let bottom = graphite ? Hue.friendsFaceGraphite : Hue.friendsFaceLilac
        // The mock's `radial-gradient(circle at 50% 22%, top, bottom 78%)`: out to the far corner, 106 pt.
        let reach = (pow(AskMetric.face / 2, 2) + pow(AskMetric.face * 0.78, 2)).squareRoot()
        return Image(systemName: "person.fill")
            .font(.glyph(46, weight: .medium))
            .foregroundStyle(Color.white)
            .frame(width: AskMetric.face, height: AskMetric.face)
            .background {
                Circle()
                    .fill(RadialGradient(stops: [.init(color: top, location: 0), .init(color: bottom, location: graphite ? 0.78 : 0.8)],
                                         center: UnitPoint(x: 0.5, y: 0.22), startRadius: 0, endRadius: reach))
                    .shadow(color: graphite ? Hue.ink.opacity(0.45) : Hue.friendsFaceGlow.opacity(0.6),
                            radius: graphite ? 10 : 12, y: 14)
            }
            .scaleEffect(shown || reduceMotion ? 1 : 0.6)
            .opacity(shown ? 1 : 0)
            .animation(reduceMotion ? .easeOut(duration: 0.2)
                       : .spring(response: 0.46, dampingFraction: 0.66).delay(0.08 + 0.09 * Double(index)), value: shown)
    }

    private var note: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your contacts stay yours.")
                .font(.apple(15, weight: .semibold))
                .foregroundStyle(Hue.ink)
            Text("Only scrambled codes leave your phone. We keep none of your contacts.")
                .font(.apple(13))
                .foregroundStyle(Hue.inkSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, AskMetric.side)
        .accessibilityElement(children: .combine)
    }

    /// The question in Luma's sheet: 22 pt semibold, then the line in 19 pt grey.
    private var sheet: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(OnboardingStep.friends.question)
                .appleFont(22, weight: .semibold)
                .kerning(-0.22)
                .foregroundStyle(Hue.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focused)
            Text("See which neighbors are already here. You can turn it off any time in Settings.")
                .font(.apple(19))
                .lineSpacing(3)
                .foregroundStyle(Hue.inkSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, AskMetric.side)
        .padding(.top, AskMetric.sheetPad)
        .padding(.bottom, AskMetric.clear)
    }

    private func rise(delay: Double, duration: Double) -> Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .timingCurve(0.22, 1, 0.36, 1, duration: duration).delay(delay)
    }
}

/// Mock v8's people rows (`.crow`, `.get`).
private enum RowMetric {
    static let face: CGFloat = 40
    static let minHeight: CGFloat = 62
    static let corner: CGFloat = 16
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
            VStack(alignment: .leading, spacing: 0) {
                heading
                rows
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
            if !onApp.isEmpty || !invite.isEmpty {
                OnboardingSearchField(prompt: "Search contacts", query: $query)
            }
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
            face(name: person.displayName, line: "In your contacts") {
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
        return face(name: contact.name, line: contact.phone) {
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
    private func face<Face: View, End: View>(name: String, line: String?, @ViewBuilder face: () -> Face,
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
