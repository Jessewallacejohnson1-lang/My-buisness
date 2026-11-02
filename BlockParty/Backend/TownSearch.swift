//
//  TownSearch.swift
//  Block Party — how well typed words match a Search row (`SearchModel.results`).
//
//  You don't have to type the exact name: a row's keywords count as aliases, a word
//  start or prefix counts ("coff" → coffee), and a small typo counts ("cofee",
//  "millstreem"). `score` ranks exact name › name prefix › whole word › alias › fuzzy
//  token, so the closest thing sits on top.
//
//  Pure, synchronous and local: no network.
//

import Foundation

enum TownSearch {
    /// A relevance score for `query` against an entity, or nil for no match.
    /// Bands, high → low: exact name, name prefix, name substring, alias, then a
    /// fuzzy token band (every query token must land somewhere — AND semantics).
    static func score(_ query: String, name: String, extra: [String] = [], aliases: [String] = []) -> Double? {
        let q = norm(query)
        guard !q.isEmpty else { return nil }

        let nn = norm(name)
        if nn == q { return 1000 }
        if nn.hasPrefix(q) { return 900 - Double(min(nn.count, 60)) }   // shorter, tighter names first
        if aliasHit(query, name) { return 800 }   // word-boundary, so "art" ≠ "heart"

        for a in aliases {
            let an = norm(a)
            if an.isEmpty { continue }
            if an == q { return 780 }
            if aliasHit(query, a) { return 720 }   // token-boundary, not mid-word substring
        }

        // Fuzzy token band: split everything into tokens; every query token must
        // fuzzy-hit some field token. Averages the per-token strength.
        let hayTokens = tokenize(([name] + extra + aliases).joined(separator: " "))
        guard !hayTokens.isEmpty else { return nil }
        let qTokens = tokenize(q)
        guard !qTokens.isEmpty else { return nil }

        var total = 0.0
        for qt in qTokens {
            guard let best = bestTokenScore(qt, hayTokens) else { return nil }
            total += best
        }
        return 400 + total / Double(qTokens.count)
    }

    /// Best match strength of one query token against a bag of field tokens.
    private static func bestTokenScore(_ q: String, _ tokens: [String]) -> Double? {
        var best: Double? = nil
        for t in tokens {
            var s: Double? = nil
            if t == q {
                s = 100
            } else if t.hasPrefix(q) {
                s = 80                                   // typeahead: "co" → "coffee"
            } else {
                // No mid-token substring (that let "art" match "party"); only a
                // bounded typo. Levenshtein only on tokens long enough to typo.
                let allow = q.count >= 6 ? 2 : (q.count >= 4 ? 1 : 0)
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

    /// Lowercased, diacritic-folded, trimmed — the canonical form everything
    /// compares in ("Café" == "cafe").
    private static func norm(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive], locale: nil)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Split into alphanumeric tokens (drops punctuation / separators).
    private static func tokenize(_ s: String) -> [String] {
        norm(s).split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { !$0.isEmpty }
    }

    /// Whole-token relation between a query and an alias/keyword: every query token
    /// must prefix-match (≥2 chars) or equal an alias token. So "coff"→"coffee",
    /// "csb"→"csb", "local blend"→"local blend" all hit — but "art" does NOT hit
    /// "party" and "a" does not hit "tap" (no mid-word substring, no 1-char flood).
    private static func aliasHit(_ query: String, _ alias: String) -> Bool {
        let aTokens = tokenize(alias)
        let qTokens = tokenize(query)
        guard !aTokens.isEmpty, !qTokens.isEmpty else { return false }
        return qTokens.allSatisfy { qt in
            aTokens.contains { $0 == qt || (qt.count >= 2 && $0.hasPrefix(qt)) }
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
