//
//  OnboardingBirthday.swift
//  Block Party — onboarding step 6, the birthday (BP app docs/plans/onboarding, ticket 19; mock v7's
//  Birthday and Under 13 screens): Instagram's field with the age beside it, over Apple's date wheel,
//  and Turo's kind dead end for under 13s.
//

import SwiftUI

/// Ages as the field and the under-13 check count them, in Town time.
nonisolated enum OnboardingAge {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago") ?? .current
        return c
    }()

    /// Whole years from `birthday` to `now`; a Feb 29 birthday turns on Feb 28 in other years.
    static func years(from birthday: Date, to now: Date) -> Int {
        max(0, calendar.dateComponents([.year], from: birthday, to: now).year ?? 0)
    }

    /// The day as the device keeps it and `town_profiles.birthday` takes it: "2001-10-24".
    static let day = Date.ISO8601FormatStyle(timeZone: calendar.timeZone).year().month().day()
}

/// The field: "Birthday (25 years old)" over the date, in a 14 pt box with an ink edge.
struct OnboardingBirthdayField: View {
    let date: Date
    let now: Date

    var body: some View {
        let age = OnboardingAge.years(from: date, to: now)
        VStack(alignment: .leading, spacing: 0) {
            Text("Birthday (\(age) years old)")
                .font(.sans(12))
                .foregroundStyle(Hue.inkSecondary)
            Text(date.formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: OnboardingAge.calendar.timeZone)))
                .font(.sansMedium(20))
                .monospacedDigit()
                .foregroundStyle(Hue.ink)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .background(Hue.surface, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Hue.ink, lineWidth: 1.5))
        .accessibilityElement(children: .combine)
    }
}

/// Apple's wheel where the keyboard sits, 272 pt with the home indicator's 34 under it. The stock
/// picker ticks under the finger on its own.
struct OnboardingBirthdayWheel: View {
    @Binding var date: Date
    let now: Date

    static let height: CGFloat = 272

    var body: some View {
        DatePicker("Birthday", selection: $date,
                   in: OnboardingAge.calendar.date(from: DateComponents(year: 1900, month: 1, day: 1))!...now,
                   displayedComponents: .date)
            .datePickerStyle(.wheel)
            .labelsHidden()
            .environment(\.calendar, OnboardingAge.calendar)
            .environment(\.timeZone, OnboardingAge.calendar.timeZone)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 34)
            .frame(height: Self.height, alignment: .center)
            .background(Hue.fill)
    }
}

/// "Come back when you're 13" (Turo's kind dead end): the wordmark on a soft yellow glow, the reason,
/// and Close, which clears everything and goes back to the Welcome. Back returns to the wheel.
struct OnboardingTooYoung: View {
    let back: () -> Void
    let close: () -> Void

    @AccessibilityFocusState private var headerFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            OnboardingBackdrop()
            VStack(alignment: .leading, spacing: 0) {
                BlockPartyWordmark(height: 33)
                    .foregroundStyle(Hue.ink)
                glow
                Text("Come back when you're 13")
                    .font(.sansHeadline(30))
                    .foregroundStyle(Hue.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 32)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($headerFocused)
                Text("Block Party is for neighbors 13 and up. We didn't save anything you entered.")
                    .font(.sans(15))
                    .foregroundStyle(Hue.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 128)
            .ignoresSafeArea(.container)

            HStack {
                OnboardingBackChevron(action: back)
                Spacer()
            }
            .padding(.leading, 10)
            .padding(.top, 56)
            .ignoresSafeArea(.container)
        }
        .overlay(alignment: .bottom) {
            OnboardingNextBar(title: "Close", action: close)
                .padding(.horizontal, 24)
                .padding(.bottom, 50)   // 84 from the bottom, over the home indicator's 34
        }
        .onAppear { headerFocused = true }
    }

    /// The mock's 200 pt card: the wordmark tipped 4°, on yellow fading out from just below centre.
    private var glow: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(RadialGradient(stops: [.init(color: Hue.brandDisc.opacity(0.55), location: 0),
                                         .init(color: Hue.brandDisc.opacity(0.1), location: 0.7),
                                         .init(color: Hue.brandDisc.opacity(0), location: 1)],
                                 center: UnitPoint(x: 0.5, y: 0.6), startRadius: 0, endRadius: 180))
            .frame(height: 200)
            .overlay {
                BlockPartyWordmark(height: 190 / BlockPartyWordmark.aspect)
                    .foregroundStyle(Hue.ink)
                    .rotationEffect(.degrees(-4))
            }
            .padding(.top, 32)
            .accessibilityHidden(true)
    }
}
