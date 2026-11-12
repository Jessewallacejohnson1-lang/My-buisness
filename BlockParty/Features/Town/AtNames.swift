//
//  AtNames.swift
//  Block Party — @ names and # tags in a post's words (BP app docs/plans/town-feed, ticket 60; mock
//  https://claude.ai/artifact/RtvFQ8D5fjStBue1cVmFYp, Jesse at Check-in 1, 2026-11-11: "i agree w all").
//  Typing `@` in New post shows your friends and the town's places in a row over the keyboard, Instagram's
//  (references/business-collab/ig-mention-picker.jpg); a pick puts "@Name" in the words. Posted, each name the
//  check kept opens its page and each #tag opens Search with its word, in Instagram's link blue (`Hue.link`).
//

import SwiftUI

// MARK: - Typing @

/// A friend or a place the row offers: its name and id, and its picture.
struct AtCandidate: Identifiable, Hashable {
    enum Picture: Hashable {
        case person(String?)
        case place(SearchItem)
    }

    let name: AtName
    let picture: Picture
    var id: String { "\(name.kind.rawValue):\(name.id)" }

    /// Your friends, A to Z.
    static func friends(_ friends: [Neighbor]) -> [AtCandidate] {
        friends.filter { !$0.displayName.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            .map { AtCandidate(name: AtName(kind: .user, id: $0.userId, name: $0.displayName), picture: .person($0.avatarUrl)) }
    }

    /// The places with a page of their own (a business, food or coffee), in New post's Place order.
    static func places(_ items: [SearchItem]) -> [AtCandidate] {
        items.compactMap { item in
            guard item.opens, let id = item.placeID else { return nil }
            return AtCandidate(name: AtName(kind: .place, id: id, name: item.name), picture: .place(item))
        }
    }
}

/// The `@` being typed, from the `@` to the cursor.
nonisolated enum AtTyping {
    /// Letters after the `@` before the row gives up.
    static let longest = 30
    /// Names the row shows at most.
    static let most = 20

    /// The `@` before the cursor and what's typed after it, spaces included ("@bad h"). nil with no `@`, one right
    /// after a letter (an email), a space right after it, a line break, more than 30 letters between, or a name
    /// already picked there (the row closes on a pick, and words typed after the name don't open it again).
    static func typed(_ words: String, cursor: String.Index, picked: [AtName] = []) -> (range: Range<String.Index>, query: String)? {
        guard cursor <= words.endIndex else { return nil }
        let before = words[..<cursor]
        guard let at = before.lastIndex(of: "@") else { return nil }
        let query = before[words.index(after: at)...]
        guard query.count <= longest, !query.contains(where: \.isNewline), query.first?.isWhitespace != true else { return nil }
        if at > words.startIndex, !words[words.index(before: at)].isWhitespace { return nil }
        if picked.contains(where: { query.hasPrefix($0.name) }) { return nil }
        return (at..<cursor, String(query))
    }

    /// Friends first, then places: each whose name starts with what's typed, or has a word that does. Nothing typed
    /// yet: everyone, in that order.
    static func matches(_ query: String, friends: [AtCandidate], places: [AtCandidate]) -> [AtCandidate] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let all = friends + places
        guard !q.isEmpty else { return Array(all.prefix(most)) }
        return Array(all.filter { hit(q, $0.name.name) }.prefix(most))
    }

    private static func hit(_ q: String, _ name: String) -> Bool {
        let name = name.lowercased()
        return name.hasPrefix(q) || name.split(whereSeparator: { $0.isWhitespace || $0 == "&" || $0 == "-" }).contains { $0.hasPrefix(q) }
    }
}

// MARK: - Links in the posted words

nonisolated enum PostWords {
    enum Target: Hashable {
        case name(AtName)
        case tag(String)
    }

    struct Link: Hashable {
        let range: Range<String.Index>
        let target: Target
    }

    /// Instagram's: a `#` at the start or after a space, then letters, numbers or `_`, with a letter among them.
    static func tags(_ words: String) -> [Link] {
        var out: [Link] = []
        var i = words.startIndex
        while let hash = words[i...].firstIndex(of: "#") {
            var end = words.index(after: hash)
            while end < words.endIndex, words[end].isLetter || words[end].isNumber || words[end] == "_" { end = words.index(after: end) }
            let word = words[words.index(after: hash)..<end]
            let starts = hash == words.startIndex || words[words.index(before: hash)].isWhitespace
            if starts, word.contains(where: \.isLetter) { out.append(Link(range: hash..<end, target: .tag(String(word)))) }
            i = end > hash ? end : words.index(after: hash)
            if i >= words.endIndex { break }
        }
        return out
    }

    /// Every `@name` the post kept, wherever it sits in the words and not running on into a longer word, then every
    /// #tag, in the words' order; where two overlap the longer name wins.
    static func links(_ words: String, names: [AtName]) -> [Link] {
        var found: [Link] = []
        for name in names.sorted(by: { $0.name.count > $1.name.count }) {
            var from = words.startIndex
            while let r = words.range(of: name.typed, range: from..<words.endIndex) {
                let after = r.upperBound < words.endIndex ? words[r.upperBound] : " "
                if !(after.isLetter || after.isNumber), !found.contains(where: { $0.range.overlaps(r) }) {
                    found.append(Link(range: r, target: .name(name)))
                }
                from = r.upperBound
            }
        }
        found += tags(words).filter { tag in !found.contains { $0.range.overlaps(tag.range) } }
        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// The link a run carries: `bp-words://place/<id>`, `bp-words://user/<id>`, `bp-words://tag/<word>`.
    static func url(_ target: Target) -> URL {
        var c = URLComponents()
        c.scheme = scheme
        switch target {
        case .name(let name): c.host = name.kind.rawValue; c.path = "/" + name.id
        case .tag(let word): c.host = "tag"; c.path = "/" + word
        }
        return c.url ?? URL(string: "\(scheme)://none")!
    }

    /// What a tapped link opens; nil for anything else.
    static func target(_ url: URL, names: [AtName]) -> Target? {
        guard url.scheme == scheme, let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let value = String(c.path.dropFirst())
        guard !value.isEmpty else { return nil }
        if c.host == "tag" { return .tag(value) }
        return names.first { $0.kind.rawValue == c.host && $0.id == value }.map(Target.name)
    }

    /// The words with each link on its run; the Text's tint colours them.
    static func attributed(_ words: String, names: [AtName]) -> AttributedString {
        var text = AttributedString(words)
        for link in links(words, names: names) {
            if let r = Range(link.range, in: text) { text[r].link = url(link.target) }
        }
        return text
    }

    /// What VoiceOver's actions on the words say: "Open Sam Rivera", "Search JoeTownNights".
    static func label(_ target: Target) -> String {
        switch target {
        case .name(let name): "Open \(name.name)"
        case .tag(let word): "Search \(word)"
        }
    }

    private static let scheme = "bp-words"
}

// MARK: - The row

/// Instagram's mention row (BP app references/at-names-and-hashtags/SPEC.md, measured): 56 pt pictures 26 pt apart,
/// each name in SF 12 8.5 pt under, scrolling sideways over the bar. A friend's photo, a place's logo on white.
struct AtRow: View {
    let candidates: [AtCandidate]
    let pick: (AtCandidate) -> Void

    private enum Metric {
        static let picture: CGFloat = 56
        static let gap: CGFloat = 26
        /// Instagram's name sits 8.5 pt under its picture, ink to ink; SF 12's line starts 2.5 pt above its capitals.
        static let nameTop: CGFloat = 6
        /// A name may run 11 pt past its picture each side before it's cut, as Instagram's "bear.2123374".
        static let nameWidth: CGFloat = 78
        /// GUESSED: Instagram's row sits on a dark story, so its top can't be read.
        static let top: CGFloat = 10
        static let bottom: CGFloat = 9
        static let logo: CGFloat = 40
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Metric.gap) {
                ForEach(candidates) { candidate in
                    Button { pick(candidate) } label: { cell(candidate) }
                        .buttonStyle(.press(.squish))
                        .accessibilityLabel(candidate.name.name)
                        .accessibilityValue(candidate.name.kind == .place ? "Place" : "Friend")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, Metric.top)
            .padding(.bottom, Metric.bottom)
        }
        .scrollClipDisabled()
        .background(Hue.paper)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Names")
    }

    private func cell(_ candidate: AtCandidate) -> some View {
        VStack(spacing: Metric.nameTop) {
            picture(candidate.picture)
                .frame(width: Metric.picture, height: Metric.picture)
            Text(candidate.name.name)
                .font(.apple(12))
                .foregroundStyle(Hue.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: Metric.nameWidth)
        }
        .frame(width: Metric.picture)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func picture(_ picture: AtCandidate.Picture) -> some View {
        switch picture {
        case .person(let url):
            Avatar(avatarUrl: url, size: Metric.picture)
        case .place(let item) where item.logo == nil:
            // No logo yet: its letter disc fills the circle, as a friend's photo does.
            LetterDisc(initial: item.initial, side: Metric.picture)
        case .place(let item):
            Circle().fill(.white)
                .overlay { PlaceMark(item: item, side: Metric.logo) }
                .overlay { Circle().strokeBorder(Hue.hairline, lineWidth: 0.5) }
        }
    }
}
