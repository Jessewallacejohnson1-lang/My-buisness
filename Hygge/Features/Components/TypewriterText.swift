//
//  TypewriterText.swift
//  Hygge — the "written in front of you" reveal.
//
//  Unveils an AttributedString by a growing prefix — by character (typewriter, for
//  the greeting) or by word (for the read-of-the-day) — over a RESERVED final
//  layout, so the card never reflows and words never jump to a new line mid-write.
//  A soft coral caret can ride the frontier while it types.
//
//  Craft (Emil Kowalski's animation framework):
//   • This is a RARE, first-open-of-the-day moment — the one place delight earns its
//     keep. Every other open passes `.shown` and renders instantly, zero animation.
//   • Typed text legitimately appears unit-by-unit — that IS the effect. The
//     "nothing appears from nothing" rule is about elements, not glyphs, so the
//     reveal stays crisp rather than fading each word from empty.
//   • The full string sits underneath at opacity 0 to reserve the final size →
//     no height thrash, no rewrapping as the words land. Only content changes; no
//     transform/opacity churn per frame.
//   • Reduce Motion never reaches here — the caller passes `.shown` instead.
//

import SwiftUI

enum TypewriterMode { case character, word }

/// `.hidden` reserves the final layout but shows nothing (a not-yet-written line);
/// `.writing` plays the reveal from empty; `.shown` renders the whole string at once.
enum TypewriterState: Equatable { case hidden, writing, shown }

struct TypewriterText: View {
    let content: AttributedString
    var mode: TypewriterMode = .word
    var state: TypewriterState
    /// Seconds between successive revealed units.
    var perUnit: Double = 0.05
    /// A beat before the first unit lands (lets the card's spring settle first).
    var startDelay: Double = 0
    var showsCaret: Bool = false
    var caretFont: Font = .system(size: 20, weight: .semibold)
    var onFinished: (() -> Void)? = nil

    @State private var revealed: Int = 0

    var body: some View {
        Group {
            switch state {
            case .shown:
                Text(content)
            case .hidden:
                // Reserve the final layout, render nothing yet.
                Text(content).opacity(0)
            case .writing:
                ZStack(alignment: .topLeading) {
                    Text(content).opacity(0)     // reserve → no reflow as words land
                    Text(displayed)
                }
            }
        }
        // Runs on appear and whenever `state` flips; cancels the prior run cleanly.
        .task(id: state) { await drive() }
    }

    // MARK: - The revealed prefix (+ trailing caret while typing)

    private var displayed: AttributedString {
        let bounds = Self.boundaries(of: content, mode: mode)
        var out: AttributedString
        if revealed <= 0 {
            out = AttributedString()
        } else if revealed >= bounds.count {
            out = content
        } else {
            out = AttributedString(content[content.startIndex ..< bounds[revealed - 1]])
        }
        if showsCaret && revealed < bounds.count {
            var caret = AttributedString("▌")
            caret.foregroundColor = Hue.accent
            caret.font = caretFont
            out += caret
        }
        return out
    }

    // MARK: - Driver

    private func drive() async {
        guard state == .writing else { return }
        let bounds = Self.boundaries(of: content, mode: mode)
        guard !bounds.isEmpty else { onFinished?(); return }

        revealed = 0
        if startDelay > 0 { try? await Task.sleep(for: .seconds(startDelay)) }
        if Task.isCancelled { return }

        for k in 1...bounds.count {
            if Task.isCancelled { return }
            revealed = k
            if k < bounds.count { try? await Task.sleep(for: .seconds(perUnit)) }
        }
        onFinished?()
    }

    // MARK: - Unit boundaries

    /// End index (exclusive) for each revealed unit. Character mode → one per
    /// character; word mode → one per word *including its trailing whitespace*, so
    /// the gap reveals with the word rather than after it.
    private static func boundaries(of s: AttributedString, mode: TypewriterMode) -> [AttributedString.Index] {
        let chars = s.characters
        var result: [AttributedString.Index] = []
        var i = chars.startIndex
        switch mode {
        case .character:
            while i < chars.endIndex {
                i = chars.index(after: i)
                result.append(i)
            }
        case .word:
            while i < chars.endIndex {
                while i < chars.endIndex && !chars[i].isWhitespace { i = chars.index(after: i) }
                while i < chars.endIndex && chars[i].isWhitespace { i = chars.index(after: i) }
                result.append(i)
            }
        }
        return result
    }
}
