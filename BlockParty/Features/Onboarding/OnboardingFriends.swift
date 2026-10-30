//
//  OnboardingFriends.swift
//  Block Party — "Find your friends" and "Friends on Block Party", onboarding's steps 9 and 10 (BP app
//  onboarding 23, mock v7): Instagram's reason before Apple's contacts prompt, then the Friends page's
//  contact check (`ContactsMatch`) as mock v7's rows. Add friend waits on the phone
//  (`OnboardingStore.requests`) and goes up once onboarding is done and the name is saved, since the
//  server refuses a request from an account with no name.
//

import SwiftUI

/// Step 9's answer under its question: the line, then the two promises rising in one after the other.
struct OnboardingFriendsReason: View {
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("See which neighbors are already here.")
                .font(.sans(15))
                .foregroundStyle(Hue.inkSecondary)
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: 24) {
                promise("arrow.triangle.2.circlepath", "Only scrambled codes leave your phone. We keep none of your contacts.")
                    .rise(shown, delay: 0.16, by: 10, duration: 0.38)
                promise("gearshape", "Turn it off any time in Settings.")
                    .rise(shown, delay: 0.23, by: 10, duration: 0.38)
            }
            .padding(.top, 32)
        }
        .onAppear { shown = true }
    }

    private func promise(_ symbol: String, _ words: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.glyph(20, weight: .medium))
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            Text(words)
                .font(.sans(15))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Hue.ink)
    }
}

/// Step 10's answer: "On Block Party" (neighbours the check found you could still add) and "Invite"
/// (everyone else with a phone number). Shimmering rows while the check is out; a line, and the Next
/// bar still going on, when it can't be made.
struct OnboardingContactsList: View {
    let model: ContactsMatch
    let requests: [String]
    let toggle: (String) -> Void

    /// Contacts Messages opened for, this visit.
    @State private var invited: Set<String> = []

    var body: some View {
        // Edge to edge, the rows back in by the 32 pt gutter, so Invite's shadow isn't cut at the side.
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 4) { rows }
                .padding(.top, 4)
                .padding(.bottom, 200)
                .padding(.horizontal, 32)
        }
        .padding(.horizontal, -32)
        // Once a visit of onboarding: back to step 9 and on again shows the same list, no check spent.
        .task { await model.load() }
    }

    @ViewBuilder private var rows: some View {
        switch model.state {
        case .asking:
            OnboardingLoadingRows(round: true)
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
            let people = onApp.filter { $0.relation == .stranger }
            if !people.isEmpty {
                section("On Block Party")
                ForEach(people) { person in
                    let on = requests.contains(person.id)
                    row(name: person.displayName, line: "In your contacts") {
                        Avatar(avatarUrl: person.avatarUrl, size: 48, outlined: true)
                    } pill: {
                        OnboardingListPill(title: on ? "Requested" : "Add friend", on: on, name: person.displayName) {
                            toggle(person.id)
                        }
                    }
                }
            }
            if !invite.isEmpty {
                section("Invite")
                ForEach(invite) { contact in
                    row(name: contact.name, line: contact.phone) {
                        ContactFace(contact: contact, size: 48)
                    } pill: {
                        invitePill(contact)
                    }
                }
            }
            if people.isEmpty, invite.isEmpty {
                line("No contacts with a phone number or email.")
            }
        }
    }

    private func invitePill(_ contact: PhoneContact) -> some View {
        let done = invited.contains(contact.id)
        return Button {
            invited.insert(contact.id)
            FriendsInvitePresenter.messages(to: contact.phone)
        } label: {
            Text(done ? "Invited" : "Invite").font(.sansSemibold(14)).lineLimit(1)
        }
        .buttonStyle(MeetupPillStyle(height: FollowMetric.rowHeight, minWidth: FollowMetric.listWidth,
                                     grey: done, sidePadding: 16))
        .accessibilityLabel("\(done ? "Invited" : "Invite") \(contact.name)")
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.sansSemibold(15))
            .foregroundStyle(Hue.ink)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, 24)
            .padding(.bottom, 8)
    }

    private func line(_ words: String) -> some View {
        Text(words)
            .font(.sans(15))
            .foregroundStyle(Hue.inkSecondary)
            .padding(.top, 24)
    }

    /// One row, the mock's (step 8's build): a 48 pt face, the name and a grey line, the pill.
    private func row<Face: View, Pill: View>(name: String, line: String?, @ViewBuilder face: () -> Face,
                                             @ViewBuilder pill: () -> Pill) -> some View {
        HStack(spacing: 12) {
            face()
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(.sansSemibold(15))
                    .foregroundStyle(Hue.ink)
                    .lineLimit(1)
                if let line {
                    Text(line)
                        .font(.sans(13))
                        .foregroundStyle(Hue.inkSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            pill()
        }
        .padding(.vertical, 8)
    }
}
