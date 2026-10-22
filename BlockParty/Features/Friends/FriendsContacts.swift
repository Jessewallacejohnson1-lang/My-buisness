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
struct PhoneContact: Identifiable, Equatable {
    let id: String
    let name: String
    /// The first phone number, as typed: who Invite writes to. Nil: not on the Invite list.
    let phone: String?
    let thumbnail: Data?
    /// The scrambled codes of every email and phone number on the card.
    let codes: Set<String>

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

    /// The emails' codes, then the phones', A to Z by contact, cut at `cap`.
    static func payload(_ contacts: [PhoneContact], emails: (PhoneContact) -> [String],
                        phones: (PhoneContact) -> [String]) -> (emails: [String], phones: [String]) {
        var e: [String] = [], p: [String] = []
        for c in contacts {
            for code in emails(c) where e.count + p.count < cap { e.append(code) }
            for code in phones(c) where e.count + p.count < cap { p.append(code) }
        }
        return (e, p)
    }

    /// Invite: contacts with a phone number whose codes found nobody, A to Z.
    static func invite(_ contacts: [PhoneContact], matched: Set<String>) -> [PhoneContact] {
        contacts.filter { $0.phone != nil && $0.codes.isDisjoint(with: matched) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
    private let match: ([String], [String]) async throws -> [(code: String, neighbor: Neighbor)]

    init(match: @escaping ([String], [String]) async throws -> [(code: String, neighbor: Neighbor)] = {
        try await CommunityAPI(auth: AuthStore.shared).matchContacts(emails: $0, phones: $1)
    }) {
        self.match = match
    }

    func load() async {
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
        let read = await Task.detached { Self.read(store) }.value
        await show(read.contacts, emails: read.emails, phones: read.phones)
    }

    /// Asks the server and splits the contacts. Apart from `load` so tests drive it with contacts.
    func show(_ contacts: [PhoneContact], emails: [String: [String]], phones: [String: [String]]) async {
        let sorted = contacts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let send = ContactCodes.payload(sorted, emails: { emails[$0.id] ?? [] }, phones: { phones[$0.id] ?? [] })
        do {
            let found = send.emails.isEmpty && send.phones.isEmpty ? [] : try await match(send.emails, send.phones)
            state = .ready(onApp: found.map(\.neighbor),
                           invite: ContactCodes.invite(sorted, matched: Set(found.map(\.code))))
        } catch let error as SupabaseError where error.message == "contacts_limit" {
            state = .limit
        } catch {
            state = .failed
        }
    }

    /// Every contact with a name, its codes by kind kept apart so emails go before phones.
    nonisolated private static func read(_ store: CNContactStore)
        -> (contacts: [PhoneContact], emails: [String: [String]], phones: [String: [String]]) {
        let keys: [CNKeyDescriptor] = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                                       CNContactPhoneNumbersKey as CNKeyDescriptor,
                                       CNContactEmailAddressesKey as CNKeyDescriptor,
                                       CNContactThumbnailImageDataKey as CNKeyDescriptor]
        var contacts: [PhoneContact] = [], emails: [String: [String]] = [:], phones: [String: [String]] = [:]
        try? store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { c, _ in
            guard let name = CNContactFormatter.string(from: c, style: .fullName), !name.isEmpty else { return }
            let e = c.emailAddresses.compactMap { ContactCodes.email($0.value as String) }
            let p = c.phoneNumbers.compactMap { ContactCodes.phone($0.value.stringValue) }
            emails[c.identifier] = e
            phones[c.identifier] = p
            contacts.append(PhoneContact(id: c.identifier, name: name, phone: c.phoneNumbers.first?.value.stringValue,
                                         thumbnail: c.thumbnailImageData, codes: Set(e + p)))
        }
        return (contacts, emails, phones)
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
                Task { await model.load() }
            }
        case .limit:
            ContactsNote(title: nil, line: "You've checked your contacts 5 times today. Try again tomorrow.",
                         button: nil) {}
        case .ready(let onApp, let invite):
            promise
            let shown = book.visible(.found(onApp))
            if case .found(let people) = shown, !people.isEmpty {
                ContactsSectionTitle(text: "On Block Party")
                ForEach(people) { ResultRow(person: $0) { signingIn = true } }
            }
            if !invite.isEmpty {
                ContactsSectionTitle(text: "Invite")
                ForEach(invite) { InviteRow(contact: $0) }
            }
            if onApp.isEmpty, invite.isEmpty {
                ContactsNote(title: nil, line: "No contacts with a phone number or email.", button: nil) {}
            }
        }
    }

    /// Read first, under the bar.
    private var promise: some View {
        Label("Only scrambled emails leave your phone.", systemImage: "lock.fill")
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
            Group {
                if let data = contact.thumbnail, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Text(contact.initials)
                        .font(.sansSemibold(20))
                        .foregroundStyle(Hue.inkSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Hue.fill)
                }
            }
            .frame(width: FriendsMetric.neighborFace, height: FriendsMetric.neighborFace)
            .clipShape(Circle())
            .accessibilityHidden(true)
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

/// Off, failed, limit or nothing to show: a line, and a button when there's something to do.
private struct ContactsNote: View {
    let title: String?
    let line: String
    let button: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let title {
                Image(systemName: "person.text.rectangle")
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
