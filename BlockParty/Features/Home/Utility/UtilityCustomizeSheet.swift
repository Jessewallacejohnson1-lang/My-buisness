//
//  UtilityCustomizeSheet.swift
//  Block Party — the Utility Row customize sheet. Rendered ENTIRELY from the
//  registry: one row per descriptor (mini preview · name · description · toggle),
//  drag-to-reorder enabled tiles, inline settings from the descriptor's editor,
//  and a pinned Save. Adding a future tile needs no edits here.
//

import SwiftUI

struct UtilityCustomizeSheet: View {
    @ObservedObject var model: UtilityRowModel
    @Environment(\.dismiss) private var dismiss

    /// All catalog tiles in draft order (enabled first, then disabled), the enabled
    /// set, and per-tile settings — applied to prefs only on Save.
    @State private var draftTiles: [UtilityTileID]
    @State private var draftEnabled: Set<UtilityTileID>
    @State private var draftSettings: [UtilityTileID: TileSettings]

    init(model: UtilityRowModel) {
        self.model = model
        let enabled = model.prefs.tiles
        let enabledSet = Set(enabled)
        let disabled = model.registry.catalog.filter { !enabledSet.contains($0) }
        _draftTiles = State(initialValue: enabled + disabled)
        _draftEnabled = State(initialValue: enabledSet)
        _draftSettings = State(initialValue: model.prefs.settings)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            list
            saveBar
        }
        .background(Hue.paper)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack {
            Text("Your quick info")
                .font(.displaySemi(22))
                .foregroundStyle(Hue.ink)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 8)
    }

    private var list: some View {
        List {
            ForEach(draftTiles, id: \.self) { id in
                if let descriptor = model.registry.descriptor(id) {
                    row(descriptor)
                        .moveDisabled(!draftEnabled.contains(id))   // reorder enabled tiles only
                        .listRowBackground(Hue.paper)
                        .listRowSeparatorTint(Hue.hairline)
                }
            }
            .onMove { draftTiles.move(fromOffsets: $0, toOffset: $1) }
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(.active))   // always-on reorder grips
    }

    private func row(_ d: UtilityTileDescriptor) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                MiniTilePreview(descriptor: d)
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.displayName).font(.sansSemibold(15)).foregroundStyle(Hue.ink)
                    Text(d.summary).font(.sans(12)).foregroundStyle(Hue.inkSecondary).lineLimit(2)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: enabledBinding(d.id)).labelsHidden().tint(Hue.ink)
            }
            // Inline settings (v1: garbage weekday), shown when enabled.
            if draftEnabled.contains(d.id), let editor = d.settingsEditor {
                editor(draftSettings[d.id] ?? TileSettings()) { updated in
                    draftSettings[d.id] = updated
                }
                .padding(.leading, 64)
            }
        }
        .padding(.vertical, 4)
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Hue.hairline).frame(height: 1)
            Button {
                let order = draftTiles, enabled = draftEnabled, settings = draftSettings
                Task { await model.applyDraft(order: order, enabled: enabled, settings: settings) }
                dismiss()
            } label: {
                Text("Save")
                    .font(.sansSemibold(16))
                    .foregroundStyle(Hue.surface)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Hue.ink)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            }
            .buttonStyle(PressableStyle(scale: 0.98))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(Hue.paper)
    }

    private func enabledBinding(_ id: UtilityTileID) -> Binding<Bool> {
        Binding(
            get: { draftEnabled.contains(id) },
            set: { on in
                if on { draftEnabled.insert(id) } else { draftEnabled.remove(id) }
            }
        )
    }
}

/// A small swatch of a tile's real gradient + symbol, for the customize sheet rows.
struct MiniTilePreview: View {
    let descriptor: UtilityTileDescriptor
    var body: some View {
        ZStack {
            LinearGradient(colors: descriptor.gradient.map { Color(hex: $0) },
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: descriptor.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 52, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Inline settings editor for the garbage tile: the weekly pickup day.
struct GarbageWeekdaySetting: View {
    let settings: TileSettings
    let apply: (TileSettings) -> Void
    var body: some View {
        HStack {
            Text("Pickup day").font(.sans(13)).foregroundStyle(Hue.inkSecondary)
            Spacer()
            Picker("Pickup day", selection: Binding(
                get: { settings.int("day") ?? GarbageSchedule.defaultWeekday },
                set: { apply(settings.setting("day", .int($0))) }
            )) {
                ForEach(1...7, id: \.self) { weekday in
                    Text(UtilityFormat.weekdayName(weekday)).tag(weekday)
                }
            }
            .labelsHidden()          // the "Pickup day" label is provided by the Text above
            .pickerStyle(.menu)
            .tint(Hue.ink)
        }
    }
}
