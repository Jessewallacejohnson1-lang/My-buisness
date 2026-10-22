//
//  MeetupPill.swift
//  Block Party — Meetup's charcoal pill: RSVP and Invite on the Town card and in the Event
//  page's bar (BP app docs/plans/rsvp-and-groups), Join group after it, and the small Join
//  beside a group's name on a Town card, white once you're in (rsvp-and-groups 07).
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
    /// Meetup's charcoal, lit from above, with its line of light inside the top.
    private var charcoal: some ShapeStyle {
        LinearGradient(stops: [.init(color: Hue.pillTop, location: 0),
                               .init(color: Hue.pillDeep, location: 0.27),
                               .init(color: Hue.pillBottom, location: 1)],
                       startPoint: .top, endPoint: .bottom)
            .shadow(.inner(color: Hue.pillRim, radius: 0, x: 0, y: 1))
    }

    /// The Town card's pill: 38 pt tall, at least 100 wide.
    var height: CGFloat = 38
    var minWidth: CGFloat = 100
    /// A flat fill in place of Meetup's charcoal: red for a called-off Event (`Hue.canceled`).
    var fill: Color?
    /// The card's Joined (Figma "Meetup depth", Club header): white with a hairline and ink
    /// words, flat. It cross-fades with the charcoal on its caller's timing.
    var light = false
    /// Town's round X (attend-x): light grey, flat, with an ink glyph. It cross-fades with the
    /// charcoal on its caller's timing too.
    var grey = false
    /// Words (and glyph) in from each end: 20 pt, the Club size's 16.
    var sidePadding: CGFloat = 20

    static let pressedScale: CGFloat = 0.97
    /// The tap area reaches past the pill to Apple's 44 pt (the card's pill is 38 tall).
    static let minTarget: CGFloat = 44

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        // The press spring moves only the sink and the shadows. The words swap on their
        // caller's timing, so the pill turns into Invite with the words beside it, not on
        // the spring (the review's frames, 2026-10-17).
        let press = FeedMarkPress.animation(reduceMotion: reduceMotion)
        return configuration.label
            .foregroundStyle(light || grey ? Hue.ink : .white)
            .padding(.horizontal, sidePadding)
            .frame(minWidth: minWidth)
            .frame(height: height)
            // A face on its way out fades where it stood; the clip keeps it inside the pill as the
            // pill shrinks into the X or grows back (attend-x's frames).
            .clipShape(Capsule())
            .background {
                Capsule()
                    .fill(fill.map(AnyShapeStyle.init) ?? AnyShapeStyle(charcoal))
                    .animation(press) { $0.meetupPillDepth(pressed: pressed) }
                    .opacity(light || grey ? 0 : 1)
                if light {
                    Capsule()
                        .fill(Hue.surface)
                        .overlay { Capsule().strokeBorder(Hue.hairline, lineWidth: 1) }
                }
                // Always there, so it shrinks and grows with the charcoal instead of popping in at
                // the circle's size. Lit like the charcoal (Jesse at event-card 06's Check-in 1): white
                // at its top into the app's light fill, a touch darker at its foot, a line of light
                // inside the top and the charcoal's two shadows, lighter.
                Capsule()
                    .fill(LinearGradient(stops: [.init(color: Hue.surface, location: 0),
                                                 .init(color: Hue.fill, location: 0.4)],
                                         startPoint: .top, endPoint: .bottom)
                        .shadow(.inner(color: Hue.surface, radius: 0, x: 0, y: 1)))
                    .overlay {
                        Capsule().fill(LinearGradient(colors: [.clear, .black.opacity(0.05)],
                                                      startPoint: .center, endPoint: .bottom))
                    }
                    .animation(press) { $0.meetupPillDepth(pressed: pressed, strength: 0.55) }
                    .opacity(grey ? 1 : 0)
            }
            .contentShape(Capsule().inset(by: min(0, (height - Self.minTarget) / 2)))
            .animation(press) {
                $0.scaleEffect(pressed && !reduceMotion ? Self.pressedScale : 1)
                    .opacity(FeedMotion.pressOpacity(isPressed: pressed, reduceMotion: reduceMotion))
            }
    }
}

/// Town's share beside the round X once you're going (event-card 06): a 38 pt BP yellow circle, the
/// X's size, with the card's send in ink, drawn heavier. Lit as the pill is: the exact yellow under a
/// white sheen over its top, a line of light inside the top, the pill's two shadows lighter; pressed
/// it sinks and the shadows pull in.
struct YellowShareButton: View {
    let action: () -> Void

    static let side: CGFloat = 38
    /// The send at 18 pt, its stroke 1.36 times the family's (3 of 24 units, the approved mock's).
    static let glyph: CGFloat = 18
    static let weight: CGFloat = 3 / 2.2

    var body: some View {
        Button(action: action) {
            FeedActionGlyphView(glyph: .send, size: Self.glyph, weight: Self.weight)
        }
        .buttonStyle(YellowDiscStyle())
        .accessibilityLabel("Share")
    }
}

private struct YellowDiscStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let press = FeedMarkPress.animation(reduceMotion: reduceMotion)
        return configuration.label
            .foregroundStyle(Hue.onBrandDisc)
            .frame(width: YellowShareButton.side, height: YellowShareButton.side)
            .background {
                Circle()
                    .fill(Hue.brandDisc.shadow(.inner(color: .white.opacity(0.7), radius: 0, x: 0, y: 1)))
                    .overlay {
                        Circle().fill(LinearGradient(colors: [.white.opacity(0.34), .white.opacity(0)],
                                                     startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45)))
                    }
                    .animation(press) { $0.meetupPillDepth(pressed: pressed, strength: 0.75) }
            }
            .contentShape(Circle().inset(by: (YellowShareButton.side - MeetupPillStyle.minTarget) / 2))
            .animation(press) {
                $0.scaleEffect(pressed && !reduceMotion ? MeetupPillStyle.pressedScale : 1)
                    .opacity(FeedMotion.pressOpacity(isPressed: pressed, reduceMotion: reduceMotion))
            }
    }
}
