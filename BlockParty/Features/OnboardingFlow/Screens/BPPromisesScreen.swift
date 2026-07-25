//
//  BPPromisesScreen.swift
//  S16 — "Here's what changes with Block Party:"
//
//  Three rows of icon + bold title + grey subtitle. These are NOT `BPRow`s: in the
//  reference they carry no border, no chip ground and no press state, because they are
//  not answers — they are a list of claims. Reusing `BPRow` here would make three
//  unselectable things look exactly like the selectable rows two screens earlier.
//

import SwiftUI

struct BPPromisesScreen: View {
    let step: BPStep
    let onBack: () -> Void
    let onContinue: () -> Void

    static let promises: [(glyph: BPGlyph, title: String, detail: String)] = [
        (.calendarCheck, "Never miss a thing",
         "every event, club night, and town update in one feed"),
        (.users, "Find your people",
         "clubs, meetups, and neighbors into what you're into"),
        (.map, "Know St. Joe like a local",
         "the spots, the news, the stuff that never makes it to Facebook"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            BPScreenTop(step: step, onBack: onBack)
                .padding(.top, 8)

            HStack(alignment: .top, spacing: BPLayout.markBubbleGap) {
                BPMark(side: BPLayout.questionMarkSide)
                BPBubble(content: BPCopy.plain("Here's what changes with Block Party:"),
                         tail: .leading(0.43))
                Spacer(minLength: 0)
            }
            .padding(.leading, BPLayout.markLeadingInset)
            .padding(.trailing, BP.Metric.pageMargin)
            .padding(.top, BPLayout.bubbleTopGap)

            VStack(alignment: .leading, spacing: 26) {
                ForEach(Self.promises, id: \.title) { p in
                    HStack(alignment: .top, spacing: BP.Metric.rowChipGap) {
                        BPLucide(glyph: p.glyph, size: 26)
                            .foregroundStyle(BP.orange)
                            .frame(width: 30, alignment: .center)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.title)
                                .font(.sansBold(16))
                                .foregroundStyle(BP.ink)
                            Text(p.detail)
                                .font(.sans(14))
                                .foregroundStyle(BP.gray)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.horizontal, BP.Metric.pageMargin + 4)
            .padding(.top, 34)

            Spacer()

            BPButton(title: "Continue", action: onContinue)
                .padding(.horizontal, BP.Metric.pageMargin)
                .padding(.bottom, BPLayout.buttonBottomGap)
        }
        .background(BP.paper.ignoresSafeArea())
    }
}
