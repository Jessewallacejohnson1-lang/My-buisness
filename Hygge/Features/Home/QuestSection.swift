//
//  QuestSection.swift
//  Hygge — the daily quest: one small nudge to get out and connect.
//  Renders the live quest when set; an honest empty state otherwise.
//

import SwiftUI

struct QuestSection: View {
    let quest: DailyQuest?
    let count: Int
    let done: Bool
    var onComplete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "leaf")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Hue.moss500)
                Text("DAILY QUEST")
                    .font(.mono(11))
                    .tracking(1.5)
                    .foregroundStyle(Hue.ink3)
            }

            if let quest {
                Text(quest.title)
                    .font(.displaySemi(20))
                    .foregroundStyle(Hue.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let desc = quest.description, !desc.isEmpty {
                    Text(desc)
                        .font(.sans(14))
                        .foregroundStyle(Hue.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Button { onComplete?() } label: {
                        HStack(spacing: 7) {
                            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 15, weight: .semibold))
                            Text(done ? "Done today" : "I did this")
                                .font(.sansSemibold(14))
                        }
                        .foregroundStyle(done ? Hue.paper : Hue.moss700)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(done ? Hue.moss700 : Hue.paper)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(done ? Color.clear : Hue.moss700.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(done)

                    if count > 0 {
                        Text("\(count) neighbor\(count == 1 ? "" : "s") did this")
                            .font(.mono(12))
                            .monospacedDigit()
                            .foregroundStyle(Hue.ink3)
                    }
                }
                .padding(.top, 2)
            } else {
                Text("A small nudge each day")
                    .font(.displaySemi(20))
                    .foregroundStyle(Hue.ink)
                Text("When a neighbor sets today's quest — a walk to the trailhead, a coffee downtown — you'll see it here, with a count of who's joined in.")
                    .font(.sans(14))
                    .foregroundStyle(Hue.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Hue.paper100)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(Hue.hairline, lineWidth: 1))
    }
}
