//
//  NewEventFilter.swift
//  BlockParty — New Event's Filter (BP app town-feed 52): who an Event is for, by gender and age, copied from
//  Badoo's Filter (references/gender-lift). A gender lifts it in that gender's Town feed; an age range is the
//  card's age mark, and an 18+ or 21+ keeps it from under-18s.
//

import SwiftUI

/// Who a neighbour's Event is for, as `club_events.for_gender` keeps it (onboarding's answers).
nonisolated enum EventGender: String, CaseIterable, Equatable {
    case female, male

    var label: String { self == .female ? NewEventFilterCopy.women : NewEventFilterCopy.men }
}

/// An Event's age range: youngest and oldest, `0` and `top` meaning no limit at that end.
nonisolated struct EventAges: Equatable {
    /// The slider's far end, "75+": kids' ranges keep room to drag (Jesse, 2026-11-09).
    static let top = 75

    var youngest = 0
    var oldest = top

    var any: Bool { youngest == 0 && oldest == Self.top }

    /// As the card's age mark says it (`club_events.ages`, BP app inside-cards 30): "18+", "Ages 6–14",
    /// "Ages 12 and under"; nil for all ages.
    var words: String? {
        if any { return nil }
        if oldest == Self.top { return "\(youngest)+" }
        if youngest == 0 { return "Ages \(oldest) and under" }
        return "Ages \(youngest)–\(oldest)"
    }

    /// One end moved to `age`, never past or onto the other.
    mutating func move(_ end: AgeEnd, to age: Int) {
        switch end {
        case .youngest: youngest = min(max(age, 0), oldest - 1)
        case .oldest: oldest = max(min(age, Self.top), youngest + 1)
        }
    }

    /// The end a finger at `age` takes: the one it's past, else the nearer.
    func end(nearest age: Int) -> AgeEnd {
        if age <= youngest { return .youngest }
        if age >= oldest { return .oldest }
        return age - youngest <= oldest - age ? .youngest : .oldest
    }

    /// Whether a finger at `age` is on both knobs at once, `reach` years being a knob's half width: then
    /// the way it moves picks (`end(movingUp:)`), so a pair pushed to either end never sticks.
    func onBoth(_ age: Int, reach: Int) -> Bool {
        abs(age - youngest) <= reach && abs(age - oldest) <= reach
    }

    func end(movingUp: Bool) -> AgeEnd { movingUp ? .oldest : .youngest }

    /// The ages a drag ticks on: the ends and the ages that change what a teen sees.
    static let ticks: Set<Int> = [0, 13, 18, 21, top]
}

nonisolated enum AgeEnd { case youngest, oldest }

nonisolated enum NewEventFilterCopy {
    static let filter = "Filter"
    static let add = "Add"
    static let clearAll = "Clear all"
    static let apply = "Apply"
    static let gender = "Gender"
    static let ageRange = "Age range"
    static let allAges = "All ages"
    static let everyone = "Everyone"
    static let women = "Women"
    static let men = "Men"
    static let youngest = "Youngest"
    static let oldest = "Oldest"
    static let any = "Any"

    /// The Filter row's words once something is picked: "Women · 18+".
    static func summary(gender: EventGender?, ages: EventAges) -> String? {
        let bits = [gender?.label, ages.words].compactMap { $0 }
        return bits.isEmpty ? nil : bits.joined(separator: " · ")
    }
}

private nonisolated enum FilterMetric {
    static let side: CGFloat = 16
    static let labelTop: CGFloat = 8
    static let labelBottom: CGFloat = 10
    static let box: CGFloat = 44
    static let boxRadius: CGFloat = 12
    static let boxRing: CGFloat = 1.6
    static let afterBoxes: CGFloat = 30
    static let knob: CGFloat = 28
    static let ring: CGFloat = 1.5
    /// How far a finger on both knobs moves before it has picked one.
    static let decide: CGFloat = 2
    static let track: CGFloat = 4
    static let slider: CGFloat = 44
    static let barPad: CGFloat = 16
}

/// Pushed from New Event's Filter row, as Place is. Back leaves both as they were; Apply keeps the picks.
struct NewEventFilter: View {
    @Binding var gender: EventGender?
    @Binding var ages: EventAges
    @State private var pickedGender: EventGender?
    @State private var pickedAges: EventAges
    @Environment(\.dismiss) private var dismiss

    init(gender: Binding<EventGender?>, ages: Binding<EventAges>) {
        _gender = gender
        _ages = ages
        _pickedGender = State(initialValue: gender.wrappedValue)
        _pickedAges = State(initialValue: ages.wrappedValue)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(NewEventFilterCopy.gender)
                    .font(.sans(15)).foregroundStyle(Hue.inkSecondary)
                    .padding(.top, FilterMetric.labelTop)
                    .padding(.bottom, FilterMetric.labelBottom)
                    .accessibilityHidden(true)
                genders
                    .padding(.bottom, FilterMetric.afterBoxes)
                HStack {
                    Text(NewEventFilterCopy.ageRange).foregroundStyle(Hue.inkSecondary)
                    Spacer(minLength: 8)
                    // Badoo's number, in bold.
                    Text(pickedAges.words ?? NewEventFilterCopy.allAges).foregroundStyle(Hue.ink)
                        .font(.sansSemibold(15))
                        .contentTransition(.numericText())
                }
                .font(.sans(15))
                .padding(.bottom, FilterMetric.labelBottom)
                .accessibilityHidden(true)
                AgeRangeSlider(ages: $pickedAges)
            }
            .padding(.horizontal, FilterMetric.side)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OnboardingNextBar(title: NewEventFilterCopy.apply) {
                gender = pickedGender
                ages = pickedAges
                dismiss()
            }
            .padding(FilterMetric.barPad)
        }
        .background(Hue.paper)
        .navigationTitle(NewEventFilterCopy.filter)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(NewEventFilterCopy.clearAll) {
                    pickedGender = nil
                    pickedAges = EventAges()
                }
                .disabled(pickedGender == nil && pickedAges.any)
            }
        }
    }

    /// Badoo's three boxes: Men, Women, Everyone, the pick ringed in ink.
    private var genders: some View {
        HStack(spacing: 0) {
            box(NewEventFilterCopy.men, .male)
            box(NewEventFilterCopy.women, .female)
            box(NewEventFilterCopy.everyone, nil)
        }
        .background(Hue.surface, in: RoundedRectangle(cornerRadius: FilterMetric.boxRadius))
        .overlay { RoundedRectangle(cornerRadius: FilterMetric.boxRadius).strokeBorder(Hue.hairline, lineWidth: 1) }
        .sensoryFeedback(.selection, trigger: pickedGender)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NewEventFilterCopy.gender)
    }

    private func box(_ label: String, _ value: EventGender?) -> some View {
        let on = pickedGender == value
        return Button { withAnimation(Motion.snappy) { pickedGender = value } } label: {
            Text(label)
                .font(.sans(15))
                .foregroundStyle(Hue.ink)
                .frame(maxWidth: .infinity)
                .frame(height: FilterMetric.box)
                .overlay {
                    RoundedRectangle(cornerRadius: FilterMetric.boxRadius)
                        .strokeBorder(Hue.ink, lineWidth: FilterMetric.boxRing)
                        .opacity(on ? 1 : 0)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.press(.squish))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Two knobs on Apple's track, a tick at each whole year (Apple has no two-handle slider). A finger
/// anywhere on it takes the nearer knob and drags it; each knob is its own adjustable element.
struct AgeRangeSlider: View {
    @Binding var ages: EventAges
    @State private var grabbed: AgeEnd?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let run = max(geo.size.width - FilterMetric.knob, 1)
            let x = { (age: Int) in FilterMetric.knob / 2 + run * CGFloat(age) / CGFloat(EventAges.top) }
            let age = { (at: CGFloat) in Int(((at - FilterMetric.knob / 2) / run * CGFloat(EventAges.top)).rounded()) }
            ZStack(alignment: .leading) {
                Capsule().fill(Hue.hairline)
                    .frame(height: FilterMetric.track)
                    .padding(.horizontal, FilterMetric.knob / 2)
                Capsule().fill(Hue.ink)
                    .frame(width: x(ages.oldest) - x(ages.youngest), height: FilterMetric.track)
                    .offset(x: x(ages.youngest))
                knob(.youngest).position(x: x(ages.youngest), y: geo.size.height / 2)
                knob(.oldest).position(x: x(ages.oldest), y: geo.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let start = age(drag.startLocation.x)
                        if grabbed == nil {
                            let reach = Int((FilterMetric.knob / 2 / run * CGFloat(EventAges.top)).rounded(.up))
                            if ages.onBoth(start, reach: reach) {
                                // On both knobs: wait for the finger to say which way.
                                guard abs(drag.translation.width) >= FilterMetric.decide else { return }
                                grabbed = ages.end(movingUp: drag.translation.width > 0)
                            } else {
                                grabbed = ages.end(nearest: start)
                            }
                        }
                        if let grabbed { ages.move(grabbed, to: age(drag.location.x)) }
                    }
                    .onEnded { _ in grabbed = nil }
            )
        }
        .frame(height: FilterMetric.slider)
        // A tick at the ends, 13, 18 and 21, not one a year.
        .sensoryFeedback(.selection, trigger: ages) { old, new in
            (old.youngest != new.youngest && EventAges.ticks.contains(new.youngest))
                || (old.oldest != new.oldest && EventAges.ticks.contains(new.oldest))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NewEventFilterCopy.ageRange)
    }

    private func knob(_ end: AgeEnd) -> some View {
        let value = end == .youngest ? ages.youngest : ages.oldest
        let open = end == .youngest ? value == 0 : value == EventAges.top
        // Badoo's knob: white with an ink ring.
        return Circle()
            .fill(Hue.surface)
            .overlay { Circle().strokeBorder(Hue.ink, lineWidth: FilterMetric.ring) }
            .frame(width: FilterMetric.knob, height: FilterMetric.knob)
            .scaleEffect(grabbed == end && !reduceMotion ? 1.15 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: grabbed)
            .accessibilityElement()
            .accessibilityLabel(end == .youngest ? NewEventFilterCopy.youngest : NewEventFilterCopy.oldest)
            .accessibilityValue(open ? NewEventFilterCopy.any : "\(value)")
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 1 : direction == .decrement ? -1 : 0
                ages.move(end, to: value + step)
            }
    }
}
