//
//  SmallLine.swift
//  Block Party — the line under an Event card's title: what it is and a short place, never cut off
//  (BP app inside-cards 07 and 11; Jesse, 2026-11-06: "i agree to all"). The app makes it as it draws
//  the card, from the place it already has, so nobody writes anything. The Event page keeps the full place.
//

import SwiftUI

/// The first of `tries` that fits on one line, and nothing when none does: a small line never cuts off.
/// With `wraps`, an accessibility text size shows the first whole, over as many lines as it takes
/// (measured 2026-09-22: at AX3 and AX5 a clipped line lost the place).
struct SmallLine: View {
    let tries: [String]
    var wraps = false
    var alignment: Alignment = .leading

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if wraps, dynamicTypeSize.isAccessibilitySize, let first = tries.first {
            Text(first).fixedSize(horizontal: false, vertical: true)
        } else {
            // It fills its width. Hugging its words, a parent could hand its measured size back a hair
            // short (139.66666666666663 of 139.66666666666666, through a padding) and `ViewThatFits`
            // would take the next try: the game card lost its town that way (2026-11-06).
            fitted.frame(maxWidth: .infinity, alignment: alignment)
                // VoiceOver hears it whole, whichever try is drawn.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tries.first ?? "")
        }
    }

    var fitted: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(tries, id: \.self) { Text($0).lineLimit(1) }
            Color.clear.frame(width: 0, height: 0)
        }
    }
}

extension FeedCardItem {
    /// The card's small line, longest first: what · place, town; what · place; place, town; place; what.
    /// The place stays over the what (Jesse's yes overrules event-card 05's long place cutting at its end).
    /// A game's special night comes before its place. With no place written, the host's name stands in,
    /// unless it's a calendar and not somewhere you can go ("CSB SJU Campus Events"). A place the title
    /// already says leaves the line when a what remains ("Sale · Heim-Kins Rescued Treasures" is "Sale").
    var smallLines: [String] {
        let lead = whatLine ?? game?.occasion ?? ""
        var (venue, town) = Self.shortPlace(whereLine)
        if venue.isEmpty, game == nil, !hostName.hasSuffix("Events") { venue = hostName }
        if !lead.isEmpty, !venue.isEmpty, Self.stems(venue).isSubset(of: Self.stems(title)) { (venue, town) = ("", "") }
        let place = town.isEmpty ? venue : "\(venue), \(town)"
        let led = lead.isEmpty ? [] : [place, venue].filter { !$0.isEmpty }.map { "\(lead) · \($0)" }
        return Self.distinct(led + (game == nil ? [] : [lead]) + [place, venue, lead])
    }

    /// The Event of the day poster's place line: the short place, with its town when that fits.
    var shortPlaces: [String] {
        let (venue, town) = Self.shortPlace(whereLine)
        return Self.distinct([town.isEmpty ? venue : "\(venue), \(town)", venue])
    }

    /// A place as a neighbour would say it: no state, not our own town, nothing after a slash, no
    /// "St. Cloud" before a high school's name and no room after a school's name. After a comma it keeps
    /// only what reads as a town or campus, a capital and at most two words, and nothing when a room came
    /// off the school's name: what follows that comma is more of the room ("Sartell High School Gym, Main").
    static func shortPlace(_ location: String?) -> (venue: String, town: String) {
        var text = (location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        func cut(_ pattern: String, with template: String = "") {
            text = text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        cut(#"[\s,]+(?:MN|Minn\.?|Minnesota)$"#)
        cut(#",\s*"# + Town.writtenName + "$")
        cut("^" + Town.writtenName + #"\s+(?=\S)"#)
        let parts = text.prefix { $0 != "/" }.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let name = parts.first else { return ("", "") }
        let town = parts.dropFirst().first { $0.first?.isUppercase == true && $0.split(separator: " ").count <= 2 }
        text = name
        cut(#"^St\. Cloud (?=\S+ High School)"#)
        let named = text
        cut(#"^(.+?\bSchool)\s+(?!of\b)\S.*$"#, with: "$1")
        return (text, text == named ? town ?? "" : "")
    }

    private static func distinct(_ lines: [String]) -> [String] {
        lines.reduce(into: []) { kept, line in
            if !line.isEmpty, !kept.contains(line) { kept.append(line) }
        }
    }
}
