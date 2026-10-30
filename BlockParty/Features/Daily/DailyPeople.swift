//
//  DailyPeople.swift
//  Block Party — Daily's People you may know: Instagram's suggestion cards in a sideways row,
//  rounder as on the Daily drafts (BP app docs/plans/daily-tab, ticket 22; Check-in 1
//  https://claude.ai/artifact/8PiBVH6VNCtHbj7MemN6pS). The face and name open their page, Add
//  friend is the Friends page's own button, and the X hides them for good.
//

import SwiftUI

/// Sizes from the Check-in 1 page Jesse said yes to (BP app `references/people-you-may-know/`),
/// the Daily drafts' card beside Instagram's (`refs/instagram-suggested-cards.jpg`).
nonisolated enum DailyPeopleMetric {
    static let card = CGSize(width: 158, height: 212)
    static let radius: CGFloat = 24
    static let gap: CGFloat = 10
    static let face: CGFloat = 84
    static let faceTop: CGFloat = 22
    static let nameTop: CGFloat = 10
    static let reasonTop: CGFloat = 2
    /// Add friend, 12 in from the card's sides and bottom.
    static let buttonInset: CGFloat = 12
    /// The X: a 12 pt glyph in a 44 pt corner the finger can hit.
    static let x: CGFloat = 12
    static let xTarget: CGFloat = 44
    static let ring: CGFloat = 0.5
}

/// "People you may know": today only, and only with someone on it.
struct PeopleYouMayKnowSection: View {
    let people: [Neighbor]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: DailyRowMetric.titleToCards) {
            DailyRowTitle(title: "People you may know")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: DailyPeopleMetric.gap) {
                    ForEach(people) { person in
                        SuggestionCard(person: person)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, DailyRowMetric.side, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
    }
}

/// One suggestion: face, name, why, Add friend, and the X in its corner.
private struct SuggestionCard: View {
    let person: Neighbor
    @Environment(FriendsBook.self) private var book

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DailyPeopleMetric.radius, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationLink(value: person) {
                VStack(spacing: 0) {
                    Avatar(avatarUrl: person.avatarUrl, size: DailyPeopleMetric.face, outlined: true)
                        .padding(.top, DailyPeopleMetric.faceTop)
                    Text(person.displayName)
                        .font(.sansSemibold(15))
                        .foregroundStyle(Hue.ink)
                        .lineLimit(1)
                        .padding(.top, DailyPeopleMetric.nameTop)
                    Text(person.suggestLine)
                        .font(.sans(13))
                        .foregroundStyle(Hue.inkSecondary)
                        .lineLimit(1)
                        .padding(.top, DailyPeopleMetric.reasonTop)
                }
                .padding(.horizontal, DailyPeopleMetric.buttonInset)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(DimStyle())
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            // Never an Anonymous account here: the row is read only for a real one.
            RelationButtons(person: person) {}
                .padding(DailyPeopleMetric.buttonInset)
        }
        .frame(width: DailyPeopleMetric.card.width, height: DailyPeopleMetric.card.height)
        .background(Hue.surface, in: shape)
        .overlay(shape.strokeBorder(Hue.hairline, lineWidth: DailyPeopleMetric.ring))
        .modifier(CardShadow())
        .overlay(alignment: .topTrailing) {
            Button { book.hide(person) } label: {
                Image(systemName: "xmark")
                    .font(.glyph(DailyPeopleMetric.x, weight: .semibold))
                    .foregroundStyle(Hue.inkSecondary)
                    .frame(width: DailyPeopleMetric.xTarget, height: DailyPeopleMetric.xTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            // `suggest-remove-vo`; after the name and Add friend, though it sits at the top.
            .accessibilityLabel("Remove suggestion, \(person.displayName)")
            .accessibilitySortPriority(-1)
        }
        .accessibilityElement(children: .contain)
    }
}
