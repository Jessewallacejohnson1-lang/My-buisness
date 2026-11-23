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

/// The field: "Birthday · 25 years old" in the small grey label, over the date in a box. Onboarding's
/// Birthday step draws it in the Big art look, a white box with a soft edge (BP app onboarding 43); the
/// Going chat's birthday ask, on its white sheet, keeps Luma's grey box.
struct OnboardingBirthdayField: View {
    let date: Date
    let now: Date
    var bigArt = false

    /// Jesse's drawing (BP app references/birthday-icon), the step's art, as the Going chat's birthday
    /// ask shows it small.
    static let cakeImage = "BirthdayCake"

    var body: some View {
        let age = OnboardingAge.years(from: date, to: now)
        VStack(alignment: .leading, spacing: 0) {
            OnboardingFieldLabel("Birthday · \(age) years old", color: bigArt ? Hue.bigArtWords : Hue.inkSecondary)
            Text(date.formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: OnboardingAge.calendar.timeZone)))
                .font(.apple(17))
                .monospacedDigit()
                .foregroundStyle(Hue.ink)
                .contentTransition(.numericText())
                .padding(.vertical, 12)
                .modifier(BirthdayBox(bigArt: bigArt))
        }
        .accessibilityElement(children: .combine)
    }
}

/// The date's box: Luma's grey field, or on the Big art step the same frame in the white box.
private struct BirthdayBox: ViewModifier {
    let bigArt: Bool
    func body(content: Content) -> some View {
        if bigArt {
            content
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: OnboardingFieldBox.height, alignment: .leading)
                .bigArtBox()
        } else {
            content.onboardingField()
        }
    }
}

/// "Gender" over Female and Male, two equal white boxes (mock v2 `.gp`), and who sees it (BP app onboarding
/// 31, 36, 43). Optional: a tap on the picked one clears it. VoiceOver reads the pair as Apple's segmented
/// control ("Female, 1 of 2"), with Clear to take a pick back.
struct OnboardingGenderRow: View {
    @Binding var pick: String?

    private static let options = [(value: "female", label: "Female"), (value: "male", label: "Male")]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // VoiceOver reads it before the pair: a segmented control says only its segments.
            OnboardingFieldLabel("Gender", color: Hue.bigArtWords)
            HStack(spacing: 8) {
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
                .foregroundStyle(Hue.bigArtWords)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
        .padding(.top, 24)
    }
}

/// One of the pair: a 46 pt white box with a soft edge, flat ink with a white check before the word once
/// picked, the check popping in. Face and words fade over the mock's 0.18 s both ways.
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
                        .font(.apple(17, weight: .bold))
                        .scaleEffect(check)
                }
                Text(label)
                    .font(.apple(17, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)   // the largest text sizes, in a half-width box
            }
            .foregroundStyle(on ? Color.white : Hue.ink)
            .frame(maxWidth: .infinity, minHeight: OnboardingFieldBox.height)
            .bigArtBox(picked: on)
            .contentShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        }
        .buttonStyle(.press(.squish, haptic: true))
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
/// picker ticks under the finger on its own. A phone with no home indicator (the iPhone SE) passes
/// its own 0 as `homeBar` (onboarding 47).
struct OnboardingBirthdayWheel: View {
    @Binding var date: Date
    let now: Date
    /// What it sits on: Luma's grey (the Going chat's ask), or the Big art step's near-white canvas.
    var canvas = Hue.onboardingCanvas
    var homeBar: CGFloat = 34

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
            .padding(.bottom, homeBar)
            .frame(height: Self.height - 34 + homeBar, alignment: .center)
            .background(canvas)
    }
}

/// "Come back when you're 13" in the Big art look (onboarding 47, mock v2 `young`, Finch's quiet intro
/// screen): the hourglass, the question and its line, centred between the top row and Close. The flow
/// draws the grey, the Back chevron and Close (it clears everything and goes back to the Welcome).
struct OnboardingTooYoung: View {
    @AccessibilityFocusState.Binding var focused: Bool

    /// Apple's hourglass stands in until there's a drawing (Jesse, 2026-11-21).
    static let art = "\u{23F3}"

    var body: some View {
        OnboardingBigArt(question: "Come back when you're 13",
                         line: "Block Party is for neighbors 13 and up. We didn't save anything you entered.",
                         focused: $focused) {
            Text(Self.art)
                .font(.glyph(92))   // artwork at the mock's size, not text
                .accessibilityHidden(true)
        }
        .padding(.horizontal, FollowGridMetric.gutter)
        // Between the top row (54 + 44 down) and Close with the slot under it.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 98)
        .padding(.bottom, OnboardingNextBar.height + 6 + 44)
        .ignoresSafeArea(.container, edges: .top)
    }
}
