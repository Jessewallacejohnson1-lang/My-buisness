//
//  TownSearch.swift
//  Block Party — how well typed words match a Search row (`SearchModel.results`).
//
//  You don't have to type the exact name: a row's keywords count as aliases, a word
//  start or prefix counts ("coff" → coffee), a plural counts ("bars" → bar), an
//  apostrophe or a missing space doesn't matter ("sals", "kwiktrip"), "&" reads as "and",
//  and a small typo counts ("cofee", "millstreem"). `score` ranks exact name › name
//  prefix › whole word › alias › every word found › found only with a typo, so the
//  closest thing sits on top; a typo's band sits under `typoCeiling`, so a caller can
//  drop typos when something matched without one (BP app search-helpful 02).
//
//  Pure, synchronous and local: no network.
//

import Foundation

enum TownSearch {
    /// Every score a match made only with a typo sits under this; every other match above it.
    static let typoCeiling = 300.0

    /// A relevance score for `query` against an entity, or nil for no match.
    /// Bands, high → low: exact name, the name typed without its spaces, another name typed whole,
    /// name prefix, the start of the name typed without spaces, every word in the name, every word in
    /// another name, every word found somewhere (AND semantics), then the same with a typo.
    static func score(_ query: String, name: String, extra: [String] = [], aliases: [String] = []) -> Double? {
        guard query.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }   // "&" alone finds nothing
        let q = norm(query)
        guard !q.isEmpty else { return nil }

        let nn = norm(name)
        if nn == q { return 1000 }
        let (cq, cn) = (compact(q), compact(nn))
        if cq.count >= 4 && cn == cq { return 990 }   // "kwiktrip" is Kwik Trip
        // Another name typed whole ("csb", "st bens") beats the start of a longer name; so does a kind typed whole
        // ("bar" finds the bars before The Barn).
        for a in aliases {
            let an = norm(a)
            if an.isEmpty { continue }
            // The same kind typed whole: a name that says it too goes first ("coffee": Caribou Coffee).
            if singulars(q).contains(an) || (cq.count >= 4 && compact(an) == cq) { return says(q, nn) ? 955 : 950 }
        }
        if nn.hasPrefix(q) { return 900 - Double(min(nn.count, 60)) }   // shorter, tighter names first
        if cq.count >= 4 && cn.hasPrefix(cq) { return 850 }
        if aliasHit(q, nn) { return says(q, nn) ? 800 : 790 }   // word-boundary, so "art" ≠ "heart"; "market" finds Meat Market before Curtis Marketing

        for a in aliases {
            let an = norm(a)
            if !an.isEmpty && aliasHit(q, an) { return 720 }   // token-boundary, not mid-word substring
        }

        // Every query word must land on some word of the row; the band says whether one needed a typo.
        let hayTokens = tokenize(([name] + extra + aliases).joined(separator: " "))
        guard !hayTokens.isEmpty else { return nil }
        let qTokens = queryTokens(q)
        guard !qTokens.isEmpty else { return nil }

        var total = 0.0
        var typo = false
        for qt in qTokens {
            guard let best = bestTokenScore(qt, hayTokens) else { return nil }
            total += best
            if best < typoMax + 1 { typo = true }
        }
        return (typo ? 200 : 400) + total / Double(qTokens.count)
    }

    /// Whether every word typed is a whole word of the name, plurals included.
    private static func says(_ normedQuery: String, _ normedName: String) -> Bool {
        let words = tokenize(normedName)
        return queryTokens(normedQuery).allSatisfy { singulars($0).contains { words.contains($0) } }
    }

    /// The most a word found only with a typo scores (one wrong letter).
    private static let typoMax = 38.0

    /// Best match strength of one query word against a bag of field words.
    private static func bestTokenScore(_ q: String, _ tokens: [String]) -> Double? {
        let forms = singulars(q)
        var best: Double? = nil
        for t in tokens {
            var s: Double? = nil
            if forms.contains(t) {
                s = 100
            } else if forms.contains(where: { ($0 == q || $0.count >= 5) && t.hasPrefix($0) }) {
                s = 80                                   // typeahead: "co" → "coffee", "clothes" → "clothing"
            } else {
                // No mid-word substring (that let "art" match "party"); only a bounded typo: one wrong
                // letter up to 7 letters, two from 8 ("hiking" is not "diving", "meeting" not "heating").
                let allow = q.count >= 8 ? 2 : (q.count >= 4 ? 1 : 0)
                if allow > 0 && abs(q.count - t.count) <= allow {
                    let d = levenshtein(q, t)
                    if d <= allow { s = 50 - Double(d) * 12 }
                }
            }
            if let s, best == nil || s > best! { best = s }
        }
        return best
    }

    // MARK: Text primitives

    /// Lowercased, diacritic-folded, apostrophes out, "&" as "and", trimmed — the canonical form
    /// everything compares in ("Café" == "cafe", "Sal's" == "sals", "Milk & Honey" == "milk and honey").
    private static func norm(_ s: String) -> String {
        if let hit = normed[s] { return hit }
        let out = s.folding(options: [.diacriticInsensitive], locale: nil)
            .lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .filter { !apostrophes.contains($0) }
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        normed[s] = out
        return out
    }

    // Search scores ~1,000 rows on every letter typed and folding a string is the slow part, so each string is
    // folded once. ponytail: grows with every name and word typed this launch (a few thousand short strings);
    // clear it on a memory warning if that ever matters.
    private static var normed: [String: String] = [:]
    private static var tokens: [String: [String]] = [:]

    private static let apostrophes: Set<Character> = ["'", "’", "`"]

    /// Only the letters and digits: the words typed with their spaces missing.
    private static func compact(_ normed: String) -> String {
        normed.filter { $0.isLetter || $0.isNumber }
    }

    /// A row's words: each word with its apostrophe dropped ("sals"), and its parts too ("sal", "s"),
    /// so a name is found typed either way.
    private static func tokenize(_ s: String) -> [String] {
        if let hit = tokens[s] { return hit }
        let folded = s.folding(options: [.diacriticInsensitive], locale: nil).lowercased()
            .replacingOccurrences(of: "&", with: " and ")
        var out: [String] = []
        for word in folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber && !apostrophes.contains($0) }) {
            let joined = String(word.filter { !apostrophes.contains($0) })
            if !joined.isEmpty { out.append(joined) }
            let parts = word.split(whereSeparator: { apostrophes.contains($0) })
            if parts.count > 1 { out += parts.map(String.init) }
        }
        tokens[s] = out
        return out
    }

    /// The words typed, less "and" unless it is all there is ("milk and honey" finds Milk & Honey).
    private static func queryTokens(_ normed: String) -> [String] {
        let words = normed.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let kept = words.filter { $0 != "and" }
        return kept.isEmpty ? words : kept
    }

    /// A word and the singular forms it may be the plural of: "bars" bar, "churches" church,
    /// "groceries" grocery, but never "jones" jon. Short words stay as they are ("bus"). A singular under 5 letters counts
    /// only whole: "sals" is not the start of "sale", but "clothes" starts "clothing".
    private static func singulars(_ w: String) -> [String] {
        var forms = [w]
        if w.count >= 5, w.hasSuffix("ies") { forms.append(String(w.dropLast(3)) + "y") }
        if w.count >= 5, ["ses", "xes", "zes", "ches", "shes", "thes"].contains(where: w.hasSuffix) { forms.append(String(w.dropLast(2))) }
        if w.count >= 4, w.hasSuffix("s"), !w.hasSuffix("ss") { forms.append(String(w.dropLast())) }
        return forms
    }

    /// Whole-word relation between a query and an alias/keyword: every query word must prefix-match
    /// (≥2 chars) or equal an alias word, or be the plural of one. So "coff"→"coffee",
    /// "csb"→"csb", "local blend"→"local blend", "bars"→"bar" all hit — but "art" does NOT hit
    /// "party" and "a" does not hit "tap" (no mid-word substring, no 1-char flood).
    private static func aliasHit(_ normedQuery: String, _ normedAlias: String) -> Bool {
        let aTokens = tokenize(normedAlias)
        let qTokens = queryTokens(normedQuery)
        guard !aTokens.isEmpty, !qTokens.isEmpty else { return false }
        return qTokens.allSatisfy { qt in
            singulars(qt).contains { form in
                aTokens.contains { $0 == form || ((form == qt ? form.count >= 2 : form.count >= 5) && $0.hasPrefix(form)) }
            }
        }
    }

    /// Classic bounded edit distance (two-row DP). Datasets are tiny, so no early
    /// cut-off is needed; callers already gate on length before calling.
    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }
}
