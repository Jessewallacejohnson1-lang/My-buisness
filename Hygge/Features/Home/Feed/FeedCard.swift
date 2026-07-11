//
//  FeedCard.swift
//  Hygge — the komoot Home-card clone (Today tab remake, Zone 3). Literal komoot
//  voice: "Follow"/"Following", "N followers", "N liked this", "N comments".
//
//  A dumb view: it renders whatever `FeedPosting` it's handed and forwards taps
//  to callbacks. HomeModel owns the API calls + optimistic update; a like/follow
//  toggle flows back down as a new `posting` value, not local state here.
//
//  See docs/superpowers/specs/2026-07-11-today-tab-remake-design.md §4 Zone 3.
//

import SwiftUI

struct FeedCard: View {
    let posting: FeedPosting
    var onLike: () -> Void
    var onFollow: () -> Void
    var onSave: () -> Void
    var onShare: () -> Void
    var onComment: () -> Void
    var onOpen: () -> Void

    /// The viewer's personal saved mark — local-only (see `SavedStore`), same
    /// mechanism as the Explore cards' bookmark. Not a fabricated backend count.
    @ObservedObject private var savedStore = SavedStore.shared

    private let heroHeight: CGFloat = 226

    init(posting: FeedPosting,
         onLike: @escaping () -> Void,
         onFollow: @escaping () -> Void,
         onSave: @escaping () -> Void,
         onShare: @escaping () -> Void,
         onComment: @escaping () -> Void,
         onOpen: @escaping () -> Void) {
        self.posting = posting
        self.onLike = onLike
        self.onFollow = onFollow
        self.onSave = onSave
        self.onShare = onShare
        self.onComment = onComment
        self.onOpen = onOpen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            accountRow
            heroButton
            engagementRow
            Rectangle().fill(Hue.hairline).frame(height: 1)
                .padding(.horizontal, 14)
                .padding(.top, 12)
            actionRow
        }
        .background(Hue.paper)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .stroke(Hue.hairline, lineWidth: 1)
        )
        .modifier(CardShadow())
    }

    // MARK: - Account row

    private var accountRow: some View {
        HStack(spacing: 11) {
            posterAvatar
            VStack(alignment: .leading, spacing: 2) {
                Text(posting.posterName)
                    .font(.sansBold(15))
                    .foregroundStyle(Hue.ink)
                    .lineLimit(1)
                accountSubtitle.lineLimit(1)
            }
            Spacer(minLength: 8)
            followButton
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var posterAvatar: some View {
        Group {
            if let url = posting.posterAvatar.flatMap(URL.init) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: initialsAvatar
                    }
                }
            } else {
                initialsAvatar
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(Circle())
    }

    private var initialsAvatar: some View {
        ZStack {
            Hue.paper200
            Text(posterInitials)
                .font(.sansBold(13))
                .foregroundStyle(Hue.ink2)
        }
    }

    private var posterInitials: String {
        let letters = posting.posterName.split(separator: " ").compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters.prefix(2)).uppercased()
    }

    /// "N followers · posted Xh ago" — the two numbers are mono/tabular, the
    /// connecting words are the system sans (weight carries hierarchy).
    private var accountSubtitle: some View {
        HStack(spacing: 0) {
            Text("\(posting.followerCount)")
                .font(.monoMedium(12)).monospacedDigit()
                .foregroundStyle(Hue.ink3)
            Text(" followers · ")
                .font(.sans(12))
                .foregroundStyle(Hue.ink3)
            Text(postedAgo)
                .font(.mono(12)).monospacedDigit()
                .foregroundStyle(Hue.ink3)
        }
    }

    /// Relative time since `posting.createdAt` ("just now" / "5m ago" / "3h ago" /
    /// "2d ago" / "1w ago"). No API dependency — pure local formatting.
    private var postedAgo: String {
        let seconds = max(0, Date().timeIntervalSince(posting.createdAt))
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days < 7 { return "\(days)d ago" }
        return "\(days / 7)w ago"
    }

    private var followButton: some View {
        Button {
            Haptics.selection()
            onFollow()
        } label: {
            Text(posting.following ? "Following" : "Follow")
                .font(.sansSemibold(13))
                .foregroundStyle(posting.following ? Hue.ink2 : Hue.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(posting.following ? Color.clear : Hue.accentSoft)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(posting.following ? Hue.hairline : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .accessibilityLabel(posting.following ? "Following" : "Follow")
    }

    // MARK: - Text-over-photo hero

    private var heroButton: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onOpen) { heroContent }
                .buttonStyle(PressableStyle(scale: 0.99))
            likeButton.padding(11)
        }
    }

    private var heroContent: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                heroPhoto
                    .frame(width: geo.size.width, height: heroHeight)
                    .clipped()

                LinearGradient(colors: [.clear, .black.opacity(0.75)],
                               startPoint: .center, endPoint: .bottom)
                    .frame(width: geo.size.width, height: heroHeight)

                VStack(alignment: .leading, spacing: 4) {
                    Text(kickerLabel)
                        .font(.sansSemibold(11))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.85))
                    Text(posting.title)
                        .font(.displaySemi(22))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(statLine)
                        .font(.mono(12)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .frame(height: heroHeight)
    }

    /// Resolution chain (matches the trail card in ActivitiesView.swift): a real
    /// posted photo first, then the bundled known-local photo, then a
    /// confidence-gated Google Places venue photo, then the intentional blank —
    /// never generic stock.
    @ViewBuilder
    private var heroPhoto: some View {
        if let url = posting.imageUrl.flatMap(URL.init) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: ExploreBlankPhoto()
                }
            }
        } else if let localName = KnownLocalPhoto.name(forTitle: posting.title) {
            PhotoView(name: localName).scaledToFill()
        } else {
            VenuePhoto(venueName: posting.location ?? posting.title,
                       hint: posting.location != nil ? posting.title : nil) { ExploreBlankPhoto() }
        }
    }

    /// A short category label derived from the posting's own text via the same
    /// keyword table onboarding/matching uses — no separate taxonomy. Falls back
    /// to "HAPPENING" when nothing matches (never blank, never fabricated).
    private var kickerLabel: String {
        let haystack = "\(posting.title) \(posting.location ?? "")".lowercased()
        for interest in Interests.all where interest.keywords.contains(where: { haystack.contains($0) }) {
            return interest.label.uppercased()
        }
        return "HAPPENING"
    }

    /// "Sat 2pm · Millstream Park · 8 going" — omits whatever part is missing
    /// rather than showing a placeholder.
    private var statLine: String {
        var parts: [String] = []
        if let when = whenLabel { parts.append(when) }
        if let loc = posting.location, !loc.isEmpty { parts.append(loc) }
        parts.append("\(posting.goingCount) going")
        return parts.joined(separator: " · ")
    }

    private var whenLabel: String? {
        let weekday = posting.eventDate.map(DateHelpers.weekdayLabel) ?? ""
        let time = posting.startTime?.trimmingCharacters(in: .whitespaces) ?? ""
        switch (weekday.isEmpty, time.isEmpty) {
        case (false, false): return "\(weekday) \(time)"
        case (false, true):  return weekday
        case (true, false):  return time
        case (true, true):   return nil
        }
    }

    private var likeButton: some View {
        Button {
            Haptics.light()
            onLike()
        } label: {
            Image(systemName: posting.liked ? "heart.fill" : "heart")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(posting.liked ? Hue.accent : Hue.mapInk)
                .symbolEffect(.bounce, value: posting.liked)
                .frame(width: 38, height: 38)
                .background(Hue.surface)
                .clipShape(Circle())
                .mapFloatShadow()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(posting.liked ? "Unlike" : "Like")
    }

    // MARK: - Engagement meta row

    private var engagementRow: some View {
        HStack {
            engagementText.lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }

    /// Literal komoot wording: "N liked this · N comments". The counts are mono;
    /// the like count turns coral when the viewer has liked it.
    private var engagementText: some View {
        HStack(spacing: 0) {
            Text("\(posting.likeCount)")
                .font(.monoMedium(13)).monospacedDigit()
                .foregroundStyle(posting.liked ? Hue.accent : Hue.ink)
            Text(" liked this · ")
                .font(.sans(13))
                .foregroundStyle(Hue.ink2)
            Text("\(posting.commentCount)")
                .font(.monoMedium(13)).monospacedDigit()
                .foregroundStyle(Hue.ink)
            Text(" comments")
                .font(.sans(13))
                .foregroundStyle(Hue.ink2)
        }
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack(spacing: 0) {
            actionButton(icon: posting.liked ? "heart.fill" : "heart",
                         tint: posting.liked ? Hue.accent : Hue.ink2,
                         bounce: posting.liked, label: "Like") {
                Haptics.light(); onLike()
            }
            actionButton(icon: "bubble.left", tint: Hue.ink2, bounce: false, label: "Comment") {
                Haptics.light(); onComment()
            }
            actionButton(icon: savedStore.isSaved(posting.id) ? "bookmark.fill" : "bookmark",
                         tint: savedStore.isSaved(posting.id) ? Hue.accent : Hue.ink2,
                         bounce: savedStore.isSaved(posting.id), label: "Save") {
                Haptics.light()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.62)) {
                    savedStore.toggle(posting.id)
                }
                onSave()
            }
            actionButton(icon: "square.and.arrow.up", tint: Hue.ink2, bounce: false, label: "Share") {
                Haptics.light(); onShare()
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .padding(.bottom, 4)
    }

    private func actionButton(icon: String, tint: Color, bounce: Bool, label: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: bounce)
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}
