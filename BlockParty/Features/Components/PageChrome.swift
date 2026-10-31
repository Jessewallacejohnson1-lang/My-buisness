//
//  PageChrome.swift
//  Block Party — what pushed pages share (BP app codebase-health 19): the top bar with its back
//  chevron and centred title, a list row with a button at its right and that grey button, their
//  sizes, and the three press styles every screen uses. Drawn, not Apple's bar, which dropped a
//  page pushed inside the Profile sheet 20pt at the end of the push (Saved, 2026-10-13).
//

import SwiftUI

nonisolated enum PageMetric {
    /// The top bar's height, and the back chevron's square.
    static let bar: CGFloat = 44
    /// The back chevron's square in from the page's left edge.
    static let backLead: CGFloat = 6
    /// A bar inside the Profile sheet, down from the sheet's edge: where Apple's own bar sat, its
    /// back button's centre 42pt down (measured on BP Build, 2026-10-13).
    static let sheetTop: CGFloat = 20
    /// The smallest tap area, Apple's 44: smaller marks get theirs grown to it.
    static let tapMin: CGFloat = 44

    // Touch, from Jesse's Search mockup.
    static let pressScale: CGFloat = 0.95
    static let dimPressed: Double = 0.45
    static let rowPressed: Double = 0.05
}

/// A tap area at least `side` each way, centred on what's drawn, for a mark whose size isn't fixed
/// (words that follow the text size): `.contentShape(TapArea())`. Nothing drawn or laid out moves.
nonisolated struct TapArea: Shape {
    var side: CGFloat = PageMetric.tapMin

    func path(in rect: CGRect) -> Path {
        Path(rect.insetBy(dx: min(0, (rect.width - side) / 2), dy: min(0, (rect.height - side) / 2)))
    }
}

/// A pushed page's top: the back chevron at the left, the title in the middle, on paper the list
/// passes under. `top` is how far down its sheet it sits; a page on the tab's own stack passes 0.
struct PageBar: View {
    let title: String
    var top: CGFloat = PageMetric.sheetTop
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(.sansSemibold(17))
                .foregroundStyle(Hue.ink)
                .accessibilityAddTraits(.isHeader)
            HStack {
                BackButton(action: onBack)
                Spacer()
            }
            .padding(.leading, PageMetric.backLead)
        }
        .frame(height: PageMetric.bar)
        .padding(.top, top)
        .frame(maxWidth: .infinity)
        .background(Hue.paper.ignoresSafeArea(edges: .top))
    }
}

/// The back chevron: 44pt, fades while pressed.
struct BackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.glyph(20, weight: .semibold))
                .foregroundStyle(Hue.ink)
                .frame(width: PageMetric.bar, height: PageMetric.bar)
                .contentShape(Rectangle())
        }
        .buttonStyle(DimStyle())
        .accessibilityLabel("Back")
    }
}

/// Instagram's list row: a face, a name, and what sits at the right (Blocked's Unblock, Muted's
/// Unmute), at the Friends page's row height.
struct ListRow<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: FriendsMetric.avatarGap) {
            leading
            Text(title)
                .font(.sansSemibold(17))
                .foregroundStyle(Hue.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, FriendsMetric.side)
        .frame(height: FriendsMetric.row)
    }
}

/// A row's grey button: 36pt drawn, 44pt to the finger, pops when pressed.
struct RowButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.sansSemibold(15))
                .foregroundStyle(Hue.ink)
                .padding(.horizontal, FriendsMetric.buttonPad)
                .frame(minHeight: FriendsMetric.button)
                .background(Hue.fill, in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                .contentShape(Rectangle().inset(by: (FriendsMetric.button - PageMetric.tapMin) / 2))
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Press styles

/// Squishes while the finger is down, sprung like the mockup's (0.95; response 0.28,
/// damping 0.68), and springs back the way it went.
struct SquishStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? PageMetric.pressScale : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.68), value: configuration.isPressed)
    }
}

/// Fades while pressed: a row's title, Cancel, back.
struct DimStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? PageMetric.dimPressed : 1)
    }
}

/// A list row darkens a touch under the finger.
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(Hue.ink.opacity(configuration.isPressed ? PageMetric.rowPressed : 0))
    }
}
