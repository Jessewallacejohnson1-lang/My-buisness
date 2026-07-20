//
//  QuickAddSheet.swift
//  Block Party — the admin quick-add composer, launched from the map's "+" button.
//
//  The fast path to post from the field: title, a spot from the curated
//  catalogue, date (today), start time (now — so a "happening now" post lights
//  its pin immediately), and an optional one line. Inserts an approved event with
//  submitted_by = the admin's uid (respecting the existing "submit events" RLS
//  policy — no policy change needed), so the Realtime pipeline makes it live.
//
//  Gated by the caller: the "+" only renders for Admin.isAdmin, so this sheet is
//  never reachable by a non-admin.
//

import SwiftUI

struct QuickAddSheet: View {
    let spots: [Spot]

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var location: String
    @State private var date = Date()
    @State private var time = Date()
    @State private var note = ""
    @State private var submitting = false
    @State private var error: String?

    private var api: CommunityAPI { CommunityAPI(auth: auth) }

    init(spots: [Spot]) {
        self.spots = spots
        _location = State(initialValue: spots.first?.name ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    labeledField("What's happening?", $title, placeholder: "Independence Day Parade")

                    VenueAutocompleteField(label: "Where", placeholder: "Pick or search a spot",
                                           text: $location, curated: MapSpots.pinnableSuggestions, palette: .map)
                    whenRow

                    labeledField("A line about it", $note,
                                 placeholder: "Anything neighbors should know (optional)",
                                 multiline: true)

                    if let error {
                        Text(error)
                            .font(.sans(13)).foregroundStyle(Hue.clay700)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    submitButton
                }
                .padding(18)
            }
            .background(Hue.surface)   // opaque: a data-entry form needs solid, high-contrast
                                       // field backing — frosting is for the map's place cards
            .navigationTitle("Add a happening")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Hue.gray)
                }
            }
        }
        // Open tall enough that the Post button is never below the fold — a
        // hidden primary action is exactly the kind of slop Part C rejects.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Radius.xl)
    }

    // MARK: Fields

    private var whenRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("When").font(.sansMedium(12)).foregroundStyle(Hue.gray)
            HStack {
                DatePicker("", selection: $date, in: Calendar.current.startOfDay(for: Date())...,
                           displayedComponents: .date)
                    .labelsHidden()
                Spacer()
                DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Hue.bgSubtle)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Hue.mapHairline, lineWidth: 1))
        }
    }

    private func labeledField(_ label: String, _ text: Binding<String>,
                              placeholder: String, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.sansMedium(12)).foregroundStyle(Hue.gray)
            Group {
                if multiline {
                    TextField(placeholder, text: text, axis: .vertical).lineLimit(2...4)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .font(.sans(15)).foregroundStyle(Hue.mapInk)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Hue.bgSubtle)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Hue.mapHairline, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if submitting { ProgressView().tint(.white) }
                Text(submitting ? "Posting…" : "Post to the map")
                    .font(.sansSemibold(16)).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(submitting ? Hue.accent.opacity(0.5) : Hue.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(submitting)
        .padding(.top, 4)
    }

    // MARK: Submit

    private func submit() async {
        error = nil
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let loc = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { error = "Give it a title."; return }
        guard !loc.isEmpty else { error = "Where is it happening?"; return }

        submitting = true
        defer { submitting = false }

        let desc = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = NewEventInput(
            title: t,
            eventDate: DateHelpers.localDate(date),
            startTime: startTimeString,
            location: loc,                       // the spot name carries the keyword → lights that pin
            description: desc.isEmpty ? nil : desc,
            imageUrl: nil
        )
        do {
            try await api.addEvent(input, clubId: nil, status: .approved)
            Haptics.success()
            dismiss()
        } catch {
            Haptics.error()   // spec §10: a failed action → error notification
            self.error = (error as? SupabaseError)?.message ?? "Couldn't post — try again."
        }
    }

    private var startTimeString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "h:mm a"
        return f.string(from: time)
    }
}
