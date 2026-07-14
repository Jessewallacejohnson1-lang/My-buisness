//
//  AddFormView.swift
//  Hygge — the event / club / trail composer.
//

import SwiftUI
import PhotosUI

struct AddFormView: View {
    let kind: AddKind
    /// Prefill the event date (e.g. tapping an empty day on the Calendar opens the
    /// composer already scoped to that day). Applied once on appear.
    var initialDate: Date? = nil
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var model = AddModel()
    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?

    private var api: CommunityAPI { CommunityAPI(auth: auth) }
    private var storage: Storage { Storage(auth: auth) }
    private var moderation: Moderation { Moderation(auth: auth) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    photoZone

                    labeledField("Title", $model.title, placeholder: titlePlaceholder)

                    switch kind {
                    case .event: eventFields
                    case .club: clubFields
                    case .trail: trailFields
                    }

                    if let err = model.error {
                        Text(err).font(.sans(13)).foregroundStyle(Hue.clay700)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    submitButton
                }
                .padding(18)
            }
            .background(Hue.canvas)
            .navigationTitle("New \(kind.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Hue.ink2)
                }
            }
            .onAppear { if let initialDate { model.eventDate = initialDate } }
            .onChange(of: pickerItem) { _, item in
                Task { @MainActor in
                    if let data = try? await item?.loadTransferable(type: Data.self) { model.photo = data }
                }
            }
            .onChange(of: model.posted) { _, done in if done { dismiss() } }
            .alert("Thanks — it's in the queue", isPresented: $model.pendingNotice) {
                Button("OK") { dismiss() }
            } message: {
                Text("A moderator will take a quick look before it goes live.")
            }
        }
    }

    // MARK: - Per-kind fields

    private var eventFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("When").font(.sansMedium(12)).foregroundStyle(Hue.ink3)
                Spacer()
                DatePicker("", selection: $model.eventDate, in: Date()..., displayedComponents: .date)
                    .labelsHidden()
                DatePicker("", selection: $model.time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Hue.paper).clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)).hyggeHairline()

            VenueAutocompleteField(label: "Where", placeholder: "Church of St. Joseph, Minnesota St",
                                   text: $model.location, curated: KnownVenues.suggestions)
            categoryField
            labeledField("Details", $model.details, placeholder: "Anything neighbors should know (optional)", multiline: true)

            Stepper(value: $model.repeatWeeklyCount, in: 1...8) {
                Text(model.repeatWeeklyCount == 1 ? "Doesn't repeat"
                     : "Repeats weekly · \(model.repeatWeeklyCount) weeks")
                    .font(.sans(14)).foregroundStyle(Hue.ink2)
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Hue.paper).clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)).hyggeHairline()
        }
    }

    private var clubFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            labeledField("Host", $model.host, placeholder: "Who runs it?")
            labeledField("When", $model.schedule, placeholder: "Every Saturday, 7am")
            labeledField("Where", $model.location, placeholder: "Millstream Park (optional)")
            labeledField("Vibe", $model.vibe, placeholder: "A one-line feel (optional)")
            labeledField("About", $model.details, placeholder: "What is it? (optional)", multiline: true)
            labeledField("What to expect", $model.expectations, placeholder: "What to bring / expect (optional)", multiline: true)
        }
    }

    private var trailFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            labeledField("Trailhead", $model.location, placeholder: "Where does it start?")
            HStack(spacing: 12) {
                labeledField("Length", $model.length, placeholder: "3.2 mi")
                labeledField("Difficulty", $model.difficulty, placeholder: "Easy")
            }
            labeledField("Details", $model.details, placeholder: "Describe the route (optional)", multiline: true)
        }
    }

    // MARK: - Category picker (horizontal chip row)

    /// A scannable chip row — each chip previews its category's real tint + glyph
    /// (the same icon the calendar day view renders), so the composer and the
    /// calendar speak the same visual language. Default `.other`.
    private var categoryField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Category").font(.sansMedium(12)).foregroundStyle(Hue.ink3)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EventCategory.allCases) { categoryChip($0) }
                }
                .padding(.horizontal, 2).padding(.vertical, 2)
            }
        }
    }

    private func categoryChip(_ cat: EventCategory) -> some View {
        let selected = model.category == cat
        return Button {
            Haptics.selection()
            model.category = cat
        } label: {
            HStack(spacing: 6) {
                Image(systemName: cat.glyph)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? .white : cat.tint)
                Text(cat.label)
                    .font(.sansMedium(13))
                    .foregroundStyle(selected ? .white : Hue.ink2)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(selected ? cat.tint : Hue.paper))
            .overlay(Capsule().stroke(selected ? Color.clear : Hue.hairline, lineWidth: 1))
            .animation(.easeOut(duration: 0.16), value: selected)
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .accessibilityLabel("\(cat.label) category")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - Pieces

    private var titlePlaceholder: String {
        switch kind { case .event: return "Farmers Market"; case .club: return "Thursday Run Club"; case .trail: return "Wobegon loop" }
    }

    private func labeledField(_ label: String, _ text: Binding<String>, placeholder: String, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.sansMedium(12)).foregroundStyle(Hue.ink3)
            Group {
                if multiline {
                    TextField(placeholder, text: text, axis: .vertical).lineLimit(3...6)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .font(.sans(15)).foregroundStyle(Hue.ink)
            .autocorrectionDisabled(false)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Hue.paper).clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)).hyggeHairline()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var photoZone: some View {
        let ui = model.photo.flatMap(UIImage.init(data:))
        return VStack(alignment: .leading, spacing: 8) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                if let ui {
                    Image(uiImage: ui).resizable().scaledToFill()
                        .frame(height: 180).frame(maxWidth: .infinity).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus").font(.system(size: 26, weight: .light))
                        Text("Add a photo (optional)").font(.sans(13))
                    }
                    .foregroundStyle(Hue.ink3)
                    .frame(maxWidth: .infinity).frame(height: 120)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])).foregroundStyle(Hue.hairline))
                }
            }
            .buttonStyle(.plain)

            if model.photo != nil {
                Button { model.photo = nil; pickerItem = nil } label: {
                    Text("Remove photo").font(.sans(13)).foregroundStyle(Hue.clay700)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var submitButton: some View {
        Button {
            Task { await model.submit(kind: kind, api: api, storage: storage, moderation: moderation) }
        } label: {
            HStack(spacing: 8) {
                if model.submitting { ProgressView().tint(Hue.paper) }
                Text("Post").font(.sansSemibold(16))
            }
            .foregroundStyle(Hue.paper)
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(model.submitting ? Hue.moss700.opacity(0.5) : Hue.moss700)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(model.submitting)
        .padding(.top, 4)
    }
}
