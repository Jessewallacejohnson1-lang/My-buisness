//
//  FeedHides.swift
//  Block Party — what you took out of the Town feed: Not interested, Mute, Report and their Undo,
//  and the Muted list.
//
//  Not interested and Mute (ticket 21) take a card out at once and go to the server straight
//  away. The card folds into a "Hidden · Undo" line for 5 seconds, then goes; Undo brings it
//  back and takes the choice back. The ids and host names hidden this session stay out of
//  every list, so a read that raced the write, or a kept list, can't bring a card back.
//  `TownFeed` holds one and asks it `isHidden`; the screens call it directly.
//

import Foundation
import UIKit

@MainActor @Observable
final class FeedHides {
    /// Events and News said Not interested to and host names muted this session (ticket 21).
    private(set) var hiddenIDs: Set<String> = []
    private(set) var mutedNames: Set<String> = []
    /// The card showing "Hidden · Undo" in its place, for 5 seconds.
    private(set) var undo: FeedHide?
    /// How long the Undo line stays.
    static let undoFor: Duration = .seconds(5)
    /// The host each Mute this session muted, by name, so its Undo can unmute it.
    @ObservationIgnored private var muteKeys: [String: String] = [:]
    /// The last choice on its way: Undo waits for it, so the take-back never lands first.
    @ObservationIgnored private var sending: Task<String?, Error>?
    /// Ends the Undo line after 5 seconds, wherever the line has scrolled to.
    @ObservationIgnored private var undoTimer: Task<Void, Never>?
    /// The Muted list as the last read gave it; nil until read.
    private(set) var muted: [MutedHost]?
    private(set) var mutedFailed = false
    /// Unmutes that didn't go through, by host: the row comes back and shakes.
    private(set) var unmuteFailures: [String: Int] = [:]
    /// Cards reported from this phone this session: their sheet has no Report row.
    private(set) var reportedIDs: Set<String> = []

    /// Where Not interested, Mute and their undoing go; a Mute answers with its host.
    private let choose: (FeedChoice) async throws -> String?
    private let readMuted: () async throws -> [MutedHost]
    /// Where your own post's Delete goes (town-feed 29).
    private let deletePost: (TownPost) async throws -> Void

    init(choose: @escaping (FeedChoice) async throws -> String?,
         readMuted: @escaping () async throws -> [MutedHost],
         deletePost: @escaping (TownPost) async throws -> Void) {
        self.choose = choose
        self.readMuted = readMuted
        self.deletePost = deletePost
    }

    /// Out of the feed: said Not interested to, or its host muted. The card showing Undo stays
    /// in, drawn as its Undo line.
    func isHidden(_ card: FeedCardItem) -> Bool { isHidden(id: card.id, host: card.hostName) }

    /// An Event's card or a News post (news-menu), by its id and its host's name.
    func isHidden(id: String, host: String) -> Bool {
        guard undo?.id != id else { return false }
        return hiddenIDs.contains(id) || (!host.isEmpty && mutedNames.contains(host))
    }

    /// An Event's or a neighbour's post's report (ticket 22, town-feed 29), by its id, from its sheet,
    /// which waits for the answer to say thanks or shake. Wrong info may carry a note (backlog 26).
    func report(id: String, _ reason: ReportReason, note: String? = nil) async throws {
        _ = try await choose(.report(id, reason, note: note))
        reportedIDs.insert(id)
    }

    /// A reported card, once its sheet has closed: out, with the same Undo line as Not interested.
    /// The report already went; Undo lifts only the hide.
    func hideReported(id: String, host: String) {
        hiddenIDs.insert(id)
        showUndo(FeedHide(id: id, hostName: host, mute: false))
    }

    /// Your own post, deleted from its ••• (town-feed 29): out at once, with no Undo; one the server
    /// didn't take comes back.
    func delete(_ post: TownPost) async {
        hiddenIDs.insert(post.id)
        do {
            try await deletePost(post)
        } catch {
            Log.network("TownFeed: post not deleted: \(error)")
            hiddenIDs.remove(post.id)
            Haptics.error()
        }
    }

    private func showUndo(_ hide: FeedHide) {
        undo = hide
        undoTimer?.cancel()
        // With VoiceOver on, the line waits for Undo or the next choice: 5 seconds is too short to
        // find it by swiping.
        if !UIAccessibility.isVoiceOverRunning {
            undoTimer = Task { [weak self] in
                try? await Task.sleep(for: Self.undoFor)
                guard !Task.isCancelled else { return }
                self?.undoEnded(hide.id)
            }
        }
    }

    /// Not interested (`mute` false) or Mute on an Event's card or a News post (news-menu), by its
    /// id and its host's name: out at once, then to the server. One that doesn't go through comes
    /// back. A newer one ends the last one's Undo.
    func hide(id: String, host hostName: String, mute: Bool) async {
        if mute { mutedNames.insert(hostName) } else { hiddenIDs.insert(id) }
        showUndo(FeedHide(id: id, hostName: hostName, mute: mute))
        let choose = self.choose
        let send = Task { try await choose(mute ? .mute(id) : .notInterested(id)) }
        sending = send
        do {
            let host = try await send.value
            if mute, let host { muteKeys[hostName] = host }
            muted = nil
        } catch {
            Log.network("TownFeed: \(mute ? "Mute" : "Not interested") not sent: \(error)")
            if mute { mutedNames.remove(hostName) } else { hiddenIDs.remove(id) }
            if undo?.id == id { undo = nil }
            Haptics.error()
        }
    }

    /// Undo on the line: the card comes back, and the choice is taken back on the server.
    func undoHide() async {
        guard let hide = undo else { return }
        undo = nil
        undoTimer?.cancel()
        let earlier = sending
        if hide.mute { mutedNames.remove(hide.hostName) } else { hiddenIDs.remove(hide.id) }
        // The choice lands before it is taken back (a slow network sent both at once).
        let answer = (try? await earlier?.value) ?? nil
        if hide.mute {
            // The Mute's own answer, when its `hide` hasn't kept it yet.
            guard let host = muteKeys.removeValue(forKey: hide.hostName) ?? answer else { return }
            _ = try? await choose(.unmute(host))
            muted = nil
        } else {
            _ = try? await choose(.undoNotInterested(hide.id))
        }
    }

    /// The Undo line's 5 seconds are up: the card goes.
    func undoEnded(_ id: String) {
        if undo?.id == id { undo = nil }
    }

    /// The Muted list, read when it opens.
    func refreshMuted() async {
        do {
            muted = try await readMuted()
            mutedFailed = false
        } catch {
            Log.network("TownFeed: Muted list: \(error)")
            mutedFailed = muted == nil
        }
    }

    /// Unmute from the Muted list: off the list at once. One that doesn't go through comes back and
    /// shakes. True when it went through, so the feed reads the host's Events back
    /// (`TownFeed.unmute`).
    func unmute(_ host: MutedHost) async -> Bool {
        guard let at = muted?.firstIndex(of: host) else { return false }
        muted?.remove(at: at)
        do {
            _ = try await choose(.unmute(host.host))
            mutedNames.remove(host.name)
            return true
        } catch {
            Log.network("TownFeed: Unmute not sent: \(error)")
            let count = muted?.count ?? 0
            muted?.insert(host, at: min(at, count))
            unmuteFailures[host.host, default: 0] += 1
            Haptics.error()
            return false
        }
    }

    /// A new account: the last one's hidden cards, mutes, reports and Undo line are not this one's.
    func reset() {
        hiddenIDs = []
        reportedIDs = []
        mutedNames = []
        muteKeys = [:]
        undoTimer?.cancel()
        undo = nil
        muted = nil
    }
}

#if DEBUG
/// `-town-samples`' Muted list: a Mute keeps the host by name, an Unmute drops it.
@MainActor
final class SampleMutes {
    var list = [MutedHost(host: "sample-library", name: "St. Joe Public Library")]
    /// Each sample's host by its id, news by its place (news-menu).
    private let names = Dictionary(TownFixtures.townEntries().map { entry in
        switch entry.item {
        case .event(let card): (card.id, card.hostName)
        case .news(let news): (news.id, news.place)
        case .post(let post): (post.id, post.poster.name)
        }
    }, uniquingKeysWith: { first, _ in first })

    func choose(_ choice: FeedChoice) async throws -> String? {
        switch choice {
        case .mute(let id):
            let name = names[id] ?? id
            list.insert(MutedHost(host: name, name: name), at: 0)
            return name
        case .unmute(let host):
            list.removeAll { $0.host == host }
        case .notInterested, .undoNotInterested, .report:
            break
        }
        return nil
    }
}
#endif
