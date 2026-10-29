//
//  FriendsContacts.swift
//  Block Party — Contacts on the Friends page (BP app docs/plans/friends, ticket 06). Pushed from the
//  ways-in card; only then does iPhone ask for contacts. Then "On Block Party" (neighbours whose
//  email, or a phone number a text code checked, is in your contacts, with the search row's buttons)
//  and "Invite" (everyone else with a phone number: Messages to them, with the invite filled in, for
//  you to send). Approved mock: https://claude.ai/artifact/5bBLpExQgLNkQvdLNLFJFP
//
//  Only scrambled codes leave the phone (`ContactCodes`); names, numbers and photos never do. The
//  server keeps none of them (`match_contacts`, which counts 5 checks a day).
//

import Contacts
import CryptoKit
import SwiftUI
import UIKit

/// One contact as the page needs it, read on the phone.
nonisolated struct PhoneContact: Identifiable, Equatable {
    let id: String
    let name: String
    /// The first phone number, as typed: who Invite writes to. Nil: not on the Invite list.
    let phone: String?
    let thumbnail: Data?
    /// The scrambled codes of the card's emails and phone numbers (`ContactCodes`).
    var emailCodes: [String] = []
    var phoneCodes: [String] = []

    var codes: Set<String> { Set(emailCodes + phoneCodes) }

    var initials: String {
        String(name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
    }
}

/// What leaves the phone: SHA-256 (hex) of each email lower-cased and trimmed, and of each phone
/// number's digits with the country code, a 10-digit US number taking a leading 1. The server
/// scrambles accounts the same way (`match_contacts`).
nonisolated enum ContactCodes {
    /// At most this many codes in one check; the server refuses more.
    static let cap = 2000

    static func email(_ address: String) -> String? {
        let clean = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return clean.contains("@") ? hash(clean) : nil
    }

    static func phone(_ number: String) -> String? {
        var digits = number.filter(\.isASCII).filter(\.isNumber)
        if digits.count == 10 { digits = "1" + digits }
        return digits.count >= 8 ? hash(digits) : nil
    }

    private static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The emails' codes, then the phones', contact by contact in the order given, cut at `cap`.
    static func payload(_ contacts: [PhoneContact]) -> (emails: [String], phones: [String]) {
        var e: [String] = [], p: [String] = []
        for c in contacts {
            for code in c.emailCodes where e.count + p.count < cap { e.append(code) }
            for code in c.phoneCodes where e.count + p.count < cap { p.append(code) }
        }
        return (e, p)
    }

    /// Invite: contacts with a phone number whose codes found nobody, A to Z, a number saved twice
    /// listed once (the review: two "Kate Lieser" cards).
    static func invite(_ contacts: [PhoneContact], matched: Set<String>) -> [PhoneContact] {
        var seen = Set<String>()
        return contacts.filter { $0.phone != nil && $0.codes.isDisjoint(with: matched) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .filter { seen.insert($0.phoneCodes.first ?? $0.id).inserted }
    }
}

@MainActor @Observable
final class ContactsMatch {
    enum State: Equatable {
        case asking
        /// Said no, or not allowed: the line and Allow in Settings.
        case off
        case failed
        /// The 6th check today.
        case limit
        case ready(onApp: [Neighbor], invite: [PhoneContact])
    }

    private(set) var state = State.asking
    /// Checked once a visit: back from a neighbour's page, the list stays as it was and no check
    /// is spent (the review: five profiles opened used up the day's five).
    private var started = false
    private let match: ([String], [String]) async throws -> [(code: String, neighbor: Neighbor)]

    init(match: @escaping ([String], [String]) async throws -> [(code: String, neighbor: Neighbor)] = {
        try await CommunityAPI(auth: AuthStore.shared).matchContacts(emails: $0, phones: $1)
    }) {
        self.match = match
    }

    func load(again: Bool = false) async {
        guard again || !started else { return }
        started = true
        state = .asking
        let store = CNContactStore()
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined:
            guard (try? await store.requestAccess(for: .contacts)) == true else { state = .off; return }
        case .denied, .restricted:
            state = .off; return
        default:
            break
        }
        let contacts = await Task.detached { Self.read(store) }.value
        await show(contacts)
    }

    /// Asks the server and splits the contacts. Apart from `load` so tests drive it with contacts.
    func show(_ contacts: [PhoneContact]) async {
        let sorted = contacts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let send = ContactCodes.payload(sorted)
        do {
            let found = send.emails.isEmpty && send.phones.isEmpty ? [] : try await match(send.emails, send.phones)
            state = .ready(onApp: found.map(\.neighbor),
                           invite: ContactCodes.invite(sorted, matched: Set(found.map(\.code))))
        } catch let error as SupabaseError where error.message == "contacts_limit" {
            state = .limit
        } catch {
            // Left mid-check (Back on onboarding's Contacts, or off the Friends page): not a failure, so
            // the next visit checks again rather than saying the connection failed.
            if Task.isCancelled { started = false; return }
            state = .failed
        }
    }

    /// Contacts on Block Party who joined since a time, newest first, for the hello pill
    /// (hello-drop 04). Only with Contacts already allowed (it never asks) and a real account; it
    /// spends one of the day's 5 checks. nil when it can't check.
    static func joined(since: Date) async -> [Neighbor]? {
        guard AuthStore.shared.isSignedIn, !AuthStore.shared.isAnonymous else { return nil }
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined, .denied, .restricted: return nil
        default: break
        }
        let store = CNContactStore()
        let contacts = await Task.detached { Self.read(store, photos: false) }.value
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        // ponytail: the server sends at most 200 matches, A to Z, from 2000 codes, so in a very
        // big book a newcomer late in the alphabet can be missed. Sort by join date server-side if so.
        let send = ContactCodes.payload(contacts)
        guard !(send.emails.isEmpty && send.phones.isEmpty),
              let found = try? await CommunityAPI(auth: AuthStore.shared).matchContacts(emails: send.emails, phones: send.phones)
        else { return nil }
        return newcomers(found.map(\.neighbor), since: since)
    }

    /// Who the pill may name: someone you could still add (not a friend, a request either way, or
    /// blocked) with a name, who joined after `since`, newest first. An unreadable join date is not new.
    nonisolated static func newcomers(_ people: [Neighbor], since: Date) -> [Neighbor] {
        let joined = { (n: Neighbor) in DateHelpers.timestamp(n.since) ?? .distantPast }
        return people.filter {
            $0.relation == .stranger && !$0.displayName.trimmingCharacters(in: .whitespaces).isEmpty && joined($0) > since
        }.sorted { joined($0) > joined($1) }
    }

    /// Every contact with a name, and its codes; `photos` false skips the thumbnails.
    nonisolated private static func read(_ store: CNContactStore, photos: Bool = true) -> [PhoneContact] {
        var keys: [CNKeyDescriptor] = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                                       CNContactPhoneNumbersKey as CNKeyDescriptor,
                                       CNContactEmailAddressesKey as CNKeyDescriptor]
        if photos { keys.append(CNContactThumbnailImageDataKey as CNKeyDescriptor) }
        var contacts: [PhoneContact] = []
        try? store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { c, _ in
            guard let name = CNContactFormatter.string(from: c, style: .fullName), !name.isEmpty else { return }
            contacts.append(PhoneContact(id: c.identifier, name: name, phone: c.phoneNumbers.first?.value.stringValue,
                                         thumbnail: photos ? c.thumbnailImageData : nil,
                                         emailCodes: c.emailAddresses.compactMap { ContactCodes.email($0.value as String) },
                                         phoneCodes: c.phoneNumbers.compactMap { ContactCodes.phone($0.value.stringValue) }))
        }
        return contacts
    }
}

struct FriendsContactsPage: View {
    @State private var model = ContactsMatch()
    @State private var signingIn = false
    @Environment(FriendsBook.self) private var book
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack(alignment: .top) {
            Hue.paper.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) { content }
                    .padding(.top, SearchMetric.pageBar)
            }
            FriendsTitleBar(title: "Contacts", titleUnder: true).accessibilitySortPriority(1)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.load() }
        .signInSheet(isPresented: $signingIn)
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .asking:
            promise
            LoadingContactRows()
        case .off:
            ContactsNote(title: "Contacts are off",
                         line: "Allow Block Party to see your contacts to find neighbors you already know.",
                         button: "Allow in Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        case .failed:
            ContactsNote(title: nil, line: "Check your connection and try again.", button: "Try again") {
                Task { await model.load(again: true) }
            }
        case .limit:
            ContactsNote(title: nil, line: "You've reached today's limit. Try again tomorrow.")
        case .ready(let onApp, let invite):
            promise
            // Less anyone you just blocked.
            let people: [Neighbor] = if case .found(let people) = book.visible(.found(onApp)) { people } else { [] }
            if !people.isEmpty {
                ContactsSectionTitle(text: "On Block Party")
                ForEach(people) { ResultRow(person: $0) { signingIn = true } }
            }
            if !invite.isEmpty {
                ContactsSectionTitle(text: "Invite")
                ForEach(invite) { InviteRow(contact: $0) }
            }
            if people.isEmpty, invite.isEmpty {
                ContactsNote(title: nil, line: "No contacts with a phone number or email.")
            }
        }
    }

    /// Read first, under the bar.
    private var promise: some View {
        Label("Only scrambled emails and numbers leave your phone.", systemImage: "lock.fill")
            .font(.sans(13))
            .foregroundStyle(Hue.inkSecondary)
            .frame(maxWidth: .infinity)
            .padding(.top, FriendsMetric.contactsPromiseTop)
    }
}

extension FriendsMetric {
    static let contactsPromiseTop: CGFloat = 6
    static let contactsNoteTop: CGFloat = 120
    static let invitePill: CGFloat = 32
    static let invitePillWidth: CGFloat = 96
}

private struct ContactsSectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.sansBold(20))
            .foregroundStyle(Hue.ink)
            .padding(.horizontal, FriendsMetric.side)
            .padding(.top, FriendsMetric.sectionTop)
            .padding(.bottom, FriendsMetric.sectionBottom)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A contact not on Block Party: their photo or initials, the name, and Invite.
private struct InviteRow: View {
    let contact: PhoneContact

    var body: some View {
        HStack(spacing: FriendsMetric.avatarGap) {
            ContactFace(contact: contact, size: FriendsMetric.neighborFace)
            Text(contact.name)
                .font(.sansSemibold(17))
                .foregroundStyle(Hue.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("Invite") { FriendsInvitePresenter.messages(to: contact.phone) }
                .font(.sansSemibold(15))
                .foregroundStyle(Hue.ink)
                .frame(minWidth: FriendsMetric.invitePillWidth, minHeight: FriendsMetric.invitePill)
                .background(Capsule().fill(Hue.fill))
                .contentShape(Capsule().inset(by: -6))
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Invite \(contact.name)")
        }
        .padding(.horizontal, FriendsMetric.side)
        .frame(height: FriendsMetric.row)
    }
}

/// A contact's own photo, or their initials on the light fill, round. Onboarding's Contacts draws it too.
struct ContactFace: View {
    let contact: PhoneContact
    let size: CGFloat

    var body: some View {
        Group {
            if let data = contact.thumbnail, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(contact.initials)
                    .font(.sansSemibold(size / 3))
                    .foregroundStyle(Hue.inkSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Hue.fill)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// Off, failed, limit or nothing to show: a line, and a button when there's something to do.
/// A note in place of a list: a glyph and a title when something is off, a line, and a button.
/// The scanner's camera notes use it too (friends 07).
struct ContactsNote: View {
    var glyph = "person.text.rectangle"
    let title: String?
    let line: String
    var button: String?
    var action: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            if let title {
                Image(systemName: glyph)
                    .font(.glyph(26, weight: .medium))
                    .foregroundStyle(Hue.ink)
                    .frame(width: FriendsMetric.ghost, height: FriendsMetric.ghost)
                    .background(Circle().fill(Hue.fill))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.sansBold(20))
                    .foregroundStyle(Hue.ink)
                    .padding(.top, FriendsMetric.emptyTitleTop)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(line)
                .font(.sans(15))
                .foregroundStyle(Hue.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, title == nil ? 0 : FriendsMetric.emptyLineTop)
            if let button {
                Button(action: action) {
                    Text(button)
                        .font(.sansSemibold(17))
                        .foregroundStyle(Hue.surface)
                        .frame(maxWidth: .infinity)
                        .frame(height: FriendsMetric.invite)
                        .background(Capsule().fill(Hue.ink))
                }
                .buttonStyle(PressableStyle())
                .padding(.top, FriendsMetric.inviteTop)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, FriendsMetric.inviteSide)
        .padding(.top, title == nil ? FriendsMetric.emptyTop : FriendsMetric.contactsNoteTop)
    }
}

/// Grey rows that shimmer while the contacts are checked.
private struct LoadingContactRows: View {
    var body: some View {
        ForEach(0..<FriendsMetric.loadingRows, id: \.self) { _ in
            HStack(spacing: FriendsMetric.avatarGap) {
                SkeletonBlock(cornerRadius: FriendsMetric.neighborFace / 2)
                    .frame(width: FriendsMetric.neighborFace, height: FriendsMetric.neighborFace)
                SkeletonBlock(cornerRadius: FriendsMetric.loadingLine / 2)
                    .frame(width: FriendsMetric.loadingName, height: FriendsMetric.loadingLine)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, FriendsMetric.side)
            .frame(height: FriendsMetric.row)
            .shimmering()
            .accessibilityHidden(true)
        }
    }
}
