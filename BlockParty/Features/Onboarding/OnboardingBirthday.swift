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

/// The field, Luma's: "Birthday · 25 years old" in the small grey label, over the date in a grey box.
struct OnboardingBirthdayField: View {
    let date: Date
    let now: Date

    var body: some View {
        let age = OnboardingAge.years(from: date, to: now)
        VStack(alignment: .leading, spacing: 0) {
            OnboardingFieldLabel("Birthday · \(age) years old")
            Text(date.formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: OnboardingAge.calendar.timeZone)))
                .font(.apple(17))
                .monospacedDigit()
                .foregroundStyle(Hue.ink)
                .contentTransition(.numericText())
                .padding(.vertical, 12)
                .onboardingField()
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Gender" over Female and Male, two equal pills on the interest chips' raised edge, and who sees it
/// (BP app onboarding 31, mock B). Optional: a tap on the picked one clears it. VoiceOver reads the
/// pair as Apple's segmented control ("Female, 1 of 2"), with Clear to take a pick back.
struct OnboardingGenderRow: View {
    @Binding var pick: String?

    private static let options = [(value: "female", label: "Female"), (value: "male", label: "Male")]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // VoiceOver reads it before the pair: a segmented control says only its segments.
            OnboardingFieldLabel("Gender")
            HStack(spacing: 12) {
                ForEach(Self.options, id: \.value) { option in
                    GenderPill(label: option.label, on: pick == option.value) {
                        pick = pick == option.value ? nil : option.value
                    }
                }
            }
            .accessibilityRepresentation {
                Picker("Gender", selection: $pick) {
                    ForEach(Self.options, id: \.value) { Text($0.label).tag(Optional($0.value)) }
                }
                .pickerStyle(.segmented)
            }
            .accessibilityAction(named: "Clear") { pick = nil }
            Text("Only you see your birthday and gender.")
                .font(.apple(13))
                .foregroundStyle(Hue.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
        .padding(.top, 24)
    }
}

/// One of the pair: 48 pt on the raised edge, a check before the word once picked, popping in as an
/// interest chip's does. Face and words fade over the mock's 0.18 s both ways.
private struct GenderPill: View {
    let label: String
    let on: Bool
    let action: () -> Void

    @State private var check: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if on {
                    Text("\u{2713}")
                        .font(.apple(17, weight: .semibold))
                        .scaleEffect(check)
                }
                Text(label)
                    .font(.apple(17, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)   // the largest text sizes, in a half-width pill
            }
            .foregroundStyle(on ? Color.white : Hue.ink)
            .frame(maxWidth: .infinity, minHeight: 48 - 7 - 6 - 1.5 - 3.5)   // 48 with the style's padding
        }
        .buttonStyle(InterestChipStyle(on: on))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: on)
        .onChange(of: on) { _, now in
            guard now, !reduceMotion else { return }
            check = 0.4
            withAnimation(.easeOut(duration: 0.1)) { check = 1.06 } completion: {
                withAnimation(.easeOut(duration: 0.1)) { check = 1 }
            }
        }
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
            .background(Hue.onboardingCanvas)
    }
}

/// "Come back when you're 13" (Turo's kind dead end): the clock in the grey circle every question
/// has, the reason, and Close, which clears everything and goes back to the Welcome. Back returns to
/// the wheel. Ticket 36 makes the rest Luma's quiet empty state.
struct OnboardingTooYoung: View {
    let back: () -> Void
    let close: () -> Void

    static let symbol = "clock"

    @AccessibilityFocusState private var headerFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            OnboardingBackdrop()
            VStack(alignment: .leading, spacing: 0) {
                OnboardingHeading(symbol: Self.symbol, question: "Come back when you're 13", focused: $headerFocused)
                Text("Block Party is for neighbors 13 and up. We didn't save anything you entered.")
                    .font(.apple(15))
                    .foregroundStyle(Hue.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                bigWordmark
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FollowGridMetric.gutter)
            .padding(.top, FollowGridMetric.headingTop)
            .ignoresSafeArea(.container)

            HStack {
                OnboardingBackChevron(action: back)
                Spacer()
            }
            .padding(.leading, 6)
            .padding(.top, 54)
            .ignoresSafeArea(.container)
        }
        .overlay(alignment: .bottom) {
            OnboardingNextBar(title: "Close", action: close)
                .padding(.horizontal, FollowGridMetric.gutter)
                .padding(.bottom, 50)   // 84 from the bottom, over the home indicator's 34
        }
        .onAppear { headerFocused = true }
    }

    /// The mock v7 200 pt card: the wordmark tipped 4°. Ticket 36 decides whether it stays.
    private var bigWordmark: some View {
        Color.clear
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
