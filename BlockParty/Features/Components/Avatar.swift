//
//  Avatar.swift
//  Block Party — a person's, place's, group's or host's picture, the one way the app draws it (BP app
//  codebase-health 18). A person's is the squircle of onboarding's Photo step (backlog 40, Jesse 2026-11-22: "tweak
//  all the profile pictures in the app now to the new one"); a place, group or host stays round.
//
//  A person without a photo is Instagram's blank profile picture (Jesse said yes to it everywhere,
//  2026-10-26); a place, group or host without one keeps its first letter. The photo
//  loads through the feed's cache (`FeedCardURLPhoto`), never `AsyncImage` (no cache), so a face
//  already decoded draws in its first frame.
//

import SwiftUI

/// A person's picture's shape: the Photo step's squircle, its corner the same share of the side at every size. A
/// ring or tap shape around a face takes it too, and an inset keeps the corner concentric.
struct FaceShape: InsettableShape {
    private var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let corner = max(0, min(rect.width, rect.height) * Radius.faceShare - inset)
        return RoundedRectangle(cornerRadius: corner, style: .continuous).path(in: rect.insetBy(dx: inset, dy: inset))
    }

    func inset(by amount: CGFloat) -> FaceShape {
        var shape = self
        shape.inset += amount
        return shape
    }
}

struct Avatar: View {
    /// What shows without a photo, or when it can't load.
    enum Blank {
        /// Instagram's blank figure: a person.
        case figure
        /// The name's first letter on the light fill, at `font` points: a place, group or host.
        case initial(String, font: CGFloat = 14)
    }

    let url: URL?
    let size: CGFloat
    let blank: Blank
    /// The faint ink line the Friends pages draw around a face.
    let outlined: Bool
    /// A photo just picked on the phone, shown ahead of `url` (onboarding, Edit profile).
    let picked: UIImage?
    /// A rounded square with these corners instead of a circle (an Event's host card).
    let corner: CGFloat?
    /// The squircle: a person, who has the blank figure. A neighbour who hosts an Event is round, as every host
    /// is (Jesse's yes), so the caller says so.
    let person: Bool

    /// The URL that failed to load, so a dead link shows the blank instead of the light fill.
    @State private var failed: URL?

    init(_ url: URL?, size: CGFloat, blank: Blank = .figure, outlined: Bool = false, picked: UIImage? = nil,
         corner: CGFloat? = nil, person: Bool? = nil) {
        self.url = url
        self.size = size
        self.blank = blank
        self.outlined = outlined
        self.picked = picked
        self.corner = corner
        if let person {
            self.person = person
        } else if case .figure = blank {
            self.person = true
        } else {
            self.person = false
        }
    }

    /// From a profile's `avatar_url`.
    init(avatarUrl url: String?, size: CGFloat, blank: Blank = .figure, outlined: Bool = false, picked: UIImage? = nil) {
        self.init(url.flatMap(URL.init(string:)), size: size, blank: blank, outlined: outlined, picked: picked)
    }

    var body: some View {
        ZStack {
            if let picked {
                Image(uiImage: picked).resizable().scaledToFill()
                    .transition(.opacity)
            } else if let url, failed != url {
                FeedCardURLPhoto(url: url, onFailure: { withAnimation(.easeOut(duration: 0.2)) { failed = url } },
                                 loadingFill: Hue.fill)
            } else {
                blankFace
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay {
            if outlined { FaceShape().strokeBorder(Hue.ink.opacity(0.16), lineWidth: FriendsMetric.ring) }
        }
        .accessibilityHidden(true)
    }

    private var shape: AnyShape {
        if let corner { return AnyShape(RoundedRectangle(cornerRadius: corner, style: .continuous)) }
        return person ? AnyShape(FaceShape()) : AnyShape(Circle())
    }

    private var blankFace: some View {
        ZStack {
            switch blank {
            case .figure:
                Hue.blankAvatar
                BlankFigure().fill(Hue.blankAvatarFigure)
            case .initial(let name, let font):
                Hue.fill
                Text(name.first.map { String($0).uppercased() } ?? "")
                    .font(.sansSemibold(font))
                    .foregroundStyle(Hue.ink)
            }
        }
    }
}

/// Instagram's blank figure, measured as fractions of the side: a head 0.284 wide whose top
/// sits 0.268 down, and shoulders, an ellipse 0.72 wide and 0.86 tall centred on the bottom
/// edge, which the picture's edge cuts off.
private struct BlankFigure: Shape {
    func path(in rect: CGRect) -> Path {
        let d = min(rect.width, rect.height)
        let x = rect.midX
        var path = Path(ellipseIn: CGRect(x: x - 0.142 * d, y: rect.minY + 0.268 * d, width: 0.284 * d, height: 0.284 * d))
        path.addEllipse(in: CGRect(x: x - 0.36 * d, y: rect.minY + 0.57 * d, width: 0.72 * d, height: 0.86 * d))
        return path
    }
}
