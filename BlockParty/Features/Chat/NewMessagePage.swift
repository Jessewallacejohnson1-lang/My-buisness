//
//  NewMessagePage.swift
//  Block Party — New message (BP app messages 02): the pencil in Messages. Instagram's people picker, measured (BP app
//  `references/messages-instagram/SPEC.md`): search, your friends with a round tick each, and the button at the foot.
//  One friend opens that chat; two or more start a group of friends, with a name if you like. Apple's sheet: it
//  follows a drag down, and the X closes it.
//

import SwiftUI

struct NewMessagePage: View {
    @Environment(ChatBook.self) private var chats
    @Environment(FriendsBook.self) private var book
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var words = ""
    @State private var picked: [Neighbor] = []
    @State private var name = ""
    @State private var failures = 0
    @State private var starting = false
    @FocusState private var searching: Bool

    private static let groupMax = 31

    private var friends: [Neighbor] {
        let typed = words.trimmingCharacters(in: .whitespaces)
        return book.friends.filter { typed.isEmpty || TownSearch.score(typed, name: $0.displayName, extra: [], aliases: []) != nil }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                count
                ForEach(friends) { person in row(person) }
                if !book.loaded {
                    SkeletonBlock(cornerRadius: ChatMetric.loadingLine / 2)
                        .frame(width: ChatMetric.loadingName, height: ChatMetric.loadingLine)
                        .frame(maxWidth: .infinity, minHeight: ChatMetric.older)
                        .shimmering()
                        .accessibilityLabel("Loading")
                } else if book.friends.isEmpty {
                    Text("Add a friend to start a chat.")
                        .appleFont(14)
                        .foregroundStyle(Hue.chatGrey)
                        .frame(maxWidth: .infinity, minHeight: ChatMetric.older)
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .top, spacing: 0) { top }
        .safeAreaInset(edge: .bottom, spacing: 0) { foot }
        .background(Hue.surface.ignoresSafeArea())
        .task { await book.refresh() }
        .presentationDetents([.large])
        .presentationBackground(Hue.surface)
    }

    /// The X, the title and the search field.
    private var top: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Text("New message")
                    .appleFont(16, weight: .bold)
                    .foregroundStyle(Hue.ink)
                    .frame(height: ChatMetric.pickTitleLine)
                    .padding(.top, ChatMetric.pickXTop)
                    .accessibilityAddTraits(.isHeader)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.glyph(22, weight: .medium))
                        .foregroundStyle(Hue.ink)
                        .frame(width: ChatMetric.pickXSide, height: ChatMetric.pickXSide)
                        .contentShape(TapArea())
                }
                .buttonStyle(.press(.dim))
                .accessibilityLabel("Close")
                .padding(.top, ChatMetric.pickXTop)
                .padding(.leading, ChatMetric.pickX)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: ChatMetric.listBar, alignment: .top)
            HStack(spacing: ChatMetric.pickFieldIconGap) {
                Image(systemName: "magnifyingglass")
                    .font(.glyph(13, weight: .medium))
                    .foregroundStyle(Hue.chatGrey)
                    .frame(width: ChatMetric.pickFieldIcon, height: ChatMetric.pickFieldIcon)
                    .accessibilityHidden(true)
                TextField("Search", text: $words, prompt: Text("Search").foregroundStyle(Hue.chatGrey))
                    .appleFont(17)
                    .foregroundStyle(Hue.ink)
                    .focused($searching)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(.leading, ChatMetric.pickFieldIconLead)
            .padding(.trailing, ChatMetric.pickFieldIconLead)
            .frame(height: ChatMetric.pickField)
            .background(Hue.chatFill, in: RoundedRectangle(cornerRadius: ChatMetric.pickFieldCorner, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { searching = true }
            .padding(.leading, ChatMetric.side)
            .padding(.trailing, ChatMetric.pickFieldTrail)
        }
        .background(Hue.surface)
    }

    /// "Friends", or how many are picked with Clear all across from it.
    private var count: some View {
        HStack(spacing: 0) {
            Text(picked.isEmpty ? "Friends" : picked.count == 1 ? "1 person" : "\(picked.count) people")
                .appleFont(14, weight: .medium)
                .foregroundStyle(Hue.ink)
            Spacer(minLength: 0)
            if !picked.isEmpty {
                Button { picked = [] } label: {
                    Text("Clear all")
                        .appleFont(14, weight: .medium)
                        .foregroundStyle(Hue.chatClearAll)
                        .contentShape(TapArea())
                }
                .buttonStyle(.press(.dim))
            }
        }
        .frame(height: ChatMetric.titleLine)
        .padding(.leading, ChatMetric.side)
        .padding(.trailing, ChatMetric.pickCountTrail)
        .padding(.top, ChatMetric.pickCountTop)
        .padding(.bottom, ChatMetric.pickListTop)
    }

    private func row(_ person: Neighbor) -> some View {
        let on = picked.contains(person)
        return Button { toggle(person) } label: {
            HStack(spacing: ChatMetric.rowGap) {
                Avatar(avatarUrl: person.avatarUrl, size: ChatMetric.pickFace)
                Text(person.displayName)
                    .appleFont(14, weight: .semibold)
                    .foregroundStyle(Hue.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                ZStack {
                    Circle().strokeBorder(Hue.chatRing, lineWidth: ChatMetric.pickTickRing)
                    if on {
                        Circle().fill(Hue.ink)
                            .overlay {
                                Image(systemName: "checkmark")
                                    .font(.glyph(ChatMetric.pickTickGlyph, weight: .bold))
                                    .foregroundStyle(Hue.surface)
                            }
                            .transition(.scale(scale: 0.01).combined(with: .opacity))
                    }
                }
                .frame(width: ChatMetric.pickTick, height: ChatMetric.pickTick)
                .animation(reduceMotion ? nil : ChatMotion.pop, value: on)
            }
            .padding(.horizontal, ChatMetric.side)
            .padding(.vertical, ChatMetric.rowPad)
            .contentShape(Rectangle())
        }
        .buttonStyle(.press(.row))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func toggle(_ person: Neighbor) {
        Haptics.selection()
        if picked.contains(person) {
            picked.removeAll { $0 == person }
        } else if picked.count < Self.groupMax {
            picked.append(person)
        }
    }

    /// The group's name once two are picked, and the button: faint until someone is.
    private var foot: some View {
        VStack(spacing: ChatMetric.pickNameGap) {
            if picked.count > 1 {
                TextField("", text: $name, prompt: Text("Group name (optional)").foregroundStyle(Hue.chatGrey))
                    .appleFont(16)
                    .foregroundStyle(Hue.ink)
                    .padding(.horizontal, ChatMetric.rowGap)
                    .frame(height: ChatMetric.pickField)
                    .background(Hue.chatFill, in: RoundedRectangle(cornerRadius: ChatMetric.pickFieldCorner, style: .continuous))
            }
            Button { open() } label: {
                Text(picked.count > 1 ? "Start group of \(picked.count + 1)" : "Chat")
                    .appleFont(14, weight: .semibold)
                    .foregroundStyle(Hue.surface)
                    .frame(maxWidth: .infinity, minHeight: ChatMetric.pickButton)
                    .background(Hue.chatBlue, in: RoundedRectangle(cornerRadius: ChatMetric.pickButtonCorner, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.press(.squish))
            .disabled(picked.isEmpty || starting)
            .opacity(picked.isEmpty ? 0.4 : 1)
            .turnBackShake(failures: failures, shakes: !reduceMotion)
        }
        .padding(.horizontal, ChatMetric.side)
        .padding(.top, ChatMetric.pickFootTop)
        .padding(.bottom, ChatMetric.pickFootBottom)
        .background(Hue.surface)
        .animation(reduceMotion ? nil : Motion.snappy, value: picked.count > 1)
    }

    private func open() {
        guard let first = picked.first else { return }
        if picked.count == 1 {
            dismiss()
            chats.push?(.person(first))
            return
        }
        starting = true
        Task {
            do {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let label = trimmed.isEmpty ? nil : trimmed
                let id = try await chats.api.startGroup(picked.map(\.id), name: label)
                dismiss()
                chats.push?(.group(id: id, others: picked, name: label))
            } catch {
                Log.network("NewMessagePage: \(error)")
                failures += 1
                Haptics.error()
            }
            starting = false
        }
    }
}
