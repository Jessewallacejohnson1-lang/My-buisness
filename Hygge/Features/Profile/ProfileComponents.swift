//
//  ProfileComponents.swift
//  Hygge — the warm-frosted-glass building blocks for the profile screen:
//  a translucent glass panel, the avatar (with a clean blank slot — no gradient
//  placeholder), coral interest chips in a flow layout, list rows, and the two
//  feature-card faces. All coral-on-white per the house system; readable ink text
//  keeps contrast on the frost.
//

import SwiftUI

// MARK: - Glass panel

/// A frosted panel that sits on the sheet's translucent backdrop: a warm-white
/// wash lets the blurred Home show faintly through while keeping ink text crisp,
/// with a bright glass rim + a grounding hairline.
private struct GlassPanel: ViewModifier {
    var radius: CGFloat = Radius.lg
    func body(content: Content) -> some View {
        content
            .background(Hue.paper.opacity(0.62), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(.white.opacity(0.5), lineWidth: 0.75)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Hue.hairline, lineWidth: 1)
            )
            .shadow(color: Color(hex: 0x2a241c, alpha: 0.08), radius: 12, x: 0, y: 5)
    }
}

extension View {
    /// Warm frosted-glass surface — the profile's card/group background.
    func glassPanel(_ radius: CGFloat = Radius.lg) -> some View { modifier(GlassPanel(radius: radius)) }
}

// MARK: - Avatar

/// The profile avatar: remote photo when set, a calm blank slot otherwise (a
/// person glyph on paper — no auto-fetched art, no gradient). White + hairline
/// ring reads as a physical disc on the glass.
struct ProfileAvatar: View {
    let url: String?
    var size: CGFloat = 104

    var body: some View {
        Group {
            if let url, let u = URL(string: url) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    case .empty: ZStack { Hue.paper; ProgressView().tint(Hue.accent) }
                    default: blank
                    }
                }
            } else {
                blank
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 3))
        .overlay(Circle().stroke(Hue.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 16, y: 7)
    }

    private var blank: some View {
        ZStack {
            Hue.paper
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.42))
                .foregroundStyle(Hue.ink3.opacity(0.5))
        }
    }
}

// MARK: - Interest chips

/// A coral-soft interest pill (matches the app's "Now" badge tone).
func interestChip(_ label: String) -> some View {
    Text(label)
        .font(.sansMedium(13))
        .foregroundStyle(Hue.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Hue.accentSoft.opacity(0.92), in: Capsule())
        .overlay(Capsule().stroke(Hue.accent.opacity(0.16), lineWidth: 1))
}

/// A minimal flow layout — chips wrap onto new lines within the available width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: maxW.isFinite ? maxW : x, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

// MARK: - List rows + groups

/// One tappable settings/activity row, styled to sit inside a `GlassGroup`.
struct ProfileRow: View {
    let icon: String
    var iconTint: Color = Hue.ink
    let title: String
    var subtitle: String? = nil
    var trailing: String? = nil        // a mono count / short value
    var accessory: Accessory = .chevron
    var destructive = false
    /// nil → a static (non-tappable) row, e.g. a count-only or read-only line.
    var action: (() -> Void)? = nil

    enum Accessory { case chevron, none, expand(Bool) }

    var body: some View {
        if let action {
            Button { Haptics.light(); action() } label: { rowContent }
                .buttonStyle(PressableStyle())
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(destructive ? Hue.clay700 : iconTint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.sansMedium(16))
                    .foregroundStyle(destructive ? Hue.clay700 : Hue.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.sans(13))
                        .foregroundStyle(Hue.ink3)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.monoMedium(15))
                    .monospacedDigit()
                    .foregroundStyle(Hue.ink2)
            }
            accessoryView
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var accessoryView: some View {
        switch accessory {
        case .none:
            EmptyView()
        case .chevron:
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Hue.ink3.opacity(0.7))
        case .expand(let open):
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Hue.ink3.opacity(0.7))
                .rotationEffect(.degrees(open ? 0 : -90))
        }
    }
}

/// The 1px indented divider between rows in a group.
struct ProfileRowDivider: View {
    var body: some View {
        Rectangle().fill(Hue.hairline).frame(height: 1).padding(.leading, 39)
    }
}

/// A frosted group card wrapping a stack of rows.
struct GlassGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 16)
            .glassPanel()
    }
}

// MARK: - Feature card face

/// The visual for the two hero cards (used inside a Button and a ShareLink). Icon
/// chip, a big value, a label, and an optional subtitle — on a frosted panel.
struct FeatureFace: View {
    let icon: String
    let value: String
    let label: String
    var subtitle: String? = nil
    var coral = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(coral ? Hue.accent : Hue.ink)
                .frame(width: 42, height: 42)
                .background((coral ? Hue.accentSoft : Hue.paper200).opacity(0.9), in: Circle())
            Spacer(minLength: 12)
            Text(value)
                .font(.displaySemi(21))
                .monospacedDigit()
                .foregroundStyle(Hue.ink)
                .lineLimit(1)
            Text(label)
                .font(.sans(13))
                .foregroundStyle(Hue.ink2)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.sans(12))
                    .foregroundStyle(Hue.ink3)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .leading)
        .padding(16)
        .glassPanel(Radius.xl)
    }
}
