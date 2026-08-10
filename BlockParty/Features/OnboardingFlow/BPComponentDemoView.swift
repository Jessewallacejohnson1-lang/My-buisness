//
//  BPComponentDemoView.swift
//  Block Party — the Phase 0 component bench.
//
//  Every §3 signature mechanic in every state, on one screen, so the press physics,
//  bar texture, typing bubble, selection recipe and check spring can be verified
//  against the reference frames before any screen work starts.
//
//  Headless: `xcrun simctl launch <udid> Jesse.BlockParty -bp-components [-bp-page N]`
//
//  PAGINATED ON PURPOSE. This simulator setup has no scroll/gesture automation, so a
//  single long ScrollView can only ever be screenshotted at its top — everything below
//  the fold would go unverified while still *looking* covered. `-bp-page 0…5` renders
//  one screenful at a time so every component and state is reachable headlessly. Page 0
//  is the metrics bench: full-width primitives at known positions, so the measurement
//  script that produced `REFERENCE-SPEC.md` can be re-run against our own render and
//  the numbers compared directly rather than eyeballed.
//
//  This is DEBUG-only scaffolding and is not reachable in a release build.
//

import SwiftUI

struct BPComponentDemoView: View {
    /// `-bp-page N`; defaults to the metrics bench.
    static func initialPage() -> Int {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-bp-page"), i + 1 < args.count,
              let n = Int(args[i + 1]) else { return 0 }
        return n
    }

    @State private var page: Int = BPComponentDemoView.initialPage()

    var body: some View {
        Group {
            switch page {
            case 0: metricsBench
            default: BPComponentGallery(page: page)
            }
        }
    }

    /// Full-width primitives at fixed offsets, for numeric comparison against the
    /// reference frames. No labels, no chrome — anything extra would perturb a measured
    /// edge and send the diff loop chasing a phantom.
    private var metricsBench: some View {
        VStack(spacing: 0) {
            BPTopBar(progress: 6.0 / 16.0, onBack: {})
                .padding(.top, 8)

            Spacer().frame(height: 40)

            VStack(spacing: BP.Metric.rowGap) {
                BPRow(label: "I live here", icon: .glyph(.house), selected: false) {}
                BPRow(label: "I'm moving here", icon: .glyph(.truck), selected: true) {}
            }
            .padding(.horizontal, BP.Metric.pageMargin)

            Spacer()

            VStack(spacing: 12) {
                BPButton(title: "Continue") {}
                BPButton(title: "Continue", enabled: false) {}
                BPButton(title: "I already have an account", variant: .secondary) {}
            }
            .padding(.horizontal, BP.Metric.pageMargin)
            .padding(.bottom, 24)
        }
        .background(BP.paper.ignoresSafeArea())
    }
}

private struct BPComponentGallery: View {
    let page: Int
    @State private var single: Int? = 1
    @State private var multi: Set<Int> = [0, 2]
    @State private var cadence: Int = 1
    @State private var card: Int? = 0
    @State private var progress: Double = 0.35
    @State private var bubbleLine = 0

    private let lines: [AttributedString] = [
        BPCopy.plain("Hey! Welcome to the party. 👋"),
        BPCopy.emphasised("Just ", "6 quick questions", " and you're in."),
        BPCopy.plain("That's what we're here for."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {

                if page == 1 {
                section("BPProgressBar — advance to see the stripe + overshoot") {
                    BPTopBar(progress: progress, onBack: {})
                        .padding(.horizontal, -BP.Metric.pageMargin)
                    HStack(spacing: 10) {
                        BPButton(title: "Back", variant: .secondary) {
                            progress = max(0, progress - 1.0 / 16)
                        }
                        BPButton(title: "Advance") {
                            progress = min(1, progress + 1.0 / 16)
                        }
                    }
                }

                section("BPBubble — .leading tail, types at 30ms/char") {
                    HStack(alignment: .top, spacing: 10) {
                        BlockPartyMark(side: 52)
                        BPBubble(content: lines[bubbleLine], tail: .leading(0.4))
                    }
                    BPButton(title: "React (swap the line)", variant: .secondary) {
                        withAnimation(BP.Motion.bubbleSwap) {
                            bubbleLine = (bubbleLine + 1) % lines.count
                        }
                    }
                }

                section("BPBubble — .bottom tail (talking screens)") {
                    VStack(spacing: 0) {
                        BPBubble(content: lines[0], tail: .bottom(0.3), typing: false)
                        BlockPartyMark(side: 84)
                            .padding(.top, 18)
                            .padding(.leading, -110)
                    }
                }
                }

                if page == 2 {
                section("BPRow — single-select, lucide chips") {
                    VStack(spacing: BP.Metric.rowGap) {
                        ForEach(Array(connectionRows.enumerated()), id: \.offset) { i, r in
                            BPRow(label: r.1, icon: .glyph(r.0), selected: single == i) {
                                single = i
                            }
                        }
                    }
                }

                section("BPRow — level bars (S08)") {
                    VStack(spacing: BP.Metric.rowGap) {
                        ForEach(0 ..< 3, id: \.self) { i in
                            BPRow(label: levelRows[i], icon: .level(i + 1), selected: single == 100 + i) {
                                single = 100 + i
                            }
                        }
                    }
                }
                }

                if page == 3 {
                section("BPRow — trailing label (S12 cadence)") {
                    VStack(spacing: BP.Metric.rowGap) {
                        ForEach(Array(cadenceRows.enumerated()), id: \.offset) { i, r in
                            BPRow(label: r.0, trailingLabel: r.1, selected: cadence == i) {
                                cadence = i
                            }
                        }
                    }
                }

                section("BPRow — multi-select, check badge springs in") {
                    VStack(spacing: BP.Metric.rowGap) {
                        ForEach(Array(motivationRows.enumerated()), id: \.offset) { i, r in
                            BPRow(label: r.1, icon: .glyph(r.0),
                                  selected: multi.contains(i), showsCheck: true) {
                                if multi.contains(i) { multi.remove(i) } else { multi.insert(i) }
                            }
                        }
                    }
                }
                }

                if page == 4 {
                section("BPCard — stacked options + RECOMMENDED pill") {
                    VStack(spacing: BP.Metric.rowGap) {
                        BPCard(title: "Founding Member",
                               subtitle: "Founding badge on your profile, first to post, name on the founders wall",
                               recommended: true, selected: card == 0) { card = 0 }
                        BPCard(title: "Just looking around",
                               subtitle: "Browse everything, join anytime",
                               selected: card == 1) { card = 1 }
                        BPCard(title: "This week in St. Joe",
                               subtitle: "Jump straight into what's happening",
                               icon: .calendar, recommended: true, selected: card == 2) { card = 2 }
                        BPCard(title: "The map", subtitle: "Explore town first",
                               icon: .map, selected: card == 3) { card = 3 }
                    }
                }
                }

                if page == 5 {
                section("BPMockDialog — inert pre-prompt + nudge") {
                    HStack { Spacer()
                        BPMockDialog(
                            title: "\u{201C}Block Party\u{201D} Would Like to Send You Notifications",
                            message: "Notifications may include alerts, sounds, and icon badges. These can be configured in Settings.",
                            allowTitle: "Allow")
                        Spacer() }
                    .padding(.bottom, 34)
                }

                section("BPButton — every variant + state") {
                    BPButton(title: "Continue") {}
                    BPButton(title: "Continue", enabled: false) {}
                    BPButton(title: "I already have an account", variant: .secondary) {}
                    BPButton(title: "Not now", variant: .quiet) {}
                }
                }
            }
            .padding(.horizontal, BP.Metric.pageMargin)
            .padding(.vertical, 24)
        }
        .background(BP.paper.ignoresSafeArea())
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.mono(11))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(BP.gray)
            content()
        }
    }

    private let connectionRows: [(BPGlyph, String)] = [
        (.house, "I live here"),
        (.truck, "I'm moving here"),
        (.graduationCap, "I'm a student (CSB/SJU)"),
        (.mapPin, "I live nearby"),
        (.car, "Just visiting"),
    ]
    private let levelRows = ["Just moved here", "I know a few spots", "I know my way around"]
    private let cadenceRows: [(String, String)] = [
        ("Weekly roundup", "Casual"),
        ("A few times a week", "Regular"),
        ("Daily digest", "Serious"),
        ("The second it happens", "Intense"),
    ]
    private let motivationRows: [(BPGlyph, String)] = [
        (.partyPopper, "Find things to do"),
        (.users, "Meet new people"),
        (.newspaper, "Stay in the loop"),
        (.baby, "Get my kids involved"),
        (.megaphone, "Promote my club or business"),
        (.ellipsis, "Other"),
    ]
}

/// Bubble copy helpers — the reference bolds a span inside an otherwise plain line
/// (S04's "6 quick questions", S13's "30+ St. Joe happenings"), so building the
/// `AttributedString` needs to stay a one-liner at the call site.
enum BPCopy {
    static func plain(_ s: String) -> AttributedString {
        AttributedString(s)
    }

    /// `lead` + bolded `strong` + `tail`. Pass a `tint` to colour the emphasised span
    /// (S07 and S13 render theirs in the primary colour).
    static func emphasised(_ lead: String, _ strong: String, _ tail: String,
                           tint: Color? = nil) -> AttributedString {
        var out = AttributedString(lead)
        var mid = AttributedString(strong)
        mid.font = .sansBold(17)
        if let tint { mid.foregroundColor = tint }
        out += mid
        out += AttributedString(tail)
        return out
    }
}
