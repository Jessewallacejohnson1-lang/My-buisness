//
//  MeetupPill.swift
//  Block Party — Meetup's charcoal pill: RSVP and Invite on the Town card (BP app
//  docs/plans/rsvp-and-groups), and Join group after it.
//
//  Every number is the Figma page "Meetup depth" (Jesse, 2026-10-17), measured off
//  Meetup's iOS pills at 3x. Not one flat black: lit from above (`Hue.pillTop` to
//  `pillDeep` a quarter down to `pillBottom`), a 1 pt line of light along the inside top,
//  and two shadows, a tight one where it touches the page and a wide soft one that lifts
//  it (`meetupPillDepth`). No Apple button draws this, so the style is BP's own, built
//  from SwiftUI's gradient and shadows.
//
//  Pressed, it sinks to 97% and its shadows pull in, on the press spring every pressable
//  in the app shares (`FeedMarkPress`, response 0.25, damping 0.6). Reduce Motion: no
//  sink, the feed's opacity dip, and the shadows still pull in.
//

import SwiftUI

struct MeetupPillStyle: ButtonStyle {
    /// The Town card's pill: 38 pt tall, at least 100 wide.
    var height: CGFloat = 38
    var minWidth: CGFloat = 100

    static let pressedScale: CGFloat = 0.97
    /// Words (and glyph) 20 pt in from each end.
    static let sidePadding: CGFloat = 20

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, Self.sidePadding)
            .frame(minWidth: minWidth)
            .frame(height: height)
            .background {
                Capsule()
                    .fill(LinearGradient(stops: [.init(color: Hue.pillTop, location: 0),
                                                 .init(color: Hue.pillDeep, location: 0.27),
                                                 .init(color: Hue.pillBottom, location: 1)],
                                         startPoint: .top, endPoint: .bottom)
                        .shadow(.inner(color: Hue.pillRim, radius: 0, x: 0, y: 1)))
                    .meetupPillDepth(pressed: pressed)
            }
            .contentShape(Capsule())
            .scaleEffect(pressed && !reduceMotion ? Self.pressedScale : 1)
            .opacity(FeedMotion.pressOpacity(isPressed: pressed, reduceMotion: reduceMotion))
            .animation(FeedMarkPress.animation(reduceMotion: reduceMotion), value: pressed)
    }
}
