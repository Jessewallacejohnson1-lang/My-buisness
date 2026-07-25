//
//  UtilityTileView.swift
//  Block Party — one Utility Row tile. Structural clone of the Calendar bento box
//  (22pt continuous corners, gradient, soft shadow) that tap-EXPANDS in place
//  (compact ⇄ expanded, same spring as the bento). Renders generically from a
//  descriptor + state — no per-tile code, so a future tile needs none here.
//

import SwiftUI

enum UtilityTileMetrics {
    static let width: CGFloat = 148          // fixed scroll-tile width (spec); height/radius/fonts match the bento
    static let gap: CGFloat = 10
    static let compactH: CGFloat = 92        // == bento compact height
    static let expandedH: CGFloat = compactH * 2 + gap
    static let corner: CGFloat = 22          // == bento (hardcoded, deliberate match)
}

struct UtilityTileView: View {
    let descriptor: UtilityTileDescriptor
    let state: UtilityTileState
    let isExpanded: Bool
    let staleAfter: TimeInterval?
    let onTap: () -> Void

    var body: some View {
        let height = isExpanded ? UtilityTileMetrics.expandedH : UtilityTileMetrics.compactH
        return ZStack {
            // Frame EACH content to the tile size (like the bento) so the taller
            // expanded content can't inflate the ZStack and shift the compact
            // content out of the clip.
            compactContent
                .frame(width: UtilityTileMetrics.width, height: height)
                .opacity(isExpanded ? 0 : 1)
            expandedContent
                .frame(width: UtilityTileMetrics.width, height: height)
                .opacity(isExpanded ? 1 : 0)
        }
        .frame(width: UtilityTileMetrics.width, height: height)
        .background(
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(isLoading ? 0.4 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: UtilityTileMetrics.corner, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 8)   // == insightsCardShadow
        .contentShape(RoundedRectangle(cornerRadius: UtilityTileMetrics.corner, style: .continuous))
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
        .accessibilityHint(isExpanded ? "Collapse" : "Expand for detail")
    }

    // MARK: - Compact

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            labelRow
                .layoutPriority(1)   // guard: the label always claims its height
            Spacer(minLength: 2)
            valueView
            if let secondary = displaySecondary {
                Text(secondary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)   // …so does the secondary — never squeezed out
            }
        }
        // Width-only fill + leading (matches the bento, which uses no maxHeight —
        // the tile's fixed frame + the Spacer distribute the height).
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    @ViewBuilder private var valueView: some View {
        switch state {
        case .loading:
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white.opacity(0.35))
                .frame(width: 84, height: 26)
                .shimmering()
        case .failed:
            Text("—").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
        case .loaded(let value):
            Text(value.content.primary)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            labelRow
            Rectangle().fill(.white.opacity(0.22)).frame(height: 1)
            ForEach(content?.expanded ?? []) { row in
                HStack(spacing: 6) {
                    if let symbol = row.symbol {
                        Image(systemName: symbol).font(.system(size: 11)).frame(width: 15)
                    }
                    Text(row.label).font(.system(size: 11)).foregroundStyle(.white.opacity(0.8))
                    Spacer(minLength: 4)
                    Text(row.value).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
    }

    // MARK: - Shared

    private var labelRow: some View {
        HStack(spacing: 5) {
            if let symbol = symbolName {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
            }
            Text(descriptor.displayName)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            if content?.badge == .warning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white.opacity(0.9))
    }

    // MARK: - Derived

    private var content: UtilityTileContent? {
        if case let .loaded(value) = state { return value.content }
        return nil
    }

    private var isLoading: Bool { if case .loading = state { return true }; return false }

    private var symbolName: String? { content?.symbol ?? descriptor.symbol }

    private var colors: [Color] {
        (content?.gradientHex ?? descriptor.gradient).map { Color(hex: $0) }
    }

    /// The secondary line, or a ">Nd ago" note when a live tile's value is stale.
    private var displaySecondary: String? {
        guard case let .loaded(value) = state else { return nil }
        if let staleAfter, Date().timeIntervalSince(value.updatedAt) > staleAfter {
            return "Updated \(UtilityFormat.relative(value.updatedAt))"
        }
        return value.content.secondary
    }

    private var a11yLabel: String {
        var parts = [descriptor.displayName]
        switch state {
        case .loading: parts.append("loading")
        case .failed:  parts.append("unavailable")
        case .loaded(let value):
            parts.append(value.content.primary)
            if let secondary = displaySecondary { parts.append(secondary) }
        }
        return parts.joined(separator: ", ")
    }
}
